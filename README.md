# GitOps Repository — frengky.xyz Homelab

This repository is the **single source of truth** for all workloads running in the k3s homelab cluster, managed by **Flux CD**.

## Architecture

```
GitHub (github.com/frengkysorituamanurung/homelabs)
  └── This repository
        └── Flux CD watches → reconciles into k3s cluster
```

- **Cluster**: k3s single-node (homelabs)
- **Domain**: `*.frengky.xyz` via Cloudflare Tunnel → Traefik ingress
- **StorageClass**: `local-path`
- **Secrets**: HashiCorp Vault + External Secrets Operator
- **GitOps**: Flux CD (GitRepository + Kustomization + HelmRelease)

## Folder Structure

```
.
├── clusters/production/flux-system/   # Flux bootstrap + top-level Kustomizations
├── k8s/clusters/production/
│   ├── applications/                 # Legacy app manifests (migration in progress)
│   └── flux/                         # Flux Kustomizations/HelmReleases (where used)
├── infrastructure/                   # Component manifests, values, and Flux releases
│   └── <component>/flux/             # HelmRepository + HelmRelease per component
├── helm/                             # Vendored Helm charts (garage, garage-ui, generic-app, immich)
├── secrets/                          # ESO templates & Vault docs
├── device/                           # Device, network, k3s, security docs
├── docs/                             # Deployment documentation
└── scripts/                          # Helper scripts
```

## How It Works

### Flux CD

Flux is bootstrapped into the `flux-system` namespace and reconciles this repository from `main`:

- `clusters/production/flux-system/gotk-components.yaml` — Flux controllers
- `clusters/production/flux-system/gitrepository.yaml` — source: this repo
- `clusters/production/flux-system/kustomization.yaml` — top-level Kustomization
- `clusters/production/flux-system/flux-system-kustomization.yaml` — self-management

Each component is reconciled by a `Kustomization` (and, for Helm apps, a `HelmRelease` + `HelmRepository`).

### Helm Chart Apps

Helm applications use Flux `HelmRelease` resources, with values kept in Git:
- Chart from an upstream/Harbor OCI registry or a vendored chart in `helm/charts/*`
- Values in `infrastructure/<component>/values.yaml` or inlined in the `HelmRelease`

### Plain Manifest Apps

Non-Helm applications are applied via Flux `Kustomization` resources pointing at manifest directories.

## Secret Management

Secrets are **not** stored in this repository. Workflow:

1. Store the secret in **Vault**: `vault kv put secret/<app> key=value`
2. Create an **ExternalSecret** CR (use the templates in `secrets/templates/`)
3. ESO automatically creates the Kubernetes Secret from Vault

See [`secrets/README.md`](secrets/README.md) for the full guide.

## Onboarding a New Application

1. Create `values.yaml` in `infrastructure/<category>/<app-name>/values.yaml` (for Helm apps).
2. Create a Flux `HelmRelease`/`Kustomization` under `infrastructure/<app>/flux/`.
3. Register it in `clusters/production/flux-system/kustomization.yaml`.
4. Push to GitHub → Flux reconciles automatically.

## Managed Components

| Component | Namespace | Type | Owner |
|---|---|---|---|
| Traefik | kube-system | k3s native HelmChartConfig | k3s |
| Grafana | monitoring | Flux HelmRelease | Flux |
| Loki | monitoring | Flux HelmRelease | Flux |
| Alloy | monitoring | Flux HelmRelease | Flux |
| VictoriaMetrics | monitoring | Flux HelmRelease | Flux |
| kube-state-metrics | monitoring | Flux HelmRelease | Flux |
| node-exporter | monitoring | Flux HelmRelease | Flux |
| Cloudflared | cloudflare | Flux Kustomization | Flux |
| Cert-Manager | cert-manager | Flux Kustomization | Flux |
| Vault | vault | Flux HelmRelease | Flux |
| ESO | external-secrets | Flux HelmRelease | Flux |
| Harbor | harbor | Flux HelmRelease | Flux |
| CloudNativePG | cnpg-system | Flux HelmRelease | Flux |
| Reloader | reloader | Flux HelmRelease | Flux |
| Immich | immich | Flux HelmRelease + Kustomization | Flux |
| Garage | garage | Flux HelmRelease + Kustomization | Flux |
| Garage UI | garage | Flux HelmRelease | Flux |
| Glance | frontend | Flux HelmRelease | Flux |
| BentoPDF | frontend | Flux HelmRelease | Flux |
| finance-landing | frontend | Flux HelmRelease | Flux |
| mcp-bridge | backend | Flux HelmRelease | Flux |
| qdrant | backend | Flux HelmRelease | Flux |
| n8n | n8n | Flux Kustomization | Flux |
| service-a | production | Flux HelmRelease | Flux |
| ckx | ckx | Flux Kustomization (plain manifests) | Flux |

## Useful Commands

```bash
# List Flux Kustomizations
flux get kustomizations -n flux-system

# List Flux HelmReleases
flux get helmreleases -A

# Force reconcile
flux reconcile source git homelabs
flux reconcile kustomization flux-system -n flux-system

# Check Flux health
flux check
```