# Qdrant Installation & Integration Documentation (Vector Database for RAG)

This document describes the installation, deployment architecture, and integration for the **Qdrant Vector Database** in the `frengky.xyz` homelab Kubernetes cluster. Qdrant is used by **mcp-bridge** as a RAG backend for semantic search.

---

## 🛠️ Architecture Summary & RAG Integration

Qdrant is deployed as a highly efficient single-node database and integrated internally:

1. **Local Storage**: Uses a persistent volume based on the K3s built-in `local-path` storage class of `10Gi` for vector data.
2. **Cluster Mode Disabled**: Since it runs on a single-node homelab, Raft consensus coordination is disabled (`cluster.enabled: false`) to save CPU/RAM resources and avoid deadlocks.
3. **Internal Connectivity & Ingress (Tailscale Only)**: Qdrant is deployed in the same namespace as `mcp-bridge` (`backend`) and can be reached via `http://qdrant:6333`. For administration, the Web UI dashboard is exposed through Traefik Ingress at the domain `qdrant.frengky.xyz` (websecure), which is only accessible when connected to the **Tailscale** VPN mesh.
4. **Offline-Ready & Self-Contained**: All Helm chart artifacts and container images are stored in the local Harbor registry (`harbor.frengky.xyz`) to avoid Docker Hub and GitHub network/IPv6 limit errors.

---

## 📁 GitOps Manifest Structure

Manifest files are stored in the GitOps repository (`gitops-repo`) with the following structure:

```
gitops-repo/
├── kubernetes/
│   ├── applications/
│   │   └── production/
│   │       └── qdrant.yaml          # ArgoCD Application definition
│   └── production/
│       └── backend/
│           └── qdrant/
│               └── values.yaml      # Qdrant Helm values configuration file
└── docs/
    └── qdrant-deployment.md         # This document (Installation Instructions)
```

### 1. ArgoCD Application (`k8s/clusters/production/applications/production/qdrant.yaml`)
Uses the ArgoCD **multi-source** pattern to fetch the chart from the Harbor OCI Registry and values from the gitops repository:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: qdrant
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3" # Runs before mcp-bridge (wave 5)
spec:
  project: default
  sources:
    - repoURL: harbor-registry-tls.harbor.svc.cluster.local
      chart: helm-repos/qdrant
      targetRevision: "1.18.2"
      helm:
        valueFiles:
          - $values/k8s/clusters/production/applications/apps/production/backend/qdrant/values.yaml
    - repoURL: http://gitea-http.gitea.svc.cluster.local:3000/devops/gitops.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: backend
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 2. Helm Values (`k8s/clusters/production/applications/apps/production/backend/qdrant/values.yaml`)
```yaml
replicaCount: 1

image:
  repository: harbor.frengky.xyz/library/qdrant
  tag: v1.18.2
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  ports:
    - name: http
      port: 6333
      targetPort: 6333
      protocol: TCP
      checksEnabled: true
    - name: grpc
      port: 6334
      targetPort: 6334
      protocol: TCP
      checksEnabled: false

ingress:
  enabled: true
  ingressClassName: traefik
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
  hosts:
    - host: qdrant.frengky.xyz
      paths:
        - path: /
          pathType: Prefix
          servicePort: 6333

persistence:
  enabled: true
  accessModes: ["ReadWriteOnce"]
  size: 10Gi
  storageClassName: local-path

config:
  cluster:
    enabled: false # Disable multi-node raft
  service:
    enable_tls: false

apiKey: false # Internal authentication disabled for pod access convenience
readOnlyApiKey: false

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 200m
    memory: 256Mi
```

---

## 🚀 Setup & Mirroring Steps

If you want to perform an update or reinstallation later, here are the commands used for setup mirroring:

### 1. Mirroring Helm Chart to Harbor
```bash
# Add the official Qdrant repo and pull the chart
helm repo add qdrant https://qdrant.to/helm
helm repo update
helm pull qdrant/qdrant --version 1.18.2

# Login to Harbor OCI registry
helm registry login harbor.frengky.xyz -u admin -p Harbor12345

# Push Chart to OCI repo
helm push qdrant-1.18.2.tgz oci://harbor.frengky.xyz/helm-repos
```

### 2. Mirroring Container Image to Harbor
```bash
# Pull image from Docker Hub
docker pull qdrant/qdrant:v1.18.2

# Login to docker registry
echo "Harbor12345" | docker login -u admin --password-stdin harbor.frengky.xyz

# Tag and Push to Harbor library
docker tag qdrant/qdrant:v1.18.2 harbor.frengky.xyz/library/qdrant:v1.18.2
docker push harbor.frengky.xyz/library/qdrant:v1.18.2
```

---

## 🔍 Connection Testing

To ensure mcp-bridge can communicate with the Qdrant database inside the cluster, perform the following test via `kubectl exec`:

```bash
# Perform HTTP query to Qdrant REST API from inside the mcp-bridge pod
kubectl exec -n backend <MCP-BRIDGE-POD-NAME> -- wget -qO- http://qdrant:6333
```

**Expected Successful Response:**
```json
{
  "title": "qdrant - vector search engine",
  "version": "1.18.2",
  "commit": "44ad62f8cd69642be5afa6441612525e24a0d063"
}
```
