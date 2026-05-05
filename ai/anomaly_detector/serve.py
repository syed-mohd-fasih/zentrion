"""
FastAPI ML inference server for anomaly detection.

Loads the trained ONNX model at startup and serves predictions.

Usage:
  uvicorn serve:app --host 0.0.0.0 --port 8000

Endpoints:
  GET  /health   — liveness check
  POST /detect   — run inference on a window of feature vectors
"""

import os
import json
import numpy as np
import onnxruntime as ort
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Any

MODEL_DIR = os.path.join(os.path.dirname(__file__), "model")
ONNX_PATH = os.path.join(MODEL_DIR, "anomaly_detector.onnx")
LABEL_PATH = os.path.join(MODEL_DIR, "label_encoder.json")

FEATURES = [
    "request_count", "error_rate", "p95_latency_ms", "mean_latency_ms",
    "unique_source_ips", "unique_paths", "req_per_second", "status_4xx_rate",
    "status_5xx_rate", "max_latency_ms", "suspicious_ip_count",
    "sensitive_path_count", "mean_request_size", "mean_response_size",
    "unique_dest_services", "p99_latency_ms",
]

app = FastAPI(title="Zentrion Anomaly Detector")

# Load at startup — not per-request.
_session: ort.InferenceSession | None = None
_label_map: dict[str, str] = {}
_input_name: str = ""


@app.on_event("startup")
def load_model():
    global _session, _label_map, _input_name
    if not os.path.exists(ONNX_PATH):
        raise RuntimeError(f"Model not found at {ONNX_PATH}. Run train.py first.")
    _session = ort.InferenceSession(ONNX_PATH, providers=["CPUExecutionProvider"])
    _input_name = _session.get_inputs()[0].name
    with open(LABEL_PATH) as f:
        _label_map = json.load(f)
    print(f"Model loaded: {ONNX_PATH}")
    print(f"Classes: {_label_map}")


class DetectRequest(BaseModel):
    window_logs: list[dict[str, Any]]


class DetectionResult(BaseModel):
    service: str
    anomalyType: str
    confidence: float
    details: str
    features: dict[str, float]


class DetectResponse(BaseModel):
    results: list[DetectionResult]


@app.get("/health")
def health():
    return {"status": "ok", "model_loaded": _session is not None}


@app.post("/detect", response_model=DetectResponse)
def detect(request: DetectRequest):
    if _session is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    results = []
    for log in request.window_logs:
        service = str(log.get("_service", log.get("service", "unknown")))
        features = {}
        for feat in FEATURES:
            features[feat] = float(log.get(feat, 0) or 0)

        X = np.array([[features[f] for f in FEATURES]], dtype=np.float32)
        output = _session.run(None, {_input_name: X})

        # output[0] = predicted class index, output[1] = probability dict
        pred_class = int(output[0][0])
        proba_dict = output[1][0] if len(output) > 1 else {}
        confidence = float(proba_dict.get(pred_class, 0.0)) if isinstance(proba_dict, dict) else 0.5

        anomaly_type = _label_map.get(str(pred_class), "UNKNOWN")
        if anomaly_type == "NORMAL":
            continue  # Skip normal windows

        results.append(DetectionResult(
            service=service,
            anomalyType=anomaly_type,
            confidence=confidence,
            details=f"ML model detected {anomaly_type} with {confidence:.0%} confidence",
            features=features,
        ))

    return DetectResponse(results=results)
