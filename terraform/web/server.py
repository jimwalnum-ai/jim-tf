import json
import os
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler
from socketserver import TCPServer
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


def _collect_metrics(rows):
    """Extract timing metrics from each row's data dict."""
    sent_to_persist = []
    pull_to_persist = []
    queue_to_db = []
    for record in rows:
        if record is None:
            continue
        if isinstance(record, str):
            try:
                record = json.loads(record)
            except json.JSONDecodeError:
                continue
        if not isinstance(record, dict):
            continue
        for key, dest in [
            ("sent_to_persist_ms", sent_to_persist),
            ("pull_to_persist_ms", pull_to_persist),
            ("queue_to_db_ms", queue_to_db),
        ]:
            val = record.get(key)
            if val is not None:
                try:
                    dest.append(float(val))
                except (TypeError, ValueError):
                    continue
    return sent_to_persist, pull_to_persist, queue_to_db


def _stats(values):
    if not values:
        return {"count": 0, "avg": None, "stddev": None, "min": None, "max": None}
    count = len(values)
    avg = sum(values) / count
    variance = sum((v - avg) ** 2 for v in values) / count
    return {
        "count": count,
        "avg": round(avg, 2),
        "stddev": round(variance ** 0.5, 2),
        "min": round(min(values), 2),
        "max": round(max(values), 2),
    }


class Handler(SimpleHTTPRequestHandler):
    def _json_response(self, payload, status=HTTPStatus.OK):
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)

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
                        cur.execute("SELECT data FROM factors")
                    else:
                        cur.execute("SELECT data FROM factors WHERE (data->>'scheme')::text = %s", (scheme_value,))
                    rows = [row[0] for row in cur.fetchall()]
            sent, pull, queue = _collect_metrics(rows)
            self._json_response({
                "scheme": scheme_value,
                "sent_to_persist": _stats(sent),
                "pull_to_persist": _stats(pull),
                "queue_to_db": _stats(queue),
            })
            return

        super().do_GET()


def main():
    port = int(os.getenv("PORT", "8000"))
    server_address = ("", port)
    directory = os.path.dirname(os.path.abspath(__file__))
    handler = lambda *args, **kwargs: Handler(*args, directory=directory, **kwargs)
    with TCPServer(server_address, handler) as httpd:
        print(f"Serving on http://localhost:{port}")
        httpd.serve_forever()


if __name__ == "__main__":
    main()
