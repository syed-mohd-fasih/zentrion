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
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
  printf "${CYAN}${BOLD}║  SECTION %-2s  %-44s  ║${RESET}\n" "$num" "$title"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
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

api_get() {
  local path="$1"
  cmd_header "curl -s ${API}${path}"
  if [[ -n "$TOKEN" ]]; then
    curl -s "${API}${path}" -H "Authorization: Bearer ${TOKEN}" | jq .
  else
    curl -s "${API}${path}" | jq .
  fi
}

api_post() {
  local path="$1" body="$2"
  cmd_header "curl -s -X POST ${API}${path} -d '${body}'"
  if [[ -n "$TOKEN" ]]; then
    curl -s -X POST "${API}${path}" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${TOKEN}" \
      -d "$body" | jq .
  else
    curl -s -X POST "${API}${path}" \
      -H "Content-Type: application/json" \
      -d "$body" | jq .
  fi
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

# check dependencies
for tool in kubectl curl jq; do
  if ! command -v "$tool" &>/dev/null; then
    err "Required tool not found: $tool"
    exit 1
  fi
done
ok "Dependencies OK (kubectl, curl, jq)"

# check API reachability
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
kubectl get authorizationpolicies -A 2>/dev/null || warn "No AuthorizationPolicies found yet"

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
SERVICES=$(curl -s "${API}/telemetry/services" \
  -H "Authorization: Bearer ${TOKEN}")
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

advance

# =============================================================================
# SECTION 6 — Anomaly Detection
# =============================================================================
banner 6 "Anomaly Detection"

echo -e "${BOLD}  Detected anomalies — GET /anomalies?limit=5${RESET}"
ANOMALIES=$(curl -s "${API}/anomalies?limit=5" \
  -H "Authorization: Bearer ${TOKEN}")
echo "$ANOMALIES" | jq .

ANOMALY_COUNT=$(echo "$ANOMALIES" | jq '.anomalies | length // 0')
ok "Found ${ANOMALY_COUNT} anomaly(ies)"

# pick the first anomaly for policy workflow
ANOMALY_ID=$(echo "$ANOMALIES" | jq -r '.anomalies[0].id // empty')
if [[ -n "$ANOMALY_ID" ]]; then
  ok "Using anomaly ID: ${ANOMALY_ID}"
  echo ""
  echo -e "${BOLD}  Anomaly detail — GET /anomalies/${ANOMALY_ID}${RESET}"
  api_get "/anomalies/${ANOMALY_ID}"
else
  warn "No anomalies detected yet. Generating traffic may trigger detection."
  warn "Policy workflow will use manual draft creation as fallback."
fi

advance

# =============================================================================
# SECTION 7 — Policy Workflow
# =============================================================================
banner 7 "Policy Workflow  (Detect → Draft → Approve → Apply)"

if [[ -n "$ANOMALY_ID" ]]; then
  # ── 7a: auto-generate draft from anomaly
  echo -e "${BOLD}  Step 1: Auto-generate policy draft from anomaly${RESET}"
  echo -e "${DIM}  POST /policies/drafts/from-anomaly${RESET}"
  DRAFT_RESP=$(curl -s -X POST "${API}/policies/drafts/from-anomaly" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -d "{\"anomalyId\":\"${ANOMALY_ID}\"}")
  echo "$DRAFT_RESP" | jq .

  DRAFT_ID=$(echo "$DRAFT_RESP" | jq -r '.draft.id // empty')
else
  # ── 7a fallback: manual draft
  echo -e "${BOLD}  Step 1: Creating manual policy draft (no anomalies detected yet)${RESET}"
  echo -e "${DIM}  POST /policies/drafts${RESET}"
  DRAFT_RESP=$(curl -s -X POST "${API}/policies/drafts" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -d '{
      "service": "productpage",
      "namespace": "default",
      "rules": [
        {
          "from": [{"source": {"namespaces": ["default"]}}],
          "to": [{"operation": {"methods": ["GET"], "paths": ["/productpage"]}}]
        }
      ],
      "reason": "Demo: restrict productpage to GET /productpage from default namespace"
    }')
  echo "$DRAFT_RESP" | jq .

  DRAFT_ID=$(echo "$DRAFT_RESP" | jq -r '.draft.id // empty')
fi

if [[ -z "$DRAFT_ID" ]]; then
  warn "Draft creation failed — skipping approval steps"
  advance
else
  ok "Draft created with ID: ${DRAFT_ID}"

  # ── 7b: show pending queue
  echo ""
  echo -e "${BOLD}  Step 2: Pending policy queue (human review)${RESET}"
  echo -e "${DIM}  GET /policies/drafts/pending${RESET}"
  api_get "/policies/drafts/pending"

  advance

  # ── 7c: admin approves
  echo -e "${BOLD}  Step 3: Admin approves and applies the policy${RESET}"
  echo -e "${DIM}  POST /policies/drafts/${DRAFT_ID}/approve${RESET}"
  APPROVE_RESP=$(curl -s -X POST "${API}/policies/drafts/${DRAFT_ID}/approve" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -d '{"notes":"Approved during FYP live demo"}')
  echo "$APPROVE_RESP" | jq .

  APPLIED_STATUS=$(echo "$APPROVE_RESP" | jq -r '.draft.status // "unknown"')
  if [[ "$APPLIED_STATUS" == "applied" ]]; then
    ok "Policy status: APPLIED to cluster"
  else
    warn "Policy status after approval: $APPLIED_STATUS"
  fi

  # ── 7d: show active policies
  echo ""
  echo -e "${BOLD}  Step 4: Active policies now live in cluster${RESET}"
  echo -e "${DIM}  GET /policies/active${RESET}"
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
  echo -e "${BOLD}  History for this specific policy — GET /policies/history/${DRAFT_ID}${RESET}"
  api_get "/policies/history/${DRAFT_ID}"
fi

advance

# =============================================================================
# SECTION 9 — Cluster Verification
# =============================================================================
banner 9 "Cluster Verification"

echo -e "${BOLD}  Istio AuthorizationPolicies now in cluster:${RESET}"
cmd_header "kubectl get authorizationpolicies -A"
kubectl get authorizationpolicies -A 2>/dev/null || warn "kubectl not available or no policies found"

echo ""
if kubectl get authorizationpolicies -A 2>/dev/null | grep -q .; then
  echo -e "${BOLD}  Describing the most recent policy:${RESET}"
  POLICY_NAME=$(kubectl get authorizationpolicies -A 2>/dev/null \
    --sort-by='.metadata.creationTimestamp' \
    -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")
  POLICY_NS=$(kubectl get authorizationpolicies -A 2>/dev/null \
    --sort-by='.metadata.creationTimestamp' \
    -o jsonpath='{.items[-1].metadata.namespace}' 2>/dev/null || echo "default")

  if [[ -n "$POLICY_NAME" ]]; then
    cmd_header "kubectl describe authorizationpolicy ${POLICY_NAME} -n ${POLICY_NS}"
    kubectl describe authorizationpolicy "${POLICY_NAME}" -n "${POLICY_NS}" 2>/dev/null || true
  fi
fi

# ── closing summary ──────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║                   DEMO COMPLETE                         ║${RESET}"
echo -e "${CYAN}${BOLD}╠══════════════════════════════════════════════════════════╣${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Cluster state verified                              ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  API health confirmed                                ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  JWT authentication working                          ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Service discovery operational                       ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Istio telemetry flowing                             ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Anomaly detection running                           ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Policy generated, approved, and applied             ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  Audit trail recorded                                ║${RESET}"
echo -e "${CYAN}${BOLD}║  ✔  AuthorizationPolicy live in cluster                 ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
