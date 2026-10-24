# Network Configuration

## Interfaces

| Interface | Status | Address | Purpose |
|---|---|---|---|
| `eth0` | UP | `192.168.1.32/24` (LAN) | Primary node IP, Traefik LoadBalancer |
| `tailscale0` | UP | `100.120.133.63/32` | Tailscale VPN access |
| `cni0` | UP | `10.42.0.1/24` | Kubernetes pod network (Flannel) |
| `flannel.1` | UP | `10.42.0.0/32` | Flannel VXLAN overlay |
| `docker0` | DOWN | `172.17.0.1/16` | Docker bridge (unused) |

## Routing

- Default gateway: `192.168.1.1` via `eth0`
- Pod network: `10.42.0.0/24` via `cni0`
- Service network: `10.43.0.0/16` (ClusterIP, in-cluster)

## DNS

- Resolver: Tailscale MagicDNS
  - `nameserver 100.100.100.100`
  - `nameserver fd7a:115c:a1e0::53`
  - search domain: `tail79205d.ts.net`
- `/etc/hosts` contains static entries for in-cluster services:
  - `10.43.27.200 gitlab-http.gitlab.svc.cluster.local` (legacy)
  - `10.43.178.227 harbor-registry-tls.harbor.svc.cluster.local`
  - `192.168.1.32 harbor.frengky.xyz`

## Tailscale

- Node name: `homelabs`
- Tailscale IP: `100.120.133.63`
- Advertised as exit node
- Peers:
  - `frengky-sre` (macOS) — active
  - `realme-c67` (Android) — offline

## Ingress & TLS

- Ingress controller: Traefik (k3s built-in)
- External IP: `192.168.1.32`
- Domains: `*.frengky.xyz` via Cloudflare Tunnel → Traefik
- TLS: cert-manager with Let's Encrypt (DNS-01 via Cloudflare)
- Certificates:
  - `wildcard-frengky-xyz` (kube-system) — `*.frengky.xyz`, `frengky.xyz`
  - `harbor-registry-tls-cert` (harbor) — `harbor.frengky.xyz`

## Notes

- `harbor.frengky.xyz` must resolve to the Tailscale/LAN IP reachable by clients.
- `/etc/hosts` on the node should not contain stale IPs (e.g. `192.168.100.6`).