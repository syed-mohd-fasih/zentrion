#!/usr/bin/env bash
# =============================================================================
#  Zentrion — Attack Simulation & Frontend Test Seeder
#
#  Injects adversarial traffic into the mesh, waits for anomaly detection,
#  then seeds the system with policy drafts in varied states so every page
#  of the frontend can be fully exercised.
#
#  Usage:
#    ./demo.sh              # run simulation (default)
#    ./demo.sh --verbose    # print all raw API responses
# =============================================================================

set -euo pipefail

API="http://localhost:3001"
NAMESPACE="zentrion-system"
VERBOSE=false

for arg in "$@"; do
  [[ "$arg" == "--verbose" ]] && VERBOSE=true
done

# ── colors ────────────────────────────────────────────────────────────────────
BOLD='\033[1m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
DIM='\033[2m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}  ✔  $*${RESET}"; }
warn() { echo -e "${YELLOW}  ⚠  $*${RESET}"; }
err()  { echo -e "${RED}  ✘  $*${RESET}"; }
step() { echo -e "\n${BOLD}  ▶  $*${RESET}"; }

show() { $VERBOSE && { echo "$1" | jq . 2>/dev/null || echo "$1"; }; true; }

countdown() {
  local seconds="$1" label="$2"
  for i in $(seq "$seconds" -1 1); do
    printf "\r  ${YELLOW}%s — %2ds remaining...${RESET}" "$label" "$i"
    sleep 1
  done
  printf "\r%-70s\n" ""
}

# ── header ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║      Zentrion — Attack Simulation & Frontend Seeder       ║${RESET}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ── pre-flight ────────────────────────────────────────────────────────────────
for tool in kubectl curl jq; do
  command -v "$tool" &>/dev/null || { err "Required tool not found: $tool"; exit 1; }
done

if ! curl -s --max-time 3 "${API}/health" &>/dev/null; then
  err "Cannot reach orchestrator at ${API}"
  echo -e "  Run: ${YELLOW}kubectl port-forward svc/zentrion-orchestrator -n ${NAMESPACE} 3001:3001${RESET}"
  exit 1
fi
ok "Orchestrator reachable at ${API}"

# ── authenticate (admin + analyst) ───────────────────────────────────────────
step "Authenticating..."

ADMIN_LOGIN=$(curl -s -X POST "${API}/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}')
show "$ADMIN_LOGIN"
ADMIN_TOKEN=$(echo "$ADMIN_LOGIN" | jq -r '.accessToken // empty')
[[ -z "$ADMIN_TOKEN" ]] && { err "Admin login failed — check credentials"; exit 1; }
ok "admin authenticated"

ANALYST_LOGIN=$(curl -s -X POST "${API}/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"analyst","password":"analyst123"}')
show "$ANALYST_LOGIN"
ANALYST_TOKEN=$(echo "$ANALYST_LOGIN" | jq -r '.accessToken // empty')
[[ -z "$ANALYST_TOKEN" ]] && warn "Analyst login failed — rejection step will be skipped"
[[ -n "$ANALYST_TOKEN" ]] && ok "analyst authenticated"

auth()     { echo "Authorization: Bearer ${ADMIN_TOKEN}"; }
auth_analyst() { echo "Authorization: Bearer ${ANALYST_TOKEN}"; }

# ── live attack simulation ────────────────────────────────────────────────────
step "Launching live attack simulation..."

ATTACK_PID=""
ATTACK_LAUNCHED=false

POD=$(kubectl get pods -n default -l app=productpage \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$POD" ]]; then
  ok "Bookinfo productpage pod: ${POD}"
  echo -e "  ${YELLOW}Injecting anomalous traffic (4 attack patterns)...${RESET}"
  echo -e "  ${DIM}• TRAFFIC_SPIKE         — 35 rapid requests (baseline ~0, far above 3× threshold)${RESET}"
  echo -e "  ${DIM}• SUSPICIOUS_PATTERN    — 35 requests from same source IP (threshold >30)${RESET}"
  echo -e "  ${DIM}• UNEXPECTED_COMM.      — productpage→details (not in known-comms whitelist)${RESET}"
  echo -e "  ${DIM}• HIGH_ERROR_RATE       — 8/10 requests to invalid path (threshold >20%)${RESET}"
  echo ""

  kubectl exec -n default "$POD" -- python3 -c "
import urllib.request
base = 'http://details:9080'
# TRAFFIC_SPIKE + SUSPICIOUS_PATTERN + UNEXPECTED_COMMUNICATION
for i in range(35):
    try: urllib.request.urlopen(base + '/details/0', timeout=2)
    except: pass
# HIGH_ERROR_RATE (8 bad + 2 good = 80% error rate on 10 samples)
for i in range(8):
    try: urllib.request.urlopen(base + '/invalid-endpoint-attack', timeout=2)
    except: pass
for i in range(2):
    try: urllib.request.urlopen(base + '/details/0', timeout=2)
    except: pass
" 2>/dev/null &

  ATTACK_PID=$!
  ATTACK_LAUNCHED=true
  ok "Attack injected in background (PID: ${ATTACK_PID})"
  countdown 30 "Waiting for Envoy logs → telemetry DB → anomaly detector"
else
  warn "Bookinfo not found in 'default' namespace — skipping live traffic injection"
  warn "To enable: kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/bookinfo/platform/kube/bookinfo.yaml"
  echo ""
fi

# ── collect live anomalies ────────────────────────────────────────────────────
step "Collecting detected anomalies..."

ANOMALIES_RESP=$(curl -s "${API}/anomalies?limit=10" -H "$(auth)")
show "$ANOMALIES_RESP"
ANOMALY_COUNT=$(echo "$ANOMALIES_RESP" | jq '.anomalies | length // 0')
ok "Found ${ANOMALY_COUNT} anomaly(ies)"

# ── generate policy drafts from anomalies ─────────────────────────────────────
step "Generating policy drafts from detected anomalies..."

ANOMALY_DRAFT_IDS=()
for i in 0 1 2; do
  ANOM_ID=$(echo "$ANOMALIES_RESP" | jq -r ".anomalies[${i}].anomalyId // empty")
  [[ -z "$ANOM_ID" ]] && continue

  RESP=$(curl -s -X POST "${API}/policies/drafts/from-anomaly" \
    -H "Content-Type: application/json" \
    -H "$(auth)" \
    -d "{\"anomalyId\": \"${ANOM_ID}\"}")
  show "$RESP"

  DID=$(echo "$RESP" | jq -r '.draft.draftId // empty')
  if [[ -n "$DID" ]]; then
    ANOMALY_DRAFT_IDS+=("$DID")
    SVC=$(echo "$ANOMALIES_RESP" | jq -r ".anomalies[${i}].service // \"?\"")
    TYPE=$(echo "$ANOMALIES_RESP" | jq -r ".anomalies[${i}].type // \"?\"")
    ok "Draft from ${TYPE} anomaly on ${SVC}: ${DID}"
  fi
done

if [[ ${#ANOMALY_DRAFT_IDS[@]} -eq 0 ]]; then
  warn "No anomaly-derived drafts created (no anomalies yet — live drafts below will still populate policy-review)"
fi

# ── create manual policy drafts (varied states) ───────────────────────────────
# These ensure the frontend always has rich data regardless of Bookinfo/Istio state.
step "Creating policy drafts for frontend state coverage..."

create_draft() {
  local body="$1"
  curl -s -X POST "${API}/policies/drafts" \
    -H "Content-Type: application/json" \
    -H "$(auth)" \
    -d "$body"
}

# Draft A — will be APPROVED: lockdown details to GET from default ns
RESP_A=$(create_draft '{
  "service": "details",
  "namespace": "default",
  "rules": [
    {
      "from": {"source": {"namespaces": ["default"]}},
      "to": {"operation": {"methods": ["GET"]}}
    }
  ],
  "reason": "Restrict details service to GET-only from default namespace — response to TRAFFIC_SPIKE anomaly"
}')
show "$RESP_A"
DRAFT_A=$(echo "$RESP_A" | jq -r '.draft.draftId // empty')
[[ -n "$DRAFT_A" ]] && ok "Draft A (details / GET-only) → ${DRAFT_A}" || warn "Draft A creation failed"

# Draft B — will be REJECTED: overly broad block on productpage
RESP_B=$(create_draft '{
  "service": "productpage",
  "namespace": "default",
  "rules": [
    {
      "from": {"source": {"namespaces": ["istio-system"]}},
      "to": {"operation": {"methods": ["GET", "POST"]}}
    }
  ],
  "reason": "Block all non-istio-system traffic to productpage — flagged for review (may break ingress)"
}')
show "$RESP_B"
DRAFT_B=$(echo "$RESP_B" | jq -r '.draft.draftId // empty')
[[ -n "$DRAFT_B" ]] && ok "Draft B (productpage / restrictive) → ${DRAFT_B}" || warn "Draft B creation failed"

# Draft C — stays PENDING: whitelist for reviews via service account
RESP_C=$(create_draft '{
  "service": "reviews",
  "namespace": "default",
  "rules": [
    {
      "from": {"source": {"principals": ["cluster.local/ns/default/sa/bookinfo-productpage"]}},
      "to": {"operation": {"methods": ["GET"]}}
    }
  ],
  "reason": "Whitelist only productpage service account for reviews — following SUSPICIOUS_PATTERN detection"
}')
show "$RESP_C"
DRAFT_C=$(echo "$RESP_C" | jq -r '.draft.draftId // empty')
[[ -n "$DRAFT_C" ]] && ok "Draft C (reviews / pending for frontend review) → ${DRAFT_C}" || warn "Draft C creation failed"

# Draft D — stays PENDING: ratings service egress restriction
RESP_D=$(create_draft '{
  "service": "ratings",
  "namespace": "default",
  "rules": [
    {
      "from": {"source": {"namespaces": ["default"]}},
      "to": {"operation": {"methods": ["GET"], "paths": ["/ratings/*"]}}
    }
  ],
  "reason": "Limit ratings service to scoped GET paths — UNEXPECTED_COMMUNICATION anomaly triggered from external source"
}')
show "$RESP_D"
DRAFT_D=$(echo "$RESP_D" | jq -r '.draft.draftId // empty')
[[ -n "$DRAFT_D" ]] && ok "Draft D (ratings / pending for frontend review) → ${DRAFT_D}" || warn "Draft D creation failed"

# ── approve anomaly-derived drafts + Draft A ──────────────────────────────────
step "Approving resolved drafts (admin)..."

approve_draft() {
  local did="$1" notes="$2"
  [[ -z "$did" ]] && return
  RESP=$(curl -s -X POST "${API}/policies/drafts/${did}/approve" \
    -H "Content-Type: application/json" \
    -H "$(auth)" \
    -d "{\"notes\": \"${notes}\"}")
  show "$RESP"
  STATUS=$(echo "$RESP" | jq -r '.draft.status // "unknown"')
  ok "Draft ${did} → ${STATUS}"
}

for did in "${ANOMALY_DRAFT_IDS[@]}"; do
  approve_draft "$did" "Auto-approved during simulation — anomaly-derived policy is appropriate response"
done

approve_draft "$DRAFT_A" "Confirmed traffic spike from productpage. GET-only restriction on details is correct mitigation."

# ── reject Draft B (as analyst — overly restrictive) ─────────────────────────
step "Rejecting overly restrictive draft (analyst)..."

if [[ -n "$DRAFT_B" && -n "$ANALYST_TOKEN" ]]; then
  RESP=$(curl -s -X POST "${API}/policies/drafts/${DRAFT_B}/reject" \
    -H "Content-Type: application/json" \
    -H "$(auth_analyst)" \
    -d '{"reason": "Rule is too restrictive — allowing only istio-system traffic would break external ingress access. Needs revision to also permit the ingress gateway service account."}')
  show "$RESP"
  STATUS=$(echo "$RESP" | jq -r '.draft.status // "unknown"')
  ok "Draft ${DRAFT_B} → ${STATUS}"
elif [[ -z "$ANALYST_TOKEN" ]]; then
  warn "Skipping rejection — analyst token unavailable"
fi

# ── wait for background attack process ───────────────────────────────────────
if [[ -n "$ATTACK_PID" ]] && kill -0 "$ATTACK_PID" 2>/dev/null; then
  wait "$ATTACK_PID" 2>/dev/null || true
fi

# ── final state snapshot ──────────────────────────────────────────────────────
step "Final state snapshot..."

FINAL_ANOMALIES=$(curl -s "${API}/anomalies?limit=20" \
  -H "$(auth)" | jq '.anomalies | length // 0' 2>/dev/null || echo "?")
ACTIVE_POLICIES=$(curl -s "${API}/policies/active" \
  -H "$(auth)" | jq '.policies | length // 0' 2>/dev/null || echo "?")
PENDING_DRAFTS=$(curl -s "${API}/policies/drafts/pending" \
  -H "$(auth)" | jq '.drafts | length // 0' 2>/dev/null || echo "?")

echo ""
echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║              Simulation Complete — System State           ║${RESET}"
echo -e "${CYAN}${BOLD}╠═══════════════════════════════════════════════════════════╣${RESET}"
printf "${CYAN}${BOLD}║  %-55s  ║${RESET}\n" "Anomalies detected:          ${FINAL_ANOMALIES}"
printf "${CYAN}${BOLD}║  %-55s  ║${RESET}\n" "Active policies applied:     ${ACTIVE_POLICIES}"
printf "${CYAN}${BOLD}║  %-55s  ║${RESET}\n" "Drafts awaiting review:      ${PENDING_DRAFTS}  ← approve/reject in frontend"
echo -e "${CYAN}${BOLD}╠═══════════════════════════════════════════════════════════╣${RESET}"
echo -e "${CYAN}${BOLD}║  Frontend pages to exercise:                              ║${RESET}"
echo -e "${CYAN}${BOLD}║  • /dashboard      real-time telemetry stream             ║${RESET}"
echo -e "${CYAN}${BOLD}║  • /anomalies      browse and filter detected anomalies   ║${RESET}"
echo -e "${CYAN}${BOLD}║  • /policy-review  approve / reject pending drafts        ║${RESET}"
echo -e "${CYAN}${BOLD}║  • /history        full audit trail (approved + rejected) ║${RESET}"
echo -e "${CYAN}${BOLD}║  • /services       mesh services with health metrics      ║${RESET}"
echo -e "${CYAN}${BOLD}╠═══════════════════════════════════════════════════════════╣${RESET}"
echo -e "${CYAN}${BOLD}║  Credentials:  admin/admin123  •  analyst/analyst123      ║${RESET}"
echo -e "${CYAN}${BOLD}║  Dashboard:    http://localhost:3000                      ║${RESET}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════╝${RESET}"
echo ""
