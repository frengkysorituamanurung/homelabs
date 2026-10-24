# OpenObserve Installation Documentation

This document describes the installation, deployment architecture, configuration, and secret management integration for **OpenObserve** in the `frengky.xyz` homelab Kubernetes cluster. OpenObserve is deployed using a **GitOps (ArgoCD)** pattern with a Helm chart from a private Harbor registry.

---

## 🔎 About OpenObserve

[OpenObserve](https://openobserve.ai) is an open-source all-in-one observability platform that supports:
- **Logs** — ingest, search, and visualize logs
- **Metrics** — Prometheus-compatible monitoring
- **Traces** — distributed tracing (OpenTelemetry)
- **Dashboards** — real-time visualization
- **Alerts** — centralized alerting

In this deployment, OpenObserve runs in **single-node / local mode** using SQLite as the meta store and NATS as the cluster coordinator.

---

## 🏗️ Deployment Architecture

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

### Deployed Components

| Component | Type | Function |
|----------|------|----------|
| `openobserve-router` | Deployment | API gateway & UI router |
| `openobserve-ingester` | StatefulSet | Receives & stores data |
| `openobserve-querier` | StatefulSet | Query engine |
| `openobserve-alertmanager` | StatefulSet | Alert management |
| `openobserve-compactor` | Deployment | Historical data compaction |
| `openobserve-nats` | StatefulSet | Cluster coordinator (JetStream) |
| `openobserve-blocked-metrics` | Deployment | Blocks public access to `/metrics` |

---

## 📁 GitOps Manifest Structure

Manifest files are stored in the GitOps repository (`gitops-repo`) with the following structure:

```
gitops-repo/
├── kubernetes/
│   ├── applications/
│   │   └── infrastructure/
│   │       └── openobserve.yaml        # ArgoCD Application definition
│   └── production/
│       └── openobserve/
│           └── values.yaml             # Helm configuration values
├── secrets/
│   └── templates/
│       └── openobserve-secret.yaml     # ExternalSecret template (Vault → ESO)
└── docs/
    └── openobserve-deployment.md       # This document
```

---

## 📄 Manifest Details

### 1. ArgoCD Application (`k8s/clusters/production/applications/infrastructure/openobserve.yaml`)

ArgoCD manages this deployment using a Helm chart from the Harbor OCI registry:

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

The main deployment configuration includes:
- **Mode**: `ZO_LOCAL_MODE: "true"` — single-node without clustering
- **Meta Store**: `ZO_META_STORE: "sqlite"` — no PostgreSQL
- **Coordinator**: built-in NATS with JetStream (1 replica)
- **Storage**: `local-path` StorageClass (K3s built-in)
- **Ingress**: Traefik with host `openobserve.frengky.xyz`

### 3. ExternalSecret (`secrets/templates/openobserve-secret.yaml`)

ExternalSecret fetches credentials from Vault and creates a Kubernetes Secret in the `openobserve` namespace:

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

OpenObserve credentials are managed using HashiCorp Vault + External Secrets Operator (ESO).

### Storing Credentials in Vault

```bash
kubectl exec -n vault -it vault-0 -- sh -c "
  VAULT_ADDR=http://127.0.0.1:8200
  VAULT_TOKEN=<ROOT_TOKEN>
  export VAULT_ADDR VAULT_TOKEN
  vault kv put secret/openobserve \
    rootEmail='admin@frengky.xyz' \
    rootPassword='<STRONG_PASSWORD>' \
    webUrl='https://openobserve.frengky.xyz'
"
```

### Paths in Vault

| Path | Key | Description |
|------|-----|-------------|
| `secret/data/openobserve` | `rootEmail` | Admin login email |
| `secret/data/openobserve` | `rootPassword` | Admin password |
| `secret/data/openobserve` | `webUrl` | Application URL |

### Apply ExternalSecret

```bash
# Apply ExternalSecret so ESO automatically creates the Kubernetes Secret
kubectl apply -f secrets/templates/openobserve-secret.yaml

# Verify sync status
kubectl get externalsecret -n openobserve openobserve-auth

# Check the secret created by ESO
kubectl get secret -n openobserve openobserve-auth
```

### Changing the Password

To change the OpenObserve root password:

1. **Update the secret in Vault:**
   ```bash
   kubectl exec -n vault -it vault-0 -- sh -c "
     VAULT_ADDR=http://127.0.0.1:8200
     VAULT_TOKEN=<ROOT_TOKEN>
     export VAULT_ADDR VAULT_TOKEN
     vault kv put secret/openobserve \
       rootEmail='admin@frengky.xyz' \
       rootPassword='<NEW_PASSWORD>' \
       webUrl='https://openobserve.frengky.xyz'
   "
   ```

2. **ESO will automatically sync** (interval: 1 hour) and update the Kubernetes Secret.

3. **Reloader will automatically restart pods** that use the secret.

> [!NOTE]
> Currently the password in values.yaml and Vault is not yet connected via `externalSecret`. To use Vault as the full source of truth, add `externalSecret.enabled: true` to values.yaml and reference the `openobserve-auth` secret.

---

## 🔧 OpenObserve Configuration

### Deployment Mode

OpenObserve runs in **Local Mode** (`ZO_LOCAL_MODE: "true"`), suitable for single-node homelabs:
- All components run in the same namespace
- Does not require S3-compatible object storage
- Data is stored on local disk via PVC

### Storage Allocation

| PVC | Size | Contents |
|-----|------|----------|
| `data-openobserve-ingester-0` | 20Gi | Raw data, WAL, stream files |
| `cache-openobserve-querier-0` | 10Gi | Query cache (disk) |
| `cache-openobserve-alertmanager-0` | 5Gi | Alert state & history |
| `nats-js-openobserve-nats-0` | 5Gi | NATS JetStream (queue/coord) |

### Ports & Protocols

| Service | Port | Protocol | Function |
|---------|------|----------|----------|
| HTTP API / UI | 5080 | HTTP | Ingress, API, Dashboard |
| gRPC | 5081 | gRPC | Internal component comm. |

---

## 🚀 How to Send Data to OpenObserve

### Ingest via API (Logs)

```bash
# Send log via HTTP API (Basic Auth)
curl -u "admin@frengky.xyz:OpenObserve@123" \
  -H "Content-Type: application/json" \
  -d '[{"level":"info","job":"test","log":"Hello OpenObserve!"}]' \
  https://openobserve.frengky.xyz/api/default/default/_json
```

### Alloy / Vector / Fluent Bit Configuration

To send logs from Kubernetes applications using **Grafana Alloy** (already deployed):

```river
// alloy config — add output to OpenObserve
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

OpenObserve supports Prometheus Remote Write:

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

## ✅ Deployment Verification

### Check Pods & Resources Status

```bash
# Status of all OpenObserve pods
kubectl get pods -n openobserve

# Status of ArgoCD Application
kubectl get application openobserve -n argocd

# Status of PVC storage
kubectl get pvc -n openobserve

# Status of ingress
kubectl get ingress -n openobserve
```

### Check Health API

```bash
# Health check endpoint
curl -s https://openobserve.frengky.xyz/healthz

# Login test
curl -u "admin@frengky.xyz:OpenObserve@123" \
  https://openobserve.frengky.xyz/api/default/streams
```

### Check Component Logs

```bash
# Router log (entry point)
kubectl logs -n openobserve -l app.kubernetes.io/component=router --tail=50

# Ingester log
kubectl logs -n openobserve statefulset/openobserve-ingester --tail=50

# NATS log
kubectl logs -n openobserve statefulset/openobserve-nats -c nats --tail=20
```

---

## 🔄 Upgrade Chart Version

To upgrade the OpenObserve version:

1. **Pull & push the latest chart to Harbor:**
   ```bash
   helm pull openobserve/openobserve --version <NEW_VERSION> -d /root/server/oo-chart/
   helm push /root/server/oo-chart/openobserve-<NEW_VERSION>.tgz oci://harbor.frengky.xyz/helm-repos
   ```

2. **Update targetRevision in the ArgoCD Application:**
   ```yaml
   # k8s/clusters/production/applications/infrastructure/openobserve.yaml
   targetRevision: "<NEW_VERSION>"
   ```

3. **Commit & push to Gitea** — ArgoCD will sync automatically.

---

## 📌 References & Related Files

| File | Function |
|------|----------|
| `k8s/clusters/production/applications/infrastructure/openobserve.yaml` | ArgoCD Application manifest |
| `infrastructure/openobserve/values.yaml` | Helm chart values |
| `secrets/templates/openobserve-secret.yaml` | ExternalSecret (Vault → K8s Secret) |
| `docs/openobserve-deployment.md` | This document |
| `docs/reloader-vault-integration.md` | Vault + ESO + Reloader guide |
| `secrets/README.md` | Complete secret management guide |

### Service URLs

| Service | URL |
|---------|-----|
| OpenObserve UI | https://openobserve.frengky.xyz |
| Vault (Secret Store) | https://vault.frengky.xyz |
| ArgoCD (GitOps) | https://argocd.frengky.xyz |
| Harbor (Registry) | https://harbor.frengky.xyz |
