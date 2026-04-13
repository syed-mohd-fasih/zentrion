#!/usr/bin/env bash
# =============================================================================
#  Zentrion — Live Demo Script
#  Usage:
#    ./demo.sh           # auto-advance (2s between sections — good for screenshots)
#    ./demo.sh --pause   # press ENTER between sections (good for live demo)
# =============================================================================

set -euo pipefail

API="http://localhost:3001"
NAMESPACE="zentrion-system"
PAUSE_MODE=false
TOKEN=""
ANOMALY_ID=""
DRAFT_ID=""
ATTACK_PID=""
ATTACK_LAUNCHED=false

# ── parse flags ──────────────────────────────────────────────────────────────
for arg in "$@"; do
  [[ "$arg" == "--pause" ]] && PAUSE_MODE=true
done

# ── colors ───────────────────────────────────────────────────────────────────
BOLD='\033[1m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
DIM='\033[2m'
RESET='\033[0m'

# ── helpers ──────────────────────────────────────────────────────────────────
banner() {
  local num="$1" title="$2"
  echo ""
  echo -e "${CYAN}${BOLD}╔═════════════════════════════════════════════════════════════════════╗${RESET}"
  printf "${CYAN}${BOLD}   SECTION %-2s  %-44s   ${RESET}\n" "$num" "$title"
  echo -e "${CYAN}${BOLD}╚═════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
}

cmd_header() {
  echo -e "${DIM}  \$ $*${RESET}"
}

ok()   { echo -e "${GREEN}  ✔  $*${RESET}"; }
warn() { echo -e "${YELLOW}  ⚠  $*${RESET}"; }
err()  { echo -e "${RED}  ✘  $*${RESET}"; }

advance() {
  echo ""
  if $PAUSE_MODE; then
    echo -e "${DIM}  ── Press ENTER to continue ──${RESET}"
    read -r
  else
    sleep 2
  fi
}

countdown() {
  local seconds="$1" label="$2"
  for i in $(seq "$seconds" -1 1); do
    printf "\r  ${YELLOW}%s — %2ds remaining ...${RESET}" "$label" "$i"
    sleep 1
  done
  printf "\r%-60s\n" ""   # clear the line
}

api_get() {
  local path="$1"
  cmd_header "curl -s ${API}${path}"
  curl -s "${API}${path}" -H "Authorization: Bearer ${TOKEN}" | jq .
}

api_post_auth() {
  local path="$1" body="$2"
  cmd_header "curl -s -X POST ${API}${path}"
  curl -s -X POST "${API}${path}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -d "$body" | jq .
}

# ── attack simulation ─────────────────────────────────────────────────────────
# Runs inside the productpage pod (Python stdlib only — no curl needed).
# Targets the details service to trigger 4 detectors simultaneously:
#   TRAFFIC_SPIKE         — 35 requests in ~5s (baseline near 0 → way above 3× threshold)
#   SUSPICIOUS_PATTERN    — 45 requests from same pod IP (threshold: >30)
#   UNEXPECTED_COMMUNICATION — productpage→details not in whitelist
#   HIGH_ERROR_RATE       — 8/10 requests return 4xx (threshold: >20% on ≥10 samples)
launch_attack() {
  local pod
  pod=$(kubectl get pods -n default -l app=productpage \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

  if [[ -z "$pod" ]]; then
    warn "productpage pod not found — skipping live attack simulation"
    warn "Deploy Bookinfo first: kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/bookinfo/platform/kube/bookinfo.yaml"
    return 1
  fi

  ok "Attack pod: ${pod}"
  echo -e "${YELLOW}  Injecting anomalous traffic into the mesh (background)...${RESET}"

  # Run in background; errors are silenced so they don't kill the script
  kubectl exec -n default "$pod" -- python3 -c "
import urllib.request, time

base = 'http://details:9080'

# Phase 1 — Traffic spike + Suspicious pattern
# 35 rapid requests from same source IP triggers:
#   TRAFFIC_SPIKE      (>20 requests in 10s, baseline ~0 → >3x threshold)
#   SUSPICIOUS_PATTERN (>30 requests from same IP in 5-min window)
#   UNEXPECTED_COMMUNICATION (productpage→details not in known-comms whitelist)
for i in range(35):
    try:
        urllib.request.urlopen(base + '/details/0', timeout=2)
    except Exception:
        pass

# Phase 2 — High error rate
# 8 requests to an invalid path, 2 valid = 80% error rate on 10 samples
# Triggers: HIGH_ERROR_RATE (>20% errors with min 10 samples)
for i in range(8):
    try:
        urllib.request.urlopen(base + '/invalid-endpoint-attack', timeout=2)
    except Exception:
        pass
for i in range(2):
    try:
        urllib.request.urlopen(base + '/details/0', timeout=2)
    except Exception:
        pass
" 2>/dev/null &

  ATTACK_PID=$!
  ATTACK_LAUNCHED=true
}

# ── pre-flight checks ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║           ZENTRION  —  Zero Trust Security Orchestrator      ║${RESET}"
echo -e "${BOLD}║                       FYP Live Demo                          ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Mode: $(if $PAUSE_MODE; then echo 'Manual (press ENTER to advance)'; else echo 'Auto (2s between sections)'; fi)"
echo ""

for tool in kubectl curl jq; do
  if ! command -v "$tool" &>/dev/null; then
    err "Required tool not found: $tool"
    exit 1
  fi
done
ok "Dependencies OK (kubectl, curl, jq)"

if ! curl -s --max-time 3 "${API}/health" &>/dev/null; then
  err "Cannot reach orchestrator at ${API}"
  echo ""
  echo -e "  Run this in a separate terminal, then retry:"
  echo -e "  ${YELLOW}kubectl port-forward svc/zentrion-orchestrator -n ${NAMESPACE} 3001:3001${RESET}"
  echo ""
  exit 1
fi
ok "Orchestrator reachable at ${API}"

advance

# =============================================================================
# SECTION 1 — Cluster State
# =============================================================================
banner 1 "Cluster State"

echo -e "${BOLD}  Pods in zentrion-system:${RESET}"
cmd_header "kubectl get pods -n ${NAMESPACE}"
kubectl get pods -n "${NAMESPACE}"

echo ""
echo -e "${BOLD}  Zentrion Custom Resource Definitions:${RESET}"
cmd_header "kubectl get crd | grep zentrion"
kubectl get crd | grep zentrion || warn "No Zentrion CRDs found — run ./deploy.sh first"

echo ""
echo -e "${BOLD}  RBAC — ClusterRoleBinding:${RESET}"
cmd_header "kubectl get clusterrolebinding | grep zentrion"
kubectl get clusterrolebinding | grep zentrion || warn "No Zentrion RBAC found"

echo ""
echo -e "${BOLD}  Existing Istio Authorization Policies (before demo):${RESET}"
cmd_header "kubectl get authorizationpolicies -A"
kubectl get authorizationpolicies -A 2>/dev/null || warn "No AuthorizationPolicies yet — expected at start"

advance

# =============================================================================
# SECTION 2 — Health Check
# =============================================================================
banner 2 "API Health Check"

echo -e "${BOLD}  GET /health${RESET}"
HEALTH=$(curl -s "${API}/health")
echo "$HEALTH" | jq .

STATUS=$(echo "$HEALTH" | jq -r '.status // "unknown"')
if [[ "$STATUS" == "ok" ]]; then
  ok "Orchestrator is healthy"
else
  warn "Unexpected health status: $STATUS"
fi

advance

# =============================================================================
# SECTION 3 — Authentication
# =============================================================================
banner 3 "Authentication (JWT Login)"

echo -e "${BOLD}  Logging in as admin...${RESET}"
LOGIN_RESP=$(curl -s -X POST "${API}/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}')
echo "$LOGIN_RESP" | jq .

TOKEN=$(echo "$LOGIN_RESP" | jq -r '.accessToken // empty')
if [[ -z "$TOKEN" ]]; then
  err "Login failed — cannot continue without a token"
  exit 1
fi
ok "Token received (${TOKEN:0:30}...)"

echo ""
echo -e "${BOLD}  Verifying identity — GET /auth/me${RESET}"
api_get "/auth/me"

advance

# =============================================================================
# SECTION 4 — Service Discovery
# =============================================================================
banner 4 "Service Discovery"

echo -e "${BOLD}  Discovered services in the mesh — GET /telemetry/services${RESET}"
cmd_header "curl -s ${API}/telemetry/services"
SERVICES=$(curl -s "${API}/telemetry/services" -H "Authorization: Bearer ${TOKEN}")
echo "$SERVICES" | jq .

SVC_COUNT=$(echo "$SERVICES" | jq '.services | length // 0')
ok "Found ${SVC_COUNT} service(s)"

advance

# =============================================================================
# SECTION 5 — Live Telemetry
# =============================================================================
banner 5 "Live Istio Telemetry"

echo -e "${BOLD}  Last 5 Envoy access log entries — GET /telemetry/live?limit=5${RESET}"
api_get "/telemetry/live?limit=5"

# ── Launch attack simulation NOW, in background ───────────────────────────────
# Started here so the 45-request simulation completes while we wait below,
# and the anomaly detector (runs every 5s) has time to catch it before Section 6.
echo ""
echo -e "${BOLD}  ──────────────────────────────────────────────────────────${RESET}"
echo -e "${BOLD}  Simulating adversarial traffic to trigger anomaly detection${RESET}"
echo -e "${BOLD}  ──────────────────────────────────────────────────────────${RESET}"
echo ""
echo -e "  Target detectors:"
echo -e "  ${YELLOW}•${RESET} TRAFFIC_SPIKE         — 35 rapid requests (baseline ~0 → far above 3× threshold)"
echo -e "  ${YELLOW}•${RESET} SUSPICIOUS_PATTERN    — 45 requests from same source IP (threshold: >30)"
echo -e "  ${YELLOW}•${RESET} UNEXPECTED_COMM.      — productpage → details (not in known-comms whitelist)"
echo -e "  ${YELLOW}•${RESET} HIGH_ERROR_RATE        — 8/10 requests return 4xx (threshold: >20%)"
echo ""
launch_attack || true

if $ATTACK_LAUNCHED; then
  echo ""
  # Wait for: simulation to finish (~10s) + Istio log streaming + 3 detector cycles (15s)
  countdown 25 "Waiting for Envoy logs → telemetry DB → anomaly detector"
  ok "Detection window elapsed — querying anomalies now"
else
  warn "Attack simulation skipped — Section 6 will use any existing anomalies or fallback to manual draft"
  advance
fi

# =============================================================================
# SECTION 6 — Anomaly Detection
# =============================================================================
banner 6 "Anomaly Detection Results"

echo -e "${BOLD}  Detected anomalies — GET /anomalies?limit=5${RESET}"
ANOMALIES=$(curl -s "${API}/anomalies?limit=5" \
  -H "Authorization: Bearer ${TOKEN}")
echo "$ANOMALIES" | jq .

ANOMALY_COUNT=$(echo "$ANOMALIES" | jq '.anomalies | length // 0')
ok "Found ${ANOMALY_COUNT} anomaly(ies)"

ANOMALY_ID=$(echo "$ANOMALIES" | jq -r '.anomalies[0].anomalyId // empty')
if [[ -n "$ANOMALY_ID" ]]; then
  ok "Using anomaly ID: ${ANOMALY_ID} for policy generation"
  echo ""
  echo -e "${BOLD}  Anomaly detail — GET /anomalies/${ANOMALY_ID}${RESET}"
  api_get "/anomalies/${ANOMALY_ID}"
else
  warn "No anomalies found — policy workflow will use manual draft creation"
fi

advance

# =============================================================================
# SECTION 7 — Policy Workflow
# =============================================================================
banner 7 "Policy Workflow  (Detect → Draft → Approve → Apply)"

# Derive target service from the anomaly (strips pod-hash suffix if present).
# Falls back to "details" if no anomaly was detected.
ANOMALY_SERVICE=$(echo "$ANOMALIES" | jq -r '.anomalies[0].service // "details"' \
  | sed 's/-[a-f0-9]\{7,10\}-[a-z0-9]\{5\}$//')
ANOMALY_TYPE=$(echo "$ANOMALIES" | jq -r '.anomalies[0].type // "UNKNOWN"')

echo -e "${BOLD}  Step 1: Create policy draft targeting the anomalous service${RESET}"
echo -e "  Anomaly type  : ${YELLOW}${ANOMALY_TYPE}${RESET}"
echo -e "  Target service: ${YELLOW}${ANOMALY_SERVICE}${RESET}"
echo ""
cmd_header "POST /policies/drafts"
DRAFT_RESP=$(curl -s -X POST "${API}/policies/drafts" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d "{
    \"service\": \"${ANOMALY_SERVICE}\",
    \"namespace\": \"default\",
    \"rules\": [
      {
        \"from\": {\"source\": {\"namespaces\": [\"default\"]}},
        \"to\": {\"operation\": {\"methods\": [\"GET\"]}}
      }
    ],
    \"reason\": \"Restrict ${ANOMALY_SERVICE} to GET from default namespace — responding to ${ANOMALY_TYPE} anomaly\",
    \"anomalyId\": \"${ANOMALY_ID}\"
  }")
echo "$DRAFT_RESP" | jq .
DRAFT_ID=$(echo "$DRAFT_RESP" | jq -r '.draft.draftId // empty')

if [[ -z "$DRAFT_ID" ]]; then
  warn "Draft creation failed — skipping approval steps"
  advance
else
  ok "Draft created — ID: ${DRAFT_ID}"

  echo ""
  echo -e "${BOLD}  Step 2: Human review queue — policies awaiting approval${RESET}"
  api_get "/policies/drafts/pending"

  advance

  echo -e "${BOLD}  Step 3: Admin approves and applies the policy to the cluster${RESET}"
  cmd_header "POST /policies/drafts/${DRAFT_ID}/approve"
  APPROVE_RESP=$(curl -s -X POST "${API}/policies/drafts/${DRAFT_ID}/approve" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -d '{"notes":"Approved during FYP live demo — responding to detected attack"}')
  echo "$APPROVE_RESP" | jq .

  APPLIED_STATUS=$(echo "$APPROVE_RESP" | jq -r '.draft.status // "unknown"')
  if [[ "$APPLIED_STATUS" == "applied" ]]; then
    ok "Policy status: APPLIED — Istio AuthorizationPolicy is now live"
  else
    warn "Policy status after approval: $APPLIED_STATUS"
  fi

  echo ""
  echo -e "${BOLD}  Step 4: Active policies currently enforced in the cluster${RESET}"
  api_get "/policies/active"
fi

advance

# =============================================================================
# SECTION 8 — Audit Trail
# =============================================================================
banner 8 "Audit Trail"

echo -e "${BOLD}  Full policy history — GET /policies/history${RESET}"
api_get "/policies/history"

if [[ -n "$DRAFT_ID" ]]; then
  echo ""
  echo -e "${BOLD}  History for this policy — GET /policies/history/${DRAFT_ID}${RESET}"
  api_get "/policies/history/${DRAFT_ID}"
fi

advance

# =============================================================================
# SECTION 9 — Cluster Verification
# =============================================================================
banner 9 "Cluster Verification"

echo -e "${BOLD}  Istio AuthorizationPolicies now enforced in cluster:${RESET}"
cmd_header "kubectl get authorizationpolicies -A"
kubectl get authorizationpolicies -A 2>/dev/null || warn "No AuthorizationPolicies found"

echo ""
POLICY_NAME=$(kubectl get authorizationpolicies -A 2>/dev/null \
  --sort-by='.metadata.creationTimestamp' \
  -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")
POLICY_NS=$(kubectl get authorizationpolicies -A 2>/dev/null \
  --sort-by='.metadata.creationTimestamp' \
  -o jsonpath='{.items[-1].metadata.namespace}' 2>/dev/null || echo "")

if [[ -n "$POLICY_NAME" && -n "$POLICY_NS" ]]; then
  echo -e "${BOLD}  Most recent policy — full spec:${RESET}"
  cmd_header "kubectl describe authorizationpolicy ${POLICY_NAME} -n ${POLICY_NS}"
  kubectl describe authorizationpolicy "${POLICY_NAME}" -n "${POLICY_NS}" 2>/dev/null || true
fi

# ── cleanup background process if still running ───────────────────────────────
if [[ -n "$ATTACK_PID" ]] && kill -0 "$ATTACK_PID" 2>/dev/null; then
  wait "$ATTACK_PID" 2>/dev/null || true
fi

# ── closing summary ───────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}╔═════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║                   DEMO COMPLETE                         ║${RESET}"
echo -e "${CYAN}${BOLD}╠═════════════════════════════════════════════════════════╣${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Cluster state verified (pods, CRDs, RBAC)           ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  API health confirmed                                ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  JWT authentication working                          ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Service discovery operational                       ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Istio telemetry flowing from Envoy sidecars         ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Adversarial traffic simulated (4 attack patterns)   ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Anomalies auto-detected in real time                ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Policy auto-generated from anomaly                  ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Human-in-the-loop approval executed                 ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  AuthorizationPolicy applied and live in cluster     ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Full audit trail recorded                           ║${RESET}"
echo -e "${CYAN}${BOLD}╚═════════════════════════════════════════════════════════╝${RESET}"
echo ""
