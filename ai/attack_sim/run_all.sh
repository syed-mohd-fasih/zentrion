#!/usr/bin/env bash
# Run all attack simulations in parallel against Bookinfo.
# Usage: ./run_all.sh [BOOKINFO_URL]
# Default URL: http://$(minikube ip)/

set -e

URL="${1:-http://$(minikube ip)/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURATION=120  # seconds per attack scenario

echo "======================================================"
echo "Zentrion Attack Simulation Suite"
echo "Target: $URL"
echo "Duration per scenario: ${DURATION}s (all run in parallel)"
echo "======================================================"
echo ""

cd "$SCRIPT_DIR"

# Run all attack scenarios in parallel
python3 traffic_spike.py        --url "$URL" --duration "$DURATION" --threads 20 &
python3 suspicious_pattern.py   --url "$URL" --duration "$DURATION" --rps 2 &
python3 new_endpoint.py         --url "$URL" --rounds 5 &
python3 unauthorized_access.py  --url "$URL" --duration "$DURATION" &
python3 high_error_rate.py      --url "$URL" --duration "$DURATION" --rps 5 &
python3 latency_anomaly.py      --url "$URL" --duration "$DURATION" --concurrency 30 &
python3 unusual_source.py       --url "$URL" --duration "$DURATION" --rps 2 &

echo "All attack scenarios running in background (PID list: $(jobs -p))"
echo "Waiting for completion..."
wait

echo ""
echo "======================================================"
echo "Attack phase complete. Running baseline traffic for 5 minutes..."
echo "======================================================"
python3normal_traffic.py --url "$URL" --duration 300

echo ""
echo "Done. Check the Zentrion dashboard for detected anomalies."
echo "Then run: python3 data/export_from_postgres.py"
