"""Demo service: environment-driven config, /health and Prometheus /metrics.

Contract for swapping in your own app: listen on :8000, answer GET /health with 200,
and (optionally) expose Prometheus metrics at /metrics.
"""
import os
import socket
import time

from flask import Flask, Response, g, jsonify, request
from prometheus_client import (CONTENT_TYPE_LATEST, Counter, Gauge, Histogram,
                               generate_latest)

app = Flask(__name__)

REQUESTS = Counter("app_http_requests_total", "HTTP requests",
                   ["method", "endpoint", "status"])
LATENCY = Histogram("app_http_request_duration_seconds", "Request latency",
                    ["endpoint"], buckets=(.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5))
INFO = Gauge("app_info", "Build info", ["version", "env"])
INFO.labels(os.getenv("APP_VERSION", "dev"), os.getenv("APP_ENV", "development")).set(1)


def cfg(name, default):
    return os.getenv(name, default)


@app.before_request
def _start():
    g.t0 = time.perf_counter()


@app.after_request
def _record(resp):
    if request.path != "/metrics":
        endpoint = request.url_rule.rule if request.url_rule else "unmatched"
        REQUESTS.labels(request.method, endpoint, resp.status_code).inc()
        LATENCY.labels(endpoint).observe(time.perf_counter() - g.t0)
    return resp


@app.get("/")
def index():
    return jsonify(message=cfg("APP_MESSAGE", "Hello from the capstone service"),
                   environment=cfg("APP_ENV", "development"),
                   version=cfg("APP_VERSION", "dev"),
                   host=socket.gethostname())


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


# Demo endpoints used to trigger alerts on purpose. Disabled unless ENABLE_DEMO_ENDPOINTS=true.
@app.get("/error")
def error():
    if cfg("ENABLE_DEMO_ENDPOINTS", "false").lower() != "true":
        return jsonify(error="not found"), 404
    return jsonify(error="simulated failure"), 500


@app.get("/slow")
def slow():
    if cfg("ENABLE_DEMO_ENDPOINTS", "false").lower() != "true":
        return jsonify(error="not found"), 404
    time.sleep(min(int(request.args.get("ms", "1500")), 3000) / 1000)
    return jsonify(status="slow ok")
