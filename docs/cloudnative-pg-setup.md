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

## Architecture & GitOps Files

```
gitops-repo/
├── kubernetes/
│   ├── applications/
│   │   └── infrastructure/
│   │       └── cloudnative-pg.yaml        # ArgoCD Application manifest
│   └── production/
│       └── cloudnative-pg/
│           └── values.yaml                # Helm values for the operator
└── docs/
    └── cloudnative-pg-setup.md            # This document
```

### App-of-Apps Pattern

This cluster uses the ArgoCD **App-of-Apps** pattern:

```
root-app (argocd)
  └── k8s/clusters/production/applications/           ← ArgoCD recursively picks up all .yaml
        └── infrastructure/
              └── cloudnative-pg.yaml    ← Installs CNPG operator via Helm
```

The `root-app.yaml` is already configured with `directory.recurse: true`, so once `cloudnative-pg.yaml` is pushed to Gitea, ArgoCD will automatically deploy the operator.

---

## Installation

### 1. ArgoCD Application File (`k8s/clusters/production/applications/infrastructure/cloudnative-pg.yaml`)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cloudnative-pg
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"   # Deploy after cert-manager
spec:
  project: default
  sources:
    - repoURL: https://cloudnative-pg.github.io/charts
      chart: cloudnative-pg
      targetRevision: "0.29.0"
      helm:
        valueFiles:
          - $values/infrastructure/cloudnative-pg/values.yaml
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
      - ServerSideApply=true    # Required for CRD management
```

> **Note on `sync-wave: "1"`**: The CNPG operator must be confirmed running before creating any `Cluster` resource (wave 2+). Cert-manager is in the same wave 1, but is usually up earlier.

### 2. Helm Values (`infrastructure/cloudnative-pg/values.yaml`)

Key configurations for the single-node homelab:
- `replicaCount: 1` — one replica is enough for single-node
- `crds.create: true` — CRDs managed directly by the Helm chart
- `config.clusterWide: true` — operator watches all namespaces
- `ServerSideApply=true` — required so Helm can manage CRDs correctly on Kubernetes 1.22+

### 3. Push to Gitea & ArgoCD Sync

```bash
# In the gitops-repo directory
git add k8s/clusters/production/applications/infrastructure/cloudnative-pg.yaml
git add infrastructure/cloudnative-pg/values.yaml
git commit -m "feat: add CloudNativePG operator v1.30.0"
git push gitea main
```

ArgoCD will automatically detect the change and sync the app within ~3 minutes, or it can be triggered manually:

```bash
argocd app sync cloudnative-pg
# or via kubectl
kubectl -n argocd patch application cloudnative-pg --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

### 4. Verify Operator Installation

```bash
# Check ArgoCD Application status
kubectl get application cloudnative-pg -n argocd

# Check operator pods in the cnpg-system namespace
kubectl get pods -n cnpg-system

# Check registered CRDs
kubectl get crd | grep postgresql

# Check operator details (deployment name = Helm release name)
kubectl describe deployment cloudnative-pg -n cnpg-system
```

Expected output:
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

## Creating a PostgreSQL Cluster (Usage Example)

Once the operator is installed, you can create a PostgreSQL cluster using the `Cluster` CRD. Below is a minimal cluster example for development in the homelab.

### Example: Standalone Cluster (1 node, local-path storage)

```yaml
# Save as: infrastructure/cloudnative-pg/example-cluster.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-cluster
  namespace: database
spec:
  # Number of instances (1 = standalone, 2+ = primary + standby)
  instances: 1

  # PostgreSQL version
  imageName: ghcr.io/cloudnative-pg/postgresql:17.5

  # Storage for PostgreSQL data
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

  # Bootstrap: initialize a new database
  bootstrap:
    initdb:
      database: myapp
      owner: myapp_user
      secret:
        name: pg-cluster-credentials

  # PostgreSQL parameter tuning
  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "64MB"
      log_min_duration_statement: "1000"  # log queries > 1 second
```

### Secret for credentials (create before deploying the Cluster):

```bash
kubectl create namespace database

kubectl create secret generic pg-cluster-credentials \
  --namespace database \
  --from-literal=username=myapp_user \
  --from-literal=password=SuperSecretPassword123!
```

### Verify the Cluster:

```bash
kubectl get cluster -n database
kubectl get pods -n database
kubectl get pvc -n database

# View detailed cluster status
kubectl describe cluster pg-cluster -n database

# Connect to the primary instance via psql
kubectl exec -it pg-cluster-1 -n database -- psql -U myapp_user -d myapp
```

---

## Example: High Availability Cluster (3 nodes)

> ⚠️ **Note**: This cluster is **single-node** (`homelabs`). The HA configuration (3 instances) is only relevant if the cluster is later expanded to multi-node. On a single node, all instances will run on the same node.

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

  # Connection pooling with PgBouncer
  # (requires a separate Pooler resource)

  monitoring:
    enablePodMonitor: false   # set true if Prometheus Operator is available
```

---

## Backup & Recovery

### Scheduled Backup to S3/MinIO (Optional)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: pg-cluster-backup
  namespace: database
spec:
  schedule: "0 2 * * *"    # Every day at 02:00
  backupOwnerReference: self
  cluster:
    name: pg-cluster
  method: barmanObjectStore  # or volumeSnapshot

# The cluster must be configured with barmanObjectStore in spec.backup
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
      source: pg-cluster      # Source cluster name
      recoveryTarget:
        targetTime: "2026-08-01 12:00:00"  # PITR to a specific time

  externalClusters:
    - name: pg-cluster
      barmanObjectStore:
        # ... S3/MinIO configuration
```

---

## kubectl-cnpg Plugin (Optional but Recommended)

The official CNPG management CLI plugin for kubectl:

```bash
# Install via krew
kubectl krew install cnpg

# Check cluster status
kubectl cnpg status pg-cluster -n database

# Promote a standby to primary (manual failover)
kubectl cnpg promote pg-cluster pg-cluster-2 -n database

# View logs
kubectl cnpg logs cluster pg-cluster -n database

# Hibernate cluster (scale down to 0)
kubectl cnpg hibernate on pg-cluster -n database

# Wake up from hibernate
kubectl cnpg hibernate off pg-cluster -n database
```

---

## Upgrade Operator

To upgrade the operator version, simply update `targetRevision` in the ArgoCD Application file:

```yaml
# k8s/clusters/production/applications/infrastructure/cloudnative-pg.yaml
sources:
  - repoURL: https://cloudnative-pg.github.io/charts
    chart: cloudnative-pg
    targetRevision: "0.30.0"   # ← Update to the new version
```

> **Warning**: Before upgrading, always read the **Upgrade Notes** in the [official documentation](https://cloudnative-pg.io/documentation/1.30/installation_upgrade/) as manual migration steps may be required, especially for minor version jumps.

---

## Troubleshooting

### Operator not syncing in ArgoCD

```bash
# Check ArgoCD events
kubectl describe application cloudnative-pg -n argocd | tail -30

# Check ArgoCD application controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

### CRD conflict during sync

If an error occurs related to CRD ownership:
```bash
# Force sync with replace
argocd app sync cloudnative-pg --force
```

Or make sure `ServerSideApply=true` is present in syncOptions.

### Cluster stuck in "Setting up primary"

```bash
kubectl describe cluster pg-cluster -n database

# Check logs of the first instance
kubectl logs pg-cluster-1 -n database -c postgres
kubectl logs pg-cluster-1 -n database -c bootstrap-controller
```

### Cluster Pod cannot start (PVC pending)

With `local-path`, a new PVC will remain `Pending` until a Pod is scheduled to the node (WaitForFirstConsumer). This is **normal** for local-path storage.

```bash
kubectl get pvc -n database
kubectl describe pvc pg-cluster-1 -n database
```

---

## References

| Resource | URL |
|----------|-----|
| Official Documentation | https://cloudnative-pg.io/documentation/1.30/ |
| GitHub | https://github.com/cloudnative-pg/cloudnative-pg |
| Helm Chart | https://github.com/cloudnative-pg/charts |
| ArtifactHub | https://artifacthub.io/packages/helm/cloudnative-pg/cloudnative-pg |
| Release Notes v1.30 | https://cloudnative-pg.io/documentation/1.30/release_notes/v1.30/ |
| PostgreSQL 17 Images | https://github.com/cloudnative-pg/postgresql |