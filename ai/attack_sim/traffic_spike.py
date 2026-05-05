"""Simulates a traffic spike: 20 threads flooding /productpage for 60s."""
import argparse
import time
import threading
import requests


def flood(base_url: str, duration: int, results: list):
    end = time.time() + duration
    count = 0
    while time.time() < end:
        try:
            requests.get(base_url.rstrip("/") + "/productpage", timeout=5)
            count += 1
        except Exception:
            pass
    results.append(count)


def run(base_url: str, duration: int, threads: int = 20):
    results = []
    workers = [threading.Thread(target=flood, args=(base_url, duration, results)) for _ in range(threads)]
    for w in workers:
        w.start()
    for w in workers:
        w.join()
    print(f"[traffic_spike] {sum(results)} requests sent by {threads} threads over {duration}s")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost/")
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--threads", type=int, default=20)
    args = parser.parse_args()
    run(args.url, args.duration, args.threads)
