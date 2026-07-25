# Desain Jaringan k3s Cluster — frengky.xyz Homelab

Dokumen ini menjelaskan arsitektur jaringan lengkap cluster k3s homelab, mencakup dua pola akses utama: **akses publik via Cloudflare Tunnel** dan **akses VPN-only via Tailscale**.

---

## Gambaran Umum Infrastruktur

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

## Pola Akses 1: VPN-Only via Tailscale (DNS-based restriction)

Digunakan untuk apps internal/privat yang tidak boleh diakses dari internet.

**Apps yang menggunakan pola ini:**
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

### Alur Traffic VPN-Only

```
User Device
  │
  ├─[Tailscale OFF]─→ nslookup bentopdf.frengky.xyz
  │                    → 100.120.133.63
  │                    → ❌ Connection Refused (IP tidak reachable)
  │
  └─[Tailscale ON]──→ nslookup bentopdf.frengky.xyz
                       → 100.120.133.63
                       → ✅ Reachable via Tailscale mesh
                            → Traefik :80/:443
                              → Ingress rule: bentopdf.frengky.xyz
                                → Service: bentopdf:8080
                                  → Pod: bentopdf
```

### Konfigurasi DNS di Cloudflare

```
Type: A
Name: bentopdf (atau nama app lain)
Content: 100.120.133.63
Proxy: DNS Only (Gray Cloud) ← WAJIB
TTL: Auto
```

### Konfigurasi Ingress (standard)

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

## Pola Akses 2: Public via Cloudflare Tunnel

Digunakan untuk apps yang perlu diakses dari internet tanpa VPN.

**Apps yang menggunakan pola ini:**
- `api.frengky.xyz` — Sample API (public endpoint)

### Alur Traffic Public (Cloudflare Tunnel)

```
User Device (internet)
  │
  └── api.frengky.xyz
       └── Cloudflare DNS: CNAME → <tunnel-id>.cfargotunnel.com
            └── Cloudflare Edge
                 └── Encrypted Tunnel (outbound dari cluster)
                      └── cloudflared pod (namespace: cloudflare)
                           └── http://traefik.kube-system.svc.cluster.local:80
                                └── Traefik → Ingress rule: api.frengky.xyz
                                     └── Service: sample-api:80
```

### Konfigurasi DNS di Cloudflare

```
Type: CNAME
Name: api
Content: <tunnel-id>.cfargotunnel.com
Proxy: Proxied (Orange Cloud) ← untuk tunnel
TTL: Auto
```

### Konfigurasi Tunnel di Cloudflare Zero Trust

```
Public Hostname: api.frengky.xyz
Service: http://traefik.kube-system.svc.cluster.local:80
```

---

## Perbandingan Kedua Pola

| Aspek | VPN-Only (Tailscale) | Public (Cloudflare Tunnel) |
|-------|----------------------|---------------------------|
| **DNS Record** | A → `100.120.133.63` | CNAME → cfargotunnel.com |
| **Cloudflare Proxy** | DNS Only (Gray) | Proxied (Orange) |
| **Siapa bisa akses** | Hanya user Tailscale | Semua orang |
| **SSL/TLS** | Traefik wildcard cert | Cloudflare SSL |
| **Latensi** | Lebih rendah (direct) | Sedikit lebih tinggi (via CF) |
| **DDoS protection** | Tidak | Ya (via Cloudflare) |
| **Ingress config** | Standard Ingress | Standard Ingress (sama) |
| **Middleware diperlukan** | Tidak | Tidak |

---

## IP Address & Network Ranges

| Range | Keterangan |
|-------|------------|
| `100.120.133.63` | Tailscale IP host `homelabs` |
| `100.64.0.0/10` | Tailscale CGNAT range (semua devices) |
| `10.42.0.0/16` | k3s pod network (internal) |
| `10.43.0.0/16` | k3s service network (internal) |
| `192.168.100.0/24` | LAN lokal homelab |
| `173.245.48.0/20` + ranges | Cloudflare edge IP ranges |

---

## Tailscale Middleware (Optional Layer)

Selain pembatasan via DNS, cluster juga punya Middleware `tailscale-whitelist` di namespace `traefik` yang bisa dipakai sebagai layer keamanan tambahan:

```yaml
# Middleware ini sudah ada di cluster (tidak perlu dibuat ulang)
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

Middleware ini tersedia di namespace: `traefik`, `argocd`, `harbor`, `monitoring`, `vault`.

> **Catatan:** Middleware ini tidak digunakan untuk BentoPDF karena pembatasan sudah cukup di level DNS (IP Tailscale tidak reachable dari internet). Middleware ini lebih relevan untuk skenario di mana host punya IP publik.

---

## Diagram Namespace & Apps

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
