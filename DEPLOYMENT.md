# Zentrion Deployment Guide

Complete guide to deploy Zentrion to your minikube cluster.

---

## 📋 Prerequisites

Before deploying, ensure you have completed **ENVIRONMENT_SETUP.md**:

- ✅ minikube is running
- ✅ Istio is installed (demo profile)
- ✅ Bookinfo sample app is deployed
- ✅ Telemetry is flowing (verified Envoy logs)
- ✅ All Istio pods are Running

---

## 🚀 **Quick Deploy (All-in-One)**

```bash
# From the project root
./deploy.sh
```

This script will:
1. Create `zentrion-system` namespace
2. Apply all CRDs
3. Apply RBAC
4. Deploy PostgreSQL
5. Deploy Orchestrator
6. Wait for all pods to be ready
7. Port-forward to localhost

---

## 📝 **Manual Deployment (Step-by-Step)**

### Step 1: Create Namespace

```bash
kubectl create namespace zentrion-system
kubectl label namespace zentrion-system istio-injection=enabled

# Verify
kubectl get namespace zentrion-system -o yaml
```

---

### Step 2: Apply CRDs

```bash
kubectl apply -f manifests/crds/security-profile.yaml
kubectl apply -f manifests/crds/policy-history.yaml
kubectl apply -f manifests/crds/anomaly-record.yaml

# Verify
kubectl get crd | grep zentrion
```

**Expected output:**
```
anomalyrecords.zentrion.io         2025-01-15T10:00:00Z
policyhistories.zentrion.io        2025-01-15T10:00:00Z
securityprofiles.zentrion.io       2025-01-15T10:00:00Z
```

---

### Step 3: Apply RBAC

```bash
kubectl apply -f manifests/rbac.yaml

# Verify
kubectl get serviceaccount -n zentrion-system
kubectl get clusterrole | grep zentrion
kubectl get clusterrolebinding | grep zentrion
```

---

### Step 4: Deploy PostgreSQL

```bash
kubectl apply -f manifests/postgresql.yaml

# Wait for PostgreSQL to be ready
kubectl wait --for=condition=ready pod -l app=postgresql -n zentrion-system --timeout=120s

# Verify
kubectl get pods -n zentrion-system
kubectl get pvc -n zentrion-system
```

**Expected output:**
```
NAME                          READY   STATUS    RESTARTS   AGE
postgresql-xxx                2/2     Running   0          30s
```

---

### Step 5: Build and Push Docker Image

**Option A: Build locally (for minikube)**

```bash
# Point Docker to minikube's Docker daemon
eval $(minikube docker-env)

# Build image
cd app/orchestrator-api
docker build -t zentrion/orchestrator-api:latest .

# Verify
docker images | grep zentrion
```

**Option B: Use Docker Hub (for remote clusters)**

```bash
# Build and tag
docker build -t your-dockerhub-username/zentrion-orchestrator:latest .

# Push
docker push your-dockerhub-username/zentrion-orchestrator:latest

# Update manifests/orchestrator-deployment.yaml with your image name
```

---

### Step 6: Apply Orchestrator Config and Secrets

```bash
kubectl apply -f manifests/orchestrator-configmap.yaml
# orchestrator-secret is included in orchestrator-deployment.yaml
```

---

### Step 7: Deploy Orchestrator

```bash
kubectl apply -f manifests/orchestrator-deployment.yaml

# Wait for orchestrator to be ready
kubectl wait --for=condition=ready pod -l app=zentrion-orchestrator -n zentrion-system --timeout=120s

# Verify
kubectl get pods -n zentrion-system
kubectl logs -f -l app=zentrion-orchestrator -n zentrion-system
```

**Expected logs:**
```
[Nest] INFO [NestFactory] Starting Nest application...
[Nest] INFO [InstanceLoader] AppModule dependencies initialized
[Nest] INFO [K8sService] Connected to Kubernetes cluster
[Nest] INFO [IstioService] Watching Istio telemetry stream
[Nest] INFO [ServiceDiscovery] Watching deployments across all namespaces
🚀 Orchestrator API running on http://localhost:3001
📡 WebSocket available at ws://localhost:3001
```

---

## 🔌 **Access the Orchestrator**

### Port-Forward to Local Machine

```bash
kubectl port-forward -n zentrion-system svc/zentrion-orchestrator 3001:3001
```

**Test in browser:**
- Health check: http://localhost:3001/health
- API docs: http://localhost:3001/api (if swagger enabled)

**Test with curl:**
```bash
# Health check
curl http://localhost:3001/health

# Login
curl -X POST http://localhost:3001/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'
```

---

### Expose via LoadBalancer (Optional)

For cloud environments:

```bash
kubectl patch svc zentrion-orchestrator -n zentrion-system -p '{"spec":{"type":"LoadBalancer"}}'

# Get external IP
kubectl get svc zentrion-orchestrator -n zentrion-system
```

---

## ✅ **Verification Checklist**

After deployment, verify everything is working:

### 1. Pods are Running

```bash
kubectl get pods -n zentrion-system
```

**Should see:**
```
NAME                                    READY   STATUS    RESTARTS   AGE
postgresql-xxx                          2/2     Running   0          5m
zentrion-orchestrator-xxx               2/2     Running   0          2m
```

---

### 2. CRDs are Registered

```bash
kubectl get crd | grep zentrion
```

**Should see 3 CRDs:**
- anomalyrecords.zentrion.io
- policyhistories.zentrion.io
- securityprofiles.zentrion.io

---

### 3. RBAC is Applied

```bash
kubectl get serviceaccount zentrion-orchestrator -n zentrion-system
kubectl auth can-i create authorizationpolicies.security.istio.io \
  --as=system:serviceaccount:zentrion-system:zentrion-orchestrator
```

**Should return: yes**

---

### 4. PostgreSQL is Accessible

```bash
kubectl exec -it -n zentrion-system deployment/postgresql -- psql -U zentrion -d zentrion -c "\dt"
```

**Should show tables:**
```
 public | anomalies        | table | zentrion
 public | policy_drafts    | table | zentrion
 public | policy_history   | table | zentrion
 public | services         | table | zentrion
 public | telemetry_logs   | table | zentrion
 public | users            | table | zentrion
```

---

### 5. Orchestrator is Watching Telemetry

```bash
kubectl logs -l app=zentrion-orchestrator -n zentrion-system | grep -i telemetry
```

**Should see:**
```
[IstioService] Started watching Istio telemetry stream
[TelemetryService] Received telemetry event from productpage
```

---

### 6. Service Discovery is Working

```bash
# Check logs for discovered services
kubectl logs -l app=zentrion-orchestrator -n zentrion-system | grep -i "discovered"
```

**Should see:**
```
[ServiceDiscovery] Discovered service: productpage in namespace: default
[ServiceDiscovery] Discovered service: details in namespace: default
[ServiceDiscovery] Discovered service: reviews in namespace: default
```

---

### 7. API Endpoints Work

```bash
# Login and get token
TOKEN=$(curl -s -X POST http://localhost:3001/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' | jq -r '.accessToken')

# Get discovered services
curl -H "Authorization: Bearer $TOKEN" http://localhost:3001/telemetry/services | jq

# Get anomalies
curl -H "Authorization: Bearer $TOKEN" http://localhost:3001/anomalies | jq
```

---

## 📊 **View Zentrion in Action**

### 1. Watch Telemetry in Real-Time

```bash
kubectl logs -f -l app=zentrion-orchestrator -n zentrion-system
```

Generate traffic to Bookinfo:
```bash
export GATEWAY_URL=$(minikube ip):$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

for i in {1..50}; do
  curl -s "http://$GATEWAY_URL/productpage" > /dev/null
  echo "Request $i sent"
  sleep 2
done
```

You should see logs flowing through the orchestrator!

---

### 2. Check Created CRD Resources

```bash
# Security profiles (auto-created)
kubectl get securityprofiles -n default

# Anomaly records (when anomalies are detected)
kubectl get anomalyrecords -n default

# Policy history (when policies are applied)
kubectl get policyhistories -n zentrion-system
```

---

### 3. View Policies in Kiali

```bash
istioctl dashboard kiali
```

Navigate to: **Istio Config → Authorization Policies**

You should see policies created by Zentrion (labeled with `zentrion.io/generated: true`)!

---

## 🔧 **Configuration**

### Adjust Anomaly Detection Sensitivity

Edit the ConfigMap:

```bash
kubectl edit configmap orchestrator-config -n zentrion-system
```

Change:
```yaml
data:
  ANOMALY_DETECTION_INTERVAL_MS: "3000"  # Faster detection
```

Restart orchestrator:
```bash
kubectl rollout restart deployment/zentrion-orchestrator -n zentrion-system
```

---

### Enable Debug Logging

```bash
kubectl edit configmap orchestrator-config -n zentrion-system
```

Set:
```yaml
data:
  LOG_LEVEL: "debug"
```

Restart and view logs:
```bash
kubectl rollout restart deployment/zentrion-orchestrator -n zentrion-system
kubectl logs -f -l app=zentrion-orchestrator -n zentrion-system
```

---

## 🐛 **Troubleshooting**

### Issue: Orchestrator pod stuck in CrashLoopBackOff

**Check logs:**
```bash
kubectl logs -l app=zentrion-orchestrator -n zentrion-system --previous
```

**Common causes:**
1. PostgreSQL not ready
2. Missing secrets
3. RBAC permissions issue

**Solution:**
```bash
# Verify PostgreSQL is running
kubectl get pods -n zentrion-system -l app=postgresql

# Verify secrets exist
kubectl get secrets -n zentrion-system

# Check RBAC
kubectl describe clusterrolebinding zentrion-orchestrator-binding
```

---

### Issue: No telemetry flowing

**Check Istio access logs are enabled:**
```bash
kubectl get configmap istio -n istio-system -o yaml | grep accessLogFile
```

**Should show:**
```yaml
accessLogFile: /dev/stdout
```

**If not enabled:**
```bash
istioctl install --set profile=demo \
  --set meshConfig.accessLogFile=/dev/stdout
```

---

### Issue: Can't create policies

**Check RBAC permissions:**
```bash
kubectl auth can-i create authorizationpolicies.security.istio.io \
  --as=system:serviceaccount:zentrion-system:zentrion-orchestrator \
  --namespace=default
```

**Should return: yes**

**If no, reapply RBAC:**
```bash
kubectl apply -f manifests/rbac.yaml
```

---

### Issue: PostgreSQL connection failed

**Check PostgreSQL service:**
```bash
kubectl get svc postgresql -n zentrion-system
```

**Test connection from orchestrator pod:**
```bash
kubectl exec -it -n zentrion-system deployment/zentrion-orchestrator -- sh
nc -zv postgresql.zentrion-system.svc.cluster.local 5432
```

---

## 🗑️ **Cleanup**

### Remove Zentrion (keep cluster)

```bash
kubectl delete namespace zentrion-system
kubectl delete crd anomalyrecords.zentrion.io
kubectl delete crd policyhistories.zentrion.io
kubectl delete crd securityprofiles.zentrion.io
kubectl delete clusterrole zentrion-orchestrator-role
kubectl delete clusterrolebinding zentrion-orchestrator-binding
```

---

### Complete Cluster Reset

```bash
minikube delete
```

Then follow ENVIRONMENT_SETUP.md to start fresh.

---

## 📚 **Next Steps**

1. **Connect Dashboard** - Deploy your Next.js frontend
2. **Generate Traffic** - Test anomaly detection
3. **Create Policies** - Use the dashboard to approve policies
4. **View in Kiali** - See policies applied in the mesh

---

## 🎓 **Demo Script for FYP**

### 1. Show Running System

```bash
kubectl get pods -n zentrion-system
kubectl get pods -n default  # Bookinfo app
```

### 2. Generate Normal Traffic

```bash
for i in {1..20}; do curl -s "http://$GATEWAY_URL/productpage" > /dev/null; done
```

**Show in dashboard:** Normal telemetry, no anomalies

### 3. Simulate Attack

```bash
# Simulate DoS
for i in {1..100}; do curl -s "http://$GATEWAY_URL/productpage" > /dev/null & done

# Or simulate suspicious IP (modify productpage pod)
```

**Show in dashboard:** Anomaly detected! 🚨

### 4. Generate Policy

**In dashboard:** Click "Generate Policy from Anomaly"

**Show policy draft YAML**

### 5. Apply Policy

**In dashboard:** Click "Approve & Apply"

**Show in Kiali:** Policy is now visible in the mesh!

### 6. Verify Policy Works

```bash
# The suspicious pattern should now be blocked
# Check Kiali for policy enforcement metrics
```

**Ta-da! 🎉 Live Zero Trust Architecture in action!**

---

That's it! Your Zentrion system is deployed and operational.
