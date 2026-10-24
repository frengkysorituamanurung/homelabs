# Dokumentasi Instalasi OpenObserve

Dokumen ini menjelaskan instalasi, arsitektur deployment, konfigurasi, dan integrasi secret management untuk **OpenObserve** di cluster Kubernetes homelab `frengky.xyz`. OpenObserve dideploy menggunakan pola **GitOps (ArgoCD)** dengan Helm chart dari Harbor private registry.

---

## 🔎 Tentang OpenObserve

[OpenObserve](https://openobserve.ai) adalah platform observability open-source all-in-one yang mendukung:
- **Logs** — ingest, search, dan visualisasi log
- **Metrics** — monitoring berbasis Prometheus-compatible
- **Traces** — distributed tracing (OpenTelemetry)
- **Dashboards** — visualisasi real-time
- **Alerts** — alerting terpusat

Pada deployment ini, OpenObserve berjalan dalam mode **single-node / local mode** menggunakan SQLite sebagai meta store dan NATS sebagai cluster coordinator.

---

## 🏗️ Arsitektur Deployment

```
Internet
    │
    ▼
Cloudflare (DNS / Tunnel)
    │
    ▼
Traefik Ingress Controller
    │  openobserve.frengky.xyz
    ▼
openobserve-router (ClusterIP:5080)
    │
    ├── openobserve-ingester  (StatefulSet, data ingest)
    ├── openobserve-querier   (StatefulSet, query engine)
    ├── openobserve-alertmanager (StatefulSet, alert mgmt)
    ├── openobserve-compactor (Deployment, data compaction)
    └── openobserve-nats      (StatefulSet, cluster coord.)

Storage:
    ├── data-openobserve-ingester-0  → 20Gi (local-path)
    ├── cache-openobserve-querier-0  → 10Gi (local-path)
    ├── cache-openobserve-alertmanager-0 → 5Gi (local-path)
    └── nats-js-openobserve-nats-0   → 5Gi  (local-path)

Secret Management:
    Vault (secret/openobserve)
        └── ExternalSecret (ESO)
                └── Kubernetes Secret (openobserve-auth)
```

### Komponen yang Dideploy

| Komponen | Tipe | Fungsi |
|----------|------|--------|
| `openobserve-router` | Deployment | API gateway & UI router |
| `openobserve-ingester` | StatefulSet | Menerima & menyimpan data |
| `openobserve-querier` | StatefulSet | Query engine |
| `openobserve-alertmanager` | StatefulSet | Manajemen alert |
| `openobserve-compactor` | Deployment | Kompaksi data historis |
| `openobserve-nats` | StatefulSet | Cluster coordinator (JetStream) |
| `openobserve-blocked-metrics` | Deployment | Memblok akses `/metrics` publik |

---

## 📁 Struktur Manifest GitOps

File manifest disimpan di dalam repository GitOps (`gitops-repo`) dengan struktur berikut:

```
gitops-repo/
├── kubernetes/
│   ├── applications/
│   │   └── infrastructure/
│   │       └── openobserve.yaml        # Definisi Aplikasi ArgoCD
│   └── production/
│       └── openobserve/
│           └── values.yaml             # Helm values konfigurasi
├── secrets/
│   └── templates/
│       └── openobserve-secret.yaml     # ExternalSecret template (Vault → ESO)
└── docs/
    └── openobserve-deployment.md       # Dokumen ini
```

---

## 📄 Detail Manifest

### 1. ArgoCD Application (`k8s/clusters/production/applications/infrastructure/openobserve.yaml`)

ArgoCD mengelola deployment ini menggunakan Helm chart dari Harbor OCI registry:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openobserve
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  project: default
  sources:
    - repoURL: harbor-registry-tls.harbor.svc.cluster.local
      chart: helm-repos/openobserve
      targetRevision: "0.91.2"
      helm:
        valueFiles:
          - $values/infrastructure/openobserve/values.yaml
    - repoURL: http://gitea-http.gitea.svc.cluster.local:3000/devops/gitops.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: openobserve
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 2. Helm Values (`infrastructure/openobserve/values.yaml`)

Konfigurasi utama deployment mencakup:
- **Mode**: `ZO_LOCAL_MODE: "true"` — single-node tanpa clustering
- **Meta Store**: `ZO_META_STORE: "sqlite"` — tanpa PostgreSQL
- **Coordinator**: NATS built-in dengan JetStream (1 replica)
- **Storage**: `local-path` StorageClass (K3s built-in)
- **Ingress**: Traefik dengan host `openobserve.frengky.xyz`

### 3. ExternalSecret (`secrets/templates/openobserve-secret.yaml`)

ExternalSecret mengambil credentials dari Vault dan membuat Kubernetes Secret di namespace `openobserve`:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: openobserve-auth
  namespace: openobserve
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: openobserve-auth
    creationPolicy: Owner
  data:
    - secretKey: ZO_ROOT_USER_EMAIL
      remoteRef:
        key: secret/data/openobserve
        property: rootEmail
    - secretKey: ZO_ROOT_USER_PASSWORD
      remoteRef:
        key: secret/data/openobserve
        property: rootPassword
```

---

## 🔐 Secret Management

Credentials OpenObserve dikelola menggunakan HashiCorp Vault + External Secrets Operator (ESO).

### Menyimpan Credentials ke Vault

```bash
kubectl exec -n vault -it vault-0 -- sh -c "
  VAULT_ADDR=http://127.0.0.1:8200
  VAULT_TOKEN=<ROOT_TOKEN>
  export VAULT_ADDR VAULT_TOKEN
  vault kv put secret/openobserve \
    rootEmail='admin@frengky.xyz' \
    rootPassword='<PASSWORD_KUAT>' \
    webUrl='https://openobserve.frengky.xyz'
"
```

### Path di Vault

| Path | Key | Keterangan |
|------|-----|-----------|
| `secret/data/openobserve` | `rootEmail` | Email login admin |
| `secret/data/openobserve` | `rootPassword` | Password admin |
| `secret/data/openobserve` | `webUrl` | URL aplikasi |

### Apply ExternalSecret

```bash
# Apply ExternalSecret agar ESO membuat Kubernetes Secret secara otomatis
kubectl apply -f secrets/templates/openobserve-secret.yaml

# Verifikasi status sync
kubectl get externalsecret -n openobserve openobserve-auth

# Cek secret yang dibuat ESO
kubectl get secret -n openobserve openobserve-auth
```

### Mengganti Password

Untuk mengganti password root OpenObserve:

1. **Update secret di Vault:**
   ```bash
   kubectl exec -n vault -it vault-0 -- sh -c "
     VAULT_ADDR=http://127.0.0.1:8200
     VAULT_TOKEN=<ROOT_TOKEN>
     export VAULT_ADDR VAULT_TOKEN
     vault kv put secret/openobserve \
       rootEmail='admin@frengky.xyz' \
       rootPassword='<PASSWORD_BARU>' \
       webUrl='https://openobserve.frengky.xyz'
   "
   ```

2. **ESO akan otomatis sync** (interval: 1 jam) dan memperbarui Kubernetes Secret.

3. **Reloader akan otomatis restart pods** yang menggunakan secret tersebut.

> [!NOTE]
> Saat ini password di values.yaml dan Vault belum dihubungkan via `externalSecret`. Untuk menggunakan Vault sebagai sumber kebenaran penuh, tambahkan `externalSecret.enabled: true` pada values.yaml dan referensikan secret `openobserve-auth`.

---

## 🔧 Konfigurasi OpenObserve

### Deployment Mode

OpenObserve berjalan dalam **Local Mode** (`ZO_LOCAL_MODE: "true"`), cocok untuk single-node homelabs:
- Semua komponen berjalan dalam namespace yang sama
- Tidak membutuhkan S3-compatible object storage
- Data disimpan di local disk via PVC

### Storage Allocation

| PVC | Ukuran | Konten |
|-----|--------|--------|
| `data-openobserve-ingester-0` | 20Gi | Raw data, WAL, stream files |
| `cache-openobserve-querier-0` | 10Gi | Query cache (disk) |
| `cache-openobserve-alertmanager-0` | 5Gi | Alert state & history |
| `nats-js-openobserve-nats-0` | 5Gi | NATS JetStream (queue/coord) |

### Port & Protokol

| Service | Port | Protokol | Fungsi |
|---------|------|----------|--------|
| HTTP API / UI | 5080 | HTTP | Ingress, API, Dashboard |
| gRPC | 5081 | gRPC | Internal component comm. |

---

## 🚀 Cara Mengirim Data ke OpenObserve

### Ingest via API (Logs)

```bash
# Kirim log via HTTP API (Basic Auth)
curl -u "admin@frengky.xyz:OpenObserve@123" \
  -H "Content-Type: application/json" \
  -d '[{"level":"info","job":"test","log":"Hello OpenObserve!"}]' \
  https://openobserve.frengky.xyz/api/default/default/_json
```

### Konfigurasi Alloy / Vector / Fluent Bit

Untuk mengirim log dari aplikasi Kubernetes menggunakan **Grafana Alloy** (yang sudah terdeploy):

```river
// alloy config — tambahkan output ke OpenObserve
loki.write "openobserve" {
  endpoint {
    url = "https://openobserve.frengky.xyz/api/default/loki/api/v1/push"
    basic_auth {
      username = "admin@frengky.xyz"
      password = env("ZO_ROOT_USER_PASSWORD")
    }
  }
}
```

### Ingest Metrics (Prometheus-compatible)

OpenObserve mendukung Prometheus Remote Write:

```yaml
# prometheus / vmsingle remote_write config
remote_write:
  - url: https://openobserve.frengky.xyz/api/default/prometheus/api/v1/write
    basic_auth:
      username: admin@frengky.xyz
      password: OpenObserve@123
```

### Ingest Traces (OpenTelemetry)

```yaml
# OTLP exporter config
exporters:
  otlphttp:
    endpoint: https://openobserve.frengky.xyz/api/default
    headers:
      Authorization: "Basic <base64(email:password)>"
```

---

## ✅ Verifikasi Deployment

### Cek Status Pods & Resources

```bash
# Status semua pods OpenObserve
kubectl get pods -n openobserve

# Status ArgoCD Application
kubectl get application openobserve -n argocd

# Status PVC storage
kubectl get pvc -n openobserve

# Status ingress
kubectl get ingress -n openobserve
```

### Cek Health API

```bash
# Health check endpoint
curl -s https://openobserve.frengky.xyz/healthz

# Login test
curl -u "admin@frengky.xyz:OpenObserve@123" \
  https://openobserve.frengky.xyz/api/default/streams
```

### Cek Logs Komponen

```bash
# Log router (entry point)
kubectl logs -n openobserve -l app.kubernetes.io/component=router --tail=50

# Log ingester
kubectl logs -n openobserve statefulset/openobserve-ingester --tail=50

# Log NATS
kubectl logs -n openobserve statefulset/openobserve-nats -c nats --tail=20
```

---

## 🔄 Upgrade Chart Version

Untuk mengupgrade versi OpenObserve:

1. **Pull & push chart terbaru ke Harbor:**
   ```bash
   helm pull openobserve/openobserve --version <VERSI_BARU> -d /root/server/oo-chart/
   helm push /root/server/oo-chart/openobserve-<VERSI_BARU>.tgz oci://harbor.frengky.xyz/helm-repos
   ```

2. **Update targetRevision di ArgoCD Application:**
   ```yaml
   # k8s/clusters/production/applications/infrastructure/openobserve.yaml
   targetRevision: "<VERSI_BARU>"
   ```

3. **Commit & push ke Gitea** — ArgoCD akan sync otomatis.

---

## 📌 Referensi & File Terkait

| File | Fungsi |
|------|--------|
| `k8s/clusters/production/applications/infrastructure/openobserve.yaml` | ArgoCD Application manifest |
| `infrastructure/openobserve/values.yaml` | Helm chart values |
| `secrets/templates/openobserve-secret.yaml` | ExternalSecret (Vault → K8s Secret) |
| `docs/openobserve-deployment.md` | Dokumen ini |
| `docs/reloader-vault-integration.md` | Panduan Vault + ESO + Reloader |
| `secrets/README.md` | Panduan lengkap secret management |

### URL Layanan

| Layanan | URL |
|---------|-----|
| OpenObserve UI | https://openobserve.frengky.xyz |
| Vault (Secret Store) | https://vault.frengky.xyz |
| ArgoCD (GitOps) | https://argocd.frengky.xyz |
| Harbor (Registry) | https://harbor.frengky.xyz |
