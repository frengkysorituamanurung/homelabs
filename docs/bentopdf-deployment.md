# Dokumentasi Deployment BentoPDF

BentoPDF adalah toolkit PDF open-source berbasis browser (client-side processing) yang di-deploy di k3s cluster `frengky.xyz` via GitOps (ArgoCD). Akses hanya tersedia ketika terhubung ke **Tailscale VPN**.

---

## Arsitektur Akses

```
User (Tailscale connected)
  └── bentopdf.frengky.xyz
        └── Cloudflare DNS A record → 100.120.133.63 (Tailscale IP host)
              └── Traefik Ingress Controller (port 80/443)
                    └── Service: bentopdf:8080 (namespace: frontend)
                          └── Pod: ghcr.io/alam00000/bentopdf-simple
```

Akses VPN-only dikendalikan **di level DNS** — domain `bentopdf.frengky.xyz` hanya resolve ke IP Tailscale `100.120.133.63` yang tidak bisa dijangkau dari internet publik tanpa terhubung ke Tailscale.

---

## Struktur File GitOps

```
gitops-repo/
├── kubernetes/
│   ├── applications/
│   │   └── production/
│   │       └── bentopdf.yaml          # ArgoCD Application
│   └── production/
│       └── frontend/
│           └── bentopdf/
│               ├── Chart.yaml         # Helm chart (pakai generic-app)
│               └── values.yaml        # Konfigurasi app
└── docs/
    └── bentopdf-deployment.md         # Dokumen ini
```

---

## File Manifest

### 1. ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bentopdf
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  project: default
  source:
    repoURL: http://gitea-http.gitea.svc.cluster.local:3000/devops/gitops.git
    path: kubernetes/production/frontend/bentopdf
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: frontend
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 2. Helm Chart (`Chart.yaml`)

```yaml
apiVersion: v2
name: bentopdf
type: application
version: 1.0.0
dependencies:
  - name: generic-app
    version: 0.1.12
    repository: oci://harbor.frengky.xyz/helm-repos
```

Chart `generic-app` adalah internal Helm chart yang dipakai semua apps di cluster ini.
Versi `0.1.12` menambahkan explicit `ingressClassName: traefik`.

### 3. Values (`values.yaml`)

```yaml
generic-app:
  baseNamespace: frontend
  baseName: bentopdf
  environment: production
  disableSecrets: true         # BentoPDF tidak butuh env secrets
  image:
    repository: ghcr.io/alam00000/bentopdf-simple
    tag: "latest"
    pullPolicy: Always
  resources:
    requests:
      memory: 64Mi
      cpu: 10m
    limits:
      memory: 128Mi
      cpu: 100m
  service:
    enabled: true
    type: ClusterIP
    ports:
      - name: http
        port: 8080
  ingress:
    enabled: true
    stripPath: false
    hosts:
      - host: bentopdf.frengky.xyz
        path: /
        port: 8080
  healthCheck:
    enabled: true
    endpoint: /
    port: 8080
  deploymentStrategy:
    type: Recreate
```

**Catatan penting:**
- `disableSecrets: true` — wajib karena `generic-app` secara default selalu mount Secret `<appname>-secrets`
- `ingress.enabled: true` — generate standard Kubernetes Ingress dengan `ingressClassName: traefik`
- BentoPDF adalah **stateless app** (semua processing PDF di browser), tidak butuh PVC

---

## Langkah Deploy

### Step 1: Konfigurasi Cloudflare DNS

Tambahkan A record di Cloudflare DNS dashboard:

| Type | Name | Content | Proxy Status | TTL |
|------|------|---------|--------------|-----|
| `A` | `bentopdf` | `100.120.133.63` | DNS Only (Gray Cloud) | Auto |

> **PENTING:** Status harus **DNS Only (Gray Cloud)** bukan Proxied (Orange).
> Jika Proxied, Cloudflare akan mencoba proxy ke IP Tailscale yang tidak reachable dari internet.

### Step 2: Verifikasi ArgoCD

```bash
# Cek status app
kubectl get application bentopdf -n argocd
# Expected: SYNC STATUS=Synced, HEALTH STATUS=Healthy

# Force sync jika perlu
kubectl annotate application bentopdf -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

### Step 3: Verifikasi Pod dan Ingress

```bash
# Cek pod
kubectl get pods -n frontend -l app.kubernetes.io/name=bentopdf
# Expected: 1/1 Running

# Cek ingress
kubectl get ingress bentopdf -n frontend
# Expected: host=bentopdf.frengky.xyz, CLASS=traefik

# Test koneksi internal
kubectl port-forward svc/bentopdf 8080:8080 -n frontend
# Buka: http://localhost:8080
```

### Step 4: Test Akses via Tailscale

```bash
# Pastikan Tailscale aktif, lalu:
curl -I http://bentopdf.frengky.xyz
# Expected: HTTP/1.1 200 OK

# Verifikasi DNS resolve ke Tailscale IP:
nslookup bentopdf.frengky.xyz
# Expected: Address: 100.120.133.63
```

---

## Image BentoPDF

| Variant | Image | Keterangan |
|---------|-------|------------|
| Simple (dipakai) | `ghcr.io/alam00000/bentopdf-simple:latest` | Tanpa marketing/footer, ideal untuk internal |
| Full | `ghcr.io/alam00000/bentopdf:latest` | Dengan landing page marketing |

BentoPDF memproses semua PDF **di browser** (client-side via WebAssembly).
Server hanya serve static files. Tidak ada data PDF yang dikirim ke server.

---

## Troubleshooting

| Gejala | Penyebab | Solusi |
|--------|----------|--------|
| `CreateContainerConfigError` | Secret `bentopdf-secrets` tidak ada | Pastikan `disableSecrets: true` di values.yaml |
| Domain tidak bisa diakses | DNS belum dikonfigurasi | Tambahkan A record di Cloudflare (DNS Only) |
| ArgoCD `OutOfSync` | Chart dep tidak ditemukan | Pastikan `generic-app:0.1.12` ada di Harbor |
| 404 saat akses | Ingress tidak ter-create | Cek `kubectl get ingress -n frontend` |

```bash
# Debug lengkap
kubectl describe pod -n frontend -l app.kubernetes.io/name=bentopdf
kubectl logs -n frontend -l app.kubernetes.io/name=bentopdf
kubectl describe ingress bentopdf -n frontend
```
