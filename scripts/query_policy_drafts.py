"""
Pull the policy_drafts table out of the running Postgres into a CSV
and compute the real HITL workflow stats for the paper.

Usage (via kubectl exec on the running orchestrator):
  python3 scripts/query_policy_drafts.py
"""
import csv
import json
import subprocess
import sys
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "Documentation" / "eval_artifacts"
ART.mkdir(parents=True, exist_ok=True)

PG_POD = "postgresql-59d6cbc5b6-qr2f5"
NAMESPACE = "zentrion-system"

DRAFTS_SQL = (
    "\\copy (SELECT id, status, service, \"createdAt\", \"appliedAt\", "
    "\"approvedBy\", \"rejectedBy\", \"rejectionReason\", \"anomalyId\" "
    "FROM policy_drafts ORDER BY \"createdAt\") TO STDOUT WITH CSV HEADER"
)

ANOMALIES_SQL = (
    "\\copy (SELECT id, type, severity, service, timestamp, \"createdAt\" "
    "FROM anomalies ORDER BY \"createdAt\") TO STDOUT WITH CSV HEADER"
)


def run_psql(sql: str) -> str:
    cmd = [
        "kubectl", "exec", "-n", NAMESPACE, PG_POD, "-c", "postgresql",
        "--", "psql", "-U", "zentrion", "-d", "zentrion", "-c", sql,
    ]
    out = subprocess.run(cmd, capture_output=True, text=True, env={
        **__import__("os").environ, "PGPASSWORD": "zentrion",
    })
    if out.returncode != 0:
        sys.exit(f"psql failed: {out.stderr}")
    return out.stdout


def main():
    print("[hitl] dumping policy_drafts...")
    drafts_csv = run_psql(DRAFTS_SQL)
    (ART / "policy_drafts.csv").write_text(drafts_csv)
    print(f"  wrote {ART / 'policy_drafts.csv'} "
          f"({drafts_csv.count(chr(10))-1} rows)")

    print("[hitl] dumping anomalies...")
    anom_csv = run_psql(ANOMALIES_SQL)
    (ART / "anomalies.csv").write_text(anom_csv)
    print(f"  wrote {ART / 'anomalies.csv'} "
          f"({anom_csv.count(chr(10))-1} rows)")

    # Compute summary
    rows = list(csv.DictReader((ART / "policy_drafts.csv").open()))
    by_status = {}
    apply_times_s = []
    review_times_s = []
    from datetime import datetime

    def parse(v):
        if not v:
            return None
        try:
            return datetime.fromisoformat(v.replace("Z", "+00:00"))
        except Exception:
            return None

    for r in rows:
        st = r.get("status", "")
        by_status[st] = by_status.get(st, 0) + 1
        ca, aa = parse(r["createdAt"]), parse(r["appliedAt"])
        if ca and aa:
            apply_times_s.append((aa - ca).total_seconds())
            review_times_s.append((aa - ca).total_seconds())

    def stats(xs):
        if not xs:
            return None
        xs = sorted(xs)
        return {
            "n": len(xs),
            "median_s": median(xs),
            "p95_s": xs[max(0, int(0.95 * len(xs)) - 1)],
            "mean_s": sum(xs) / len(xs),
            "min_s": xs[0],
            "max_s": xs[-1],
        }

    anomalies_rows = list(csv.DictReader((ART / "anomalies.csv").open()))
    anom_types = {}
    for r in anomalies_rows:
        anom_types[r["type"]] = anom_types.get(r["type"], 0) + 1

    summary = {
        "drafts_total": len(rows),
        "drafts_by_status": by_status,
        "anomalies_total": len(anomalies_rows),
        "anomalies_by_type": anom_types,
        "review_time_s": stats(review_times_s),
        "apply_time_s": stats(apply_times_s),
    }
    print(json.dumps(summary, indent=2))
    (ART / "hitl_real_summary.json").write_text(json.dumps(summary, indent=2))
    print(f"  wrote {ART / 'hitl_real_summary.json'}")


if __name__ == "__main__":
    main()
