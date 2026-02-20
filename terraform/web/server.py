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


def _collect_ms(rows):
    ms_values = []
    for factors in rows:
        if factors is None:
            continue
        if isinstance(factors, str):
            try:
                factors = json.loads(factors)
            except json.JSONDecodeError:
                continue
        if isinstance(factors, dict):
            factors = [factors]
        if not isinstance(factors, list):
            continue
        for item in factors:
            if not isinstance(item, dict):
                continue
            ms_value = item.get("ms")
            if ms_value is None:
                continue
            try:
                ms_values.append(float(ms_value))
            except (TypeError, ValueError):
                continue
    return ms_values


def _stats(ms_values):
    if not ms_values:
        return {"count": 0, "average_ms": None, "stddev_ms": None}
    count = len(ms_values)
    avg = sum(ms_values) / count
    variance = sum((value - avg) ** 2 for value in ms_values) / count
    return {
        "count": count,
        "average_ms": avg,
        "stddev_ms": variance ** 0.5,
    }


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/api/scheme":
            query = parse_qs(parsed.query)
            scheme_value = query.get("scheme", [None])[0]
            with _db_conn() as conn:
                with conn.cursor() as cur:
                    if scheme_value is None or scheme_value == "":
                        cur.execute("SELECT factors FROM scheme")
                    else:
                        cur.execute("SELECT factors FROM scheme WHERE scheme = %s", (scheme_value,))
                    rows = [row[0] for row in cur.fetchall()]
            ms_values = _collect_ms(rows)
            payload = {
                "scheme": scheme_value,
                **_stats(ms_values),
            }
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
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
