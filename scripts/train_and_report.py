"""
Wrapper around ai/anomaly_detector/train.py that also exports a JSON
training report (per-class P/R/F1, confusion matrix, feature importance)
for the paper.

Reads:  ai/anomaly_detector/data/training_data.csv
Writes: ai/anomaly_detector/model/anomaly_detector.joblib
        ai/anomaly_detector/model/label_encoder.json
        Documentation/eval_artifacts/training_report.json
        Documentation/eval_artifacts/classification_report.txt
"""
import json
import os
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import (
    classification_report,
    confusion_matrix,
)
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from xgboost import XGBClassifier

ROOT = Path(__file__).resolve().parent.parent
AI = ROOT / "ai" / "anomaly_detector"
ART = ROOT / "Documentation" / "eval_artifacts"
ART.mkdir(parents=True, exist_ok=True)

FEATURES = [
    "request_count", "error_rate", "p95_latency_ms", "mean_latency_ms",
    "unique_source_ips", "unique_paths", "req_per_second", "status_4xx_rate",
    "status_5xx_rate", "max_latency_ms", "suspicious_ip_count",
    "sensitive_path_count", "mean_request_size", "mean_response_size",
    "unique_dest_services", "p99_latency_ms",
]


def main():
    csv_path = AI / "data" / "training_data.csv"
    if not csv_path.exists():
        sys.exit(f"training data not found: {csv_path}")
    df = pd.read_csv(csv_path)
    print(f"[train] rows={len(df)}, classes={df['label'].value_counts().to_dict()}")

    # Drop classes with too few samples for a meaningful train/test split.
    counts = df["label"].value_counts()
    keep = counts[counts >= 2].index
    dropped = counts[counts < 2].to_dict()
    if dropped:
        print(f"[train] dropping singleton classes (n<2): {dropped}")
    df = df[df["label"].isin(keep)].reset_index(drop=True)

    X = df[FEATURES].fillna(0).astype(np.float32).values
    le = LabelEncoder()
    y = le.fit_transform(df["label"].values)
    labels = list(le.classes_)
    n_classes = len(labels)

    if n_classes < 2:
        sys.exit(f"[train] need ≥2 classes after filtering, got {n_classes}: {labels}")

    # Stratify if every kept class has ≥2 samples (always true after filter).
    test_size = 0.3 if len(df) < 30 else 0.2
    X_tr, X_te, y_tr, y_te = train_test_split(
        X, y, test_size=test_size, random_state=42, stratify=y,
    )

    clf = XGBClassifier(
        n_estimators=300,
        max_depth=6,
        learning_rate=0.1,
        objective="binary:logistic" if n_classes == 2 else "multi:softprob",
        num_class=None if n_classes == 2 else n_classes,
        eval_metric="logloss" if n_classes == 2 else "mlogloss",
        random_state=42,
        n_jobs=-1,
        tree_method="hist",
    )
    clf.fit(X_tr, y_tr, verbose=False)

    y_pred = clf.predict(X_te)
    report_dict = classification_report(
        y_te, y_pred, target_names=labels, output_dict=True, zero_division=0,
    )
    report_str = classification_report(
        y_te, y_pred, target_names=labels, zero_division=0,
    )
    print("\n" + report_str)

    cm = confusion_matrix(y_te, y_pred, labels=range(n_classes)).tolist()
    booster = clf.get_booster()
    raw_imp = booster.get_score(importance_type="gain")
    # XGBoost names features f0, f1, ... — map back to our names
    importance = {}
    for k, v in raw_imp.items():
        idx = int(k[1:])
        importance[FEATURES[idx]] = float(v)
    for f in FEATURES:
        importance.setdefault(f, 0.0)

    out = {
        "n_rows": int(len(df)),
        "n_features": len(FEATURES),
        "labels": labels,
        "label_counts": df["label"].value_counts().to_dict(),
        "train_test_split": {"train": int(len(X_tr)), "test": int(len(X_te))},
        "classification_report": report_dict,
        "confusion_matrix": cm,
        "feature_importance": importance,
    }
    (ART / "training_report.json").write_text(json.dumps(out, indent=2, default=str))
    (ART / "classification_report.txt").write_text(report_str)

    # Persist model with the same artefact names serve.py expects
    model_dir = AI / "model"
    model_dir.mkdir(exist_ok=True)
    joblib.dump(clf, model_dir / "anomaly_detector.joblib")
    with open(model_dir / "label_encoder.json", "w") as f:
        json.dump({int(i): str(c) for i, c in enumerate(le.classes_)}, f, indent=2)
    print(f"[train] wrote {ART / 'training_report.json'}")


if __name__ == "__main__":
    main()
