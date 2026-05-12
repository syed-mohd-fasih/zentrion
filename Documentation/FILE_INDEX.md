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

### Infrastructure (6 files)
| File | Description | Status |
|------|-------------|--------|
| `manifests/rbac.yaml` | RBAC (ClusterRole, ServiceAccount) | ✅ Done |
| `manifests/postgresql.yaml` | PostgreSQL deployment | ✅ Done |
| `manifests/orchestrator-configmap.yaml` | Configuration (incl. AI service env vars) | ✅ Done |
| `manifests/orchestrator-deployment.yaml` | Main deployment (incl. AI env var refs) | ✅ Done |
| `manifests/ollama.yaml` | (Legacy) in-cluster Ollama deployment. Current setup runs Ollama as a sibling Docker container on the `minikube` network with a host bind mount; managed by `deploy.sh`. | ⚠️ Deprecated |
| `deploy.sh` | One-command deployment script. Manages the Ollama container lifecycle (persistent volume), builds + rolls out orchestrator & dashboard, supports `--no-cache` | ✅ Done |

---

## 💻 **Backend Source Code**

### Core Application
| File | Description | Status |
|------|-------------|--------|
| `src/main.ts` | Application bootstrap | ✅ Done |
| `src/app.module.ts` | Root module (all modules wired) | ✅ Done |
| `src/health.controller.ts` | Health check endpoint | ✅ Done |
| `src/config/app.config.ts` | Configuration (synthetic config removed) | ✅ Done |

### Database Module (8 files)
| File | Description | Status |
|------|-------------|--------|
| `src/modules/database/database.module.ts` | TypeORM + PostgreSQL setup | ✅ Done |
| `src/modules/database/entities/telemetry-log.entity.ts` | Telemetry log entity | ✅ Done |
| `src/modules/database/entities/anomaly.entity.ts` | Anomaly entity | ✅ Done |
| `src/modules/database/entities/policy-draft.entity.ts` | Policy draft (+ llmExplanation, sandboxResult cols) | ✅ Done |
| `src/modules/database/entities/policy-history.entity.ts` | Policy history entity | ✅ Done |
| `src/modules/database/entities/service.entity.ts` | Service entity | ✅ Done |
| `src/modules/database/entities/system-setting.entity.ts` | Key-value runtime settings | ✅ Done |
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

### Settings Module
| File | Description | Status |
|------|-------------|--------|
| `src/modules/settings/settings.module.ts` | Settings module (exports SettingsService) | ✅ Done |
| `src/modules/settings/settings.service.ts` | OnModuleInit seeds defaults, in-memory cache | ✅ Done |
| `src/modules/settings/settings.controller.ts` | GET /settings, PATCH /settings (ADMIN) | ✅ Done |

### Anomaly Module
| File | Description | Status |
|------|-------------|--------|
| `src/modules/anomaly/anomaly.module.ts` | Anomaly module (+ AiDetectionService + SettingsModule) | ✅ Done |
| `src/modules/anomaly/anomaly.service.ts` | Rules OR ML detection, routed by SettingsService | ✅ Done |
| `src/modules/anomaly/anomaly.controller.ts` | REST endpoints (DB queries) | ✅ Done |
| `src/modules/anomaly/ai-detection.service.ts` | Calls FastAPI XGBoost ONNX service (host:8000) | ✅ Done |

### Policy Module
| File | Description | Status |
|------|-------------|--------|
| `src/modules/policy/policy.module.ts` | Policy module (+ LlmService + SandboxService + SettingsModule) | ✅ Done |
| `src/modules/policy/policy.service.ts` | Draft workflow + lazy LLM explanation backfill + simulate + per-draft chat (`chatWithDraft`, `getChatHistory`, `bootstrapChat`) + 5-min compliance score cache | ✅ Done |
| `src/modules/policy/policy.controller.ts` | REST endpoints: explain, simulate, compliance, **GET/POST `/drafts/:id/chat`** (SSE stream) | ✅ Done |
| `src/modules/policy/policy.dto.ts` | Request DTOs | ✅ Done |
| `src/modules/policy/llm.service.ts` | Calls Ollama `/api/generate` (explain, compliance) and `/api/chat` (streaming chat); robust to empty/error responses when no model is loaded | ✅ Done |
| `src/modules/policy/sandbox.service.ts` | Simulates policy against historical traffic (pure-JS) | ✅ Done |
| `src/modules/anomaly/anomaly.controller.ts` | Read routes + **PATCH `:id/resolve`**, **PATCH `:id/whitelist`**, **POST `:id/block-ip`** (drafts a deny policy from the anomaly's source IP) | ✅ Done |
| `src/modules/database/entities/policy-draft.entity.ts` | `policy_drafts` row. New `chatHistory` jsonb column persists the AI chat conversation per draft | ✅ Done |
| `src/modules/k8s/istio.builder.ts` | YAML builder for AuthorizationPolicy/PeerAuthentication. `needsQuoting()` now quotes values containing `:`, `#`, flow chars, or leading whitespace so colons in annotation values don't break `js-yaml` | ✅ Done |

### Bootstrap
| File | Description | Status |
|------|-------------|--------|
| `src/bootstrap/seed.ts` | Seeds 3 default users (admin/analyst/viewer) to PostgreSQL | ✅ Done |

---

## 🤖 **AI Layer Files**

### Python ML Service (`ai/anomaly_detector/`)
| File | Description | Status |
|------|-------------|--------|
| `requirements.txt` | FastAPI, XGBoost, ONNX, scikit-learn, psycopg2 | ✅ Done |
| `data/export_from_postgres.py` | Exports telemetry → 5-min feature windows CSV | ✅ Done |
| `train.py` | Trains XGBClassifier, exports ONNX + label encoder | ✅ Done |
| `serve.py` | FastAPI server: GET /health, POST /detect | ✅ Done |

### Attack Simulation (`ai/attack_sim/`)
| File | Description | Status |
|------|-------------|--------|
| `traffic_spike.py` | 20-thread flood for 60 s | ✅ Done |
| `suspicious_pattern.py` | 50+ requests from single IP | ✅ Done |
| `new_endpoint.py` | Probes /admin, /.env, /config, /debug | ✅ Done |
| `unauthorized_access.py` | Invalid/missing auth requests | ✅ Done |
| `high_error_rate.py` | Requests to non-existent paths | ✅ Done |
| `latency_anomaly.py` | Concurrent requests overwhelming endpoint | ✅ Done |
| `unusual_source.py` | X-Forwarded-For spoofing | ✅ Done |
| `normal_traffic.py` | Realistic baseline (0.5–3 s delays) | ✅ Done |
| `run_all.sh` | Runs all 8 scripts in parallel | ✅ Done |

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

All phases are **complete**.

1. ☑ Setup minikube cluster + Istio
2. ☑ Apply CRDs: `kubectl apply -f manifests/crds/`
3. ☑ Apply RBAC: `kubectl apply -f manifests/rbac.yaml`
4. ☑ Deploy PostgreSQL: `kubectl apply -f manifests/postgresql.yaml`
5. ☑ Build Docker image and push to minikube
6. ☑ Deploy Zentrion + Ollama: `./deploy.sh`
7. ☑ Deploy Bookinfo sample app and verify telemetry
8. ☑ Dashboard deployed and connected
9. ☑ AI layer: Settings page, Explain drawer, Simulate modal
10. ☐ Start FastAPI ML service on host: `cd ai/anomaly_detector && uvicorn serve:app --host 0.0.0.0 --port 8000`
11. ☐ Train model (run attack sim → export → train)
12. ☐ Enable AI detection mode via Settings page

See `DEPLOYMENT.md` for full deployment guide including AI layer setup.
