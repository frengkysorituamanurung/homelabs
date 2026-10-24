# BentoPDF Deployment Documentation

BentoPDF is an open-source, browser-based (client-side processing) PDF toolkit deployed in the k3s cluster `frengky.xyz` via GitOps (ArgoCD). Access is only available when connected to the **Tailscale VPN**.

---

## Access Architecture

```
User (Tailscale connected)
  └── bentopdf.frengky.xyz
        └── Cloudflare DNS A record → 100.120.133.63 (Tailscale IP host)
              └── Traefik Ingress Controller (port 80/443)
                    └── Service: bentopdf:8080 (namespace: frontend)
                          └── Pod: ghcr.io/alam00000/bentopdf-simple
```

VPN-only access is enforced **at the DNS level** — the domain `bentopdf.frengky.xyz` only resolves to the Tailscale IP `100.120.133.63`, which is unreachable from the public internet without being connected to Tailscale.

---

## GitOps File Structure

```
gitops-repo/
├── kubernetes/
│   ├── applications/
│   │   └── production/
│   │       └── bentopdf.yaml          # ArgoCD Application
│   └── production/
│       └── frontend/
│           └── bentopdf/
│               ├── Chart.yaml         # Helm chart (uses generic-app)
│               └── values.yaml        # App configuration
└── docs/
    └── bentopdf-deployment.md         # This document
```

---

## Manifest Files

### 1. ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bentopdf
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  project: default
  source:
    repoURL: http://gitea-http.gitea.svc.cluster.local:3000/devops/gitops.git
    path: k8s/clusters/production/applications/apps/production/frontend/bentopdf
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: frontend
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 2. Helm Chart (`Chart.yaml`)

```yaml
apiVersion: v2
name: bentopdf
type: application
version: 1.0.0
dependencies:
  - name: generic-app
    version: 0.1.12
    repository: oci://harbor.frengky.xyz/helm-repos
```

The `generic-app` chart is an internal Helm chart used by all apps in this cluster.
Version `0.1.12` adds explicit `ingressClassName: traefik`.

### 3. Values (`values.yaml`)

```yaml
generic-app:
  baseNamespace: frontend
  baseName: bentopdf
  environment: production
  disableSecrets: true         # BentoPDF needs no env secrets
  image:
    repository: ghcr.io/alam00000/bentopdf-simple
    tag: "latest"
    pullPolicy: Always
  resources:
    requests:
      memory: 64Mi
      cpu: 10m
    limits:
      memory: 128Mi
      cpu: 100m
  service:
    enabled: true
    type: ClusterIP
    ports:
      - name: http
        port: 8080
  ingress:
    enabled: true
    stripPath: false
    hosts:
      - host: bentopdf.frengky.xyz
        path: /
        port: 8080
  healthCheck:
    enabled: true
    endpoint: /
    port: 8080
  deploymentStrategy:
    type: Recreate
```

**Important notes:**
- `disableSecrets: true` — required because `generic-app` by default always mounts the Secret `<appname>-secrets`
- `ingress.enabled: true` — generates a standard Kubernetes Ingress with `ingressClassName: traefik`
- BentoPDF is a **stateless app** (all PDF processing happens in the browser), no PVC needed

---

## Deployment Steps

### Step 1: Cloudflare DNS Configuration

Add an A record in the Cloudflare DNS dashboard:

| Type | Name | Content | Proxy Status | TTL |
|------|------|---------|--------------|-----|
| `A` | `bentopdf` | `100.120.133.63` | DNS Only (Gray Cloud) | Auto |

> **IMPORTANT:** Status must be **DNS Only (Gray Cloud)**, not Proxied (Orange).
> If Proxied, Cloudflare will attempt to proxy to the Tailscale IP, which is unreachable from the internet.

### Step 2: Verify ArgoCD

```bash
# Check app status
kubectl get application bentopdf -n argocd
# Expected: SYNC STATUS=Synced, HEALTH STATUS=Healthy

# Force sync if needed
kubectl annotate application bentopdf -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

### Step 3: Verify Pod and Ingress

```bash
# Check pod
kubectl get pods -n frontend -l app.kubernetes.io/name=bentopdf
# Expected: 1/1 Running

# Check ingress
kubectl get ingress bentopdf -n frontend
# Expected: host=bentopdf.frengky.xyz, CLASS=traefik

# Test internal connection
kubectl port-forward svc/bentopdf 8080:8080 -n frontend
# Open: http://localhost:8080
```

### Step 4: Test Access via Tailscale

```bash
# Make sure Tailscale is active, then:
curl -I http://bentopdf.frengky.xyz
# Expected: HTTP/1.1 200 OK

# Verify DNS resolves to Tailscale IP:
nslookup bentopdf.frengky.xyz
# Expected: Address: 100.120.133.63
```

---

## BentoPDF Image

| Variant | Image | Description |
|---------|-------|-------------|
| Simple (used) | `ghcr.io/alam00000/bentopdf-simple:latest` | No marketing/footer, ideal for internal use |
| Full | `ghcr.io/alam00000/bentopdf:latest` | With marketing landing page |

BentoPDF processes all PDFs **in the browser** (client-side via WebAssembly).
The server only serves static files. No PDF data is sent to the server.

---

## Troubleshooting

| Symptom | Cause | Solution |
|---------|-------|----------|
| `CreateContainerConfigError` | Secret `bentopdf-secrets` not found | Make sure `disableSecrets: true` in values.yaml |
| Domain unreachable | DNS not configured | Add A record in Cloudflare (DNS Only) |
| ArgoCD `OutOfSync` | Chart dependency not found | Make sure `generic-app:0.1.12` exists in Harbor |
| 404 when accessing | Ingress not created | Check `kubectl get ingress -n frontend` |

```bash
# Full debug
kubectl describe pod -n frontend -l app.kubernetes.io/name=bentopdf
kubectl logs -n frontend -l app.kubernetes.io/name=bentopdf
kubectl describe ingress bentopdf -n frontend
```