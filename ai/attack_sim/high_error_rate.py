"""Simulates high error rate: requests to non-existent paths."""
import argparse
import time
import requests
import random
import string


def random_path():
    return "/" + "".join(random.choices(string.ascii_lowercase, k=random.randint(4, 12)))


def run(base_url: str, duration: int, rps: int = 5):
    end = time.time() + duration
    sent = 0
    interval = 1.0 / rps
    while time.time() < end:
        try:
            requests.get(base_url.rstrip("/") + random_path(), timeout=5)
            sent += 1
        except Exception:
            pass
        time.sleep(interval)
    print(f"[high_error_rate] Sent {sent} requests to non-existent paths")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost/")
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--rps", type=int, default=5)
    args = parser.parse_args()
    run(args.url, args.duration, args.rps)
