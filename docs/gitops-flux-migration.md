# Migrating from Argo CD to Flux CD (Homelab)

This document summarizes the completed migration of the `frengky.xyz` homelab
from Argo CD to Flux CD. All workloads are now managed by Flux.

## Overview

- **Source of truth:** `https://github.com/frengkysorituamanurung/homelabs.git` (`main`)
- **Cluster:** single-node k3s `v1.36.2+k3s1`
- **GitOps engine:** Flux CD (source-controller, kustomize-controller, helm-controller)
- **Secrets:** HashiCorp Vault + External Secrets Operator (unchanged)
- **Bootstrap path:** `clusters/production/flux-system`

## Prerequisites

- `kubectl` with cluster-admin access
- `flux` CLI (v2.9.x)
- GitHub push access to the repository
- Backups of persistent data (PVCs, databases)

## Phase 1 — Discovery and Baseline

1. Inventory all Argo CD `Application` resources:
   ```bash
   kubectl get applications -n argocd
   ```
2. Record PVCs and stateful data:
   ```bash
   kubectl get pvc -A
   kubectl get cluster -A   # CloudNativePG
   ```
3. Document sync waves, prune settings, and manual changes.

## Phase 2 — Architecture and Preparation

- Define Flux repository layout (`clusters/production/flux-system`, `infrastructure/<app>/flux`).
- Map Argo CD sync waves to Flux `Kustomization.dependsOn`.
- Choose secret strategy (keep Vault + ESO; optional SOPS later).
- Pin unpinned images (`latest` tags).

## Phase 3 — Flux CD Bootstrap

```bash
flux install
flux create source git homelabs \
  --url=https://github.com/frengkysorituamanurung/homelabs.git \
  --branch=main \
  --interval=1m
```

Persist controllers and source in Git under `clusters/production/flux-system/`.

> Note: the homelab has outbound egress restrictions. The source-controller
> (and helm-controller) may need `hostNetwork: true` + `dnsPolicy: ClusterFirstWithHostNet`
> to reach GitHub/Harbor, matching the existing cert-manager workaround.

## Phase 4 — Controlled Workload Migration

For each workload:

1. Disable Argo CD auto-sync (remove `automated:` block from the Application).
2. Create Flux manifests:
   - Plain manifests: `Kustomization` pointing at the manifest directory.
   - Helm apps: `HelmRepository` + `HelmRelease` (set `releaseName` to the existing release name to adopt it).
   - Local charts: use `chart.spec.chart: ./path/in/repo` with `sourceRef` GitRepository.
   - OCI charts: use `HelmRepository` with `type: oci`.
3. Add the new Kustomization to `clusters/production/flux-system/kustomization.yaml`.
4. Commit and push.
5. Reconcile:
   ```bash
   flux reconcile source git homelabs
   flux reconcile kustomization flux-system -n flux-system
   ```
6. Validate:
   ```bash
   flux get kustomizations -n flux-system
   flux get helmreleases -A
   ```
7. Remove the Argo CD `Application` manifest from Git and delete the Application:
   ```bash
   kubectl delete application <name> -n argocd --cascade=orphan
   ```

### Migration order used

1. `cloudflared`, `cert-manager`, `external-secrets`, `kube-state-metrics`, `node-exporter`, `alloy`
2. `argo-rollouts`, ingress rules, `vault-unsealer`
3. `vmsingle`, `loki`, `harbor`, `vault`
4. `cloudnative-pg`, `grafana-production`
5. `n8n`, `sandbox-finance-db`, `qdrant`, `immich`, `garage`, `garage-ui`
6. `bentopdf`, `finance-landing`, `mcp-bridge`, `service-a`, `glance`, `reloader`
7. Retire Argo CD (delete namespace + CRDs)

## Phase 5 — Validation

- All Flux `Kustomization`/`HelmRelease` resources `Ready`.
- Applications reachable via ingress/DNS/TLS.
- Persistent data intact (PVCs, databases, object storage).
- Drift correction tested (change a field, verify Flux reverts it).
- Argo CD no longer manages any resources.

## Phase 6 — Argo CD Retirement

```bash
kubectl delete namespace argocd
# Remove Argo CD CRDs
kubectl get crd -o name | grep argoproj.io | sed 's|customresourcedefinition.apiextensions.k8s.io/||' | xargs -r kubectl delete crd
```

Remove Argo-related manifests from Git (`k8s/clusters/production/applications/infrastructure/argocd.yaml`, etc.).

## Rollback

- Re-enable Argo CD: re-apply `bootstrap/root-app.yaml`.
- For a single workload: delete the Flux `Kustomization`/`HelmRelease`, re-add the Argo `Application` manifest, Argo CD re-adopts.
- Keep etcd backups and PVC snapshots before any destructive step.

## Notes

- Vault was running in dev mode during migration; move to file storage + backups for production.
- Image tags using `latest` should be pinned for reproducibility.
- The `helm/` directory is still required: Flux builds `garage`, `garage-ui`, `immich`, and `generic-app` charts from it.
```