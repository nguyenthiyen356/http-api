import os
import random
import hashlib
import time

from flask import Flask, jsonify
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)

# ── Prometheus metrics ────────────────────────────────────────────────────────
# Auto-registers /metrics and tracks flask_http_request_total (Counter) and
# flask_http_request_duration_seconds (Histogram) for every route.
# Buckets tuned to the ~100 ms CPU-burn workload.
# https://github.com/rycus86/prometheus_flask_exporter
metrics = PrometheusMetrics(
    app,
    group_by="endpoint",
    buckets=[0.05, 0.075, 0.1, 0.125, 0.15, 0.2, 0.25, 0.5, 1.0],
)
metrics.info("app_info", "Quote API service", version="1.0.0")

# Custom counter required by the assignment
quotes_served = metrics.counter(
    "quotes_served_total",
    "Total number of /api/quote requests served",
)

QUOTES = [
    {"quote": "The only way to do great work is to love what you do.", "author": "Steve Jobs"},
    {"quote": "Innovation distinguishes between a leader and a follower.", "author": "Steve Jobs"},
    {"quote": "Life is what happens when you're busy making other plans.", "author": "John Lennon"},
    {"quote": "The future belongs to those who believe in the beauty of their dreams.", "author": "Eleanor Roosevelt"},
    {"quote": "It is during our darkest moments that we must focus to see the light.", "author": "Aristotle"},
    {"quote": "Spread love everywhere you go. Let no one ever come to you without leaving happier.", "author": "Mother Teresa"},
    {"quote": "When you reach the end of your rope, tie a knot in it and hang on.", "author": "Franklin D. Roosevelt"},
    {"quote": "Always remember that you are absolutely unique. Just like everyone else.", "author": "Margaret Mead"},
    {"quote": "Do not go where the path may lead; go instead where there is no path and leave a trail.", "author": "Ralph Waldo Emerson"},
    {"quote": "You will face many defeats in life, but never let yourself be defeated.", "author": "Maya Angelou"},
    {"quote": "In the end, it's not the years in your life that count. It's the life in your years.", "author": "Abraham Lincoln"},
    {"quote": "Never let the fear of striking out keep you from playing the game.", "author": "Babe Ruth"},
    {"quote": "Life is either a daring adventure or nothing at all.", "author": "Helen Keller"},
    {"quote": "Many of life's failures are people who did not realize how close they were to success.", "author": "Thomas A. Edison"},
    {"quote": "You have brains in your head. You have feet in your shoes. You can steer yourself any direction you choose.", "author": "Dr. Seuss"},
]

def cpu_burn(duration_seconds: float = 0.1) -> None:
    """Burn CPU for approximately the given duration (simulates real work)."""
    deadline = time.monotonic() + duration_seconds
    while time.monotonic() < deadline:
        hashlib.sha256(b"x" * 4096).digest()

@app.route("/healthz")
@metrics.do_not_track()
def healthz():
    return jsonify({"status": "ok"}), 200

@app.route("/readyz")
@metrics.do_not_track()
def readyz():
    return jsonify({"status": "ready"}), 200

@app.route("/api/quote")
@quotes_served
def api_quote():
    picked = random.choice(QUOTES)
    start = time.perf_counter()
    cpu_burn(0.1)                               # ~100 ms of real CPU work
    elapsed_ms = (time.perf_counter() - start) * 1000
    return jsonify({
        "quote": picked["quote"],
        "author": picked["author"],
        "processing_ms": round(elapsed_ms, 1),
    }), 200


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
