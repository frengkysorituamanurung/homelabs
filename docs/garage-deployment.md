# Garage S3-Compatible Object Storage Deployment

This document describes the deployment of [Garage](https://garagehq.deuxfleurs.fr/), a lightweight S3-compatible object store, in the `frengky.xyz` homelab Kubernetes cluster.

## Summary

- **UI Domain:** `https://garage.frengky.xyz`
- **S3 API:** internal service `garage:3900` (not publicly exposed)
- **Mode:** single-node (`--single-node`, `replication_factor = 1`)
- **StorageClass:** `local-path`
- **Persistence:** 1Gi metadata + 20Gi data
- **Admin API:** ClusterIP service `garage-admin` (port 3903), not publicly exposed

## GitOps Manifests

- ArgoCD Application: `k8s/clusters/production/applications/infrastructure/garage.yaml`
- Helm values: `infrastructure/garage/values.yaml`

The application uses the official Garage Helm chart from `https://git.deuxfleurs.fr/Deuxfleurs/garage.git` (tag `v2.4.1`, chart `0.10.3`) with values from this repository.

## Post-Deploy Management

After ArgoCD syncs the application:

```bash
# Check status
kubectl get pods -n garage
kubectl exec -n garage garage-0 -- ./garage status

# Port-forward admin API
kubectl port-forward -n garage svc/garage-admin 3903:3903
```

Create an access key and bucket (example):

```bash
kubectl exec -n garage garage-0 -- ./garage key create homelab-key
kubectl exec -n garage garage-0 -- ./garage bucket create homelab-bucket
kubectl exec -n garage garage-0 -- ./garage bucket allow --read --write homelab-bucket --key homelab-key
```

## S3 Client Usage

The S3 API is not publicly exposed. Use the in-cluster endpoint from workloads:

Endpoint: `http://garage:3900` (namespace `garage`)
Region: `garage`

For external access, use port-forward:

```bash
kubectl port-forward -n garage svc/garage 3900:3900
aws --endpoint-url http://localhost:3900 s3 ls
```

Use path-style addressing.

## Notes

- Garage refuses `--single-node` if a multi-node layout already exists; this setup is intended for a fresh single-node deployment.
- The ingress uses the Traefik default wildcard certificate (`*.frengky.xyz`) via the `websecure` entrypoint.
- Metrics are exposed on the admin port (`/metrics`) through the `garage-metrics` service.

## Garage UI

A web UI is deployed as `garage-ui` in the same `garage` namespace.

- **Domain:** `https://garage.frengky.xyz`
- **Chart:** `oci://ghcr.io/noooste/charts/garage-ui` (`0.14.0`)
- **Manifest:** `k8s/clusters/production/applications/infrastructure/garage-ui.yaml`
- **Values:** `infrastructure/garage-ui/values.yaml`

The UI connects to Garage via in-cluster services:
- S3 API: `http://garage:3900`
- Admin API: `http://garage-admin:3903`

The Garage admin token is read from the `garage-admin-token` Kubernetes secret (key `admin-token`), which is created by ESO from Vault path `secret/garage` property `admin_token`.

Store the token in Vault before sync:

```bash
kubectl exec -n vault -it vault-0 -- vault kv put secret/garage admin_token="$(openssl rand -base64 32)"
```

The token value must also match the `GARAGE_ADMIN_TOKEN` environment variable used by the Garage pod (provided through the same secret).