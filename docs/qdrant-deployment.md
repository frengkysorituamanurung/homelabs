# Dokumentasi Instalasi & Integrasi Qdrant (Vector Database untuk RAG)

Dokumen ini menjelaskan instalasi, arsitektur deployment, dan integrasi untuk **Qdrant Vector Database** di cluster Kubernetes homelab `frengky.xyz`. Qdrant digunakan oleh **mcp-bridge** sebagai RAG backend untuk pencarian semantik (semantic search).

---

## 🛠️ Ringkasan Arsitektur & Integrasi RAG

Qdrant dideploy sebagai database single-node yang sangat efisien dan terintegrasi secara internal:

1. **Penyimpanan Lokal**: Menggunakan persistent volume berbasis class `local-path` bawaan K3s sebesar `10Gi` untuk data vektor.
2. **Cluster Mode Dinonaktifkan**: Karena berjalan pada single-node homelab, koordinasi Raft consensus dinonaktifkan (`cluster.enabled: false`) untuk menghemat resource CPU/RAM dan menghindari deadlock.
3. **Konektivitas Internal & Ingress (Tailscale Only)**: Qdrant dideploy pada namespace yang sama dengan `mcp-bridge` (`backend`) dan dapat dihubungi via `http://qdrant:6333`. Untuk kebutuhan administrasi, dashboard Web UI diekspos melalui Traefik Ingress di domain `qdrant.frengky.xyz` (websecure) yang hanya bisa diakses saat terhubung ke VPN mesh **Tailscale**.
4. **Offline-Ready & Mandiri**: Seluruh artefak Helm chart dan container image disimpan di dalam registry lokal Harbor (`harbor.frengky.xyz`) agar terhindar dari error network/limit IPv6 Docker Hub dan GitHub.

---

## 📁 Struktur Manifest GitOps

File manifest disimpan di dalam repository GitOps (`gitops-repo`) dengan struktur berikut:

```
gitops-repo/
├── kubernetes/
│   ├── applications/
│   │   └── production/
│   │       └── qdrant.yaml          # Definisi Aplikasi ArgoCD
│   └── production/
│       └── backend/
│           └── qdrant/
│               └── values.yaml      # File konfigurasi values Helm Qdrant
└── docs/
    └── qdrant-deployment.md         # Dokumen ini (Petunjuk Instalasi)
```

### 1. Aplikasi ArgoCD (`argocd/applications/production/qdrant.yaml`)
Menggunakan pattern **multi-source** ArgoCD untuk mengambil chart dari Harbor OCI Registry dan values dari gitops repository:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: qdrant
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3" # Dijalankan sebelum mcp-bridge (wave 5)
spec:
  project: default
  sources:
    - repoURL: harbor-registry-tls.harbor.svc.cluster.local
      chart: helm-repos/qdrant
      targetRevision: "1.18.2"
      helm:
        valueFiles:
          - $values/apps/production/backend/qdrant/values.yaml
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

### 2. Helm Values (`apps/production/backend/qdrant/values.yaml`)
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
    enabled: false # Nonaktifkan multi-node raft
  service:
    enable_tls: false

apiKey: false # Autentikasi internal dinonaktifkan demi kemudahan akses pod
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

## 🚀 Langkah Setup & Mirroring

Apabila Anda ingin melakukan update atau instalasi ulang di kemudian hari, berikut perintah yang digunakan untuk setup mirroring:

### 1. Mirroring Helm Chart ke Harbor
```bash
# Tambahkan repo resmi Qdrant dan unduh chart
helm repo add qdrant https://qdrant.to/helm
helm repo update
helm pull qdrant/qdrant --version 1.18.2

# Login registry OCI Harbor
helm registry login harbor.frengky.xyz -u admin -p Harbor12345

# Push Chart ke OCI repo
helm push qdrant-1.18.2.tgz oci://harbor.frengky.xyz/helm-repos
```

### 2. Mirroring Container Image ke Harbor
```bash
# Pull image dari Docker Hub
docker pull qdrant/qdrant:v1.18.2

# Login ke docker registry
echo "Harbor12345" | docker login -u admin --password-stdin harbor.frengky.xyz

# Tag dan Push ke library Harbor
docker tag qdrant/qdrant:v1.18.2 harbor.frengky.xyz/library/qdrant:v1.18.2
docker push harbor.frengky.xyz/library/qdrant:v1.18.2
```

---

## 🔍 Pengujian Koneksi

Guna memastikan mcp-bridge dapat berkomunikasi dengan database Qdrant di dalam cluster, lakukan pengujian berikut via `kubectl exec`:

```bash
# Lakukan query HTTP ke REST API Qdrant dari dalam pod mcp-bridge
kubectl exec -n backend <MCP-BRIDGE-POD-NAME> -- wget -qO- http://qdrant:6333
```

**Respon Sukses yang Diharapkan:**
```json
{
  "title": "qdrant - vector search engine",
  "version": "1.18.2",
  "commit": "44ad62f8cd69642be5afa6441612525e24a0d063"
}
```
