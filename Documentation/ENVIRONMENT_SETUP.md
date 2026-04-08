# Zentrion Environment Setup Guide

Complete guide to set up a local Kubernetes + Istio cluster for Zentrion development.

---

## 📋 **Prerequisites**

### System Requirements
- **OS**: Linux, macOS, or Windows (WSL2)
- **RAM**: 8GB minimum (16GB recommended)
- **CPU**: 4 cores minimum
- **Disk**: 20GB free space

### Software to Install
- Docker Desktop (or Docker Engine + Docker Compose)
- kubectl
- minikube
- Helm 3

---

## 🔧 **Step 1: Install Required Tools**

### Install Docker Desktop

**macOS:**
```bash
brew install --cask docker
```

**Linux:**
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker
```

**Windows:**
Download from https://www.docker.com/products/docker-desktop

**Verify:**
```bash
docker --version
# Should show: Docker version 24.x.x or higher
```

---

### Install kubectl

**macOS:**
```bash
brew install kubectl
```

**Linux:**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

**Windows (WSL2):**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

**Verify:**
```bash
kubectl version --client
```

---

### Install minikube

**macOS:**
```bash
brew install minikube
```

**Linux:**
```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

**Windows (WSL2):**
```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

**Verify:**
```bash
minikube version
```

---

### Install Helm

**macOS:**
```bash
brew install helm
```

**Linux/WSL2:**
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**Verify:**
```bash
helm version
```

---

## 🚀 **Step 2: Start minikube Cluster**

### Start with Proper Resources

```bash
minikube start \
  --cpus=4 \
  --memory=8192 \
  --disk-size=20g \
  --driver=docker \
  --kubernetes-version=v1.28.0
```

**What this does:**
- Allocates 4 CPU cores
- Allocates 8GB RAM
- Creates 20GB disk
- Uses Docker driver (best compatibility)
- Uses K8s 1.28 (stable, Istio-compatible)

**Wait for:**
```
✅ minikube v1.x.x on Darwin 14.x (arm64)
✨ Using the docker driver based on user configuration
👍 Starting control plane node minikube in cluster minikube
🚜 Pulling base image ...
🔥 Creating docker container (CPUs=4, Memory=8192MB) ...
🐳 Preparing Kubernetes v1.28.0 on Docker 24.x.x ...
🔎 Verifying Kubernetes components...
🌟 Enabled addons: storage-provisioner, default-storageclass
🏄 Done! kubectl is now configured to use "minikube" cluster
```

---

### Verify Cluster is Running

```bash
kubectl cluster-info
# Should show: Kubernetes control plane is running at https://...

kubectl get nodes
# Should show:
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   1m    v1.28.0
```

---

## 🌐 **Step 3: Install Istio**

### Download Istio

```bash
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH
```

**Add to your shell profile (optional):**
```bash
echo 'export PATH="$HOME/istio-1.20.0/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Verify:**
```bash
istioctl version
# Should show: no running Istio pods in "istio-system"
# (This is normal - we haven't installed yet)
```

---

### Install Istio with Demo Profile

The demo profile includes everything we need:
- Istio control plane (istiod)
- Ingress gateway
- Egress gateway
- Prometheus
- Grafana
- Kiali
- Jaeger

```bash
istioctl install --set profile=demo -y
```

**Expected output:**
```
✔ Istio core installed
✔ Istiod installed
✔ Ingress gateways installed
✔ Egress gateways installed
✔ Installation complete
```

**Verify installation:**
```bash
kubectl get pods -n istio-system
```

**Should see (all Running):**
```
NAME                                    READY   STATUS    RESTARTS   AGE
grafana-xxx                             1/1     Running   0          1m
istio-egressgateway-xxx                 1/1     Running   0          1m
istio-ingressgateway-xxx                1/1     Running   0          1m
istiod-xxx                              1/1     Running   0          1m
jaeger-xxx                              1/1     Running   0          1m
kiali-xxx                               1/1     Running   0          1m
prometheus-xxx                          1/1     Running   0          1m
```

---

### Enable Automatic Sidecar Injection

```bash
# Label default namespace for automatic injection
kubectl label namespace default istio-injection=enabled

# Verify
kubectl get namespace -L istio-injection
```

**Should show:**
```
NAME              STATUS   AGE   ISTIO-INJECTION
default           Active   10m   enabled
istio-system      Active   5m
kube-node-lease   Active   10m
kube-public       Active   10m
kube-system       Active   10m
```

---

## 📊 **Step 4: Access Istio Dashboards**

### Port-Forward Grafana

```bash
kubectl port-forward -n istio-system svc/grafana 3000:3000 &
```

**Access:** http://localhost:3000
- Username: admin
- Password: admin (default)

**Dashboards to explore:**
- Istio Mesh Dashboard
- Istio Service Dashboard
- Istio Workload Dashboard

---

### Port-Forward Kiali

```bash
kubectl port-forward -n istio-system svc/kiali 20001:20001 &
```

**Access:** http://localhost:20001
- Token auth (get token with: `kubectl -n istio-system create token kiali-service-account`)

**Or use port-forward without auth:**
```bash
istioctl dashboard kiali
```

---

### Port-Forward Jaeger

```bash
kubectl port-forward -n istio-system svc/tracing 16686:16686 &
```

**Access:** http://localhost:16686

---

## 🎯 **Step 5: Deploy Sample Application**

Deploy Istio's Bookinfo app to test telemetry:

```bash
# Deploy bookinfo
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/bookinfo/platform/kube/bookinfo.yaml

# Wait for pods to be ready
kubectl get pods
# Wait until all show 2/2 READY (app + envoy sidecar)

# Create ingress gateway
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/bookinfo/networking/bookinfo-gateway.yaml

# Get ingress IP/port
export INGRESS_HOST=$(minikube ip)
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

echo "Bookinfo URL: http://$GATEWAY_URL/productpage"
```

**Test in browser:**
Visit: `http://<minikube-ip>:<ingress-port>/productpage`

You should see the Bookinfo application!

---

### Generate Traffic

```bash
# Generate continuous traffic for testing
for i in {1..100}; do
  curl -s "http://$GATEWAY_URL/productpage" > /dev/null
  echo "Request $i sent"
  sleep 1
done
```

---

## 🔍 **Step 6: Verify Telemetry is Flowing**

### Check Envoy Access Logs

```bash
# Pick any pod
kubectl logs -l app=productpage -c istio-proxy --tail=10
```

**You should see JSON logs like:**
```json
{
  "start_time": "2025-01-15T10:30:45.123Z",
  "method": "GET",
  "path": "/productpage",
  "protocol": "HTTP/1.1",
  "response_code": 200,
  "response_flags": "-",
  "bytes_received": 0,
  "bytes_sent": 4183,
  "duration": 127,
  "upstream_service_time": "125",
  "x_forwarded_for": "10.244.0.1",
  "user_agent": "curl/7.64.1",
  "request_id": "abc-123-xyz",
  "authority": "192.168.49.2:31234",
  "upstream_host": "10.244.0.15:9080"
}
```

**This is what Zentrion will consume!**

---

### Check Prometheus Metrics

```bash
kubectl port-forward -n istio-system svc/prometheus 9090:9090 &
```

**Access:** http://localhost:9090

**Try this PromQL query:**
```promql
istio_requests_total{destination_service_name="productpage"}
```

You should see metrics!

---

## 📦 **Step 7: Create Zentrion Namespace**

```bash
kubectl create namespace zentrion-system
kubectl label namespace zentrion-system istio-injection=enabled

# Verify
kubectl get ns zentrion-system -o yaml
```

---

## ✅ **Verification Checklist**

Before proceeding to deploy Zentrion, verify:

- [ ] minikube is running: `minikube status`
- [ ] Kubectl works: `kubectl get nodes`
- [ ] Istio is installed: `kubectl get pods -n istio-system`
- [ ] All Istio pods are Running (7 pods)
- [ ] Default namespace has sidecar injection: `kubectl get ns default -L istio-injection`
- [ ] Bookinfo app is deployed: `kubectl get pods` (all 2/2 READY)
- [ ] Can access Bookinfo: Visit productpage URL
- [ ] Envoy logs are visible: `kubectl logs -l app=productpage -c istio-proxy`
- [ ] Grafana accessible: http://localhost:3000
- [ ] Kiali accessible: http://localhost:20001
- [ ] zentrion-system namespace created

---

## 🐛 **Troubleshooting**

### Issue: minikube won't start

**Solution:**
```bash
minikube delete
minikube start --cpus=4 --memory=8192 --driver=docker
```

---

### Issue: Istio pods stuck in Pending

**Solution:**
```bash
# Check resources
kubectl describe pod <pod-name> -n istio-system

# If resource issues, restart with more memory
minikube delete
minikube start --cpus=4 --memory=12288
```

---

### Issue: Bookinfo pods show 1/2 READY

**Solution:**
```bash
# Check if namespace is labeled
kubectl get ns default -L istio-injection

# If not labeled:
kubectl label namespace default istio-injection=enabled

# Delete and recreate pods
kubectl delete pods --all
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/bookinfo/platform/kube/bookinfo.yaml
```

---

### Issue: Can't access dashboards

**Solution:**
```bash
# Kill existing port-forwards
pkill kubectl

# Restart specific port-forward
kubectl port-forward -n istio-system svc/grafana 3000:3000
```

---

## 📚 **Useful Commands**

### Cluster Management
```bash
# Stop cluster
minikube stop

# Start cluster
minikube start

# Delete cluster (clean slate)
minikube delete

# SSH into minikube
minikube ssh

# Get cluster IP
minikube ip
```

### Istio Commands
```bash
# Check Istio version
istioctl version

# Analyze configuration
istioctl analyze

# View proxy config
istioctl proxy-config routes <pod-name>

# Enable access logs (if not already)
istioctl install --set profile=demo \
  --set meshConfig.accessLogFile=/dev/stdout
```

### Debugging
```bash
# Describe pod
kubectl describe pod <pod-name>

# Get logs
kubectl logs <pod-name> -c <container-name>

# Get events
kubectl get events --sort-by='.lastTimestamp'

# Execute into pod
kubectl exec -it <pod-name> -- /bin/sh
```

---

## 🎉 **Next Steps**

Your environment is ready! Now proceed to:

1. **Deploy Zentrion CRDs** (next guide)
2. **Deploy PostgreSQL** (next guide)
3. **Deploy Zentriion Orchestrator** (next guide)
4. **Connect Dashboard** (next guide)

---

## 📖 **Additional Resources**

- [Istio Documentation](https://istio.io/latest/docs/)
- [minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
