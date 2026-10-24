# GitOps Repository — frengky.xyz Homelab

This repository is the **single source of truth** for all workloads running in the k3s homelab cluster, managed by ArgoCD.

## Architecture

```
GitHub (github.com/frengkysorituamanurung/homelabs)
  └── This repository
        └── ArgoCD watches → deploys to k3s cluster
```

- **Cluster**: k3s single-node (homelabs)
- **Domain**: `*.frengky.xyz` via Cloudflare Tunnel → Traefik ingress
- **StorageClass**: `local-path`
- **Secrets**: HashiCorp Vault + External Secrets Operator

## Folder Structure

```
.
├── k8s/clusters/production/applications/   # ArgoCD Application manifests
│   ├── root-app.yaml                      # App of Apps — main entry point
│   ├── monitoring/                        # Grafana, Loki, Alloy, VictoriaMetrics, etc.
│   ├── cloudflare/                        # Cloudflared tunnel daemon
│   ├── infra/                             # ArgoCD, Harbor, Vault, ESO
│   └── ingress/                           # Ingress rules per application
├── charts/                                # Helm values files
│   ├── monitoring/                        # values per monitoring app
│   └── infra/                             # argocd, harbor, vault values
├── manifests/                             # Plain Kubernetes YAML (non-Helm)
│   ├── cloudflare/
│   └── ingress/
├── helm/                                  # Helm charts
├── secrets/                               # ESO templates & Vault docs
│   ├── README.md
│   └── templates/                         # ExternalSecret CRD templates
└── docs/                                  # Deployment documentation
```

## How It Works

### App of Apps Pattern

`k8s/clusters/production/applications/root-app.yaml` is the ArgoCD Application deployed **manually first**. After that, it automatically discovers and deploys every other Application in `k8s/clusters/production/applications/**/*.yaml`.

```bash
# Deploy root-app for the first time (bootstrap)
kubectl apply -f k8s/clusters/production/applications/root-app.yaml
```

### Helm Chart Apps (sources pattern)

For Helm applications we use the **multi-source** pattern (`sources`):
- Source 1: Chart from an upstream Helm registry (Artifact Hub, etc.)
- Source 2: This GitOps repo (as `ref: values`) to fetch `values.yaml`

This keeps values in Git while charts always come from official registries.

### Plain Manifest Apps

For non-Helm applications (Cloudflared, Ingress), ArgoCD points directly to the `manifests/` folder with type `Directory`.

## Onboarding a New Application

1. Create `values.yaml` in `charts/<category>/<app-name>/values.yaml`
2. Create an ArgoCD Application in `k8s/clusters/production/applications/<category>/<app-name>.yaml`
3. Push to GitHub → ArgoCD deploys automatically

## Secret Management

Secrets are **not** stored in this repository. Workflow:

1. Store the secret in **Vault**: `vault kv put secret/<app> key=value`
2. Create an **ExternalSecret** CR (use the templates in `secrets/templates/`)
3. ESO automatically creates the Kubernetes Secret from Vault

See [`secrets/README.md`](secrets/README.md) for the full guide.

For automatic SSL/TLS certificate management via cert-manager, see [`docs/gitops-cert-manager.md`](docs/gitops-cert-manager.md).

## Managed Components

| Component | Namespace | Type | Chart Version |
|---|---|---|---|
| Traefik | kube-system | k3s native HelmChartConfig | - |
| Grafana | monitoring | Helm | grafana/grafana ~8.x |
| Loki | monitoring | Helm | grafana/loki ~6.x |
| Alloy | monitoring | Helm | grafana/alloy ~0.x |
| VictoriaMetrics | monitoring | Helm | vm/victoria-metrics-single ~0.x |
| kube-state-metrics | monitoring | Helm | prometheus-community ~5.x |
| node-exporter | monitoring | Helm | prometheus-community ~4.x |
| Cloudflared | cloudflare | Manifest | - |
| **ArgoCD** | argocd | Helm | argo/argo-cd ~7.x |
| **Harbor** | harbor | Helm | harbor/harbor ~1.16.x |
| **Vault** | vault | Helm | hashicorp/vault ~0.29.x |
| **ESO** | external-secrets | Helm | external-secrets ~0.10.x |
| **Cert-Manager** | cert-manager | Manifest (GitOps) | v1.15.1 |

## Useful Commands

```bash
# List all ArgoCD apps
kubectl get applications -n argocd

# Force sync one app
argocd app sync grafana
```