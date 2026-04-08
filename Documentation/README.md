# Zentrion - Zero Trust Security Orchestrator for Istio

**A plug-and-play security orchestrator that watches your Kubernetes + Istio cluster, detects anomalies in real-time, and generates security policies automatically.**

---

## 🎯 **What is Zentrion?**

Zentrion is a control-plane microservice for Kubernetes + Istio service meshes that:

- ✅ **Monitors** all traffic flowing through Istio sidecars
- ✅ **Detects** anomalies using rule-based detection (AI-ready architecture)
- ✅ **Generates** Istio AuthorizationPolicy manifests automatically
- ✅ **Enforces** human-in-the-loop approval workflow
- ✅ **Applies** policies directly to the cluster
- ✅ **Audits** all actions with full history trail

### Zero Trust Architecture

Every microservice communication is monitored, analyzed, and secured based on learned behavioral patterns.

---

## 📋 **Quick Start**

### Prerequisites

- minikube (running)
- kubectl
- Istio installed (demo profile)
- Docker

### Deploy in 3 Commands

```bash
# 1. Clone and navigate
git clone <repo> && cd zentrion

# 2. Deploy everything
chmod +x deploy.sh
./deploy.sh

# 3. Access API
curl http://localhost:3001/health
```

**That's it!** Zentrion is now watching your cluster.

---

## 🏗️ **Architecture**

```
┌───────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                    │
│  ┌─────────────────────────────────────────────────────┐  │
│  │              Istio Service Mesh                     │  │
│  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐             │  │
│  │  │ Pod  │  │ Pod  │  │ Pod  │  │ Pod  │             │  │
│  │  │      │  │      │  │      │  │      │             │  │
│  │  │+-----│  │+-----│  │+-----│  │+-----│             │  │
│  │  ││Envoy│  ││Envoy│  ││Envoy│  ││Envoy│◄────┐       │  │
│  │  │+-----│  │+-----│  │+-----│  │+-----│     │       │  │
│  │  └──────┘  └──────┘  └──────┘  └──────┘     │       │  │
│  │      │         │         │         │        │       │  │
│  │      └─────────┴─────────┴─────────┘        │       │  │
│  │                Access Logs (JSON)           │       │  │
│  └─────────────────────────────────────────────┼───────┘  │
│                                                │          │
│  ┌─────────────────────────────────────────────▼───────┐  │
│  │         Zentrion Orchestrator (Pod)                 │  │
│  │  ┌──────────────────────────────────────────────┐   │  │
│  │  │  Istio Watcher → Telemetry Parser            │   │  │
│  │  └──────────────┬───────────────────────────────┘   │  │
│  │                 │                                   │  │
│  │  ┌──────────────▼───────────────────────────────┐   │  │
│  │  │  Anomaly Detector (8 rules)                  │   │  │
│  │  └──────────────┬───────────────────────────────┘   │  │
│  │                 │                                   │  │
│  │  ┌──────────────▼───────────────────────────────┐   │  │
│  │  │  Policy Generator (Template-based)           │   │  │
│  │  └──────────────┬───────────────────────────────┘   │  │
│  │                 │                                   │  │
│  │  ┌──────────────▼───────────────────────────────┐   │  │
│  │  │  REST API + WebSocket (Dashboard Interface)  │   │  │
│  │  └──────────────────────────────────────────────┘   │  │
│  │                                                     │  │
│  │  PostgreSQL │ Zentrion CRDs                         │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
└───────────────────────────────────────────────────────────┘
                           │
                           │ HTTP/WS
                           ▼
                  ┌─────────────────┐
                  │  Next.js        │
                  │  Dashboard      │
                  └─────────────────┘
```

---

## 🔧 **Components**

### Backend (NestJS)

- **Istio Watcher** - Streams Envoy access logs from all pods
- **Service Discovery** - Watches Kubernetes Deployments
- **Anomaly Detector** - 8 detection rules (traffic spikes, unusual sources, etc.)
- **Policy Generator** - Creates AuthorizationPolicy YAML
- **K8s Client** - Applies policies to cluster
- **CRD Manager** - Manages Zentrion custom resources
- **PostgreSQL** - Stores telemetry, anomalies, policies, audit logs

### Custom Resource Definitions (CRDs)

1. **SecurityProfile** - Learned traffic baselines per service
2. **AnomalyRecord** - Persistent anomaly records
3. **PolicyHistory** - Complete audit trail

### Frontend (Next.js)

- **Live Telemetry Feed** - Real-time logs from cluster
- **Anomaly Dashboard** - Detected threats and patterns
- **Policy Review** - Approve/reject auto-generated policies
- **Audit Trail** - Who did what, when

---

## 📊 **Data Flow**

```
Envoy Logs → Istio Watcher → Telemetry Parser → PostgreSQL
                                      ↓
                                Anomaly Detector
                                      ↓
                                Policy Generator
                                      ↓
                              Policy Draft (pending)
                                      ↓
                            Dashboard Review (human)
                                      ↓
                              Approve → K8s API
                                      ↓
                           AuthorizationPolicy Applied
                                      ↓
                              Visible in Kiali ✅
```

---

## 🎓 **For Academic Projects (FYP)**

### What Makes This FYP-Worthy?

1. **Novel Integration** - Combines Istio, K8s, and Zero Trust
2. **Real Implementation** - Not a simulation, runs on actual cluster
3. **Custom CRDs** - Demonstrates K8s extension knowledge
4. **Service Mesh Security** - Modern cloud-native topic
5. **Human-in-Loop** - Not fully automated (reviewable decisions)
6. **Scalable Architecture** - Ready for AI/ML integration later

### Demo Flow (5 Minutes)

```bash
# 1. Show running system
kubectl get pods -n zentrion-system
kubectl get pods -n default  # Bookinfo sample app

# 2. Generate normal traffic
for i in {1..20}; do
  curl http://$GATEWAY_URL/productpage
done

# Open dashboard - show normal telemetry ✅

# 3. Simulate attack (traffic spike)
for i in {1..100}; do
  curl http://$GATEWAY_URL/productpage &
done

# Dashboard shows anomaly detected! 🚨

# 4. Generate policy
Click "Generate Policy from Anomaly"
# Shows AuthorizationPolicy YAML

# 5. Approve policy
Click "Approve & Apply"

# 6. Verify in Kiali
istioctl dashboard kiali
# Navigate to Istio Config → Authorization Policies
# See Zentrion-generated policy! ✅

# 7. Show audit trail
Click "Policy History" in dashboard
# Complete record of who approved what
```

---

## 🚀 **Deployment**

See detailed guides:

- **[ENVIRONMENT_SETUP.md](./Documentation/ENVIRONMENT_SETUP.md)** - Set up minikube + Istio
- **[DEPLOYMENT.md](./Documentation/DEPLOYMENT.md)** - Deploy Zentrion
- **[CODE_MIGRATION.md](./Documentation/CODE_MIGRATION.md)** - From mock to production

### Quick Deploy

```bash
./deploy.sh
```

### Manual Deploy

```bash
# Create namespace
kubectl create namespace zentrion-system
kubectl label namespace zentrion-system istio-injection=enabled

# Apply CRDs
kubectl apply -f manifests/crds/

# Apply RBAC
kubectl apply -f manifests/rbac.yaml

# Deploy PostgreSQL
kubectl apply -f manifests/postgresql.yaml

# Build image
eval $(minikube docker-env)
cd apps/orchestrator-api
docker build -t zentrion/orchestrator-api:latest .

# Deploy orchestrator
kubectl apply -f manifests/orchestrator-configmap.yaml
kubectl apply -f manifests/orchestrator-deployment.yaml

# Port-forward
kubectl port-forward -n zentrion-system svc/zentrion-orchestrator 3001:3001
```

---

## 📡 **API Reference**

### Authentication

```bash
# Login
curl -X POST http://localhost:3001/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'
# Returns: {"accessToken": "...", "user": {...}}

# Use token in subsequent requests
TOKEN="your-jwt-token"
```

### Endpoints

```bash
# Health check
GET /health

# Get services
GET /telemetry/services
Authorization: Bearer $TOKEN

# Get live logs
GET /telemetry/live?limit=100&service=productpage
Authorization: Bearer $TOKEN

# Get anomalies
GET /anomalies
Authorization: Bearer $TOKEN

# Get pending policy drafts
GET /policies/drafts/pending
Authorization: Bearer $TOKEN

# Approve policy (ADMIN only)
POST /policies/drafts/:id/approve
Authorization: Bearer $TOKEN

# Get audit history
GET /policies/history
Authorization: Bearer $TOKEN
```

### WebSocket Events

```javascript
import io from "socket.io-client";

const socket = io("http://localhost:3001");

socket.on("telemetry.log", (log) => {
	console.log("New log:", log);
});

socket.on("anomaly.created", (anomaly) => {
	console.log("Anomaly detected!", anomaly);
});

socket.on("policy.applied", (policy) => {
	console.log("Policy applied!", policy);
});
```

---

## 🔍 **Anomaly Detection Rules**

1. **UNUSUAL_SOURCE** - Requests from suspicious IPs
2. **UNEXPECTED_COMMUNICATION** - Service calls not in known graph
3. **NEW_ENDPOINT** - Previously unseen API paths
4. **HIGH_ERROR_RATE** - Error rate > 20%
5. **TRAFFIC_SPIKE** - 3x traffic increase
6. **SUSPICIOUS_PATTERN** - Rapid requests (potential DoS)
7. **LATENCY_ANOMALY** - 3x latency increase
8. **UNAUTHORIZED_ACCESS** - Multiple 401/403 responses

---

## 🗄️ **Database Schema**

```sql
-- Telemetry logs
telemetry_logs (
  id, timestamp, source, source_ip, method, path,
  status, latency_ms, service, dest_service
)

-- Anomalies
anomalies (
  id, anomaly_id, timestamp, service, type, severity,
  details, associated_logs, resolved
)

-- Policy drafts
policy_drafts (
  id, draft_id, service, namespace, yaml_content,
  status, created_by, approved_by, applied_at
)

-- Policy history (audit trail)
policy_history (
  id, policy_id, action, timestamp, user_id, details
)

-- Discovered services
services (
  id, name, namespace, labels, dependencies, first_seen
)

-- Users
users (
  id, username, password_hash, role, email
)
```

---

## 🐛 **Troubleshooting**

### Orchestrator pod won't start

```bash
# Check logs
kubectl logs -l app=zentrion-orchestrator -n zentrion-system

# Common issues:
# 1. PostgreSQL not ready
kubectl get pods -n zentrion-system -l app=postgresql

# 2. RBAC permissions
kubectl auth can-i create authorizationpolicies.security.istio.io \
  --as=system:serviceaccount:zentrion-system:zentrion-orchestrator
```

### No telemetry flowing

```bash
# Check Istio access logs are enabled
kubectl get configmap istio -n istio-system -o yaml | grep accessLogFile
# Should show: accessLogFile: /dev/stdout

# If not:
istioctl install --set profile=demo --set meshConfig.accessLogFile=/dev/stdout
```

### Can't create policies

```bash
# Check RBAC
kubectl get clusterrolebinding | grep zentrion

# Reapply if missing
kubectl apply -f manifests/rbac.yaml
```

---

## 📚 **Project Structure**

```
zentrion/
├── apps/
│   └── orchestrator-api/          # NestJS backend
│       ├── src/
│       │   ├── modules/
│       │   │   ├── auth/          # JWT authentication
│       │   │   ├── database/      # TypeORM entities
│       │   │   ├── k8s/           # Kubernetes client
│       │   │   ├── istio/         # Istio telemetry watcher
│       │   │   ├── crd/           # CRD management
│       │   │   ├── service-discovery/  # Deployment watcher
│       │   │   ├── telemetry/     # Telemetry service
│       │   │   ├── anomaly/       # Anomaly detection
│       │   │   └── policy/        # Policy management
│       │   ├── main.ts
│       │   └── app.module.ts
│       └── Dockerfile
├── manifests/
│   ├── crds/                      # Zentrion CRDs
│   ├── rbac.yaml                  # RBAC for orchestrator
│   ├── postgresql.yaml            # Database deployment
│   ├── orchestrator-configmap.yaml
│   └── orchestrator-deployment.yaml
├── deploy.sh                      # One-command deploy
├── ENVIRONMENT_SETUP.md           # Cluster setup guide
├── DEPLOYMENT.md                  # Deployment guide
└── CODE_MIGRATION.md              # Migration guide
```

---

## 🎯 **Roadmap**

### Phase 1: MVP (Current) ✅

- [x] Real Istio telemetry integration
- [x] PostgreSQL persistence
- [x] Zentrion CRDs
- [x] Service discovery
- [x] Rule-based anomaly detection
- [x] Policy generation & application
- [x] Audit trail

### Phase 2: AI Integration (Future)

- [ ] Train Qwen model on cluster data
- [ ] ML-based anomaly detection
- [ ] Intelligent policy generation
- [ ] Predictive threat analysis

### Phase 3: Production Hardening (Future)

- [ ] Multi-replica orchestrator (HA)
- [ ] Kafka/NATS event broker
- [ ] GitOps workflow
- [ ] Advanced RBAC
- [ ] Prometheus metrics export

---

## 🙌 **Contributing**

This is a Final Year Project (FYP). For academic integrity, contributions are limited to the project team.

---

## 📄 **License**

MIT License - Academic Project

---

## 👨‍💻 **Team**

Zentrion Team - Final Year Project 2025

---

## 📞 **Support**

- **Issues**: Check troubleshooting guides first
- **Logs**: `kubectl logs -f -l app=zentrion-orchestrator -n zentrion-system`
- **Kiali**: `istioctl dashboard kiali` (visualize mesh)
- **Grafana**: `kubectl port-forward -n istio-system svc/grafana 3000:3000`

---

**Built with ❤️ for Zero Trust Security in Cloud-Native Environments**
