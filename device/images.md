# Container Image Inventory (current cluster)

This file lists the container images currently deployed in the cluster.  
Use it as a reference when pinning image versions in Helm values or manifests.

## Infrastructure

| App | Image |
|---|---|
| Alloy | `docker.io/grafana/alloy:v1.21.2` |
| Grafana | `docker.io/grafana/grafana:12.3.1` |
| Loki | `grafana/loki:3.6.16` |
| VictoriaMetrics | `victoriametrics/victoria-metrics:v1.154.0` |
| kube-state-metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.20.0` |
| node-exporter | `prom/node-exporter:v1.12.1` |
| Vault | `hashicorp/vault:2.0.4` |
| Vault Agent Injector | `hashicorp/vault-k8s:1.7.5` |
| External Secrets | `ghcr.io/external-secrets/external-secrets:v2.14.0` |
| cert-manager | `quay.io/jetstack/cert-manager-controller:v1.15.1` |
| Harbor | `docker.io/goharbor/*:v2.15.4` |
| ArgoCD | `quay.io/argoproj/argocd:v3.5.6` |
| CloudNativePG | `ghcr.io/cloudnative-pg/cloudnative-pg:1.30.1` |
| Reloader | `ghcr.io/stakater/reloader:v1.4.22` |
| Traefik | `rancher/mirrored-library-traefik:3.7.4` |
| CoreDNS | `rancher/mirrored-coredns-coredns:1.14.4` |
| metrics-server | `rancher/mirrored-metrics-server:v0.8.1` |

## Applications

| App | Image |
|---|---|
| Glance | `glanceapp/glance:v0.8.5` |
| mcp-bridge | `harbor.frengky.xyz/backend/mcp-bridge:v1.2.1` |
| sample-api | `harbor.frengky.xyz/backend/sample-api:5f9d9c5` |
| finance-backend | `harbor.frengky.xyz/devops/finance-backend:v1.3.2` |
| finance-frontend | `harbor.frengky.xyz/devops/finance-frontend:v1.3.2` |
| finance-landing | `harbor.frengky.xyz/frontend/finance-landing:v1.3.2` |
| bentopdf | `ghcr.io/alam00000/bentopdf-simple:latest` |
| n8n | `docker.io/n8nio/n8n:latest` |
| qdrant | `qdrant/qdrant:v1.20.0` |
| service-a | `harbor.frengky.xyz/frontend/hello-world:latest` |
| cloudflared | `cloudflare/cloudflared:latest` |
| vault-unsealer | `curlimages/curl:8.2.1` |

## Notes

- Many images are provided by Helm charts by default. To pin a version, add an `image:` block to the corresponding `values.yaml`.
- `latest` tags should be pinned to a specific version for reproducibility.