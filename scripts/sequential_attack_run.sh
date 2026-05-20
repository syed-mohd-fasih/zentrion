#!/usr/bin/env bash
# Low-intensity sequential attack harness for the Zentrion paper run.
# Background baseline traffic runs the whole time. Each attack gets its own
# 90s window so the orchestrator's 200-log buffer is dominated by that
# attack's signature when its detector ticks (every 5s).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/ai/anomaly_detector/venv/bin/python3"
SIM="$ROOT/ai/attack_sim"
URL="${1:-http://127.0.0.1:18080/}"
ATTACK_DURATION="${ATTACK_DURATION:-90}"
GAP="${GAP:-30}"
TAIL_BASELINE="${TAIL_BASELINE:-300}"
BG_DURATION=$(( ATTACK_DURATION * 7 + GAP * 7 + TAIL_BASELINE + 30 ))

echo "[seq] URL=$URL attack=${ATTACK_DURATION}s gap=${GAP}s tail=${TAIL_BASELINE}s total_bg=${BG_DURATION}s"

# 1. Start continuous low-rate baseline in the background for the full run.
echo "[seq] starting background baseline (~2 req/s) for ${BG_DURATION}s..."
"$PY" "$SIM/normal_traffic.py" --url "$URL" --duration "$BG_DURATION" \
    >/tmp/seq_baseline.log 2>&1 &
BG_PID=$!
trap 'kill $BG_PID 2>/dev/null || true' EXIT

# Brief warm-up so the orchestrator's 200-log buffer has baseline data
# before the first attack hits.
sleep 20

run_attack() {
    local name="$1"; shift
    echo ""
    echo "[seq] ===== $name (${ATTACK_DURATION}s) ====="
    ( cd "$SIM" && "$PY" "$@" --duration "$ATTACK_DURATION" ) || true
    echo "[seq] cooldown gap (${GAP}s)..."
    sleep "$GAP"
}

# 2. Sequential attacks — each gets its own dominance window.
run_attack "suspicious_pattern"  suspicious_pattern.py   --url "$URL" --rps 1
run_attack "unauthorized_access" unauthorized_access.py  --url "$URL"
run_attack "high_error_rate"     high_error_rate.py      --url "$URL" --rps 2
run_attack "traffic_spike"       traffic_spike.py        --url "$URL" --threads 2
run_attack "latency_anomaly"     latency_anomaly.py      --url "$URL" --concurrency 4
run_attack "unusual_source"      unusual_source.py       --url "$URL" --rps 1
echo ""
echo "[seq] ===== new_endpoint (${ATTACK_DURATION}s, expected to NOT fire vs Bookinfo) ====="
( cd "$SIM" && "$PY" new_endpoint.py --url "$URL" --rounds 2 ) || true
sleep "$GAP"

# 3. Tail baseline so NORMAL windows accumulate.
echo ""
echo "[seq] ===== tail baseline (${TAIL_BASELINE}s) ====="
sleep "$TAIL_BASELINE"

# 4. Stop background baseline (it may also exit on its own).
kill $BG_PID 2>/dev/null || true
wait $BG_PID 2>/dev/null || true
echo "[seq] done."
