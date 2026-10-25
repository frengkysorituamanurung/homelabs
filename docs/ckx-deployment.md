# CK-X Simulator Deployment (GitOps / Flux CD)

This deploys the **CK-X Kubernetes certification simulator cluster** (`nishanb/ck-x-simulator-cluster:latest`)
into the homelab k3s cluster using Flux CD (plain manifests pattern, like `n8n`).

Reference upstream project: https://github.com/sailor-sh/CK-X

## What is deployed

- Namespace: `ckx`
- Deployment: `ckx` running `nishanb/ck-x-simulator-cluster:latest` (privileged, Docker-in-Docker + k3d)
- Service: `ckx` (ports `6443` for the nested Kubernetes API, `22` for SSH)

## Access

The nested cluster API is exposed internally as `ckx.ckx.svc.cluster.local:6443`.
From inside the cluster, use port-forwarding or exec into the pod:

```bash
kubectl -n ckx port-forward svc/ckx 6443:6443
kubectl -n ckx port-forward svc/ckx 2222:22
```

The pod writes `/ready` once Docker + k3d are initialized (readiness probe).

## Resources

- Requests: 1 CPU / 2Gi memory
- Limits: 2 CPU / 4Gi memory

## Notes

- The container runs **privileged** (required for Docker-in-Docker / k3d). Only deploy on a trusted single-node homelab.
- Full CK-X web UI (webapp, VNC, nginx, facilitator, ...) is distributed by upstream as a Docker Compose stack and is **not** part of this GitOps deployment. Use upstream `docker-compose.yaml` if you want the complete simulator experience on a Docker host.
- To remove: delete `clusters/production/flux-system/pilot-ckx.yaml`, remove it from `clusters/production/flux-system/kustomization.yaml`, delete `k8s/clusters/production/applications/apps/production/ckx`, commit and push.