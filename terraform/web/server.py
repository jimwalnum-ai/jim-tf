import json
import os
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler
from socketserver import ThreadingTCPServer
from urllib.parse import parse_qs, urlparse

import psycopg2


def _db_conn():
    database_url = os.getenv("DATABASE_URL")
    if database_url:
        return psycopg2.connect(database_url)

    params = {
        "dbname": os.getenv("FACTOR_DB_NAME", "factors"),
        "user": os.getenv("FACTOR_DB_USER"),
        "password": os.getenv("FACTOR_DB_PASSWORD"),
        "host": os.getenv("FACTOR_DB_HOST", "localhost"),
        "port": os.getenv("FACTOR_DB_PORT", "5432"),
    }
    return psycopg2.connect(**params)


def _ensure_table():
    try:
        conn = _db_conn()
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
        conn.close()
    except Exception as exc:
        print(f"Warning: could not ensure factors table exists: {exc}")


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
        parsed = urlparse(self.path)

        if parsed.path == "/health":
            self._json_response({"status": "ok"})
            return

        if parsed.path == "/api/schemes":
            with _db_conn() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT DISTINCT data->>'scheme' AS scheme FROM factors "
                        "WHERE data->>'scheme' IS NOT NULL ORDER BY scheme"
                    )
                    schemes = [row[0] for row in cur.fetchall()]
            self._json_response({"schemes": schemes})
            return

        if parsed.path == "/api/scheme":
            query = parse_qs(parsed.query)
            scheme_value = query.get("scheme", [None])[0]
            with _db_conn() as conn:
                with conn.cursor() as cur:
                    if scheme_value is None or scheme_value == "":
                        cur.execute(_build_agg_sql())
                    else:
                        cur.execute(
                            _build_agg_sql("(data->>'scheme')::text = %s"),
                            (scheme_value,),
                        )
                    row = cur.fetchone()
            stats = _row_to_stats(row)
            self._json_response({
                "scheme": scheme_value,
                **stats,
            })
            return

        super().do_GET()


def main():
    port = int(os.getenv("PORT", "8000"))
    server_address = ("", port)
    directory = os.path.dirname(os.path.abspath(__file__))
    handler = lambda *args, **kwargs: Handler(*args, directory=directory, **kwargs)
    ThreadingTCPServer.allow_reuse_address = True
    ThreadingTCPServer.daemon_threads = True
    _ensure_table()
    with ThreadingTCPServer(server_address, handler) as httpd:
        print(f"Serving on http://localhost:{port}")
        httpd.serve_forever()


if __name__ == "__main__":
    main()
