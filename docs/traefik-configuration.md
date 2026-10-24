# Traefik Configuration — frengky.xyz Homelab

This document describes the complete configuration of Traefik v3.7.4 as the Ingress Controller in the k3s cluster `frengky.xyz`, covering entrypoints, providers, forwarded headers, middleware, SSL/TLS, and how to make configuration changes.

---

## Version & Info

```
Traefik Version : v3.7.4 (codename: langres)
Deployment      : k3s native (HelmChartConfig)
Namespace       : kube-system
```

---

## How Traefik Is Installed in k3s

Traefik in k3s is **not installed via Flux CD/regular Helm**; instead it is managed by k3s itself through the `HelmChartConfig` resource. The configuration file is at:

```
helm-charts/traefik-helmchartconfig.yaml
```

To apply changes:
```bash
kubectl apply -f /root/server/traefik-helmchartconfig.yaml
# or if it already exists:
kubectl edit helmchartconfig traefik -n kube-system
```

---

## Currently Active Configuration

### HelmChartConfig (`traefik-helmchartconfig.yaml`)

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    additionalArguments:
      - "--api.insecure=true"
      # Trust Cloudflare as proxy - read real client IP from X-Forwarded-For
      - "--entrypoints.web.forwardedHeaders.trustedIPs=173.245.48.0/20,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,141.101.64.0/18,108.162.192.0/18,190.93.240.0/20,188.114.96.0/20,197.234.240.0/22,198.41.128.0/17,162.158.0.0/15,104.16.0.0/13,104.24.0.0/14,172.64.0.0/13,131.0.72.0/22,127.0.0.1/32,192.168.100.0/24,10.42.0.0/16"
      - "--entrypoints.websecure.forwardedHeaders.trustedIPs=173.245.48.0/20,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,141.101.64.0/18,108.162.192.0/18,190.93.240.0/20,188.114.96.0/20,197.234.240.0/22,198.41.128.0/17,162.158.0.0/15,104.16.0.0/13,104.24.0.0/14,172.64.0.0/13,131.0.72.0/22,127.0.0.1/32,192.168.100.0/24,10.42.0.0/16"
      # Enable access log for debug
      - "--accesslog=true"
      - "--accesslog.fields.headers.defaultmode=keep"
```

### Full Args Running in the Pod

```bash
--entryPoints.metrics.address=:9100/tcp
--entryPoints.traefik.address=:8080/tcp
--entryPoints.web.address=:8000/tcp
--entryPoints.websecure.address=:8443/tcp
--api.dashboard=true
--ping=true
--metrics.prometheus=true
--metrics.prometheus.entrypoint=metrics
--providers.kubernetescrd
--providers.kubernetescrd.allowEmptyServices=true
--providers.kubernetesingress
--providers.kubernetesingress.allowEmptyServices=true
--providers.kubernetesingress.ingressendpoint.publishedservice=kube-system/traefik
--entryPoints.websecure.http.tls=true
--log.level=INFO
--api.insecure=true
--accesslog=true
--accesslog.fields.headers.defaultmode=keep
--entrypoints.web.forwardedHeaders.trustedIPs=<cloudflare-ranges>
--entrypoints.websecure.forwardedHeaders.trustedIPs=<cloudflare-ranges>
```

---

## EntryPoints

| EntryPoint | Port (Internal) | Protocol | Description |
|------------|----------------|----------|-------------|
| `web` | `:8000` | HTTP | HTTP traffic from all sources |
| `websecure` | `:8443` | HTTPS/TLS | HTTPS traffic, TLS enabled by default |
| `traefik` | `:8080` | HTTP | Traefik Dashboard & API |
| `metrics` | `:9100` | HTTP | Prometheus metrics endpoint |

> **Port Note:** k3s NodePort mapping: `8000→80`, `8443→443` on the host. So from outside, access via ports 80/443.

---

## Providers

Traefik is configured with two main providers:

### 1. Kubernetes Ingress Provider (`--providers.kubernetesingress`)

Reads standard Kubernetes `Ingress` resources:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
spec:
  ingressClassName: traefik  # required explicitly in generic-app v0.1.12+
```

### 2. Kubernetes CRD Provider (`--providers.kubernetescrd`)

Reads Traefik CRD resources such as `IngressRoute`, `Middleware`, `TLSStore`, etc:
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
# or
kind: Middleware
# or
kind: TLSStore
```

---

## Forwarded Headers & IP Trust

This configuration is important so Traefik can read the real client IP from the `X-Forwarded-For` header when traffic passes through a proxy (Cloudflare or Cloudflare Tunnel).

```
# Cloudflare IP ranges that are trusted
173.245.48.0/20
103.21.244.0/22
103.22.200.0/22
103.31.4.0/22
141.101.64.0/18
108.162.192.0/18
190.93.240.0/20
188.114.96.0/20
197.234.240.0/22
198.41.128.0/17
162.158.0.0/15
104.16.0.0/13
104.24.0.0/14
172.64.0.0/13
131.0.72.0/22

# Internal ranges
127.0.0.1/32       # Localhost
192.168.100.0/24   # LAN homelab
10.42.0.0/16       # k3s pod network
```

Function: When Cloudflare Tunnel forwards a request to Traefik, the `X-Forwarded-For` header contains the real client IP. With this trust list, Traefik knows which IPs are valid to read.

---

## SSL/TLS

Traefik uses the wildcard certificate `*.frengky.xyz` managed by cert-manager.

### TLSStore (Default)

```yaml
apiVersion: traefik.io/v1alpha1
kind: TLSStore
metadata:
  name: default
  namespace: kube-system
spec:
  defaultCertificate:
    secretRef:
      name: wildcard-frengky-xyz-tls
```

All `IngressRoute`s with the `websecure` entrypoint automatically use this wildcard cert without additional configuration.

For regular Ingress, use the annotation:
```yaml
annotations:
  traefik.ingress.kubernetes.io/router.entrypoints: websecure
```

---

## Existing Middleware

### `tailscale-whitelist` (IP Allowlist)

Available in namespaces: `traefik`, `argocd`, `harbor`, `monitoring`, `vault`

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: tailscale-whitelist
  namespace: traefik    # change according to the namespace that needs it
spec:
  ipAllowList:
    ipStrategy:
      depth: 1          # read 1 hop from X-Forwarded-For
    sourceRange:
      - 100.64.0.0/10   # Tailscale CGNAT range
      - 127.0.0.1/32    # Localhost
      - 192.168.100.0/24 # LAN
      - 10.42.0.0/16    # k3s pod network
```

Usage in IngressRoute:
```yaml
spec:
  routes:
    - middlewares:
        - name: tailscale-whitelist
          namespace: traefik
```

> **Note:** For VPN-only apps, this middleware is **not required** if DNS is already pointed to the Tailscale IP (100.120.133.63). This middleware is useful as an additional layer when needed.

---

## Traefik Dashboard

Dashboard available via IngressRoute (restricted to localhost/LAN):

```
Internal URL: http://traefik.frengky.xyz/dashboard/
```

Its IngressRoute:
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: kube-system
spec:
  entryPoints:
    - web
  routes:
    - match: (Host(`traefik.frengky.xyz`) || Host(`localhost`)) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))
      kind: Rule
      services:
        - name: api@internal
          kind: TraefikService
```

Or access directly via port-forward:
```bash
kubectl port-forward -n kube-system svc/traefik 9000:9000
# Open: http://localhost:9000/dashboard/
```

---

## How to Add New Configuration

### Adding an Argument to Traefik

Edit the `HelmChartConfig`:
```bash
kubectl edit helmchartconfig traefik -n kube-system
```

Add to `spec.valuesContent.additionalArguments`:
```yaml
- "--new-argument=value"
```

k3s will automatically restart the Traefik pod after the change.

### Adding a New App (VPN-only)

1. Add an A record in Cloudflare DNS → `100.120.133.63` (DNS Only)
2. Create an Ingress with `ingressClassName: traefik`
3. Deploy via GitOps (Flux CD)

### Adding a New App (Public via Tunnel)

1. Configure a public hostname in the Cloudflare Zero Trust dashboard
2. Service: `http://traefik.kube-system.svc.cluster.local:80`
3. Create an Ingress with `ingressClassName: traefik` (same, no difference)

---

## Monitoring & Debug

```bash
# Check Traefik pod status
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# View Traefik logs (access log + error)
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=100

# Check all Ingress in the cluster
kubectl get ingress -A

# Check active config via Traefik API
kubectl port-forward -n kube-system svc/traefik 9000:9000 &
curl http://localhost:9000/api/http/routers | python3 -m json.tool | head -100

# Check registered middleware
kubectl get middleware -A

# Check IngressRoutes
kubectl get ingressroutes -A

# Describe Traefik pod to see full args
kubectl describe pod -n kube-system -l app.kubernetes.io/name=traefik
```

---

## Traefik Annotation Reference for Ingress

```yaml
metadata:
  annotations:
    # Force HTTPS only
    traefik.ingress.kubernetes.io/router.entrypoints: websecure

    # Apply middleware (format: namespace-name@kubernetescrd)
    traefik.ingress.kubernetes.io/router.middlewares: traefik-tailscale-whitelist@kubernetescrd

    # Custom router priority
    traefik.ingress.kubernetes.io/router.priority: "10"

    # Strip prefix
    traefik.ingress.kubernetes.io/router.middlewares: default-strip-prefix@kubernetescrd
```
