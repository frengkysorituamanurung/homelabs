# Network Configuration

## Interfaces

| Interface | Status | Address | Purpose |
|---|---|---|---|
| `eth0` | UP | `<LAN_NODE_IP>/24` (LAN) | Primary node IP, Traefik LoadBalancer |
| `tailscale0` | UP | `<TAILSCALE_NODE_IP>/32` | Tailscale VPN access |
| `cni0` | UP | `<POD_NETWORK_GATEWAY>/24` | Kubernetes pod network (Flannel) |
| `flannel.1` | UP | <POD_CIDR> | Flannel VXLAN overlay |
| `docker0` | DOWN | `172.17.0.1/16` | Docker bridge (unused) |

## Routing

- Default gateway: `<LAN_GATEWAY>` via `eth0`
- Pod network: `<POD_CIDR>` via `cni0`
- Service network: `<SERVICE_CIDR>` (ClusterIP, in-cluster)

## DNS

- Resolver: Tailscale MagicDNS
  - `nameserver <TAILSCALE_DNS>`
  - `nameserver <TAILSCALE_DNS_IPV6>`
  - search domain: `<TAILSCALE_DOMAIN>`
- `/etc/hosts` contains static entries for in-cluster services:
  - `<CLUSTER_IP> gitlab-http.gitlab.svc.cluster.local` (legacy)
  - `<CLUSTER_IP> harbor-registry-tls.harbor.svc.cluster.local`
  - `<LAN_NODE_IP> harbor.frengky.xyz`

## Tailscale

- Node name: `homelabs`
- Tailscale IP: `<TAILSCALE_NODE_IP>`
- Advertised as exit node
- Peers:
  - `frengky-sre` (macOS) — active
  - `realme-c67` (Android) — offline

## Ingress & TLS

- Ingress controller: Traefik (k3s built-in)
- External IP: `<LAN_NODE_IP>`
- Domains: `*.frengky.xyz` via Cloudflare Tunnel → Traefik
- TLS: cert-manager with Let's Encrypt (DNS-01 via Cloudflare)
- Certificates:
  - `wildcard-frengky-xyz` (kube-system) — `*.frengky.xyz`, `frengky.xyz`
  - `harbor-registry-tls-cert` (harbor) — `harbor.frengky.xyz`

## Notes

- `harbor.frengky.xyz` must resolve to the Tailscale/LAN IP reachable by clients.
- `/etc/hosts` on the node should not contain stale IPs (e.g. `<STALE_IP>`).