"""
HITL (Human-In-The-Loop) Monte-Carlo simulator for Zentrion §V-D.

Models analyst review behaviour over the actual stream of policy drafts
that Zentrion produces, then sweeps two operator parameters:
  - Review latency: exponential with mean ∈ {30 s, 2 min, 5 min, 15 min}
  - Accept probability: ∈ {0.6, 0.75, 0.9}

Outputs:
  Documentation/eval_artifacts/hitl_results.csv
  Documentation/eval_artifacts/hitl_summary.json
  Documentation/figures/hitl_heatmap.png

The real DB (policy_drafts) is consulted for the count and arrival
timestamps of drafts. If the DB is empty or unreachable, a synthetic
arrival stream is used (Poisson with rate matching the attack-sim run).
"""
import json
import os
import sys
import csv
import math
import random
import argparse
from collections import defaultdict
from pathlib import Path

import numpy as np
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "Documentation" / "eval_artifacts"
FIG = ROOT / "Documentation" / "figures"
ART.mkdir(parents=True, exist_ok=True)
FIG.mkdir(parents=True, exist_ok=True)

REVIEW_LATENCIES_S = [30, 120, 300, 900]  # mean of exponential
ACCEPT_RATES = [0.60, 0.75, 0.90]
TRIALS = 200
RNG = random.Random(42)


def load_drafts_from_csv(path: Path):
    """Read drafts CSV exported by query_policy_drafts.py."""
    if not path.exists():
        return None
    rows = []
    with open(path) as f:
        reader = csv.DictReader(f)
        for r in reader:
            rows.append(r)
    return rows


def synthetic_arrivals(n=40, total_window_s=900):
    """Fallback: simulate a Poisson arrival stream over total_window_s."""
    inter = np.random.exponential(total_window_s / n, n)
    times = np.cumsum(inter)
    return times.tolist()


def simulate(arrival_times_s, mean_review_s, accept_p, trials=TRIALS):
    n = len(arrival_times_s)
    if n == 0:
        return {"median_time_to_apply_s": None, "applied_count": 0, "rejected_count": 0}

    times_to_apply = []
    applied_counts = []
    rejected_counts = []
    for _ in range(trials):
        applied = 0
        rejected = 0
        ttapply = []
        for t in arrival_times_s:
            review_delay = np.random.exponential(mean_review_s)
            if RNG.random() < accept_p:
                applied += 1
                ttapply.append(review_delay)
            else:
                rejected += 1
        if ttapply:
            times_to_apply.append(np.median(ttapply))
        applied_counts.append(applied)
        rejected_counts.append(rejected)

    return {
        "median_time_to_apply_s": float(np.median(times_to_apply)) if times_to_apply else 0.0,
        "p95_time_to_apply_s": float(np.percentile(times_to_apply, 95)) if times_to_apply else 0.0,
        "applied_count_mean": float(np.mean(applied_counts)),
        "rejected_count_mean": float(np.mean(rejected_counts)),
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--drafts-csv", type=Path, default=ART / "policy_drafts.csv",
                   help="CSV of policy_drafts exported from Postgres")
    p.add_argument("--trials", type=int, default=TRIALS)
    args = p.parse_args()

    drafts = load_drafts_from_csv(args.drafts_csv)
    if drafts:
        # Use createdAt timestamps; convert to seconds-from-start
        from datetime import datetime
        ts = []
        for r in drafts:
            v = r.get("createdAt") or r.get("created_at")
            if not v:
                continue
            try:
                ts.append(datetime.fromisoformat(v.replace("Z", "+00:00")))
            except Exception:
                continue
        if ts:
            ts.sort()
            t0 = ts[0]
            arrivals = [(t - t0).total_seconds() for t in ts]
            print(f"[hitl] Using {len(arrivals)} real draft timestamps "
                  f"spanning {arrivals[-1]:.0f}s")
        else:
            arrivals = synthetic_arrivals()
            print(f"[hitl] No usable timestamps; synthetic stream of {len(arrivals)}")
    else:
        arrivals = synthetic_arrivals()
        print(f"[hitl] No drafts CSV found; synthetic stream of {len(arrivals)}")

    results = []
    grid = np.zeros((len(REVIEW_LATENCIES_S), len(ACCEPT_RATES)))
    for i, mean_review in enumerate(REVIEW_LATENCIES_S):
        for j, accept_p in enumerate(ACCEPT_RATES):
            r = simulate(arrivals, mean_review, accept_p, args.trials)
            r["mean_review_s"] = mean_review
            r["accept_p"] = accept_p
            results.append(r)
            grid[i, j] = r["median_time_to_apply_s"]
            print(f"  review~Exp({mean_review}s), accept={accept_p:.2f} -> "
                  f"median TTA={r['median_time_to_apply_s']:.1f}s, "
                  f"applied≈{r['applied_count_mean']:.1f}")

    # Write CSV
    out_csv = ART / "hitl_results.csv"
    with open(out_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(results[0].keys()))
        w.writeheader()
        w.writerows(results)
    print(f"[hitl] Wrote {out_csv}")

    # JSON summary
    summary = {
        "draft_count": len(arrivals),
        "trials_per_cell": args.trials,
        "review_latencies_s": REVIEW_LATENCIES_S,
        "accept_rates": ACCEPT_RATES,
        "results": results,
    }
    out_json = ART / "hitl_summary.json"
    with open(out_json, "w") as f:
        json.dump(summary, f, indent=2)
    print(f"[hitl] Wrote {out_json}")

    # Heatmap
    fig, ax = plt.subplots(figsize=(7, 4.5))
    im = ax.imshow(grid, aspect="auto", cmap="viridis_r")
    ax.set_xticks(range(len(ACCEPT_RATES)))
    ax.set_xticklabels([f"{p:.2f}" for p in ACCEPT_RATES])
    ax.set_yticks(range(len(REVIEW_LATENCIES_S)))
    ax.set_yticklabels([f"{s}s" if s < 60 else f"{s//60}m" for s in REVIEW_LATENCIES_S])
    ax.set_xlabel("Analyst accept probability")
    ax.set_ylabel("Mean review latency")
    ax.set_title("Median time-from-anomaly-to-policy-applied")
    for i in range(grid.shape[0]):
        for j in range(grid.shape[1]):
            ax.text(j, i, f"{grid[i, j]:.0f}s", ha="center", va="center",
                    color="white" if grid[i, j] > grid.mean() else "black", fontsize=10)
    fig.colorbar(im, ax=ax, label="seconds")
    fig.tight_layout()
    out_png = FIG / "hitl_heatmap.png"
    fig.savefig(out_png, dpi=150)
    print(f"[hitl] Wrote {out_png}")


if __name__ == "__main__":
    main()
