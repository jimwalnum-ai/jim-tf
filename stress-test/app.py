import math
import multiprocessing
import os
import signal
import threading
import time
from dataclasses import dataclass, field

import psutil
from flask import Flask, jsonify, request

app = Flask(__name__)


@dataclass
class StressState:
    active: bool = False
    cpu_target: int = 0
    memory_mb: int = 0
    duration: int = 0
    start_time: float = 0.0
    cpu_workers: list = field(default_factory=list)
    memory_block: bytearray | None = None
    lock: threading.Lock = field(default_factory=threading.Lock)
    stop_timer: threading.Timer | None = None


state = StressState()


def cpu_burn():
    """Tight loop that keeps a single core near 100%."""
    while True:
        math.sqrt(random_ish_number())


_counter = 0


def random_ish_number():
    """Cheap pseudo-random without importing random (keeps the loop tight)."""
    global _counter
    _counter += 1
    return (_counter * 1103515245 + 12345) & 0x7FFFFFFF


def allocate_memory(mb: int) -> bytearray:
    """Allocate a bytearray of the given size and touch every page."""
    size = mb * 1024 * 1024
    block = bytearray(size)
    page_size = 4096
    for i in range(0, size, page_size):
        block[i] = 1
    return block


def stop_stress():
    with state.lock:
        for p in state.cpu_workers:
            if p.is_alive():
                p.terminate()
                p.join(timeout=2)
        state.cpu_workers.clear()
        state.memory_block = None
        state.active = False
        state.cpu_target = 0
        state.memory_mb = 0
        state.duration = 0
        state.start_time = 0.0
        if state.stop_timer:
            state.stop_timer.cancel()
            state.stop_timer = None


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


@app.route("/metrics", methods=["GET"])
def metrics():
    process = psutil.Process(os.getpid())
    children = process.children(recursive=True)

    total_cpu = process.cpu_percent(interval=0.5)
    total_rss = process.memory_info().rss
    for child in children:
        try:
            total_cpu += child.cpu_percent(interval=0)
            total_rss += child.memory_info().rss
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    remaining = 0
    if state.active and state.duration > 0:
        elapsed = time.time() - state.start_time
        remaining = max(0, state.duration - elapsed)

    return jsonify({
        "stress_active": state.active,
        "cpu_target_percent": state.cpu_target,
        "memory_target_mb": state.memory_mb,
        "duration_seconds": state.duration,
        "remaining_seconds": round(remaining, 1),
        "measured_cpu_percent": round(total_cpu, 1),
        "measured_memory_mb": round(total_rss / (1024 * 1024), 1),
        "worker_count": len(state.cpu_workers),
    })


@app.route("/stress", methods=["POST"])
def start_stress():
    if state.active:
        return jsonify({"error": "Stress test already running. DELETE /stress first."}), 409

    cpu_percent = request.args.get("cpu", type=int, default=0)
    memory_mb = request.args.get("memory", type=int, default=0)
    duration = request.args.get("duration", type=int, default=60)

    if cpu_percent < 0 or cpu_percent > 100:
        return jsonify({"error": "cpu must be 0-100"}), 400
    if memory_mb < 0:
        return jsonify({"error": "memory must be >= 0"}), 400
    if duration < 1 or duration > 3600:
        return jsonify({"error": "duration must be 1-3600 seconds"}), 400

    available_cores = multiprocessing.cpu_count()
    num_workers = max(1, round(available_cores * cpu_percent / 100))

    with state.lock:
        state.active = True
        state.cpu_target = cpu_percent
        state.memory_mb = memory_mb
        state.duration = duration
        state.start_time = time.time()

        if cpu_percent > 0:
            for _ in range(num_workers):
                p = multiprocessing.Process(target=cpu_burn, daemon=True)
                p.start()
                state.cpu_workers.append(p)

        if memory_mb > 0:
            state.memory_block = allocate_memory(memory_mb)

        state.stop_timer = threading.Timer(duration, stop_stress)
        state.stop_timer.daemon = True
        state.stop_timer.start()

    return jsonify({
        "status": "started",
        "cpu_percent": cpu_percent,
        "memory_mb": memory_mb,
        "duration_seconds": duration,
        "cpu_workers_spawned": num_workers if cpu_percent > 0 else 0,
    }), 201


@app.route("/stress", methods=["GET"])
def get_stress():
    if not state.active:
        return jsonify({"status": "idle"}), 200

    elapsed = time.time() - state.start_time
    remaining = max(0, state.duration - elapsed)
    return jsonify({
        "status": "active",
        "cpu_percent": state.cpu_target,
        "memory_mb": state.memory_mb,
        "elapsed_seconds": round(elapsed, 1),
        "remaining_seconds": round(remaining, 1),
    })


@app.route("/stress", methods=["DELETE"])
def stop_stress_endpoint():
    if not state.active:
        return jsonify({"status": "already idle"}), 200
    stop_stress()
    return jsonify({"status": "stopped"}), 200


def handle_shutdown(signum, frame):
    stop_stress()
    raise SystemExit(0)


signal.signal(signal.SIGTERM, handle_shutdown)
signal.signal(signal.SIGINT, handle_shutdown)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
