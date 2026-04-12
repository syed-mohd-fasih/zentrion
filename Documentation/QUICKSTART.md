# Zentrion Quick Start (30 Minutes)

Get Zentrion running on your local machine in 30 minutes.

---

## ⚡ **Prerequisites** (5 min)

```bash
# macOS
brew install docker kubectl minikube helm

# Verify
docker --version && kubectl version --client && minikube version
```

---

## 🚀 **Step 1: Start Cluster** (5 min)

```bash
# Start minikube
minikube start --cpus=4 --memory=8192

# Install Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH
istioctl install --set profile=demo -y

# Enable sidecar injection
kubectl label namespace default istio-injection=enabled
```

---

## 📦 **Step 2: Deploy Sample App** (5 min)

```bash
# Deploy Bookinfo
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/bookinfo/platform/kube/bookinfo.yaml

# Create gateway
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/bookinfo/networking/bookinfo-gateway.yaml

# Wait for pods
kubectl wait --for=condition=ready pod --all --timeout=120s

# Get URL
export GATEWAY_URL=$(minikube ip):$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

# Test
curl http://$GATEWAY_URL/productpage
```

---

## 🎯 **Step 3: Deploy Zentrion** (10 min)

```bash
# Clone repo
git clone <your-repo>
cd zentrion

# Install backend dependencies
cd app/orchestrator-api

# Copy all new files from artifacts (see file list below)

# Build Docker image
eval $(minikube docker-env)
docker build -t zentrion/orchestrator-api:latest .

# Deploy
cd ../..
./deploy.sh
```

**Files to copy from artifacts:**
```
manifests/crds/*.yaml               (3 files)
manifests/rbac.yaml
manifests/postgresql.yaml
manifests/orchestrator-*.yaml       (2 files)
modules/database/                   (8 files)
modules/istio/                      (2 files)
modules/crd/                        (2 files)
modules/service-discovery/          (2 files)
app.module.ts                       (updated)
config/app.config.ts                (updated)
modules/k8s/k8s.service.ts          (updated)
package.json                        (updated)
Dockerfile
.dockerignore
```

---

## ✅ **Step 4: Verify** (5 min)

```bash
# Check pods
kubectl get pods -n zentrion-system

# Port-forward
kubectl port-forward -n zentrion-system svc/zentrion-orchestrator 3001:3001 &

# Test health
curl http://localhost:3001/health

# Login
curl -X POST http://localhost:3001/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' \
  | jq

# Save token
export TOKEN="<your-token>"

# Check discovered services
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/telemetry/services | jq
```

---

## 🎨 **Step 5: Test the System** (5 min)

```bash
# Generate traffic
for i in {1..50}; do
  curl -s "http://$GATEWAY_URL/productpage" > /dev/null
  echo "Request $i"
  sleep 1
done

# Check telemetry
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/telemetry/live?limit=10 | jq

# Wait 30 seconds for anomaly detection

# Check anomalies
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/anomalies | jq

# Check policy drafts
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/policies/drafts/pending | jq
```

---

## 🎉 **You're Done!**

Zentrion is now:
- ✅ Watching all traffic in your cluster
- ✅ Detecting anomalies in real-time
- ✅ Generating security policies
- ✅ Ready for dashboard connection

---

## 🔌 **Next: Connect Dashboard**

```bash
cd apps/dashboard
npm install
echo "NEXT_PUBLIC_API_URL=http://localhost:3001" > .env.local
npm run dev
```

Open http://localhost:3000 and login with `admin/admin123`

---

## 🐛 **Troubleshooting**

### Orchestrator won't start
```bash
kubectl logs -l app=zentrion-orchestrator -n zentrion-system
```

### No telemetry
```bash
# Check Envoy logs
kubectl logs -l app=productpage -c istio-proxy --tail=10
```

### PostgreSQL issues
```bash
kubectl get pods -n zentrion-system -l app=postgresql
kubectl logs -l app=postgresql -n zentrion-system
```

---

## 📚 **Full Guides**

- **ENVIRONMENT_SETUP.md** - Detailed cluster setup
- **DEPLOYMENT.md** - Complete deployment guide
- **CODE_MIGRATION.md** - Understanding the code
- **IMPLEMENTATION_CHECKLIST.md** - Step-by-step checklist

---

## 🎓 **For FYP Demo**

1. Show architecture diagram
2. Show running pods: `kubectl get pods -n zentrion-system`
3. Generate traffic and show anomaly detection
4. Generate policy from anomaly
5. Approve policy
6. Show in Kiali: `istioctl dashboard kiali`
7. Show audit trail

**Total demo time: 5 minutes** ✅

---

That's it! Your Zero Trust Security Orchestrator is operational. 🚀
