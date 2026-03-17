import json
import logging
import os
import time
from contextlib import contextmanager
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler
from socketserver import ThreadingTCPServer
from urllib.parse import parse_qs, urlparse

import psycopg2
from psycopg2 import pool as pg_pool

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

_conn_pool = None


def _build_pool_kwargs():
    database_url = os.getenv("DATABASE_URL")
    if database_url:
        return {"dsn": database_url}
    return {
        "dbname": os.getenv("FACTOR_DB_NAME", "factors"),
        "user": os.getenv("FACTOR_DB_USER"),
        "password": os.getenv("FACTOR_DB_PASSWORD"),
        "host": os.getenv("FACTOR_DB_HOST", "localhost"),
        "port": os.getenv("FACTOR_DB_PORT", "5432"),
    }


def _init_pool():
    global _conn_pool
    _conn_pool = pg_pool.ThreadedConnectionPool(2, 10, **_build_pool_kwargs())


def _get_conn_with_retry(attempts=3):
    global _conn_pool
    last_err = None
    for attempt in range(attempts):
        try:
            if _conn_pool is None or _conn_pool.closed:
                _init_pool()
            conn = _conn_pool.getconn()
            if conn.closed:
                _conn_pool.putconn(conn, close=True)
                continue
            try:
                conn.rollback()
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
            except Exception:
                try:
                    _conn_pool.putconn(conn, close=True)
                except Exception:
                    pass
                raise psycopg2.OperationalError("stale connection")
            return conn
        except psycopg2.OperationalError as exc:
            last_err = exc
            logger.warning("db_connect attempt=%d err=%s", attempt + 1, exc)
            try:
                if _conn_pool and not _conn_pool.closed:
                    _conn_pool.closeall()
            except Exception:
                pass
            _conn_pool = None
            time.sleep(0.5 * (attempt + 1))
    raise last_err


@contextmanager
def _db_conn():
    conn = _get_conn_with_retry()
    try:
        yield conn
    finally:
        try:
            _conn_pool.putconn(conn)
        except Exception:
            pass


def _ensure_table():
    try:
        with _db_conn() as conn:
            conn.autocommit = True
            with conn.cursor() as cur:
                cur.execute(
                    """
                    CREATE TABLE IF NOT EXISTS factors (
                        sequence UUID PRIMARY KEY,
                        data JSONB NOT NULL
                    )
                    """
                )
                cur.execute(
                    """
                    CREATE INDEX IF NOT EXISTS idx_factors_scheme
                        ON factors ((data->>'scheme'))
                    """
                )
                cur.execute(
                    """
                    CREATE TABLE IF NOT EXISTS scheme_summary (
                        scheme TEXT PRIMARY KEY,
                        total_count BIGINT NOT NULL DEFAULT 0,
                        first_persisted_at_ms BIGINT,
                        last_persisted_at_ms BIGINT
                    )
                    """
                )
    except Exception as exc:
        logger.warning("could not ensure tables exist: %s", exc)


_METRIC_KEYS = ["sent_to_persist_ms", "pull_to_persist_ms", "queue_to_db_ms", "factor_time_ms"]
_METRIC_LABELS = ["sent_to_persist", "pull_to_persist", "queue_to_db", "factor_time"]


def _build_agg_sql(where_clause=""):
    """Build a SQL query that computes count/avg/stddev/min/max per metric key."""
    agg_cols = []
    for key in _METRIC_KEYS:
        cast = f"(data->>'{key}')::double precision"
        agg_cols.extend([
            f"COUNT({cast}) AS \"{key}_count\"",
            f"AVG({cast}) AS \"{key}_avg\"",
            f"STDDEV_POP({cast}) AS \"{key}_stddev\"",
            f"MIN({cast}) AS \"{key}_min\"",
            f"MAX({cast}) AS \"{key}_max\"",
        ])
    sql = f"SELECT {', '.join(agg_cols)} FROM factors"
    if where_clause:
        sql += f" WHERE {where_clause}"
    return sql


def _row_to_stats(row):
    """Convert a single aggregation result row into per-metric stat dicts."""
    result = {}
    for i, label in enumerate(_METRIC_LABELS):
        offset = i * 5
        count = row[offset] or 0
        result[label] = {
            "count": count,
            "avg": round(row[offset + 1], 2) if row[offset + 1] is not None else None,
            "stddev": round(row[offset + 2], 2) if row[offset + 2] is not None else None,
            "min": round(row[offset + 3], 2) if row[offset + 3] is not None else None,
            "max": round(row[offset + 4], 2) if row[offset + 4] is not None else None,
        }
    return result


_THROUGHPUT_WINDOWS = [60, 300, 3600]

def _build_throughput_sql(where_clause=""):
    now_ms = "(extract(epoch from now()) * 1000)::bigint"
    ts = "(data->>'persisted_at_ms')::bigint"
    window_cols = []
    for secs in _THROUGHPUT_WINDOWS:
        ms = secs * 1000
        window_cols.append(
            f"COUNT(*) FILTER (WHERE {ts} > {now_ms} - {ms}) AS w_{secs}"
        )
    cols = ", ".join(window_cols + [
        f"MIN({ts}) AS first_ms",
        f"MAX({ts}) AS last_ms",
        f"COUNT(*) AS total",
    ])
    sql = f"SELECT {cols} FROM factors WHERE data->>'persisted_at_ms' IS NOT NULL"
    if where_clause:
        sql += f" AND ({where_clause})"
    return sql


def _throughput_from_row(row):
    result = {}
    for i, secs in enumerate(_THROUGHPUT_WINDOWS):
        count = row[i] or 0
        result[f"last_{secs}s"] = {
            "count": count,
            "msgs_per_sec": round(count / secs, 2) if secs > 0 else 0,
        }
    first_ms, last_ms, total = row[len(_THROUGHPUT_WINDOWS)], row[len(_THROUGHPUT_WINDOWS) + 1], row[len(_THROUGHPUT_WINDOWS) + 2]
    if first_ms and last_ms and last_ms > first_ms:
        span_sec = (last_ms - first_ms) / 1000.0
        result["overall"] = {
            "count": total,
            "msgs_per_sec": round(total / span_sec, 2),
            "span_seconds": round(span_sec, 1),
        }
    else:
        result["overall"] = {"count": total or 0, "msgs_per_sec": 0, "span_seconds": 0}
    return result


class Handler(SimpleHTTPRequestHandler):
    def _json_response(self, payload, status=HTTPStatus.OK):
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            pass

    def do_GET(self):
        try:
            self._route_get()
        except Exception:
            logger.exception("request_failed path=%s", self.path)
            try:
                self._json_response(
                    {"error": "internal server error"},
                    status=HTTPStatus.INTERNAL_SERVER_ERROR,
                )
            except Exception:
                pass

    def _query_with_retry(self, fn, retries=2):
        """Execute *fn(conn)* with automatic retry on stale-connection errors."""
        last_err = None
        for attempt in range(retries + 1):
            try:
                with _db_conn() as conn:
                    return fn(conn)
            except psycopg2.OperationalError as exc:
                last_err = exc
                logger.warning("query retry attempt=%d err=%s", attempt + 1, exc)
        raise last_err

    def _route_get(self):
        parsed = urlparse(self.path)

        if parsed.path == "/health":
            self._json_response({"status": "ok"})
            return

        if parsed.path == "/api/schemes":
            def _do(conn):
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT scheme, total_count, first_persisted_at_ms, last_persisted_at_ms "
                        "FROM scheme_summary ORDER BY last_persisted_at_ms DESC"
                    )
                    return cur.fetchall()
            rows = self._query_with_retry(_do)
            schemes = []
            for r in rows:
                scheme, count, first_ms, last_ms = r
                if first_ms and last_ms and last_ms > first_ms:
                    span_sec = (last_ms - first_ms) / 1000.0
                    avg_mps = round(count / span_sec, 2)
                else:
                    avg_mps = 0
                schemes.append({"scheme": scheme, "count": count, "avg_msgs_per_sec": avg_mps})
            self._json_response({"schemes": schemes})
            return

        if parsed.path == "/api/scheme":
            query = parse_qs(parsed.query)
            scheme_value = query.get("scheme", [None])[0]
            def _do(conn):
                with conn.cursor() as cur:
                    if scheme_value is None or scheme_value == "":
                        cur.execute(_build_agg_sql())
                        agg_row = cur.fetchone()
                        cur.execute(_build_throughput_sql())
                        tp_row = cur.fetchone()
                    else:
                        where = "(data->>'scheme')::text = %s"
                        cur.execute(_build_agg_sql(where), (scheme_value,))
                        agg_row = cur.fetchone()
                        cur.execute(_build_throughput_sql(where), (scheme_value,))
                        tp_row = cur.fetchone()
                    return agg_row, tp_row
            agg_row, tp_row = self._query_with_retry(_do)
            stats = _row_to_stats(agg_row)
            throughput = _throughput_from_row(tp_row)
            self._json_response({
                "scheme": scheme_value,
                **stats,
                "throughput": throughput,
            })
            return

        if parsed.path == "/api/throughput":
            query = parse_qs(parsed.query)
            scheme_value = query.get("scheme", [None])[0]
            def _do(conn):
                with conn.cursor() as cur:
                    if scheme_value is None or scheme_value == "":
                        cur.execute(_build_throughput_sql())
                    else:
                        cur.execute(
                            _build_throughput_sql("(data->>'scheme')::text = %s"),
                            (scheme_value,),
                        )
                    return cur.fetchone()
            tp_row = self._query_with_retry(_do)
            throughput = _throughput_from_row(tp_row)
            self._json_response({"scheme": scheme_value, "throughput": throughput})
            return

        super().do_GET()


def main():
    port = int(os.getenv("PORT", "8000"))
    server_address = ("", port)
    directory = os.path.dirname(os.path.abspath(__file__))
    handler = lambda *args, **kwargs: Handler(*args, directory=directory, **kwargs)
    ThreadingTCPServer.allow_reuse_address = True
    ThreadingTCPServer.daemon_threads = True
    import threading
    threading.Thread(target=_ensure_table, daemon=True).start()
    with ThreadingTCPServer(server_address, handler) as httpd:
        print(f"Serving on http://localhost:{port}")
        httpd.serve_forever()


if __name__ == "__main__":
    main()
