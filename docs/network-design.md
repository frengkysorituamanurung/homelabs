# k3s Cluster Network Design — frengky.xyz Homelab

This document describes the complete network architecture of the homelab k3s cluster, covering two main access patterns: **public access via Cloudflare Tunnel** and **VPN-only access via Tailscale**.

---

## Infrastructure Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         INTERNET (PUBLIC)                           │
└───────────────┬─────────────────────────────┬───────────────────────┘
                │                             │
    ┌───────────▼──────────┐     ┌────────────▼────────────┐
    │  Cloudflare Tunnel   │     │  Cloudflare DNS          │
    │  (Public Apps)       │     │  A record → 100.120.133.63│
    │  api.frengky.xyz     │     │  (VPN-only Apps)          │
    └───────────┬──────────┘     └────────────┬────────────┘
                │                             │
                │ HTTPS encrypted tunnel      │ DNS resolve
                │                             │ (only reachable via Tailscale)
                ▼                             ▼
┌───────────────────────────────────────────────────────────────────┐
│                    HOMELAB SERVER (homelabs)                       │
│                                                                   │
│  ┌─────────────────────┐    ┌──────────────────────────────────┐  │
│  │  Tailscale          │    │  Cloudflared Pod                 │  │
│  │  IP: 100.120.133.63 │    │  (namespace: cloudflare)         │  │
│  │  (VPN interface)    │    │  Tunnel → Traefik svc:80         │  │
│  └──────────┬──────────┘    └──────────────┬───────────────────┘  │
│             │                              │                       │
│             └──────────────┬───────────────┘                       │
│                            │                                       │
│              ┌─────────────▼──────────────────┐                   │
│              │         TRAEFIK v3.7.4          │                   │
│              │         (kube-system)           │                   │
│              │                                 │                   │
│              │  EntryPoints:                   │                   │
│              │  - web      :8000 (HTTP)        │                   │
│              │  - websecure:8443 (HTTPS)       │                   │
│              │  - traefik  :8080 (dashboard)   │                   │
│              │  - metrics  :9100               │                   │
│              └─────────────┬───────────────────┘                   │
│                            │                                       │
│            ┌───────────────┼───────────────────┐                  │
│            │               │                   │                  │
│     ┌──────▼──────┐ ┌──────▼──────┐ ┌─────────▼───────┐          │
│     │  frontend   │ │  backend    │ │  monitoring/    │          │
│     │  namespace  │ │  namespace  │ │  infra ns       │          │
│     │             │ │             │ │                 │          │
│     │ - glance    │ │ - mcp-bridge│ │ - grafana       │          │
│     │ - bentopdf  │ │ - sample-api│ │ - argocd        │          │
│     │ - hello-world│ │ - qdrant   │ │ - vault         │          │
│     └─────────────┘ └─────────────┘ └─────────────────┘          │
└───────────────────────────────────────────────────────────────────┘
```

---

## Access Pattern 1: VPN-Only via Tailscale (DNS-based restriction)

Used for internal/private apps that must not be accessible from the internet.

**Apps using this pattern:**
- `bentopdf.frengky.xyz` — BentoPDF
- `n8n.frengky.xyz` — N8N automation
- `grafana.frengky.xyz` — Grafana monitoring
- `argocd.frengky.xyz` — ArgoCD dashboard
- `vault.frengky.xyz` — HashiCorp Vault
- `gitea.frengky.xyz` — Gitea Git server
- `harbor.frengky.xyz` — Harbor registry
- `glance.frengky.xyz` — Glance dashboard
- `qdrant.frengky.xyz` — Qdrant vector DB
- `mcp-bridge.frengky.xyz` — MCP Bridge
- `rollouts.frengky.xyz` — Argo Rollouts dashboard

### VPN-Only Traffic Flow

```
User Device
  │
  ├─[Tailscale OFF]─→ nslookup bentopdf.frengky.xyz
  │                    → 100.120.133.63
  │                    → ❌ Connection Refused (IP not reachable)
  │
  └─[Tailscale ON]──→ nslookup bentopdf.frengky.xyz
                       → 100.120.133.63
                       → ✅ Reachable via Tailscale mesh
                            → Traefik :80/:443
                              → Ingress rule: bentopdf.frengky.xyz
                                → Service: bentopdf:8080
                                  → Pod: bentopdf
```

### DNS Configuration in Cloudflare

```
Type: A
Name: bentopdf (or other app name)
Content: 100.120.133.63
Proxy: DNS Only (Gray Cloud) ← REQUIRED
TTL: Auto
```

### Ingress Configuration (standard)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bentopdf
  namespace: frontend
spec:
  ingressClassName: traefik
  rules:
    - host: bentopdf.frengky.xyz
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: bentopdf
                port:
                  number: 8080
```

---

## Access Pattern 2: Public via Cloudflare Tunnel

Used for apps that need to be accessible from the internet without a VPN.

**Apps using this pattern:**
- `api.frengky.xyz` — Sample API (public endpoint)

### Public Traffic Flow (Cloudflare Tunnel)

```
User Device (internet)
  │
  └── api.frengky.xyz
       └── Cloudflare DNS: CNAME → <tunnel-id>.cfargotunnel.com
            └── Cloudflare Edge
                 └── Encrypted Tunnel (outbound from cluster)
                      └── cloudflared pod (namespace: cloudflare)
                           └── http://traefik.kube-system.svc.cluster.local:80
                                └── Traefik → Ingress rule: api.frengky.xyz
                                     └── Service: sample-api:80
```

### DNS Configuration in Cloudflare

```
Type: CNAME
Name: api
Content: <tunnel-id>.cfargotunnel.com
Proxy: Proxied (Orange Cloud) ← for tunnel
TTL: Auto
```

### Tunnel Configuration in Cloudflare Zero Trust

```
Public Hostname: api.frengky.xyz
Service: http://traefik.kube-system.svc.cluster.local:80
```

---

## Comparison of Both Patterns

| Aspect | VPN-Only (Tailscale) | Public (Cloudflare Tunnel) |
|-------|----------------------|---------------------------|
| **DNS Record** | A → `100.120.133.63` | CNAME → cfargotunnel.com |
| **Cloudflare Proxy** | DNS Only (Gray) | Proxied (Orange) |
| **Who can access** | Tailscale users only | Everyone |
| **SSL/TLS** | Traefik wildcard cert | Cloudflare SSL |
| **Latency** | Lower (direct) | Slightly higher (via CF) |
| **DDoS protection** | No | Yes (via Cloudflare) |
| **Ingress config** | Standard Ingress | Standard Ingress (same) |
| **Middleware required** | No | No |

---

## IP Address & Network Ranges

| Range | Description |
|-------|-------------|
| `100.120.133.63` | Tailscale IP of host `homelabs` |
| `100.64.0.0/10` | Tailscale CGNAT range (all devices) |
| `10.42.0.0/16` | k3s pod network (internal) |
| `10.43.0.0/16` | k3s service network (internal) |
| `192.168.100.0/24` | Homelab local LAN |
| `173.245.48.0/20` + ranges | Cloudflare edge IP ranges |

---

## Tailscale Middleware (Optional Layer)

In addition to DNS-based restriction, the cluster also has a `tailscale-whitelist` Middleware in the `traefik` namespace that can be used as an extra security layer:

```yaml
# This middleware already exists in the cluster (no need to recreate)
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: tailscale-whitelist
  namespace: traefik
spec:
  ipAllowList:
    ipStrategy:
      depth: 1
    sourceRange:
      - 100.64.0.0/10    # Tailscale
      - 127.0.0.1/32     # Localhost
      - 192.168.100.0/24 # LAN
      - 10.42.0.0/16     # k3s pods
```

This middleware is available in the namespaces: `traefik`, `argocd`, `harbor`, `monitoring`, `vault`.

> **Note:** This middleware is not used for BentoPDF because restriction at the DNS level (Tailscale IP not reachable from the internet) is sufficient. This middleware is more relevant for scenarios where the host has a public IP.

---

## Namespace & Apps Diagram

```
k3s Cluster (homelabs)
│
├── kube-system
│   ├── traefik (Ingress Controller)
│   └── local-path-provisioner (Storage)
│
├── argocd          → argocd.frengky.xyz        [VPN-only]
├── cert-manager    → (wildcard TLS management)
├── cloudflare      → cloudflared (Tunnel daemon)
├── external-secrets→ ESO (Vault → K8s Secrets)
│
├── frontend
│   ├── bentopdf    → bentopdf.frengky.xyz      [VPN-only] ← NEW
│   ├── glance      → glance.frengky.xyz        [VPN-only]
│   └── hello-world → hello.frengky.xyz         [VPN-only]
│
├── backend
│   ├── mcp-bridge  → mcp-bridge.frengky.xyz   [VPN-only]
│   ├── sample-api  → api.frengky.xyz           [PUBLIC via Tunnel]
│   └── qdrant      → qdrant.frengky.xyz        [VPN-only]
│
├── monitoring
│   ├── grafana     → grafana.frengky.xyz       [VPN-only]
│   ├── loki        → (internal only)
│   ├── alloy       → (internal only)
│   └── vmsingle    → (internal only)
│
├── gitea           → gitea.frengky.xyz         [VPN-only]
├── gitea-runner    → (internal CI runner)
├── harbor          → harbor.frengky.xyz        [VPN-only]
├── vault           → vault.frengky.xyz         [VPN-only]
├── n8n             → n8n.frengky.xyz           [VPN-only]
└── argo-rollouts   → rollouts.frengky.xyz      [VPN-only]
```