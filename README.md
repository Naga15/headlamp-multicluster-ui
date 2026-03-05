# headlamp-multicluster-ui

Deploy and expose [Headlamp](https://headlamp.dev) as a multi-cluster Kubernetes dashboard using:

- **Istio Ambient Mesh** — zero-sidecar service mesh with mTLS
- **Istio Gateway API** — replaces legacy Nginx Ingress
- **Waypoint Proxy** — L7 policy enforcement without sidecars
- **OIDC Authentication** — seamless SSO login, no token pasting
- **cert-manager** — automated TLS lifecycle via Let's Encrypt
- **XListenerSet** *(advanced)* — distributed listener ownership for multi-team platforms

---

## Architecture

```
User Browser
     │
     ▼ HTTPS (port 443)
┌─────────────────────────────────┐
│   Istio Gateway (Gateway API)   │  ← TLS termination via cert-manager
│   gatewayClassName: istio       │
└─────────────────────────────────┘
     │
     ▼ HTTP (mTLS via ztunnel — Ambient)
┌─────────────────────────────────┐
│       Waypoint Proxy            │  ← L7 AuthorizationPolicy enforcement
│  (istio.io/waypoint-for: svc)   │
└─────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────┐
│     Headlamp Service (ClusterIP)│
│       namespace: kube-system    │
└─────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────┐
│   Multi-cluster kubeconfigs     │  ← Mounted via Secret
│   cluster-prod / staging / dev  │
└─────────────────────────────────┘
```

### Why Ambient Mesh instead of sidecar?

| | Sidecar Mode | Ambient Mode |
|---|---|---|
| Sidecar injection required | ✅ Yes | ❌ No |
| mTLS between pods | ✅ | ✅ (via ztunnel) |
| L7 policies | ✅ | ✅ (via waypoint) |
| Resource overhead | Higher | Lower |
| Restart on mesh enroll | Required | Not required |

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Kubernetes | 1.27+ | Cluster |
| Istio | 1.22+ | Ambient Mesh + Gateway API |
| Gateway API CRDs | v1.1.0+ | Gateway / HTTPRoute resources |
| cert-manager | v1.14+ | TLS certificate automation |
| Helm | 3.x | Headlamp installation |

### Install prerequisites

```bash
# 1. Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

# 2. Istio with Ambient Mesh profile
istioctl install --set profile=ambient --skip-confirmation

# 3. cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# 4. Headlamp Helm repo
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update
```

---

## Repository Structure

```
headlamp-multicluster-ui/
├── README.md
├── helm/
│   ├── custom-values.yaml        # Helm overrides (OIDC, kubeconfigs, ambient annotations)
│   └── oidc-secret.yaml          # OIDC credentials secret template
├── gateway/
│   ├── gateway.yaml              # Gateway API Gateway (HTTP + HTTPS listeners)
│   ├── httproute.yaml            # HTTPRoute (redirect + HTTPS routing)
│   ├── waypoint.yaml             # Ambient Waypoint + AuthorizationPolicy
│   └── certificate.yaml         # cert-manager Certificate + ClusterIssuer
└── scripts/
    └── deploy.sh                 # Full automated deployment script
```

---

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/<your-org>/headlamp-multicluster-ui.git
cd headlamp-multicluster-ui
```

Replace placeholder values across files:

| Placeholder | File | Replace with |
|---|---|---|
| `headlamp.example.com` | gateway/, helm/ | Your actual domain |
| `your-idp.example.com` | helm/custom-values.yaml | Your OIDC issuer URL |
| `your-email@example.com` | gateway/certificate.yaml | Your email for Let's Encrypt |

### 2. Enroll namespace into Ambient Mesh

```bash
kubectl label namespace kube-system \
  istio.io/dataplane-mode=ambient \
  istio.io/use-waypoint=waypoint \
  --overwrite
```

### 3. Create OIDC secret

```bash
kubectl create secret generic headlamp-oidc \
  --from-literal=clientId='your-client-id' \
  --from-literal=clientSecret='your-client-secret' \
  -n kube-system
```

### 4. Create kubeconfigs secret (multi-cluster)

```bash
kubectl create secret generic headlamp-kubeconfigs \
  --from-file=cluster-prod=/path/to/prod-kubeconfig \
  --from-file=cluster-staging=/path/to/staging-kubeconfig \
  --from-file=cluster-dev=/path/to/dev-kubeconfig \
  -n kube-system
```

### 5. Deploy everything

```bash
# Option A: automated script
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# Option B: manual step by step
kubectl apply -f gateway/certificate.yaml
kubectl apply -f gateway/waypoint.yaml
kubectl apply -f gateway/gateway.yaml
kubectl apply -f gateway/httproute.yaml

helm upgrade --install my-headlamp headlamp/headlamp \
  --namespace kube-system \
  -f helm/custom-values.yaml \
  --wait
```

### 6. Verify

```bash
# Check Gateway status
kubectl get gateway -n kube-system
kubectl get httproute -n kube-system

# Check Headlamp pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=headlamp

# Check waypoint
kubectl get gateway waypoint -n kube-system

# Check TLS certificate
kubectl get certificate headlamp-tls -n kube-system

# Check ambient mesh enrollment
kubectl get namespace kube-system --show-labels
```

---

## OIDC Setup

Headlamp supports OIDC out of the box. This eliminates the manual token workflow from the legacy Kubernetes Dashboard.

### Supported Identity Providers

| IdP | Issuer URL format |
|---|---|
| Keycloak | `https://<host>/realms/<realm>` |
| Azure AD | `https://login.microsoftonline.com/<tenant-id>/v2.0` |
| Okta | `https://<org>.okta.com/oauth2/default` |
| Google | `https://accounts.google.com` |

Update `helm/custom-values.yaml`:

```yaml
env:
  - name: HEADLAMP_CONFIG_OIDC_ISSUER_URL
    value: "https://your-idp.example.com"
  - name: HEADLAMP_CONFIG_OIDC_SCOPES
    value: "openid,profile,email,groups"
```

---

## Accessing Headlamp

Once deployed, access Headlamp at:

```
https://headlamp.example.com
```

Login is handled by your OIDC provider — no token copy-paste required.

### Temporary port-forward (no ingress needed)

```bash
kubectl port-forward -n kube-system service/my-headlamp 8080:80
# Access: http://localhost:8080
```

---

## Security Notes

- **mTLS** is enforced by Istio ztunnel at L4 across all ambient-enrolled pods — no config needed
- **AuthorizationPolicy** in `gateway/waypoint.yaml` restricts which principals can reach Headlamp
- **TLS** is terminated at the Gateway with auto-renewed certs via cert-manager
- **OIDC** replaces static ServiceAccount tokens — credentials never live in the browser
- **Do not commit** real kubeconfigs or OIDC secrets — use Vault Secrets Operator (VSO) or Sealed Secrets

---

## Advanced: XListenerSet (Multi-team Listener Management)

> **Status:** Experimental (`gateway.networking.k8s.io/v1alpha2`)
> **Requires:** Gateway API v1.1.0+ with experimental channel CRDs

### When to use it

The default `gateway.yaml` defines HTTP and HTTPS listeners **inline** in a single Gateway object — this is the right approach for a single team owning the whole Gateway.

`XListenerSet` becomes useful at **platform scale** where listener ownership is distributed:

| Scenario | Approach |
|---|---|
| Single team, HTTP + HTTPS on one Gateway | ✅ Inline listeners (default — `gateway.yaml`) |
| Multiple teams sharing one Gateway | ✅ `XListenerSet` per team |
| Listeners managed from different namespaces | ✅ `XListenerSet` with cross-namespace refs |
| Platform team owns Gateway, app teams own listeners | ✅ `XListenerSet` |

### Install experimental Gateway API CRDs

The standard install only includes stable resources. For `XListenerSet` you need the experimental channel:

```bash
# Replace standard CRDs with experimental channel (includes XListenerSet)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/experimental-install.yaml
```

### Example: split listener ownership

**Platform team** owns the Gateway (no inline listeners):

```yaml
# gateway-platform.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: headlamp-gateway
  namespace: kube-system
spec:
  gatewayClassName: istio
  listeners: []    # intentionally empty — listeners managed via XListenerSet
```

**App team** attaches their own listeners via `XListenerSet`:

```yaml
# xlistenerset-headlamp.yaml
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: XListenerSet
metadata:
  name: headlamp-listeners
  namespace: kube-system
spec:
  parentRef:
    name: headlamp-gateway
    namespace: kube-system
    kind: Gateway
    group: gateway.networking.k8s.io

  listeners:
    # ── HTTP listener (redirect to HTTPS) ───────────────────────────────
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same

    # ── HTTPS listener (TLS termination via cert-manager) ───────────────
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - name: headlamp-tls
            kind: Secret
            namespace: kube-system
      allowedRoutes:
        namespaces:
          from: Same
```

The `HTTPRoute` resources remain unchanged — they reference `parentRefs` by `sectionName` which maps to the listener name defined in the `XListenerSet`.

### Apply

```bash
# If using XListenerSet approach, apply in this order:
kubectl apply -f gateway/gateway-platform.yaml      # empty Gateway
kubectl apply -f gateway/xlistenerset-headlamp.yaml # listeners via XListenerSet
kubectl apply -f gateway/httproute.yaml             # unchanged
```

### Verify listener attachment

```bash
kubectl get xlistenerset -n kube-system
kubectl describe xlistenerset headlamp-listeners -n kube-system

# Should show listeners attached to the parent Gateway
kubectl get gateway headlamp-gateway -n kube-system -o yaml | grep -A10 status
```

---

## Troubleshooting

```bash
# Gateway not getting an IP?
kubectl describe gateway headlamp-gateway -n kube-system

# HTTPRoute not attached?
kubectl describe httproute headlamp-https-route -n kube-system

# Certificate not issued?
kubectl describe certificate headlamp-tls -n kube-system
kubectl describe certificaterequest -n kube-system

# Ambient mesh not applied?
kubectl get pod -n kube-system -l app.kubernetes.io/name=headlamp -o yaml | grep -A5 annotations

# Waypoint not intercepting?
istioctl proxy-status
istioctl analyze -n kube-system
```

---

## Contributing

PRs welcome. Please open an issue before making large changes.

---

## License

MIT
