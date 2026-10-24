# Immich Deployment (Photo & Video Management)

## Summary

- **Domain (UI):** `https://immich.frengky.xyz`
- **Database:** CloudNativePG cluster `immich` (VectorChord/PostgreSQL 18)
- **Cache:** Valkey (in-chart, emptyDir)
- **Machine Learning:** enabled (cache emptyDir)
- **Library storage:** PVC `immich-library` (50Gi, `local-path`)

## GitOps Manifests

- Flux CD Application: `k8s/clusters/production/applications/infrastructure/immich.yaml`
- Helm values: `infrastructure/immich/values.yaml`
- Helm chart: `oci://ghcr.io/immich-app/immich-charts/immich` (Flux `HelmRepository` of type `oci`)
- Manifests: `infrastructure/immich/manifests/`
  - `pvc.yaml`
  - `external-secret.yaml`
  - `cnpg-cluster.yaml`

## Secrets

Vault path: `secret/immich` with keys:
- `username` (immich)
- `password`

ESO creates Kubernetes secret `immich-db-credentials` in namespace `immich`.

## Post-Deploy Notes

- First start may take time while ML models download.
- Upload limit: Traefik has no default body size limit; Immich handles large uploads.
- Library PVC uses `local-path` (RWO). For multi-node, change storage class.
- Database uses CNPG with VectorChord extension enabled.