#!/usr/bin/env bash
# Reproducible end-to-end evaluation run for the Zentrion paper.
# Assumes ./deploy.sh has already brought the cluster up.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PG_POD="postgresql-59d6cbc5b6-qr2f5"
NS="zentrion-system"
GATEWAY_PORT=18080
GATEWAY_URL="http://127.0.0.1:${GATEWAY_PORT}"

echo "[1/7] Verify cluster..."
kubectl get pods -n "$NS" >/dev/null

echo "[2/7] Truncate evaluation tables..."
PGPASSWORD=zentrion kubectl exec -n "$NS" "$PG_POD" -c postgresql -- \
  psql -U zentrion -d zentrion -c \
  "TRUNCATE TABLE telemetry_logs, anomalies, policy_drafts RESTART IDENTITY;"

echo "[3/7] Start port-forward to ingress..."
kubectl port-forward -n istio-system svc/istio-ingressgateway "${GATEWAY_PORT}":80 \
  >/tmp/pf.log 2>&1 &
echo $! > /tmp/pf.pid
sleep 4
curl -sf "$GATEWAY_URL/productpage" >/dev/null || { echo "ingress not reachable"; exit 1; }

echo "[4/7] Pre-warm baseline traffic (60s)..."
"$ROOT/ai/anomaly_detector/venv/bin/python3" \
    "$ROOT/ai/attack_sim/normal_traffic.py" --url "$GATEWAY_URL/" --duration 60

echo "[5/7] Run attack simulation suite..."
( cd "$ROOT/ai/attack_sim" && \
  PATH="$ROOT/ai/anomaly_detector/venv/bin:$PATH" \
  bash run_all.sh "$GATEWAY_URL/" ) || true

echo "[6/7] Export training data + train model..."
"$ROOT/ai/anomaly_detector/venv/bin/python3" \
    "$ROOT/ai/anomaly_detector/data/export_from_postgres.py"
"$ROOT/ai/anomaly_detector/venv/bin/python3" \
    "$ROOT/scripts/train_and_report.py"

echo "[7/7] Pull HITL stats + run simulation + render figures..."
"$ROOT/ai/anomaly_detector/venv/bin/python3" "$ROOT/scripts/query_policy_drafts.py" || true
"$ROOT/ai/anomaly_detector/venv/bin/python3" "$ROOT/scripts/hitl_simulate.py"
"$ROOT/ai/anomaly_detector/venv/bin/python3" "$ROOT/scripts/make_figures.py"

kill "$(cat /tmp/pf.pid)" 2>/dev/null || true
echo "Done. Artefacts in Documentation/eval_artifacts/ and Documentation/figures/."
