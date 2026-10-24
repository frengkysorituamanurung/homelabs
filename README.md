# GitOps Repository — frengky.xyz Homelab

Repository ini adalah **single source of truth** untuk seluruh workload yang berjalan di k3s cluster homelabs, di-manage oleh ArgoCD.

## Arsitektur

```
GitHub (github.com/frengkysorituamanurung/homelabs)
  └── Repository ini
        └── ArgoCD watches → deploys ke k3s cluster
```

- **Cluster**: k3s single-node (homelabs)
- **Domain**: `*.frengky.xyz` via Cloudflare Tunnel → Traefik ingress
- **StorageClass**: `local-path`
- **Secrets**: HashiCorp Vault + External Secrets Operator

## Struktur Folder

```
.
├── k8s/clusters/production/applications/apps/                          # ArgoCD Application manifests
│   ├── root-app.yaml              # App of Apps — entry point utama
│   ├── monitoring/                # Grafana, Loki, Alloy, VictoriaMetrics, dll
│   ├── cloudflare/                # Cloudflared tunnel daemon
│   ├── infra/                     # ArgoCD, Harbor, Vault, ESO
│   └── ingress/                   # Ingress rules per aplikasi
├── charts/                        # Helm values files
│   ├── monitoring/                # values per monitoring app
│   └── infra/                     # argocd, harbor, vault values
├── manifests/                     # Plain Kubernetes YAML (non-Helm)
│   ├── cloudflare/
│   └── ingress/
└── secrets/                       # ESO templates & Vault docs
    ├── README.md
    └── templates/                 # ExternalSecret CRD templates
```

## Cara Kerja

### App of Apps Pattern

`k8s/clusters/production/applications/apps/root-app.yaml` adalah ArgoCD Application yang di-deploy **pertama kali secara manual**. Setelah itu, ia akan secara otomatis men-discover dan men-deploy semua Application lain di folder `k8s/clusters/production/applications/apps/**/*.yaml`.

```bash
# Deploy root-app pertama kali (bootstrap)
kubectl apply -f k8s/clusters/production/applications/apps/root-app.yaml
```

### Helm Chart Apps (sources pattern)

Untuk aplikasi Helm, kami menggunakan pola **multi-source** (`sources`):
- Source 1: Chart dari upstream Helm registry (Artifact Hub, dll)
- Source 2: Repo GitOps ini (sebagai `ref: values`) untuk mengambil `values.yaml`

Ini memastikan values disimpan di Git, tapi chart selalu dari registry resmi.

### Plain Manifest Apps

Untuk aplikasi non-Helm (Cloudflared, Ingress), ArgoCD langsung mem-point ke folder `manifests/` dengan tipe `Directory`.

## Onboarding Aplikasi Baru

1. Buat `values.yaml` di `charts/<kategori>/<nama-app>/values.yaml`
2. Buat ArgoCD Application di `k8s/clusters/production/applications/apps/<kategori>/<nama-app>.yaml`
3. Push ke GitHub → ArgoCD otomatis deploy

## Secret Management

Secrets **tidak** disimpan di repo ini. Workflow:

1. Simpan secret ke **Vault**: `vault kv put secret/<app> key=value`
2. Buat **ExternalSecret** CR (gunakan template di `secrets/templates/`)
3. ESO akan otomatis membuat Kubernetes Secret dari Vault

Lihat [`secrets/README.md`](secrets/README.md) untuk panduan lengkap.

Untuk pengelolaan sertifikat SSL/TLS otomatis via Tailscale, lihat [`docs/gitops-cert-manager.md`](docs/gitops-cert-manager.md).

## Komponen yang Di-manage

| Komponen | Namespace | Type | Chart Version |
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
# Lihat semua ArgoCD apps
kubectl get applications -n argocd

# Force sync satu app
argocd app sync grafana

# Lihat status cluster
kubectl get pods -A

# Port-forward ArgoCD UI (sebelum ingress aktif)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login ArgoCD CLI
argocd login argocd.frengky.xyz --insecure

# Vault: simpan secret
kubectl exec -n vault vault-0 -- vault kv put secret/grafana adminUser=admin adminPassword=changeme123
```
