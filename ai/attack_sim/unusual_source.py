"""Simulates unusual source: requests spoofing known-bad IPs via X-Forwarded-For."""
import argparse
import time
import requests

SUSPICIOUS_IPS = ["192.0.2.1", "198.51.100.42", "203.0.113.99"]


def run(base_url: str, duration: int, rps: int = 2):
    end = time.time() + duration
    sent = 0
    i = 0
    interval = 1.0 / rps
    while time.time() < end:
        ip = SUSPICIOUS_IPS[i % len(SUSPICIOUS_IPS)]
        try:
            requests.get(
                base_url.rstrip("/") + "/productpage",
                headers={"X-Forwarded-For": ip, "X-Real-IP": ip},
                timeout=5,
            )
            sent += 1
        except Exception:
            pass
        i += 1
        time.sleep(interval)
    print(f"[unusual_source] Sent {sent} requests from suspicious IPs: {SUSPICIOUS_IPS}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost/")
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--rps", type=int, default=2)
    args = parser.parse_args()
    run(args.url, args.duration, args.rps)
