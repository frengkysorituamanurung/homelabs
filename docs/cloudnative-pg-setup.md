# CloudNative PG (CNPG) - Setup Documentation

## Overview

| Item | Detail |
|------|--------|
| **Operator** | CloudNativePG |
| **Chart Version** | `0.29.0` |
| **App Version** | `v1.30.0` |
| **Namespace** | `cnpg-system` |
| **Cluster** | `homelabs` (k3s v1.36.2, single-node, Ubuntu 26.04) |
| **Storage Class** | `local-path` (rancher.io/local-path) |
| **Managed By** | ArgoCD (GitOps via Gitea) |
| **Helm Repo** | `https://cloudnative-pg.github.io/charts` |

---

## Arsitektur & File GitOps

```
gitops-repo/
├── kubernetes/
│   ├── applications/
│   │   └── infrastructure/
│   │       └── cloudnative-pg.yaml        # ArgoCD Application manifest
│   └── production/
│       └── cloudnative-pg/
│           └── values.yaml                # Helm values untuk operator
└── docs/
    └── cloudnative-pg-setup.md            # Dokumen ini
```

### App-of-Apps Pattern

Cluster ini menggunakan pola **App-of-Apps** ArgoCD:

```
root-app (argocd)
  └── kubernetes/applications/           ← ArgoCD recursively picks up all .yaml
        └── infrastructure/
              └── cloudnative-pg.yaml    ← Installs CNPG operator via Helm
```

File `root-app.yaml` sudah dikonfigurasi dengan `directory.recurse: true`, sehingga begitu `cloudnative-pg.yaml` di-push ke Gitea, ArgoCD secara otomatis akan men-deploy operator.

---

## Instalasi

### 1. File ArgoCD Application (`kubernetes/applications/infrastructure/cloudnative-pg.yaml`)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cloudnative-pg
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"   # Deploy setelah cert-manager
spec:
  project: default
  sources:
    - repoURL: https://cloudnative-pg.github.io/charts
      chart: cloudnative-pg
      targetRevision: "0.29.0"
      helm:
        valueFiles:
          - $values/kubernetes/production/cloudnative-pg/values.yaml
    - repoURL: http://gitea-http.gitea.svc.cluster.local:3000/devops/gitops.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: cnpg-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true    # Wajib untuk CRD management
```

> **Catatan `sync-wave: "1"`**: Operator CNPG harus dipastikan running sebelum pembuatan `Cluster` resource (wave 2+). Cert-manager berada di wave 1 yang sama, namun biasanya sudah up lebih dulu.

### 2. Helm Values (`kubernetes/production/cloudnative-pg/values.yaml`)

Key configurations untuk homelab single-node:
- `replicaCount: 1` — satu replica cukup untuk single-node
- `crds.create: true` — CRD dikelola langsung oleh Helm chart
- `config.clusterWide: true` — operator mengawasi semua namespace
- `ServerSideApply=true` — diperlukan agar Helm dapat me-manage CRD dengan benar di Kubernetes 1.22+

### 3. Push ke Gitea & Sinkronisasi ArgoCD

```bash
# Di direktori gitops-repo
git add kubernetes/applications/infrastructure/cloudnative-pg.yaml
git add kubernetes/production/cloudnative-pg/values.yaml
git commit -m "feat: add CloudNativePG operator v1.30.0"
git push gitea main
```

ArgoCD akan otomatis mendeteksi perubahan dan men-sync aplikasi dalam ~3 menit, atau bisa di-trigger manual:

```bash
argocd app sync cloudnative-pg
# atau via kubectl
kubectl -n argocd patch application cloudnative-pg --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

### 4. Verifikasi Instalasi Operator

```bash
# Cek status ArgoCD Application
kubectl get application cloudnative-pg -n argocd

# Cek pods operator di namespace cnpg-system
kubectl get pods -n cnpg-system

# Cek CRDs yang terdaftar
kubectl get crd | grep postgresql

# Cek detail operator
kubectl describe deployment cnpg-controller-manager -n cnpg-system
```

Output yang diharapkan:
```
NAME                        READY   STATUS    RESTARTS   AGE
cnpg-controller-manager-x   1/1     Running   0          2m

NAME                                     CREATED AT
backups.postgresql.cnpg.io               ...
clusters.postgresql.cnpg.io              ...
databases.postgresql.cnpg.io             ...
imagecatalogs.postgresql.cnpg.io         ...
poolers.postgresql.cnpg.io               ...
publications.postgresql.cnpg.io          ...
scheduledbackups.postgresql.cnpg.io      ...
subscriptions.postgresql.cnpg.io         ...
```

---

## Membuat PostgreSQL Cluster (Contoh Penggunaan)

Setelah operator terinstall, kamu dapat membuat PostgreSQL cluster menggunakan CRD `Cluster`. Berikut contoh cluster minimal untuk development di homelab.

### Contoh: Cluster Standalone (1 node, local-path storage)

```yaml
# Simpan sebagai: kubernetes/production/cloudnative-pg/example-cluster.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-cluster
  namespace: database
spec:
  # Jumlah instance (1 = standalone, 2+ = primary + standby)
  instances: 1

  # Versi PostgreSQL
  imageName: ghcr.io/cloudnative-pg/postgresql:17.5

  # Storage untuk data PostgreSQL
  storage:
    size: 5Gi
    storageClass: local-path

  # Resource limits
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  # Bootstrap: inisialisasi database baru
  bootstrap:
    initdb:
      database: myapp
      owner: myapp_user
      secret:
        name: pg-cluster-credentials

  # PostgreSQL parameters tuning
  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "64MB"
      log_min_duration_statement: "1000"  # log query > 1 detik
```

### Secret untuk credentials (buat sebelum deploy Cluster):

```bash
kubectl create namespace database

kubectl create secret generic pg-cluster-credentials \
  --namespace database \
  --from-literal=username=myapp_user \
  --from-literal=password=SuperSecretPassword123!
```

### Verifikasi Cluster:

```bash
kubectl get cluster -n database
kubectl get pods -n database
kubectl get pvc -n database

# Lihat status cluster detail
kubectl describe cluster pg-cluster -n database

# Sambungkan ke primary instance via psql
kubectl exec -it pg-cluster-1 -n database -- psql -U myapp_user -d myapp
```

---

## Contoh: Cluster High Availability (3 nodes)

> ⚠️ **Catatan**: Cluster ini adalah **single-node** (`homelabs`). Konfigurasi HA (3 instances) hanya relevan jika cluster dikembangkan menjadi multi-node di masa depan. Dengan single-node, semua instances akan berjalan pada node yang sama.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-ha-cluster
  namespace: database
spec:
  instances: 3   # 1 primary + 2 standby (streaming replication)

  imageName: ghcr.io/cloudnative-pg/postgresql:17.5

  storage:
    size: 10Gi
    storageClass: local-path

  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: "1"
      memory: 1Gi

  bootstrap:
    initdb:
      database: production_db
      owner: app_user
      secret:
        name: pg-ha-credentials

  # Connection pooling dengan PgBouncer
  # (membutuhkan Pooler resource terpisah)

  monitoring:
    enablePodMonitor: false   # set true jika Prometheus Operator tersedia
```

---

## Backup & Recovery

### Scheduled Backup ke S3/MinIO (Opsional)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: pg-cluster-backup
  namespace: database
spec:
  schedule: "0 2 * * *"    # Setiap pukul 02:00
  backupOwnerReference: self
  cluster:
    name: pg-cluster
  method: barmanObjectStore  # atau volumeSnapshot

# Cluster harus dikonfigurasi dengan barmanObjectStore di spec.backup
```

### Point-in-Time Recovery (PITR)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-restored
  namespace: database
spec:
  instances: 1
  storage:
    size: 5Gi

  bootstrap:
    recovery:
      source: pg-cluster      # Nama cluster sumber
      recoveryTarget:
        targetTime: "2026-08-01 12:00:00"  # PITR ke waktu tertentu

  externalClusters:
    - name: pg-cluster
      barmanObjectStore:
        # ... konfigurasi S3/MinIO
```

---

## Plugin kubectl-cnpg (Opsional tapi Direkomendasikan)

Plugin CLI resmi untuk manajemen CNPG via kubectl:

```bash
# Install via krew
kubectl krew install cnpg

# Cek status cluster
kubectl cnpg status pg-cluster -n database

# Promote standby menjadi primary (manual failover)
kubectl cnpg promote pg-cluster pg-cluster-2 -n database

# Lihat logs
kubectl cnpg logs cluster pg-cluster -n database

# Hibernate cluster (scale down ke 0)
kubectl cnpg hibernate on pg-cluster -n database

# Wake up dari hibernate
kubectl cnpg hibernate off pg-cluster -n database
```

---

## Upgrade Operator

Untuk upgrade versi operator, cukup update `targetRevision` di file ArgoCD Application:

```yaml
# kubernetes/applications/infrastructure/cloudnative-pg.yaml
sources:
  - repoURL: https://cloudnative-pg.github.io/charts
    chart: cloudnative-pg
    targetRevision: "0.30.0"   # ← Update ke versi baru
```

> **Peringatan**: Sebelum upgrade, selalu baca **Upgrade Notes** di [dokumentasi resmi](https://cloudnative-pg.io/documentation/1.30/installation_upgrade/) karena ada kalanya diperlukan langkah migrasi manual, terutama untuk minor version jump.

---

## Troubleshooting

### Operator tidak sync di ArgoCD

```bash
# Cek events ArgoCD
kubectl describe application cloudnative-pg -n argocd | tail -30

# Cek logs ArgoCD application controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

### CRD conflict saat sync

Jika muncul error terkait CRD ownership:
```bash
# Force sync dengan replace
argocd app sync cloudnative-pg --force
```

Atau pastikan `ServerSideApply=true` sudah ada di syncOptions.

### Cluster stuck di "Setting up primary"

```bash
kubectl describe cluster pg-cluster -n database

# Cek logs instance pertama
kubectl logs pg-cluster-1 -n database -c postgres
kubectl logs pg-cluster-1 -n database -c bootstrap-controller
```

### Pod Cluster tidak bisa start (PVC pending)

Dengan `local-path`, PVC baru akan `Pending` sampai ada Pod yang dijadwalkan ke node (WaitForFirstConsumer). Ini **normal** pada local-path storage.

```bash
kubectl get pvc -n database
kubectl describe pvc pg-cluster-1 -n database
```

---

## Referensi

| Resource | URL |
|----------|-----|
| Dokumentasi Resmi | https://cloudnative-pg.io/documentation/1.30/ |
| GitHub | https://github.com/cloudnative-pg/cloudnative-pg |
| Helm Chart | https://github.com/cloudnative-pg/charts |
| ArtifactHub | https://artifacthub.io/packages/helm/cloudnative-pg/cloudnative-pg |
| Release Notes v1.30 | https://cloudnative-pg.io/documentation/1.30/release_notes/v1.30/ |
| PostgreSQL 17 Images | https://github.com/cloudnative-pg/postgresql |
