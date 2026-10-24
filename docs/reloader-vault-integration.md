# Reloader Guide with Vault & External Secrets Operator (ESO) Pattern

This document contains a complete guide on the architecture, installation, and workings of **Stakater Reloader** integrated with **External Secrets Operator (ESO)** and **HashiCorp Vault** in this Kubernetes cluster.

---

## 1. Problem Solved

By default in Kubernetes:
1. When data in **HashiCorp Vault** changes, **External Secrets Operator (ESO)** will automatically update the `Secret` resource in Kubernetes.
2. However, **Pods/Deployments already running do NOT automatically read those secret changes** (especially when secrets are injected via `envFrom` / `secretRef`).
3. As a result, developers must run `kubectl rollout restart` manually every time there is a credential/secret change in Vault.

With **Stakater Reloader**, every change to a Kubernetes `Secret` (triggered by Vault & ESO) will automatically trigger a **rolling restart** of the related Pod/Deployment without downtime.

---

## 2. Architecture & Working (End-to-End Workflow)

```
┌─────────────────┐       (1) Sync       ┌──────────────────────────┐
│ HashiCorp Vault │ ───────────────────> │ External Secrets Operator│
└─────────────────┘                      └──────────────────────────┘
                                                       │
                                                       │ (2) Update Secret
                                                       ▼
┌─────────────────┐       (4) Rollout    ┌──────────────────────────┐
│ Pod / Workload  │ <─────────────────── │ Kubernetes Secret        │
└─────────────────┘       Restart        └──────────────────────────┘
         ▲                                             │
         │                                             │ (3) Detect Change
         └─────────────────────────────────────────────┘
                      Stakater Reloader
```

1. **Vault (Upstream Secret Store)**: Stores application credentials/secrets (e.g. `secret/data/ci/credentials` or `secret/data/backend/sample-api`).
2. **External Secrets Operator (ESO)**: Fetches data from Vault via `ClusterSecretStore` and periodically mirrors it into a Kubernetes `Secret` resource (e.g. `sample-api-secrets`).
3. **Stakater Reloader Controller**: Monitors change events (*add/update/delete*) on all `Secret` and `ConfigMap` resources in the Kubernetes cluster.
4. **Automatic Rolling Restart**: Once Reloader detects a hash change in the `Secret`, it immediately triggers a *rolling update* on the Deployment/Argo Rollout referencing that secret.

---

## 3. Implementation Details on This Server

All Reloader components are stored and managed independently through **Harbor (Private Registry)** and **Flux CD**:

### 1. Container Image & Helm Chart Registration in Harbor
* **Container Image**: `harbor.frengky.xyz/library/reloader:v1.4.19`
* **Helm Chart OCI**: `oci://harbor.frengky.xyz/helm-repos/reloader:2.2.14`

### 2. Flux CD Application Manifest (`k8s/clusters/production/applications/infrastructure/reloader.yaml`)
Reloader is registered to the Flux CD GitOps pattern with the following manifest:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: reloader
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default
  source:
    repoURL: harbor-registry-tls.harbor.svc.cluster.local
    chart: helm-repos/reloader
    targetRevision: "2.2.14"
    helm:
      parameters:
        - name: reloader.deployment.image.name
          value: "harbor.frengky.xyz/library/reloader"
        - name: reloader.deployment.image.tag
          value: "v1.4.19"
        - name: reloader.autoReloadAll
          value: "true"
  destination:
    server: https://kubernetes.default.svc
    namespace: reloader
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

## 4. Workload Annotation Options (Deployment / Rollout)

There are two approaches to enable reload automation on applications:

### Method A: Global Auto-Reload (Default on This Server)
Because the `reloader.autoReloadAll: "true"` parameter is enabled on Reloader, all Deployments/StatefulSets using `secretRef`, `envFrom`, or `volumeMounts` from Secret/ConfigMap will be **automatically reloaded** when the secret changes.

### Method B: Specific Annotations on Chart / Deployment
To explicitly specify on the Deployment/Argo Rollout manifest:

1. **Auto Reload All Related Secrets**:
   ```yaml
   metadata:
     annotations:
       reloader.stakater.com/auto: "true"
   ```

2. **Reload Only for a Specific Secret**:
   ```yaml
   metadata:
     annotations:
       secret.reloader.stakater.com/reload: "sample-api-secrets"
   ```

---

## 5. Integration Test Procedure (Vault → ESO → Reloader → Pod)

To verify that the automation flow works perfectly:

1. **Change the Secret Value in Vault**:
   ```bash
   vault kv put secret/ci/credentials APP_VERSION="2.0.0" DB_PASSWORD="REPLACE_WITH_DB_PASSWORD"
   ```

2. **Check ExternalSecrets Sync**:
   External Secrets Operator will update the k8s secret:
   ```bash
   kubectl get externalsecrets -A
   ```

3. **Check Reloader Log**:
   Watch the Reloader log when it detects the secret change:
   ```bash
   kubectl logs -n reloader -l app.kubernetes.io/name=reloader --tail=20 -f
   ```
   *The log will show:*
   `Changes detected in secret: sample-api-secrets in namespace: backend, triggering reload for deployment: sample-api`

4. **Verify Pod Rolling Restart**:
   ```bash
   kubectl get pods -n backend -w
   ```
   Old pods will be terminated gradually and replaced by new pods that immediately read the latest secret from Vault.

---

## 6. Related Files & Manifests

| File | Function |
| :--- | :--- |
| `k8s/clusters/production/applications/infrastructure/reloader.yaml` | Flux CD Application manifest for Reloader |
| `helm-charts/charts/generic-app/templates/deployment.yaml` | Microservice Helm Chart template supporting Reloader |
| `docs/reloader-vault-integration.md` | Architecture documentation and setup guide |
