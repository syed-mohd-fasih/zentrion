"""
Train XGBoost anomaly classifier and export to ONNX.

Usage:
  python train.py

Input:  data/training_data.csv
Output: model/anomaly_detector.onnx
        model/label_encoder.json
"""

import os
import json
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import classification_report
from xgboost import XGBClassifier
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType

FEATURES = [
    "request_count", "error_rate", "p95_latency_ms", "mean_latency_ms",
    "unique_source_ips", "unique_paths", "req_per_second", "status_4xx_rate",
    "status_5xx_rate", "max_latency_ms", "suspicious_ip_count",
    "sensitive_path_count", "mean_request_size", "mean_response_size",
    "unique_dest_services", "p99_latency_ms",
]

MODEL_DIR = os.path.join(os.path.dirname(__file__), "model")
DATA_PATH = os.path.join(os.path.dirname(__file__), "data", "training_data.csv")


def main():
    os.makedirs(MODEL_DIR, exist_ok=True)

    print("Loading training data...")
    df = pd.read_csv(DATA_PATH)
    print(f"  {len(df)} windows, {df['label'].nunique()} unique classes")
    print(df["label"].value_counts().to_string())

    X = df[FEATURES].fillna(0).astype(np.float32).values
    le = LabelEncoder()
    y = le.fit_transform(df["label"].values)

    # Save label mapping for the serving layer.
    label_map = {int(i): str(c) for i, c in enumerate(le.classes_)}
    with open(os.path.join(MODEL_DIR, "label_encoder.json"), "w") as f:
        json.dump(label_map, f, indent=2)
    print(f"  Labels: {label_map}")

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    print("\nTraining XGBoost classifier...")
    clf = XGBClassifier(
        n_estimators=200,
        max_depth=6,
        learning_rate=0.1,
        use_label_encoder=False,
        eval_metric="mlogloss",
        random_state=42,
        n_jobs=-1,
    )
    clf.fit(X_train, y_train, eval_set=[(X_test, y_test)], verbose=50)

    y_pred = clf.predict(X_test)
    print("\nClassification Report:")
    print(classification_report(y_test, y_pred, target_names=[label_map[i] for i in range(len(label_map))]))

    print("\nExporting to ONNX...")
    initial_type = [("float_input", FloatTensorType([None, len(FEATURES)]))]
    onnx_model = convert_sklearn(clf, initial_types=initial_type, target_opset=17)

    onnx_path = os.path.join(MODEL_DIR, "anomaly_detector.onnx")
    with open(onnx_path, "wb") as f:
        f.write(onnx_model.SerializeToString())
    print(f"Model saved to {onnx_path}")


if __name__ == "__main__":
    main()
