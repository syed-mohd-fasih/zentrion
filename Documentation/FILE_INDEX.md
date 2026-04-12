# Zentrion Complete File Index

Every file in the production system.

---

## 📚 **Documentation Files**

| File | Description | Status |
|------|-------------|--------|
| `README.md` | Main documentation | ✅ Done |
| `QUICKSTART.md` | 30-minute setup guide | ✅ Done |
| `ENVIRONMENT_SETUP.md` | Cluster setup (minikube + Istio) | ✅ Done |
| `DEPLOYMENT.md` | Deployment guide | ✅ Done |
| `CODE_MIGRATION.md` | Mock → Production migration reference | ✅ Done |
| `Documentation/IMPLEMENTATION_CHECKLIST.md` | Step-by-step checklist | ✅ Done |
| `Documentation/FILE_INDEX.md` | This file | ✅ Done |

---

## 🐳 **Docker Files**

| File | Description | Status |
|------|-------------|--------|
| `app/orchestrator-api/Dockerfile` | Container build | ✅ Done |
| `app/orchestrator-api/.dockerignore` | Docker ignore | ✅ Done |

---

## 📦 **Kubernetes Manifests**

### CRDs (3 files)
| File | Description | Status |
|------|-------------|--------|
| `manifests/crds/security-profile.yaml` | SecurityProfile CRD | ✅ Done |
| `manifests/crds/policy-history.yaml` | PolicyHistory CRD | ✅ Done |
| `manifests/crds/anomaly-record.yaml` | AnomalyRecord CRD | ✅ Done |

### Infrastructure (5 files)
| File | Description | Status |
|------|-------------|--------|
| `manifests/rbac.yaml` | RBAC (ClusterRole, ServiceAccount) | ✅ Done |
| `manifests/postgresql.yaml` | PostgreSQL deployment | ✅ Done |
| `manifests/orchestrator-configmap.yaml` | Configuration | ✅ Done |
| `manifests/orchestrator-deployment.yaml` | Main deployment | ✅ Done |
| `deploy.sh` | One-command deployment script | ✅ Done |

---

## 💻 **Backend Source Code**

### Core Application
| File | Description | Status |
|------|-------------|--------|
| `src/main.ts` | Application bootstrap | ✅ Done |
| `src/app.module.ts` | Root module (all modules wired) | ✅ Done |
| `src/health.controller.ts` | Health check endpoint | ✅ Done |
| `src/config/app.config.ts` | Configuration (synthetic config removed) | ✅ Done |

### Database Module (7 files)
| File | Description | Status |
|------|-------------|--------|
| `src/modules/database/database.module.ts` | TypeORM + PostgreSQL setup | ✅ Done |
| `src/modules/database/entities/telemetry-log.entity.ts` | Telemetry log entity | ✅ Done |
| `src/modules/database/entities/anomaly.entity.ts` | Anomaly entity | ✅ Done |
| `src/modules/database/entities/policy-draft.entity.ts` | Policy draft entity | ✅ Done |
| `src/modules/database/entities/policy-history.entity.ts` | Policy history entity | ✅ Done |
| `src/modules/database/entities/service.entity.ts` | Service entity | ✅ Done |
| `src/modules/database/entities/user.entity.ts` | User entity | ✅ Done |

### Auth Module
| File | Description | Status |
|------|-------------|--------|
| `src/modules/auth/auth.module.ts` | Auth module (UserRepository registered) | ✅ Done |
| `src/modules/auth/auth.service.ts` | Auth service (UserRepository + bcrypt) | ✅ Done |
| `src/modules/auth/auth.controller.ts` | Auth endpoints | ✅ Done |
| `src/modules/auth/jwt.strategy.ts` | JWT strategy (UserRepository) | ✅ Done |
| `src/modules/auth/jwt-auth.guard.ts` | Auth guard | ✅ Done |
| `src/modules/auth/roles.guard.ts` | Roles guard | ✅ Done |

### K8s Module
| File | Description | Status |
|------|-------------|--------|
| `src/modules/k8s/k8s.module.ts` | K8s module | ✅ Done |
| `src/modules/k8s/k8s.service.ts` | Real K8s client (`@kubernetes/client-node`) | ✅ Done |
| `src/modules/k8s/istio.builder.ts` | Istio AuthorizationPolicy YAML builder | ✅ Done |

### Istio Module
| File | Description | Status |
|------|-------------|--------|
| `src/modules/istio/istio.module.ts` | Istio module | ✅ Done |
| `src/modules/istio/istio.service.ts` | Envoy log watcher (emits `telemetry.log` events) | ✅ Done |

### CRD Module
| File | Description | Status |
|------|-------------|--------|
| `src/modules/crd/crd.module.ts` | CRD module | ✅ Done |
| `src/modules/crd/crd.service.ts` | SecurityProfile / AnomalyRecord / PolicyHistory CRD management | ✅ Done |

### Service Discovery Module
| File | Description | Status |
|------|-------------|--------|
| `src/modules/service-discovery/service-discovery.module.ts` | Service discovery module | ✅ Done |
| `src/modules/service-discovery/service-discovery.service.ts` | Deployment watcher → writes to `services` table | ✅ Done |

### Events Module (internal pub/sub)
| File | Description | Status |
|------|-------------|--------|
| `src/modules/events/events.module.ts` | EventEmitter2 module | ✅ Done |
| `src/modules/events/events.service.ts` | Internal event emit/subscribe helper | ✅ Done |

### Telemetry Module
| File | Description | Status |
|------|-------------|--------|
| `src/modules/telemetry/telemetry.module.ts` | Telemetry module (TelemetryLog + Service repos) | ✅ Done |
| `src/modules/telemetry/telemetry.service.ts` | `@OnEvent('telemetry.log')` → saves to PostgreSQL | ✅ Done |
| `src/modules/telemetry/telemetry.controller.ts` | REST endpoints (DB queries) | ✅ Done |
| `src/modules/telemetry/telemetry.gateway.ts` | WebSocket gateway (emits real-time events) | ✅ Done |

### Anomaly Module
| File | Description | Status |
|------|-------------|--------|
| `src/modules/anomaly/anomaly.module.ts` | Anomaly module (Anomaly + TelemetryLog repos) | ✅ Done |
| `src/modules/anomaly/anomaly.service.ts` | 8 detection rules, reads from DB, saves to DB | ✅ Done |
| `src/modules/anomaly/anomaly.controller.ts` | REST endpoints (DB queries) | ✅ Done |

### Policy Module
| File | Description | Status |
|------|-------------|--------|
| `src/modules/policy/policy.module.ts` | Policy module (PolicyDraft + PolicyHistory + Anomaly repos) | ✅ Done |
| `src/modules/policy/policy.service.ts` | Full workflow: DB-backed drafts/history, applies to K8s | ✅ Done |
| `src/modules/policy/policy.controller.ts` | REST endpoints (DB queries, no store imports) | ✅ Done |
| `src/modules/policy/policy.dto.ts` | Request DTOs | ✅ Done |

### Bootstrap
| File | Description | Status |
|------|-------------|--------|
| `src/bootstrap/seed.ts` | Seeds 3 default users (admin/analyst/viewer) to PostgreSQL | ✅ Done |

---

## ✅ **Files Status Summary**

All backend files are production-ready. No in-memory store usage remains in any module.

### Deleted
- `src/common/store.ts` — removed; all data now persists in PostgreSQL

### Notes
- **Sessions**: Auth token revocation tracked in an in-memory Map in `auth.service.ts`. Acceptable for FYP scope (sessions clear on app restart).
- **Istio telemetry**: `IstioService` watches Envoy logs and emits `telemetry.log` events. `TelemetryService` listens via `@OnEvent` and persists to DB.
- **No synthetic data**: The synthetic telemetry generator has been removed. All logs come from real Istio/Envoy traffic.

---

## 📦 **Dependencies (already installed)**

```bash
# All packages are in package.json
@kubernetes/client-node
@nestjs/typeorm
@nestjs/event-emitter
@nestjs/schedule
typeorm
pg
bcrypt
```

---

## ✅ **Deployment Status**

Phase 3 (Deployment) is **complete**. All backend services are deployed and verified.

1. ☑ Setup minikube cluster + Istio
2. ☑ Apply CRDs: `kubectl apply -f manifests/crds/`
3. ☑ Apply RBAC: `kubectl apply -f manifests/rbac.yaml`
4. ☑ Deploy PostgreSQL: `kubectl apply -f manifests/postgresql.yaml`
5. ☑ Build Docker image and push to minikube
6. ☑ Deploy Zentrion: `./deploy.sh`
7. ☑ Deploy Bookinfo sample app and verify telemetry
8. ☑ Test all 22 API endpoints
9. ☐ Connect Next.js dashboard — **next phase**

See `DEMO.md` for a step-by-step demo walkthrough.
