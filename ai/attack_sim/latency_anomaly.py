"""Simulates latency anomaly: concurrent requests to overwhelm slow endpoints."""
import argparse
import time
import threading
import requests


def slow_request(url: str, results: list):
    try:
        r = requests.get(url, timeout=30)
        results.append(r.elapsed.total_seconds() * 1000)
    except Exception:
        results.append(30000)


def run(base_url: str, duration: int, concurrency: int = 30):
    end = time.time() + duration
    url = base_url.rstrip("/") + "/productpage"
    total = 0
    while time.time() < end:
        results = []
        workers = [threading.Thread(target=slow_request, args=(url, results)) for _ in range(concurrency)]
        for w in workers:
            w.start()
        for w in workers:
            w.join()
        total += len(results)
        if results:
            avg_ms = sum(results) / len(results)
            print(f"  Batch avg latency: {avg_ms:.0f}ms")
        time.sleep(2)
    print(f"[latency_anomaly] Sent {total} concurrent requests over {duration}s")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost/")
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--concurrency", type=int, default=30)
    args = parser.parse_args()
    run(args.url, args.duration, args.concurrency)
