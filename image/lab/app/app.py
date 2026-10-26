#!/usr/bin/env python3
"""The 'shop' backend. Deliberately boring: every request opens a fresh DB
connection by hostname, so DNS, routing, firewall and DB faults all surface here.

  GET /        order count (hits the DB)
  GET /health  200 if the DB answers, 503 otherwise (used by HAProxy)
  GET /report  ~1.5 MB response (large packets: exposes MTU problems)
"""
import datetime
import http.server
import socket
import socketserver
import sys

import psycopg2

DB = dict(host="db1.dc.lab", dbname="shop", user="app", password="app", connect_timeout=3)
HOST = socket.gethostname()


def log(msg):
    print(f"{datetime.datetime.now().isoformat(timespec='seconds')} {HOST} {msg}", flush=True)


def query(sql):
    conn = psycopg2.connect(**DB)
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
            return cur.fetchone()[0]
    finally:
        conn.close()


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, code, body, ctype="text/plain"):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            log(f"client {self.client_address[0]} went away before the response was sent")

    def do_GET(self):
        try:
            if self.path == "/health":
                query("SELECT 1")
                return self.reply(200, "ok\n")
            if self.path == "/":
                n = query("SELECT count(*) FROM orders")
                return self.reply(200, f"<h1>shop</h1><p>served by {HOST}, {n} orders</p>\n", "text/html")
            if self.path == "/report":
                n = query("SELECT count(*) FROM orders")
                line = f"{HOST} orders={n} " + "x" * 90 + "\n"
                return self.reply(200, line * 15000)
            return self.reply(404, "not found\n")
        except Exception as e:  # noqa: BLE001 - we want every DB error in the log
            err = str(e).strip().replace("\n", " | ")
            log(f"ERROR {self.path}: {type(e).__name__}: {err}")
            return self.reply(503 if self.path == "/health" else 500, f"error: {err}\n")

    def log_message(self, fmt, *args):
        log(f"{self.client_address[0]} {fmt % args}")


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    log("starting on 127.0.0.1:8080")
    try:
        Server(("127.0.0.1", 8080), Handler).serve_forever()
    except Exception as e:  # noqa: BLE001
        log(f"FATAL {e}")
        sys.exit(1)
