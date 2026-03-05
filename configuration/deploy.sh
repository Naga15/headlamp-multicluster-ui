#!/bin/bash
## deploy.sh
## Full deployment script for Headlamp multi-cluster with Istio Ambient Mesh + Gateway API
## Usage: ./scripts/deploy.sh

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────
NAMESPACE="kube-system"
HELM_RELEASE="my-headlamp"
DOMAIN="headlamp.example.com"          # Replace with your domain
OIDC_ISSUER="https://your-idp.example.com"  # Replace with your IdP

echo "🚀 Starting Headlamp multi-cluster deployment..."

# ── Step 1: Install Gateway API CRDs ──────────────────────────────────────
echo "📦 Installing Gateway API CRDs..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

# ── Step 2: Enroll namespace into Istio Ambient Mesh ──────────────────────
echo "🔒 Enrolling kube-system into Istio Ambient Mesh..."
kubectl label namespace $NAMESPACE \
  istio.io/dataplane-mode=ambient \
  istio.io/use-waypoint=waypoint \
  --overwrite

# ── Step 3: Apply Gateway API resources ───────────────────────────────────
echo "🌐 Applying Gateway, HTTPRoute, Waypoint, Certificate..."
kubectl apply -f gateway/certificate.yaml
kubectl apply -f gateway/waypoint.yaml
kubectl apply -f gateway/gateway.yaml
kubectl apply -f gateway/httproute.yaml

# ── Step 4: Wait for Gateway to be ready ──────────────────────────────────
echo "⏳ Waiting for Gateway to be ready..."
kubectl wait --for=condition=Ready gateway/headlamp-gateway \
  -n $NAMESPACE --timeout=120s

# ── Step 5: Install Headlamp via Helm ─────────────────────────────────────
echo "⎈  Installing Headlamp via Helm..."
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ --force-update
helm repo update

helm upgrade --install $HELM_RELEASE headlamp/headlamp \
  --namespace $NAMESPACE \
  -f helm/custom-values.yaml \
  --wait

# ── Step 6: Verify deployment ─────────────────────────────────────────────
echo "✅ Verifying deployment..."
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=headlamp
kubectl get gateway -n $NAMESPACE
kubectl get httproute -n $NAMESPACE

# ── Step 7: Print access info ─────────────────────────────────────────────
GATEWAY_IP=$(kubectl get gateway headlamp-gateway -n $NAMESPACE \
  -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "pending")

echo ""
echo "══════════════════════════════════════════════════"
echo "  Headlamp is deployed!"
echo "  Gateway IP : $GATEWAY_IP"
echo "  URL        : https://$DOMAIN"
echo "  OIDC       : $OIDC_ISSUER"
echo ""
echo "  If DNS is not configured yet, add to /etc/hosts:"
echo "  $GATEWAY_IP  $DOMAIN"
echo "══════════════════════════════════════════════════"
