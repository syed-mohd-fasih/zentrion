"""Simulates a single-IP burst: 50+ requests in 60s from one source IP."""
import argparse
import time
import requests

ATTACKER_IP = "198.51.100.42"


def run(base_url: str, duration: int, rps: int = 2):
    end = time.time() + duration
    sent = 0
    interval = 1.0 / rps
    while time.time() < end:
        try:
            requests.get(
                base_url.rstrip("/") + "/productpage",
                headers={"X-Forwarded-For": ATTACKER_IP},
                timeout=5,
            )
            sent += 1
        except Exception:
            pass
        time.sleep(interval)
    print(f"[suspicious_pattern] Sent {sent} requests from spoofed IP {ATTACKER_IP}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost/")
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--rps", type=int, default=2)
    args = parser.parse_args()
    run(args.url, args.duration, args.rps)
