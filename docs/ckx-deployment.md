# CK-X Simulator Deployment (GitOps / Flux CD)

This deploys the **full CK-X Kubernetes certification simulator stack**
(`nishanb/ck-x-simulator-*`) into the homelab k3s cluster using Flux CD
(plain manifests pattern, like `n8n`), and exposes the web UI at
`https://ckx.frengky.xyz`.

Reference upstream project: https://github.com/sailor-sh/CK-X

## What is deployed

- Namespace: `ckx`
- Deployments: `ckx-cluster` (k3d cluster, privileged), `ckx-jumphost`,
  `ckx-remote-terminal`, `ckx-remote-desktop`, `ckx-webapp`,
  `ckx-redis`, `ckx-facilitator`, `ckx-nginx`
- Services: one per component (see `service.yaml`)
- Ingress: `ckx.frengky.xyz` -> `ckx` service (nginx) port 80
- Shared PVC: `ckx-kube-config` (kubeconfig shared between cluster and jumphost)

## Access

Web UI: `https://ckx.frengky.xyz`

The nested cluster API is exposed internally as `ckx-cluster.ckx.svc.cluster.local:6443`.

From inside the cluster, use port-forwarding or exec into the pod:

```bash
kubectl -n ckx port-forward svc/ckx-cluster 6443:6443
kubectl -n ckx port-forward svc/ckx-cluster 2222:22
```

The pod writes `/ready` once Docker + k3d are initialized (readiness probe).

## Resources

Total requests roughly: 2.5 CPU / 3.5Gi memory (limits higher). Runs on the
single-node homelab; ensure capacity.

## Notes

- Containers run **privileged** where required (cluster, jumphost). Only deploy
  on a trusted single-node homelab.
- Shared kube-config uses a `ReadWriteOnce` PVC on `local-path`; all pods run on
  the same node.
- To remove: delete `clusters/production/flux-system/pilot-ckx.yaml`, remove it
  from `clusters/production/flux-system/kustomization.yaml`, delete
  `k8s/clusters/production/applications/apps/production/ckx`, commit and push.