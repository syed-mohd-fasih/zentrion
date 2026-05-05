"""Simulates credential stuffing: requests with bad/missing auth tokens."""
import argparse
import time
import requests

BAD_TOKENS = [
    "Bearer invalid-token-12345",
    "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.expired.signature",
    "Bearer",
    "Basic dXNlcjp3cm9uZ3Bhc3M=",  # user:wrongpass
    "",
]

AUTH_ENDPOINTS = [
    "/api/v1/auth/me",
    "/api/v1/admin",
    "/api/v1/users",
    "/api/v1/settings",
]


def run(base_url: str, duration: int):
    end = time.time() + duration
    sent = 0
    i = 0
    while time.time() < end:
        token = BAD_TOKENS[i % len(BAD_TOKENS)]
        path = AUTH_ENDPOINTS[i % len(AUTH_ENDPOINTS)]
        headers = {"Authorization": token} if token else {}
        try:
            requests.get(base_url.rstrip("/") + path, headers=headers, timeout=5)
            sent += 1
        except Exception:
            pass
        i += 1
        time.sleep(0.3)
    print(f"[unauthorized_access] Sent {sent} requests with bad/missing auth")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost/")
    parser.add_argument("--duration", type=int, default=60)
    args = parser.parse_args()
    run(args.url, args.duration)
