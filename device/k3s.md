# k3s Configuration

## Version

- k3s: `v1.36.2+k3s1`
- containerd: `2.3.2-k3s2`
- Node: `homelabs` (control-plane, single node)

## Configuration Files

- `/etc/rancher/k3s/config.yaml`
  ```yaml
  flannel-mtu: 1400
  ```
- `/etc/rancher/k3s/registries.yaml`
  - Harbor registry mirror for `harbor-registry-tls.harbor.svc.cluster.local:443`
- `/etc/rancher/k3s/k3s.yaml` (kubeconfig)

## Core Components (Running)

- Traefik (ingress)
- cert-manager
- Flux CD (GitOps)
- Vault + Vault Unsealer
- Harbor
- Grafana, Loki, Alloy, VictoriaMetrics
- CloudNativePG
- External Secrets Operator
- Reloader, Node Exporter, kube-state-metrics

## Networking

- CNI: Flannel (VXLAN)
- Pod CIDR: `10.42.0.0/24`
- Service CIDR: `10.43.0.0/16`
- MTU: 1400 (set for WSL2 compatibility)

## Storage

- StorageClass: `local-path` (k3s default)
- PVCs backed by `/var/lib/rancher/k3s/storage/...`

## GitOps

- Flux CD watches `https://github.com/frengkysorituamanurung/homelabs.git`
- Branch: `main`
- Reconciliation interval: `1m` (GitRepository), `5-10m` (Kustomizations)
- Bootstrap path: `clusters/production/flux-system`

## Certificates

- Issuer: `letsencrypt-prod` (ClusterIssuer, DNS-01 via Cloudflare)
- Certificates:
  - `wildcard-frengky-xyz` (kube-system)
  - `harbor-registry-tls-cert` (harbor)

## Notes

- Single-node cluster; no HA.
- WSL2-based; ensure MTU and DNS are compatible with Tailscale.