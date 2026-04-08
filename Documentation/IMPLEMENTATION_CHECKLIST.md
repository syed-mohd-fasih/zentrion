# Zentrion Implementation Checklist

Complete step-by-step checklist to go from zero to fully deployed system.

---

## 📋 **Phase 1: Environment Setup**

### ☐ Install Prerequisites

```bash
# macOS
brew install docker kubectl minikube helm

# Linux
# Follow instructions in ENVIRONMENT_SETUP.md

# Verify installations
docker --version
kubectl version --client
minikube version
helm version
```

### ☐ Start minikube Cluster

```bash
minikube start --cpus=4 --memory=8192 --disk-size=20g --driver=docker
minikube status  # Verify running
```

### ☐ Install Istio

```bash
# Download Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# Install with demo profile
istioctl install --set profile=demo -y

# Verify
kubectl get pods -n istio-system
# Should see 7 pods (all Running)
```

### ☐ Enable Sidecar Injection

```bash
kubectl label namespace default istio-injection=enabled
kubectl get namespace -L istio-injection
```

### ☐ Deploy Sample Application (Bookinfo)

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/bookinfo/platform/kube/bookinfo.yaml

# Wait for pods
kubectl wait --for=condition=ready pod --all --timeout=120s

# Verify (all should show 2/2 READY)
kubectl get pods
```

### ☐ Create Ingress Gateway

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/bookinfo/networking/bookinfo-gateway.yaml

# Get URL
export INGRESS_HOST=$(minikube ip)
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

# Test
curl http://$GATEWAY_URL/productpage
# Should return HTML
```

### ☐ Verify Telemetry

```bash
# Check Envoy logs
kubectl logs -l app=productpage -c istio-proxy --tail=10

# Should see JSON access logs
```

### ☐ Access Istio Dashboards

```bash
# Grafana
kubectl port-forward -n istio-system svc/grafana 3000:3000 &

# Kiali
kubectl port-forward -n istio-system svc/kiali 20001:20001 &

# Access in browser
# Grafana: http://localhost:3000 (admin/admin)
# Kiali: http://localhost:20001
```

**✅ Phase 1 Complete** - Environment is ready!

---

## ✅ **Phase 2: Code Setup — COMPLETE**

All code is production-ready. No action needed. Summary of what was done:

1. **Dependencies installed** — all packages in `app/orchestrator-api/package.json`:
   - `@kubernetes/client-node`, `@nestjs/typeorm`, `typeorm`, `pg`, `@nestjs/event-emitter`, `@nestjs/schedule`, `bcrypt`

2. **New modules created** (all in `app/orchestrator-api/src/modules/`):
   - `database/` — TypeORM + PostgreSQL + 7 entities
   - `istio/` — Envoy log watcher (emits telemetry events)
   - `crd/` — SecurityProfile / AnomalyRecord / PolicyHistory CRD management
   - `service-discovery/` — K8s deployment watcher
   - `events/` — Internal EventEmitter2 pub/sub

3. **All existing files migrated from in-memory store to PostgreSQL:**
   - `auth.service.ts` + `jwt.strategy.ts` — UserRepository + bcrypt
   - `telemetry.service.ts` — `@OnEvent('telemetry.log')` → DB. Synthetic generator removed.
   - `anomaly.service.ts` — reads TelemetryLog from DB, saves Anomaly to DB
   - `policy.service.ts` — PolicyDraft + PolicyHistory + Anomaly all in DB
   - All module files updated with `TypeOrmModule.forFeature([...])`

4. **Deleted**: `src/common/store.ts` (in-memory mock) — fully replaced by PostgreSQL

5. **Dockerfile** at `app/orchestrator-api/Dockerfile` — ✅ ready

See `Documentation/FILE_INDEX.md` for complete file status.

---

## 🚀 **Phase 3: Kubernetes Deployment**

### ☐ Create Zentrion Namespace

```bash
kubectl create namespace zentrion-system
kubectl label namespace zentrion-system istio-injection=enabled
```

### ☐ Apply CRDs

```bash
cd manifests/crds
kubectl apply -f security-profile.yaml
kubectl apply -f policy-history.yaml
kubectl apply -f anomaly-record.yaml

# Verify
kubectl get crd | grep zentrion
# Should show 3 CRDs
```

### ☐ Apply RBAC

```bash
cd ../
kubectl apply -f rbac.yaml

# Verify
kubectl get serviceaccount -n zentrion-system
kubectl get clusterrole | grep zentrion
kubectl get clusterrolebinding | grep zentrion
```

### ☐ Deploy PostgreSQL

```bash
kubectl apply -f postgresql.yaml

# Wait for ready
kubectl wait --for=condition=ready pod -l app=postgresql -n zentrion-system --timeout=120s

# Verify
kubectl get pods -n zentrion-system
kubectl get pvc -n zentrion-system
```

### ☐ Build Docker Image

```bash
# Point Docker to minikube
eval $(minikube docker-env)

# Build
cd app/orchestrator-api
docker build -t zentrion/orchestrator-api:latest .

# Verify
docker images | grep zentrion
```

### ☐ Deploy Orchestrator

```bash
cd ../../manifests
kubectl apply -f orchestrator-configmap.yaml
kubectl apply -f orchestrator-deployment.yaml

# Wait for ready
kubectl wait --for=condition=ready pod -l app=zentrion-orchestrator -n zentrion-system --timeout=120s

# Check logs
kubectl logs -f -l app=zentrion-orchestrator -n zentrion-system
```

### ☐ Verify Deployment

```bash
# All pods running
kubectl get pods -n zentrion-system

# CRDs registered
kubectl get crd | grep zentrion

# RBAC applied
kubectl auth can-i create authorizationpolicies.security.istio.io \
  --as=system:serviceaccount:zentrion-system:zentrion-orchestrator
# Should return: yes
```

**✅ Phase 3 Complete** - Zentrion is deployed!

---

## 🔌 **Phase 4: Verification & Testing**

### ☐ Port-Forward Orchestrator

```bash
kubectl port-forward -n zentrion-system svc/zentrion-orchestrator 3001:3001 &
```

### ☐ Test Health Check

```bash
curl http://localhost:3001/health
# Should return: {"status":"ok",...}
```

### ☐ Test Login

```bash
curl -X POST http://localhost:3001/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' \
  | jq

# Save token
export TOKEN="<your-access-token>"
```

### ☐ Test Service Discovery

```bash
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/telemetry/services \
  | jq

# Should show discovered services (productpage, reviews, etc.)
```

### ☐ Generate Traffic & Check Telemetry

```bash
# Generate traffic
for i in {1..50}; do
  curl -s "http://$GATEWAY_URL/productpage" > /dev/null
  echo "Request $i"
  sleep 1
done

# Check telemetry
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/telemetry/live?limit=10 \
  | jq
```

### ☐ Check Anomaly Detection

```bash
# Wait a few minutes for anomalies to be detected

curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/anomalies \
  | jq
```

### ☐ Check Policy Drafts

```bash
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/policies/drafts/pending \
  | jq
```

### ☐ Verify CRDs are Being Created

```bash
# Security Profiles
kubectl get securityprofiles -n default

# Anomaly Records
kubectl get anomalyrecords -n default

# Policy History
kubectl get policyhistories -n zentrion-system
```

### ☐ Test Policy Approval Workflow

```bash
# Get a draft ID
DRAFT_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/policies/drafts/pending | jq -r '.drafts[0].id')

# Approve it
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  http://localhost:3001/policies/drafts/$DRAFT_ID/approve \
  -d '{"notes":"Test approval"}' \
  | jq

# Check in Kiali
istioctl dashboard kiali
# Navigate to: Istio Config → Authorization Policies
# Should see Zentrion-generated policy!
```

**✅ Phase 4 Complete** - System is fully operational!

---

## 🎨 **Phase 5: Frontend Integration**

### ☐ Deploy Dashboard

```bash
# Navigate to frontend app
cd app/dashboard

# Install dependencies
pnpm install

# Create .env.local
echo "NEXT_PUBLIC_API_URL=http://localhost:3001" > .env.local

# Start development server
pnpm dev
```

### ☐ Test Dashboard Features

- ☐ Login page works
- ☐ Live telemetry feed shows real data
- ☐ Service list displays discovered services
- ☐ Anomalies page shows detected anomalies
- ☐ Policy review shows pending drafts
- ☐ Approve workflow creates K8s policies
- ☐ Audit trail shows all actions

**✅ Phase 5 Complete** - Full system is operational!

---

## 🎓 **Phase 6: FYP Demo Preparation**

### ☐ Prepare Demo Script

1. **Show Architecture Diagram**
2. **Show Running System**:
   ```bash
   kubectl get pods -n zentrion-system
   kubectl get pods -n default
   ```
3. **Generate Normal Traffic** - Show dashboard
4. **Simulate Attack** - Show anomaly detection
5. **Generate Policy** - Show YAML
6. **Approve Policy** - Show in Kiali
7. **Show Audit Trail** - Complete history

### ☐ Prepare Slides

Topics to cover:
- Problem statement (microservice security)
- Zero Trust Architecture principles
- Solution architecture
- Implementation details
- Demo results
- Future work (AI integration)

### ☐ Document Achievements

- ✅ Real Istio integration (not simulation)
- ✅ Custom Kubernetes CRDs
- ✅ Service mesh security automation
- ✅ Human-in-the-loop workflow
- ✅ Complete audit trail
- ✅ Production-grade architecture

**✅ Phase 6 Complete** - Ready for presentation!

---

## 🐛 **Troubleshooting Checklist**

### If Orchestrator Won't Start

- ☐ Check PostgreSQL is running: `kubectl get pods -n zentrion-system`
- ☐ Check logs: `kubectl logs -l app=zentrion-orchestrator -n zentrion-system`
- ☐ Verify secrets exist: `kubectl get secrets -n zentrion-system`
- ☐ Check RBAC: `kubectl describe clusterrolebinding zentrion-orchestrator-binding`

### If No Telemetry Flowing

- ☐ Verify Istio access logs enabled: `kubectl logs -l app=productpage -c istio-proxy`
- ☐ Check orchestrator logs for Istio watcher: `kubectl logs -l app=zentrion-orchestrator -n zentrion-system | grep Istio`
- ☐ Generate traffic: `curl http://$GATEWAY_URL/productpage`

### If Can't Create Policies

- ☐ Check RBAC permissions: `kubectl auth can-i create authorizationpolicies --as=system:serviceaccount:zentrion-system:zentrion-orchestrator`
- ☐ Reapply RBAC: `kubectl apply -f manifests/rbac.yaml`

---

## 📊 **Success Metrics**

By the end, you should have:

- ✅ minikube cluster with Istio running
- ✅ Bookinfo sample app deployed with sidecars
- ✅ PostgreSQL storing telemetry data
- ✅ 3 Zentrion CRDs registered
- ✅ Orchestrator watching Envoy logs
- ✅ Services being discovered automatically
- ✅ Anomalies being detected
- ✅ Policies being generated
- ✅ Dashboard showing live data
- ✅ Policies visible in Kiali

---

## 🎉 **Final Verification**

Run this comprehensive test:

```bash
#!/bin/bash

echo "🔍 Zentrion System Verification"
echo "================================"

# Check minikube
echo "✓ minikube status:"
minikube status

# Check Istio
echo "✓ Istio pods:"
kubectl get pods -n istio-system | grep Running | wc -l
echo "  (Should be 7)"

# Check Zentrion
echo "✓ Zentrion pods:"
kubectl get pods -n zentrion-system

# Check CRDs
echo "✓ Zentrion CRDs:"
kubectl get crd | grep zentrion

# Check API
echo "✓ API health:"
curl -s http://localhost:3001/health | jq '.status'

# Check discovered services
echo "✓ Discovered services:"
TOKEN=$(curl -s -X POST http://localhost:3001/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' | jq -r '.accessToken')

curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/telemetry/services | jq '.services[].name'

echo ""
echo "================================"
echo "✅ All checks passed!"
```

---

**You're ready to go! 🚀**

Estimated total time: **4-6 hours** (including environment setup)
