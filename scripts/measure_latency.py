"""
Latency overhead harness for Zentrion §V-C.

Issues N HTTP requests against the productpage endpoint and records
per-request latency. Operator switches the detection mode between runs
via the dashboard settings page (or REST PATCH), so we just need to
hit the gateway and measure.

Usage:
  python3 scripts/measure_latency.py --url http://127.0.0.1:18080/productpage \\
        --label baseline --n 600 --concurrency 4

Output: appends to Documentation/eval_artifacts/latency_runs.csv
        (one row per request) and prints summary stats.
"""
import argparse
import csv
import statistics
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Documentation" / "eval_artifacts" / "latency_runs.csv"
OUT.parent.mkdir(parents=True, exist_ok=True)


def one(url, label):
    t0 = time.perf_counter()
    try:
        r = requests.get(url, timeout=10)
        dt = (time.perf_counter() - t0) * 1000.0
        return {"label": label, "ms": round(dt, 3), "status": r.status_code}
    except Exception as e:
        return {"label": label, "ms": -1.0, "status": f"ERR:{e.__class__.__name__}"}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True)
    p.add_argument("--label", required=True,
                   help="run label, e.g. baseline | rules | ai")
    p.add_argument("--n", type=int, default=600)
    p.add_argument("--concurrency", type=int, default=4)
    args = p.parse_args()

    # Warm up so JIT/connection-pool effects don't skew the first samples.
    for _ in range(10):
        try:
            requests.get(args.url, timeout=10)
        except Exception:
            pass

    rows = []
    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futures = [pool.submit(one, args.url, args.label) for _ in range(args.n)]
        for f in as_completed(futures):
            rows.append(f.result())

    ms = [r["ms"] for r in rows if r["ms"] > 0]
    ms.sort()
    n = len(ms)
    if n == 0:
        print(f"[{args.label}] all requests failed")
        return
    mean = statistics.fmean(ms)
    p50 = ms[n // 2]
    p95 = ms[int(0.95 * n) - 1]
    p99 = ms[int(0.99 * n) - 1]
    print(f"[{args.label}] n={n} mean={mean:.2f}ms p50={p50:.2f}ms "
          f"p95={p95:.2f}ms p99={p99:.2f}ms")

    write_header = not OUT.exists()
    with open(OUT, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["label", "ms", "status"])
        if write_header:
            w.writeheader()
        w.writerows(rows)
    print(f"  appended {len(rows)} rows to {OUT}")


if __name__ == "__main__":
    main()
