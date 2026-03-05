#!/bin/bash
## push-to-github.sh
## Initialize and push this repo to GitHub
## Usage: ./scripts/push-to-github.sh <github-username> <repo-name>
##
## Prerequisites:
##   - git installed
##   - GitHub CLI (gh) installed: https://cli.github.com
##     OR a GitHub repo already created manually

set -euo pipefail

GITHUB_USER="${1:-your-github-username}"
REPO_NAME="${2:-headlamp-multicluster-ui}"

echo "📁 Initializing git repo..."
cd "$(dirname "$0")/.."

git init
git add .
git commit -m "feat: headlamp multi-cluster with Istio Ambient Mesh + Gateway API

- Gateway API (gateway.yaml + httproute.yaml) replaces Nginx Ingress
- Istio Ambient Mesh with waypoint proxy for L7 policies (no sidecars)
- OIDC authentication via Helm values (no manual token required)
- cert-manager TLS automation with Let's Encrypt
- Multi-cluster kubeconfig mounting via Kubernetes Secret
- AuthorizationPolicy for mTLS-based access control
- Automated deploy.sh script for full stack deployment"

echo "🐙 Creating GitHub repo and pushing..."

# Option A: using GitHub CLI (recommended)
if command -v gh &> /dev/null; then
  gh repo create "$REPO_NAME" \
    --public \
    --description "Headlamp multi-cluster UI with Istio Ambient Mesh + Gateway API + OIDC" \
    --source=. \
    --remote=origin \
    --push
  echo "✅ Pushed to: https://github.com/$GITHUB_USER/$REPO_NAME"
else
  # Option B: manual remote setup
  echo "⚠️  GitHub CLI not found. Add remote manually:"
  echo ""
  echo "  1. Create repo at: https://github.com/new"
  echo "     Name: $REPO_NAME"
  echo ""
  echo "  2. Run these commands:"
  echo "     git remote add origin https://github.com/$GITHUB_USER/$REPO_NAME.git"
  echo "     git branch -M main"
  echo "     git push -u origin main"
fi
