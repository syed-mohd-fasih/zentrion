"""Simulates realistic baseline traffic to Bookinfo."""
import argparse
import random
import time
import requests

ENDPOINTS = [
    "/productpage",
    "/productpage?u=normal",
    "/api/v1/products",
    "/api/v1/products/0",
    "/api/v1/products/1",
    "/api/v1/products/2",
]

AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
]


def run(base_url: str, duration: int):
    end = time.time() + duration
    sent = 0
    while time.time() < end:
        url = base_url.rstrip("/") + random.choice(ENDPOINTS)
        try:
            requests.get(url, headers={"User-Agent": random.choice(AGENTS)}, timeout=5)
            sent += 1
        except Exception:
            pass
        time.sleep(random.uniform(0.5, 3.0))
    print(f"[normal_traffic] Sent {sent} requests over {duration}s")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost/", help="Base URL of Bookinfo")
    parser.add_argument("--duration", type=int, default=300, help="Duration in seconds")
    args = parser.parse_args()
    run(args.url, args.duration)
