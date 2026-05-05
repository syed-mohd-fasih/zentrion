"""Simulates reconnaissance: probing sensitive endpoints."""
import argparse
import time
import requests

SENSITIVE_PATHS = [
    "/admin", "/admin/login", "/admin/config",
    "/.env", "/.env.local", "/.env.production",
    "/config", "/config.json", "/configuration",
    "/debug", "/debug/vars",
    "/actuator", "/actuator/health", "/actuator/env",
    "/metrics", "/prometheus",
    "/api/admin", "/api/internal",
]


def run(base_url: str, rounds: int = 3):
    sent = 0
    for _ in range(rounds):
        for path in SENSITIVE_PATHS:
            try:
                r = requests.get(base_url.rstrip("/") + path, timeout=5)
                sent += 1
                print(f"  {path} -> {r.status_code}")
            except Exception as e:
                print(f"  {path} -> error: {e}")
            time.sleep(0.5)
    print(f"[new_endpoint] Probed {sent} sensitive paths across {rounds} rounds")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost/")
    parser.add_argument("--rounds", type=int, default=3)
    args = parser.parse_args()
    run(args.url, args.rounds)
