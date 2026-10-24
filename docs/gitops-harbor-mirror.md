# GitOps Helm Charts Mirroring to Harbor (Air-Gapped / Private Registry)

This document explains the configuration and workflow applied to overcome the outbound internet access limitation issue (TCP `DeadlineExceeded` failure when Flux CD tries to pull Helm Charts from external registries).

## Problem Background
Pods inside the cluster experience outbound TCP resolution issues (outgoing internet), causing `argocd-repo-server` to be unable to run `helm pull` from public registries such as GitHub, HashiCorp, Prometheus Community, etc. If the sync is left failing, Flux CD will not update the cluster state and applications will get stuck in `Unknown` or `ComparisonError` status.

## Solution: Air-Gapped GitOps Pattern
Instead of relying on the internet to download Helm Charts in real time, we implement a **Private Registry Mirroring** pattern:
1. Copy (pull) all external Helm chart `.tgz` files via the host server (which has normal internet access).
2. Push those charts into the `helm-repos` project in our local Harbor (as OCI artifacts).
3. Configure Flux CD to use the local Harbor as the source (Single Source of Truth) for Helm Charts.

Benefits:
- **Zero Internet Dependency:** Flux CD now runs 100% offline (communicating between pods in the cluster via `harbor-core.harbor.svc.cluster.local`).
- **Security (Enterprise Grade):** Resilient against third-party downtime.
- **Performance:** Sync process becomes instant (in milliseconds).

## Configuration Performed

### 1. Migrating Charts to Harbor
Using an automated script, all Helm chart dependencies are pulled at specific versions and pushed to the local Harbor OCI registry:
```bash
helm pull hashicorp/vault --version 0.29.1
helm push vault-0.29.1.tgz oci://harbor.frengky.xyz/helm-repos
# (Done for all charts such as argo-cd, grafana, loki, kube-state-metrics, etc.)
```

### 2. Registering the Repository Secret in Flux CD
Harbor must be registered inside the `argocd` namespace as a `helm` repository (OCI). This secret tells Flux CD how to log in to Harbor via internal HTTP:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: harbor-helm-repos
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  name: harbor-helm-repos
  url: harbor-core.harbor.svc.cluster.local   # Uses Internal DNS (not the Cloudflare domain)
  type: helm
  enableOCI: "true"
  insecure: "true"
  username: admin
  password: <harbor_password>
```

### 3. Updating GitOps Manifests (Flux CD Application)
All Flux CD manifest files (such as `k8s/clusters/production/applications/apps/monitoring/grafana.yaml`) have been updated so that the `source` block points to the local Harbor with the `helm-repos/` prefix for the chart name:
```yaml
spec:
  source:
    # PREVIOUSLY: repoURL: https://grafana.github.io/helm-charts (chart: grafana)
    repoURL: harbor-core.harbor.svc.cluster.local
    chart: helm-repos/grafana
    targetRevision: 8.10.4
```

## Sync Process
If a sync fails in Flux CD, the components currently running in Kubernetes will remain safe (unaffected). Flux CD will retry in the next automatic sync cycle. With this internal Harbor configuration, the likelihood of failure due to network (connectivity) issues is minimal.