"""
Export telemetry_logs from PostgreSQL into a feature CSV for model training.

Groups logs into 5-minute windows per service and computes 16 features.
Labels each window using the anomalies table (weak supervision).

Usage:
  python data/export_from_postgres.py

Environment variables (or set in .env):
  DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
"""

import os
import sys
import psycopg2
import pandas as pd
import numpy as np
from dotenv import load_dotenv

load_dotenv()

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "zentrion"),
    "user": os.getenv("DB_USER", "zentrion"),
    "password": os.getenv("DB_PASSWORD", "zentrion"),
}

SUSPICIOUS_IPS = {"192.0.2.1", "198.51.100.42", "203.0.113.99"}
SENSITIVE_PATHS = ["/admin", "/.env", "/config", "/debug", "/actuator", "/metrics"]


def fetch_logs(conn) -> pd.DataFrame:
    query = """
        SELECT
            id, timestamp, source, "sourceIp" AS source_ip,
            method, path, status, "latencyMs" AS latency_ms,
            service, "destService" AS dest_service,
            "requestSize" AS request_size, "responseSize" AS response_size
        FROM telemetry_logs
        ORDER BY timestamp ASC
    """
    return pd.read_sql(query, conn)


def fetch_anomaly_labels(conn) -> dict:
    """
    Returns a dict: log_id -> anomaly_type for all logs associated with anomalies.
    """
    query = """
        SELECT "associatedLogs", type
        FROM anomalies
    """
    df = pd.read_sql(query, conn)
    label_map = {}
    for _, row in df.iterrows():
        if row["associatedLogs"]:
            for log_id in row["associatedLogs"]:
                label_map[log_id] = row["type"]
    return label_map


def compute_features(group: pd.DataFrame, label_map: dict, window_seconds: int = 300) -> dict:
    n = len(group)
    latencies = group["latency_ms"].sort_values().values
    errors = group[group["status"] >= 400]
    logs_4xx = group[(group["status"] >= 400) & (group["status"] < 500)]
    logs_5xx = group[group["status"] >= 500]

    p95 = float(np.percentile(latencies, 95)) if n > 0 else 0
    p99 = float(np.percentile(latencies, 99)) if n > 0 else 0

    suspicious_ip_count = group["source_ip"].isin(SUSPICIOUS_IPS).sum()
    sensitive_path_count = group["path"].apply(
        lambda p: any(s in str(p) for s in SENSITIVE_PATHS)
    ).sum()

    # Label: use the most frequent anomaly type for logs in this window, else NORMAL
    log_ids = set(group["id"].values)
    window_labels = [label_map[lid] for lid in log_ids if lid in label_map]
    if window_labels:
        from collections import Counter
        label = Counter(window_labels).most_common(1)[0][0]
    else:
        label = "NORMAL"

    return {
        "service": group["service"].iloc[0],
        "request_count": n,
        "error_rate": len(errors) / n if n > 0 else 0,
        "p95_latency_ms": p95,
        "mean_latency_ms": float(latencies.mean()) if n > 0 else 0,
        "unique_source_ips": group["source_ip"].nunique(),
        "unique_paths": group["path"].nunique(),
        "req_per_second": n / window_seconds if window_seconds > 0 else 0,
        "status_4xx_rate": len(logs_4xx) / n if n > 0 else 0,
        "status_5xx_rate": len(logs_5xx) / n if n > 0 else 0,
        "max_latency_ms": float(latencies.max()) if n > 0 else 0,
        "suspicious_ip_count": int(suspicious_ip_count),
        "sensitive_path_count": int(sensitive_path_count),
        "mean_request_size": float(group["request_size"].fillna(0).mean()),
        "mean_response_size": float(group["response_size"].fillna(0).mean()),
        "unique_dest_services": group["dest_service"].dropna().nunique(),
        "p99_latency_ms": p99,
        "label": label,
    }


def main():
    print("Connecting to PostgreSQL...")
    conn = psycopg2.connect(**DB_CONFIG)

    print("Fetching telemetry logs...")
    logs = fetch_logs(conn)
    print(f"  Loaded {len(logs)} log rows")

    if len(logs) == 0:
        print("No logs found. Run attack simulation scripts first.")
        sys.exit(1)

    print("Fetching anomaly labels...")
    label_map = fetch_anomaly_labels(conn)
    print(f"  {len(label_map)} log IDs have anomaly labels")

    conn.close()

    # Bucket logs into windows. 1-min buckets give more samples on short
    # experiments; override with WINDOW=5min for the original behaviour.
    window_size = os.getenv("WINDOW", "1min")
    logs["timestamp"] = pd.to_datetime(logs["timestamp"], utc=True)
    logs["window"] = logs["timestamp"].dt.floor(window_size)

    print(f"Computing features per (service, {window_size} window)...")
    window_seconds = int(pd.Timedelta(window_size).total_seconds())
    rows = []
    for (service, window), group in logs.groupby(["service", "window"]):
        rows.append(compute_features(group, label_map, window_seconds))

    df = pd.DataFrame(rows)
    out_path = os.path.join(os.path.dirname(__file__), "training_data.csv")
    df.to_csv(out_path, index=False)

    label_counts = df["label"].value_counts()
    print(f"\nExported {len(df)} windows to {out_path}")
    print("Label distribution:")
    print(label_counts.to_string())


if __name__ == "__main__":
    main()
