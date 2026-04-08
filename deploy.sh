#!/bin/bash

# Zentrion One-Command Deployment Script
# Deploys complete system to minikube

set -e

echo "🚀 Zentrion Deployment Script"
echo "================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check prerequisites
echo "🔍 Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please install kubectl.${NC}"
    exit 1
fi

if ! command -v minikube &> /dev/null; then
    echo -e "${RED}❌ minikube not found. Please install minikube.${NC}"
    exit 1
fi

# Check if minikube is running
if ! minikube status &> /dev/null; then
    echo -e "${RED}❌ minikube is not running. Please start minikube first.${NC}"
    echo "Run: minikube start --cpus=4 --memory=8192"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Step 1: Create namespace
echo "📦 Step 1: Creating zentrion-system namespace..."
kubectl create namespace zentrion-system --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace zentrion-system istio-injection=enabled --overwrite
echo -e "${GREEN}✅ Namespace created${NC}"
echo ""

# Step 2: Apply CRDs
echo "📋 Step 2: Applying Zentrion CRDs..."
kubectl apply -f manifests/crds/security-profile.yaml
kubectl apply -f manifests/crds/policy-history.yaml
kubectl apply -f manifests/crds/anomaly-record.yaml
echo -e "${GREEN}✅ CRDs applied${NC}"
echo ""

# Step 3: Apply RBAC
echo "🔐 Step 3: Applying RBAC..."
kubectl apply -f manifests/rbac.yaml
echo -e "${GREEN}✅ RBAC applied${NC}"
echo ""

# Step 4: Deploy PostgreSQL
echo "🐘 Step 4: Deploying PostgreSQL..."
kubectl apply -f manifests/postgresql.yaml

echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=postgresql -n zentrion-system --timeout=120s || {
    echo -e "${RED}❌ PostgreSQL failed to start${NC}"
    exit 1
}
echo -e "${GREEN}✅ PostgreSQL deployed${NC}"
echo ""

# Step 5: Build Docker image
echo "🐳 Step 5: Building Docker image..."
eval $(minikube docker-env)

cd apps/orchestrator-api
docker build -t zentrion/orchestrator-api:latest . || {
    echo -e "${RED}❌ Docker build failed${NC}"
    exit 1
}
cd ../..

echo -e "${GREEN}✅ Docker image built${NC}"
echo ""

# Step 6: Deploy Orchestrator
echo "🎯 Step 6: Deploying Orchestrator..."
kubectl apply -f manifests/orchestrator-configmap.yaml
kubectl apply -f manifests/orchestrator-deployment.yaml

echo "Waiting for Orchestrator to be ready..."
kubectl wait --for=condition=ready pod -l app=zentrion-orchestrator -n zentrion-system --timeout=120s || {
    echo -e "${YELLOW}⚠️  Orchestrator not ready yet. Checking logs...${NC}"
    kubectl logs -l app=zentrion-orchestrator -n zentrion-system --tail=50
    exit 1
}
echo -e "${GREEN}✅ Orchestrator deployed${NC}"
echo ""

# Step 7: Verify deployment
echo "🔍 Step 7: Verifying deployment..."
echo ""

echo "Pods in zentrion-system:"
kubectl get pods -n zentrion-system
echo ""

echo "CRDs:"
kubectl get crd | grep zentrion
echo ""

echo "Services:"
kubectl get svc -n zentrion-system
echo ""

# Step 8: Port-forward setup
echo "🔌 Step 8: Setting up port-forward..."
echo ""

# Kill existing port-forwards
pkill -f "kubectl port-forward.*zentrion-orchestrator" || true

# Start port-forward in background
kubectl port-forward -n zentrion-system svc/zentrion-orchestrator 3001:3001 &
PF_PID=$!

echo -e "${GREEN}✅ Port-forward started (PID: $PF_PID)${NC}"
echo ""

# Wait a moment for port-forward to establish
sleep 3

# Step 9: Test API
echo "🧪 Step 9: Testing API..."
echo ""

HEALTH_RESPONSE=$(curl -s http://localhost:3001/health || echo "failed")

if echo "$HEALTH_RESPONSE" | grep -q "ok"; then
    echo -e "${GREEN}✅ API health check passed${NC}"
    echo "$HEALTH_RESPONSE" | jq '.' || echo "$HEALTH_RESPONSE"
else
    echo -e "${RED}❌ API health check failed${NC}"
    echo "Response: $HEALTH_RESPONSE"
    echo ""
    echo "Checking logs..."
    kubectl logs -l app=zentrion-orchestrator -n zentrion-system --tail=20
fi

echo ""

# Summary
echo "================================"
echo -e "${GREEN}🎉 Deployment Complete!${NC}"
echo "================================"
echo ""
echo "📊 Access Points:"
echo "  • Orchestrator API: http://localhost:3001"
echo "  • Health Check: http://localhost:3001/health"
echo "  • WebSocket: ws://localhost:3001"
echo ""
echo "👥 Default Users:"
echo "  • admin / admin123 (ADMIN)"
echo "  • analyst / analyst123 (ANALYST)"
echo "  • viewer / viewer123 (VIEWER)"
echo ""
echo "🔧 Useful Commands:"
echo "  • View logs: kubectl logs -f -l app=zentrion-orchestrator -n zentrion-system"
echo "  • Get pods: kubectl get pods -n zentrion-system"
echo "  • Get CRDs: kubectl get securityprofiles,anomalyrecords,policyhistories -A"
echo "  • Restart: kubectl rollout restart deployment/zentrion-orchestrator -n zentrion-system"
echo ""
echo "📚 Next Steps:"
echo "  1. Test login: curl -X POST http://localhost:3001/auth/login -H 'Content-Type: application/json' -d '{\"username\":\"admin\",\"password\":\"admin123\"}'"
echo "  2. Check discovered services: Use JWT from login to call /telemetry/services"
echo "  3. View in Kiali: istioctl dashboard kiali"
echo ""
echo "To stop port-forward: kill $PF_PID"
echo ""
