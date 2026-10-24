# K3s Cluster Infrastructure Documentation (Homelab frengky.xyz)

> **How to use this document:** This document is designed as a *living document*; update it every time there is a change in topology, a new node, or a new application in the cluster.

---

## 0. Table of Contents

1. Architecture Overview
2. Network Topology
3. Node & K3s Cluster Structure
4. Application Access Model (Private vs Public)
5. Private Access — Tailscale-only (DNS-Only Gray Cloud)
6. Public Access — Internet-facing via Cloudflare Tunnel
7. DNS & TLS/Certificates
8. Namespace Structure & Application Deployment
9. GitOps / CI-CD
10. Security & Hardening
11. Actual YAML Manifest Examples
12. Architecture Diagram
13. Runbook / Operational Checklist
14. Appendix — Actual Application Inventory
---

## 1. Architecture Overview

| Item | Detail |
|---|---|
| Project/cluster name | `homelabs` (frengky.xyz Homelab) |
| Kubernetes distribution | K3s version `v1.36.2+k3s1` |
| Number of nodes | `1` (1 server / control-plane, 0 agent/worker) |
| Provider/hosting | `Homelab WSL2 (Windows Host, Ubuntu 26.04 LTS)` |
| CNI (Container Network Interface) | `Flannel (default k3s)` |
| Ingress Controller | `Traefik (default k3s)` |
| Internal Load Balancer | `ServiceLB (Klipper)` |
| VPN mesh | `Tailscale` |
| Public reverse proxy | `Cloudflare Tunnel (cloudflared)` |
| TLS Certificates | `cert-manager (v1.15.1) + Let's Encrypt (DNS-01 Challenge via Cloudflare API)` |
| GitOps | `Flux CD (GitRepository + Kustomization)` |
| Storage | `local-path (local-path-provisioner)` |
| Secret Management | `HashiCorp Vault + External Secrets Operator (ESO)` |

### Access design principles
This cluster implements **two different access paths** for applications:

1. **Private / internal-only** → Only accessible by devices that are part of the **tailnet** (Tailscale network); not exposed to the public internet at all.
2. **Public** → Applications intended for general access, exposed via ingress + public reverse proxy (Cloudflare Tunnel) with a valid TLS certificate.

This separation is done at the **DNS & Ingress/Service** level, not at the node level, so a single cluster can safely run both kinds of applications side by side.

---

## 2. Network Topology

There are **4 network layers** operating on the homelab cluster:

### 2.1 Physical/Local Network (Underlay)
- Local WSL2 network on the host computer, allocated a local IP.
- Main node: `homelabs: 192.168.100.6`
### 2.2 Tailscale Network (Overlay VPN — Tailnet)
- Every k3s node, and every admin device (laptop `frengky-sre`, phone `realme-c67`), has `tailscaled` installed and is joined to the tailnet `tail79205d.ts.net`.
- Tailscale gives the host node a stable, encrypted (WireGuard) **CGNAT IP 100.x.x.x** (Tailscale IP).
- **MagicDNS** is active so nodes can be accessed via the hostname `homelabs.tail79205d.ts.net`.
| Node | Tailscale IP | Tailscale Hostname | Tags |
|---|---|---|---|
| `homelabs` | `100.120.133.63` | `homelabs.tail79205d.ts.net` | `tag:k3s-server` |

> **Note:** K3s API server traffic (port 6443) only listens on the Tailscale IP and localhost, so it is not exposed to the host's public network.

### 2.3 Kubernetes Pod Network (CNI Overlay)
- Managed by Flannel, default CIDR: `10.42.0.0/16`
- Pod-to-pod communication between containers is handled internally by the CNI overlay.
### 2.4 Kubernetes Service Network (ClusterIP)
- Default CIDR: `10.43.0.0/16`
- Internal-only; accessible only from inside the cluster (unless exposed via Ingress/NodePort/LoadBalancer).
### 2.5 Layer Summary

```
[Public Internet]
       │
       ▼
[Cloudflare Tunnel] (Proxied via cloudflared) ← Only for public apps
       │
       ▼
[Local/WSL Network — IP 192.168.100.6]
       │
       ├── Tailscale overlay (100.120.133.63) ← Admin & private app access (Gray Cloud DNS)
       │
       ▼
[K3s Cluster]
  ├── Pod Network   (10.42.0.0/16)
  └── Service Network (10.43.0.0/16)
```

---

## 3. Node & K3s Cluster Structure

### 3.1 Node Roles

| Role | Node | OS | Specs | Notes |
|---|---|---|---|---|
| Server (control-plane + etcd) | `homelabs` | `Ubuntu 26.04 LTS (WSL2)` | `8 Cores / 16GB / 512GB (Dynamic)` | Single-node, HA: no |

### 3.2 Installing K3s with Tailscale as the node-to-node network

For a single-node install with a Tailscale interface, use the `--node-ip` and `--flannel-iface` flags so k3s runs on top of the Tailscale interface (`tailscale0`).

```bash
# On the server node (control-plane)
curl -sfL https://get.k3s.io | sh -s - server \
  --node-ip=100.120.133.63 \
  --flannel-iface=tailscale0 \
  --tls-san=homelabs.tail79205d.ts.net
```

> With this configuration, the **k3s API server (port 6443) only listens/is reachable via the Tailscale IP and localhost**, not the host's public IP.

### 3.3 Standard Namespaces

| Namespace | Function |
|---|---|
| `kube-system` | Core k3s components (CoreDNS, Traefik, local-path-provisioner, metrics-server) |
| `argocd` | GitOps controller (Flux CD) |
| `cert-manager` | TLS certificate management (cert-manager) |
| `external-secrets` | Secret synchronization from Vault to Kubernetes Secrets (ESO) |
| `vault` | Main secret store (HashiCorp Vault) |
| `harbor` | Local Docker/Helm Registry (Harbor) |
| `cloudflare` | Cloudflare Tunnel daemon (`cloudflared`) |
| `gitea` | Local Git repository provider (Gitea) |
| `gitea-runner` | CI/CD runner for pipeline automation (Gitea Actions Runner) |
| `monitoring` | Observability components (Grafana, Loki, Alloy, VictoriaMetrics, node-exporter, kube-state-metrics) |
| `frontend` | End-user applications (`hello-world`, `glance` dashboard) |
| `backend` | API backend (`sample-api`) |
| `production` | Application deployments for the production environment (`service-a`) |
| `staging` | Application deployments for the staging environment (`service-a-staging`) |
| `argo-rollouts` | Controller for canary/bluegreen deployments (`argo-rollouts`) |

---

## 4. Application Access Model

Every new application is deployed following this decision flow:

```mermaid
flowchart TD
    A[New application to be deployed] --> B{Needs public access?}
    B -- No, admin/team only --> C[Access via Tailscale only]
    B -- Yes, for general users --> D[Access via Public Ingress]
    C --> E[Cloudflare DNS Gray Cloud\n-> Point to Tailscale IP 100.120.133.63\n+ Traefik Ingress + cert-manager TLS]
    D --> F[Cloudflare DNS Orange Cloud (Proxied)\n-> Cloudflare Tunnel + Traefik Ingress]
```

| Criteria | Private (Tailscale-only) | Public (Internet-facing) |
|---|---|---|
| Example apps | Gitea, Harbor, Flux CD, Vault, Grafana, Glance Dashboard, Argo Rollouts | Hello World, Sample API, Service A, Service A Staging |
| Service type | `ClusterIP` | `ClusterIP` (exposed via Ingress) |
| Exposure | DNS Gray Cloud -> Tailscale IP `100.120.133.63` -> Traefik Ingress | Cloudflare Tunnel -> `cloudflared` deployment -> Traefik Ingress |
| TLS | cert-manager + Let's Encrypt (DNS-01 Wildcard `*.frengky.xyz`) | Automatic via Cloudflare Edge TLS / Let's Encrypt |
| DNS | Public DNS Gray Cloud (`app.frengky.xyz` -> `100.120.133.63`) | Public DNS Orange Cloud (`app.frengky.xyz` -> Cloudflare CNAME) |
| Firewall | Ports 80/443 reachable only by devices within the Tailnet | No VPS ports opened; outbound connection via Cloudflare Tunnel |

---

## 5. Private Access — Tailscale-only (DNS-Only Gray Cloud)

This cluster implements the **Private Custom Domain via Tailscale IP + DNS-01 Challenge** pattern.

```
[Device with Tailscale] ──► DNS Query `grafana.frengky.xyz` ──► Returns `100.120.133.63`
                                                                    │
    ┌───────────────────────────────────────────────────────────────┘
    ▼
[Host Homelabs (Port 443)] ──► Traefik ──► Serves Wildcard Cert `*.frengky.xyz` ──► Grafana Pod
```

### 5.1 Private Access Workflow
1. **Public Domain DNS**: The `*.frengky.xyz` domain is defined in Cloudflare. Subdomains for private tools are set as **DNS-Only (Gray Cloud)** and pointed at the Host Tailscale IP: `100.120.133.63`.
2. **Security**: Devices outside the tailnet cannot reach the IP `100.120.133.63` because the Tailscale CGNAT IP is only routable within the Tailscale mesh network.
3. **SSL/TLS Encryption**: Because traffic does not go through the Cloudflare Edge Proxy, TLS certificates are terminated directly in Traefik. A valid wildcard certificate is issued by `cert-manager` using a **Let's Encrypt DNS-01 Challenge** via the Cloudflare API.

---

## 6. Public Access — Internet-facing via Cloudflare Tunnel

Public applications (such as `api.frengky.xyz`, `hello.frengky.xyz`, `service-a.frengky.xyz`) are exposed using Cloudflare Tunnel. This pattern keeps the homelab cluster safe without needing to open inbound ports (such as 80/443) on the host's public IP.

### 6.1 Public Access Workflow
1. **Cloudflared Daemon**: The `cloudflared` pod in the `cloudflare` namespace creates a secure **outbound** connection to the Cloudflare edge network using `TUNNEL_TOKEN`.
2. **Inbound Routing**: Cloudflare routes requests for public subdomains to the `cloudflared` pod inside the cluster.
3. **Ingress Controller**: The `cloudflared` pod forwards traffic internally to the Traefik Ingress Controller in `kube-system`. Traefik then routes the request to the correct application Service based on the `Host` header.

---

## 7. DNS & TLS/Certificates

| Access Scheme | Domain | DNS Provider/Resolver | TLS Certificate |
|---|---|---|---|
| **Private** | `*.frengky.xyz` (such as `argocd.`, `vault.`, `grafana.`, `harbor.`, `gitea.`, `glance.`) | Cloudflare (Gray Cloud) -> Tailscale IP `100.120.133.63` | cert-manager + Let's Encrypt Wildcard TLS (`wildcard-frengky-xyz-tls`) |
| **Public** | `*.frengky.xyz` (such as `hello.`, `api.`, `service-a.`) | Cloudflare (Orange Cloud) -> Cloudflare Tunnel CNAME | Cloudflare Edge TLS / Let's Encrypt |

### 7.1 cert-manager & Let's Encrypt DNS-01 Configuration

Because cluster pods experience **outbound egress timeout** issues reaching the internet, the `cert-manager` pod is patched with a **Host Network Workaround** so it can contact the Let's Encrypt ACME server directly from the host network namespace:

- `hostNetwork: true`
- `dnsPolicy: ClusterFirstWithHostNet`

---

## 8. Namespace Structure & Application Deployment

All deployments are managed centrally in the local Gitea GitOps repository (`http://gitea-http.gitea.svc.cluster.local:3000/devops/gitops.git`).

### GitOps Repository Folder Structure:
```
gitops-repo/
├── kubernetes/
│   ├── applications/              # Flux CD Application definitions (App of Apps Pattern)
│   │   ├── root-app.yaml          # Main Flux CD entry point (App-of-Apps)
│   │   ├── infrastructure/        # Basic infrastructure application manifests
│   │   │   ├── vault.yaml, argocd.yaml, cert-manager.yaml, gitea.yaml, harbor.yaml, etc.
│   │   ├── production/            # Production application manifests
│   │   │   ├── glance.yaml, sample-api.yaml, hello-world.yaml, service-a.yaml, etc.
│   │   └── staging/               # Staging application manifests
│   │       └── service-a.yaml
│   │
│   ├── infrastructure/            # Non-production infrastructure component customization/install
│   │   └── argo-rollouts/
│   │
│   ├── production/                # Helm Values & per-application manifests for production
│   │   ├── argocd/, vault/, gitea/, harbor/, cloudflare/, cert-manager/, etc.
│   │   ├── frontend/
│   │   │   ├── glance/            # Values, templates, and Chart.yaml for Glance Dashboard
│   │   │   └── hello-world/       # Values and Chart.yaml for Hello-World
│   │   └── backend/
│   │       └── sample-api/        # Values and Chart.yaml for Go-based Sample API
│   │
│   ├── staging/                   # Staging Helm Values
│   │   └── service-a/
│   │
│   └── secrets/                   # ESO templating & Secret Integration documentation
└── README.md
```

---

## 9. GitOps / CI-CD

| Item | Detail |
|---|---|
| GitOps Engine | `Flux CD` |
| Source Repository | `http://gitea-http.gitea.svc.cluster.local:3000/devops/gitops.git` |
| Public/Backup Remote | `https://gitea.frengky.xyz/devops/gitops.git`, `https://gitlab.frengky.xyz/frengky/gitops.git` |
| Sync Strategy | `Auto-Sync with Prune & Self-Heal` |
| Environment | `Staging` (namespace: `staging`), `Production` (namespace: `production`, `backend`, `frontend`) |
| Secret Management | `HashiCorp Vault` integrated with `External Secrets Operator (ESO)` |

---

## 10. Security & Hardening

- [x] **API Server Isolation**: The K3s API server (port 6443) is only accessible via the Tailscale interface (`100.120.133.63`) and localhost. Port 6443 is not exposed to the internet.
- [x] **Zero Inbound Ports for Public**: Public applications are exposed using Cloudflare Tunnel, so ports 80 and 443 on the host do not need to be opened to the public.
- [x] **Default SSL/TLS Store**: Traefik is configured with a custom default `TLSStore` (`wildcard-frengky-xyz-tls`) in the `kube-system` namespace, so all ingresses automatically serve a valid SSL certificate.
- [x] **Secret Externalization**: No secret files (such as API tokens, database passwords) are stored in Git. All are pulled dynamically from Vault by ESO using the `ExternalSecret` CRD.
- [x] **Network Policy / Namespace Isolation**: Ingress is configured per namespace to logically isolate traffic.

---

## 11. Actual YAML Manifest Examples

### 11.1 ClusterIssuer (Let's Encrypt DNS-01 via Cloudflare)
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: frengky@frengky.xyz
    privateKeySecretRef:
      name: letsencrypt-prod-issuer-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
```

### 11.2 Wildcard Certificate (*.frengky.xyz)
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-frengky-xyz
  namespace: kube-system
spec:
  secretName: wildcard-frengky-xyz-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: "*.frengky.xyz"
  dnsNames:
    - "*.frengky.xyz"
    - "frengky.xyz"
```

### 11.3 Traefik Default TLS Store
```yaml
apiVersion: traefik.io/v1alpha1
kind: TLSStore
metadata:
  name: default
  namespace: kube-system
spec:
  defaultCertificate:
    secretName: wildcard-frengky-xyz-tls
```

### 11.4 Ingress for a Private Application (Grafana)
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
spec:
  ingressClassName: traefik
  rules:
    - host: grafana.frengky.xyz
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 80
```

### 11.5 ExternalSecret Integration (Pulling secrets from Vault)
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: sample-api-secrets
  namespace: backend
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: sample-api-secret
    creationPolicy: Owner
  data:
    - secretKey: APP_ENV
      remoteRef:
        key: secret/data/production/backend/sample-api
        property: APP_ENV
```

---

## 12. Architecture Diagram (Mermaid)

```mermaid
graph TB
    subgraph Internet_Publik["Public Internet"]
        User1[Public User]
    end
    
    subgraph Tailnet_VPN["Tailscale VPN Network (Overlay 100.x.x.x)"]
        Admin[Admin / Laptop / Phone]
    end
    
    subgraph Cloudflare_Edge["Cloudflare Edge Network"]
        Tunnel[Cloudflare Tunnel / Edge TLS]
    end
    
    subgraph K3s_Host["K3s Cluster (Host: homelabs)"]
        direction TB
        
        subgraph Cloudflare_Ingress["Public Access Layer"]
            CF_Daemon[Cloudflared Daemon Pods]
        end
        
        subgraph Traefik_Core["Ingress Controller"]
            Traefik[Traefik Service / TLS termination]
            TLSStore[Default TLSStore: wildcard-frengky-xyz-tls]
        end
        
        subgraph Apps_Private["Private Apps (Access via Tailscale IP)"]
            Gitea[Gitea: gitea.frengky.xyz]
            Harbor[Harbor: harbor.frengky.xyz]
            Flux CD[Flux CD: argocd.frengky.xyz]
            Vault[Vault: vault.frengky.xyz]
            Grafana[Grafana: grafana.frengky.xyz]
            Glance[Glance Dashboard: glance.frengky.xyz]
        end
        
        subgraph Apps_Public["Public Apps (Access via CF Tunnel)"]
            HelloWorld[Hello-World: hello.frengky.xyz]
            SampleAPI[Sample API: api.frengky.xyz]
            ServiceA[Service A: service-a.frengky.xyz]
        end
    end
    
    %% Public traffic path
    User1 -->|HTTPS 443| Tunnel
    Tunnel -->|Outbound Secure Connection| CF_Daemon
    CF_Daemon -->|HTTP 80| Traefik
    Traefik -->|Routing| Apps_Public
    
    %% Private traffic path
    Admin -->|Encrypted WireGuard traffic| Traefik
    note["DNS resolves private *.frengky.xyz to 100.120.133.63"]
    Traefik -.-> TLSStore
    Traefik -->|Routing| Apps_Private
```

---

## 13. Runbook / Operational Checklist

**Adding a new private application:**
1. Deploy a Deployment + Service (`ClusterIP`) in the target namespace.
2. Create an Ingress file with `ingressClassName: traefik` and include the domain `app-baru.frengky.xyz`.
3. Store the application secret in Vault: `vault kv put secret/production/<namespace>/<app-baru> key=value`.
4. Create an `ExternalSecret` manifest to sync the secret into a Kubernetes Secret.
5. Register a **DNS-Only (Gray Cloud) A Record** in the Cloudflare Dashboard for `app-baru.frengky.xyz` -> pointing at the Host Tailscale IP `100.120.133.63`.
6. Test access via a browser on a device connected to Tailscale: `https://app-baru.frengky.xyz`.

**Adding a new public application:**
1. Deploy a Deployment + Service (`ClusterIP`) in the target namespace.
2. Create an Ingress file with `ingressClassName: traefik` and include the domain `public-app.frengky.xyz`.
3. Configure the DNS route in the **Cloudflare Dashboard (Tunnels)** so that `public-app.frengky.xyz` is routed internally to `http://traefik.kube-system.svc.cluster.local:80` or directly to the application Service.
4. Verify the sync status in Flux CD and ensure the pod status is `Running`.
5. Test access from an external network (e.g., mobile internet) to `https://public-app.frengky.xyz`.

**Incident/Debug: Let's Encrypt DNS issues:**
1. If the Let's Encrypt certificate fails to verify, check the logs from the cert-manager pod:
   ```bash
   kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager --tail=100
   ```
2. Make sure the Cloudflare API Token secret is valid:
   ```bash
   kubectl describe secret cloudflare-api-token-secret -n cert-manager
   ```
3. Make sure the `cert-manager` pod is running on the host network:
   ```bash
   kubectl get pod -n cert-manager -o wide
   ```

---

## 14. Appendix — Actual Application Inventory

| Application | Namespace | Category | Access URL (HTTPS) | Description / Notes |
|---|---|---|---|---|
| **Flux CD** | `argocd` | Private | `https://argocd.frengky.xyz` | GitOps Engine Dashboard |
| **Gitea** | `gitea` | Private | `https://gitea.frengky.xyz` | Local Git repository (source-of-truth) |
| **Harbor** | `harbor` | Private | `https://harbor.frengky.xyz` | Local image registry for base & runner images |
| **Vault** | `vault` | Private | `https://vault.frengky.xyz` | Credential & Secret Management |
| **Grafana** | `monitoring` | Private | `https://grafana.frengky.xyz` | Metrics visualization (VictoriaMetrics/Loki) |
| **Glance** | `frontend` | Private | `https://glance.frengky.xyz` | Personal homepage & homelab dashboard |
| **Argo Rollouts** | `argo-rollouts` | Private | `https://rollouts.frengky.xyz` | Canary/blue-green deployment management dashboard |
| **Traefik Dashboard** | `kube-system` | Private | `https://traefik.frengky.xyz/dashboard/` | Ingress proxy traffic router dashboard |
| **Hello World** | `frontend` | Public | `https://hello.frengky.xyz` | Example static web frontend deployment |
| **Sample API** | `backend` | Public | `https://api.frengky.xyz` | Go-based REST API (sample backend) |
| **Service A (Prod)** | `production` | Public | `https://service-a.frengky.xyz` | Service-A Production Application |
| **Service A (Staging)** | `staging` | Public | `https://service-a-staging.frengky.xyz` | Service-A Staging Application |
| **Loki** | `monitoring` | Internal | - | Log aggregation engine (VictoriaMetrics backend) |
| **Alloy** | `monitoring` | Internal | - | Logs/metrics collection agent |
| **VictoriaMetrics** | `monitoring` | Internal | - | TSDB metrics engine |