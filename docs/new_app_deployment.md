# Panduan Deployment Aplikasi Baru (End-to-End GitOps via Gitea)
 
Dokumentasi ini menjelaskan langkah demi langkah untuk melakukan deploy aplikasi baru dari nol (contoh: **`sample-api`** di namespace **`backend`**) menggunakan pipeline GitOps terpusat dengan **Gitea** dan **Gitea Actions**.
 
---
 
## Tahap 1: Setup Harbor Registry & Base Images
 
Agar runner CI/CD dapat mendorong (*push*) image Docker hasil build, folder proyek di Harbor harus dibuat terlebih dahulu.
 
### 1. Membuat Project Baru di Harbor
Jalankan perintah ini di terminal host Anda untuk membuat project `backend` secara otomatis via API Harbor:
```bash
curl -s -X POST -u admin:Harbor12345 \
  -H "Content-Type: application/json" \
  -d '{"project_name": "backend", "public": true}' \
  -k https://harbor.frengky.xyz/api/v2.0/projects
```
 
### 2. Pre-seed Base Images (Untuk Offline/WSL Environment)
Untuk mencegah error *network timeout* di runner pod (karena pembatasan egress), pull base image yang dibutuhkan di komputer host Anda dan dorong ke Harbor:
```bash
# Pull and Push Golang Builder Image
docker pull golang:1.22-alpine
docker tag golang:1.22-alpine harbor.frengky.xyz/library/golang:1.22-alpine
docker push harbor.frengky.xyz/library/golang:1.22-alpine
 
# Pull and Push Alpine Runner Image
docker pull alpine:3.18
docker tag alpine:3.18 harbor.frengky.xyz/library/alpine:3.18
docker push harbor.frengky.xyz/library/alpine:3.18
```
 
---
 
## Tahap 2: Setup Kredensial di HashiCorp Vault
 
Daftarkan variabel rahasia aplikasi Anda ke Vault. Berkat fitur **Zero-Config Secrets** di Helm chart `generic-app:0.1.5`, rahasia akan dibaca secara dinamis berdasarkan format path `<environment>/<namespace>/<app-name>`.
 
Jalankan perintah berikut di CLI untuk menulis secret ke Vault (atau lakukan via Vault Web UI):
```bash
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=root \
  vault kv put secret/production/backend/sample-api APP_ENV=production
```
 
---
 
## Tahap 3: Pembuatan & Konfigurasi Project di Gitea
 
### 1. Membuat Repositori Baru via API Gitea
Jalankan perintah ini untuk membuat repositori baru bernama `sample-api` di dalam organisasi `devops` menggunakan API token Gitea Anda:
```bash
curl -s -X POST -H "Authorization: token 8b431296decb92dd20b5bc74c10117622dd03018" \
  -H "Content-Type: application/json" \
  -d '{"name": "sample-api", "private": false}' \
  https://gitea.frengky.xyz/api/v1/orgs/devops/repos
```
 
### 2. Mendaftarkan Actions Secrets di Gitea
Agar Gitea Actions Runner dapat berjalan dan menyinkronkan manifest kembali ke GitOps, daftarkan rahasia berikut di menu **Repository Settings** -> **Actions** -> **Secrets**:
 
- **`GITOPS_TOKEN`**: Personal Access Token Gitea untuk user `gitea_admin` yang memiliki hak akses tulis (*write*) ke repositori `devops/gitops`.
- **`VAULT_TOKEN`**: Token akses untuk mengautentikasi runner ke HashiCorp Vault.
- **`ARGOCD_TOKEN`**: Token akses API ArgoCD untuk memicu sinkronisasi manual jika dibutuhkan.
 
---
 
## Tahap 4: Menulis Kode Aplikasi & Pemicuan Pipeline
 
Buat folder proyek lokal, buat file-file berikut, lalu lakukan commit dan push ke Gitea.
 
### 1. File `main.go`
```go
package main
 
import (
	"fmt"
	"net/http"
	"os"
)
 
func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
 
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		appEnv := os.Getenv("APP_ENV")
		if appEnv == "" {
			appEnv = "unknown"
		}
		fmt.Fprintf(w, "Hello from Golang API! Environment (APP_ENV): %s\n", appEnv)
	})
 
	fmt.Printf("Starting server on port %s...\n", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		fmt.Printf("Error starting server: %v\n", err)
	}
}
```
 
### 2. File `Dockerfile`
```dockerfile
FROM harbor.frengky.xyz/library/golang:1.22-alpine AS builder
WORKDIR /app
COPY . .
RUN go build -o server main.go
 
FROM harbor.frengky.xyz/library/alpine:3.18
WORKDIR /app
COPY --from=builder /app/server .
EXPOSE 8080
CMD ["./server"]
```
 
### 3. File Gitea Actions Workflow (`.github/workflows/ci.yml`)
```yaml
name: CI/CD Pipeline
 
on:
  push:
    branches:
      - main
 
jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
 
      - name: Setup Git
        run: |
          git config --global user.name "GitOps Bot"
          git config --global user.email "gitops-bot@frengky.xyz"
 
      - name: Clone deployment-tools
        run: |
          git clone http://gitea_admin:${{ secrets.GITOPS_TOKEN }}@gitea-http.gitea.svc.cluster.local:3000/devops/deployment-tools.git
 
      - name: Run Build and Deploy Script
        env:
          VAULT_TOKEN: ${{ secrets.VAULT_TOKEN }}
          ARGOCD_TOKEN: ${{ secrets.ARGOCD_TOKEN }}
        run: |
          chmod +x ./deployment-tools/scripts/build-and-deploy.sh
          ./deployment-tools/scripts/build-and-deploy.sh "sample-api" "harbor.frengky.xyz/backend/sample-api" "apps/production/backend/sample-api/values.yaml"
```
 
### 4. Push Kode ke Gitea
```bash
git init
git checkout -b main
git remote add origin https://gitea.frengky.xyz/devops/sample-api.git
git add .
git commit -m "feat: initialize Go sample-api with Dockerfile and Gitea Actions workflow"
git push -u origin main
```
 
---
 
## Tahap 5: Konfigurasi GitOps (`devops/gitops` Repo)
 
Tambahkan manifest dan values di repositori `devops/gitops` Anda.
 
### 1. File `apps/production/backend/sample-api/Chart.yaml`
```yaml
apiVersion: v2
name: sample-api
type: application
version: 1.0.0
dependencies:
  - name: generic-app
    version: 0.1.5
    repository: oci://harbor.frengky.xyz/helm-repos
```
 
### 2. File `apps/production/backend/sample-api/values.yaml`
```yaml
generic-app:
  baseNamespace: backend
  baseName: sample-api
  environment: production
  image:
    repository: harbor.frengky.xyz/backend/sample-api
    tag: "latest" # Otomatis diupdate oleh pipeline Gitea Actions
    pullPolicy: Always
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
      - host: api.frengky.xyz
        path: /
        port: 8080
```
 
### 3. File `k8s/clusters/production/applications/production/sample-api.yaml`
Daftarkan ke ArgoCD via pola *App of Apps*:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-api
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  project: default
  source:
    repoURL: http://gitea-http.gitea.svc.cluster.local:3000/devops/gitops.git
    path: apps/production/backend/sample-api
    targetRevision: main
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
 
Push seluruh perubahan di atas ke repositori `devops/gitops` branch `main`. ArgoCD akan otomatis mendeteksi, membuat namespace `backend` jika belum ada, lalu mendeploy aplikasi dengan rahasia dari Vault terintegrasi!
 
---
 
## Tahap 6: Contoh Studi Kasus — Onboarding n8n (Akses Publik vs Privat/Tailscale)
 
Bagian ini menjelaskan secara konkret cara men-deploy aplikasi **n8n** (sebuah platform otomatisasi workflow) pada kluster homelab. Kita akan membahas proses dari pre-seed image, setup di repositori `devops/gitops`, hingga konfigurasi jaringannya untuk kedua skenario akses (Publik vs Privat).
 
### 1. Pre-seed Image n8n ke Harbor
Karena runner pod dibatasi akses internet keluar (outbound egress timeout), kita perlu melakukan pull image resmi n8n dari Docker Hub pada komputer host, memberi tag lokal, dan mendorongnya ke Harbor Registry internal.
 
Jalankan perintah ini di komputer host Anda:
```bash
# Pull image resmi n8n dari Docker Hub
docker pull n8nio/n8n:latest
 
# Berikan tag yang mengarah ke Harbor lokal Anda
docker tag n8nio/n8n:latest harbor.frengky.xyz/library/n8n:latest
 
# Push image ke Harbor
docker push harbor.frengky.xyz/library/n8n:latest
```
 
### 2. Setup Kredensial di HashiCorp Vault
Aplikasi n8n membutuhkan database dan encryption key untuk menyimpan workflow dengan aman. Tulis rahasia ini ke Vault pada path production untuk namespace `tools`:
 
```bash
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=root \
  vault kv put secret/production/tools/n8n \
  N8N_ENCRYPTION_KEY="kunci-enkripsi-sangat-rahasia-123" \
  N8N_USER_MANAGEMENT_DISABLED="false"
```
 
### 3. Konfigurasi Repositori GitOps (`devops/gitops`)
 
Buat berkas konfigurasi Helm values dan aplikasi ArgoCD untuk n8n di repositori `devops/gitops` Anda.
 
#### A. File `apps/production/tools/n8n/Chart.yaml`
```yaml
apiVersion: v2
name: n8n
type: application
version: 1.0.0
dependencies:
  - name: generic-app
    version: 0.1.5
    repository: oci://harbor.frengky.xyz/helm-repos
```
 
#### B. File `apps/production/tools/n8n/values.yaml`
```yaml
generic-app:
  baseNamespace: tools
  baseName: n8n
  environment: production
  image:
    repository: harbor.frengky.xyz/library/n8n
    tag: "latest"
    pullPolicy: Always
  service:
    enabled: true
    type: ClusterIP
    ports:
      - name: http
        port: 5678
  ingress:
    enabled: true
    stripPath: false
    hosts:
      - host: n8n.frengky.xyz
        path: /
        port: 5678
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
```
 
#### C. File `k8s/clusters/production/applications/production/n8n.yaml` (ArgoCD Application)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: n8n
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  project: default
  source:
    repoURL: http://gitea-http.gitea.svc.cluster.local:3000/devops/gitops.git
    path: apps/production/tools/n8n
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: tools
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```
 
---
 
### 4. Konfigurasi Jaringan & Jalur Akses (Pilih Salah Satu)
 
Di bawah ini adalah konfigurasi untuk membatasi akses (hanya via Tailscale) atau membuka akses ke internet umum (via Cloudflare Tunnel).
 
#### OPSI A — Akses Privat (Khusus via Tailscale — REKOMENDASI)
Skenario ini membuat n8n hanya bisa diakses saat perangkat Anda (Laptop/HP) terhubung ke VPN Tailscale, menggunakan domain kustom `n8n.frengky.xyz`.
 
1. **Konfigurasi Ingress**: Tetap aktifkan Ingress Traefik di `values.yaml` (seperti di atas).
2. **Setup DNS di Cloudflare**:
   - Masuk ke Dashboard Cloudflare Anda.
   - Tambahkan DNS Record baru:
     - **Type**: `A`
     - **Name**: `n8n` (sehingga membentuk `n8n.frengky.xyz`)
     - **IPv4 Address**: `100.120.133.63` (IP Tailscale Host Anda)
     - **Proxy Status**: **DNS-Only (Gray Cloud)** ⚠️ *Jangan centang orange proxy!*
3. **Terminasi TLS**: Traefik secara otomatis menyajikan sertifikat wildcard valid `*.frengky.xyz` yang telah di-fetch oleh `cert-manager`. HTTPS berjalan aman tanpa SSL warning.
 
#### OPSI B — Akses Publik (Internet-facing via Cloudflare Tunnel)
Skenario ini membuat n8n dapat diakses oleh publik di internet umum melalui rute Cloudflare Tunnel yang aman.
 
1. **Konfigurasi Ingress**: Tetap aktifkan Ingress Traefik di `values.yaml`.
2. **Setup Cloudflare Tunnel**:
   - Masuk ke dashboard **Cloudflare Zero Trust** -> **Access** -> **Tunnels**.
   - Pilih tunnel aktif untuk homelab Anda, lalu pilih **Edit**.
   - Tambahkan **Public Hostname**:
     - **Subdomain**: `n8n`
     - **Domain**: `frengky.xyz`
     - **Service Type**: `HTTP`
     - **URL**: `http://traefik.kube-system.svc.cluster.local:80` (Meneruskan ke Traefik Ingress) atau arahkan langsung ke Service n8n di `http://n8n.tools.svc.cluster.local:5678`.
3. **Setup DNS di Cloudflare**:
   - Cloudflare akan otomatis mengelola DNS record `n8n.frengky.xyz` sebagai **Proxied (Orange Cloud)** mengarah ke CNAME tunnel.
   - Trafik akan difilter melalui WAF Cloudflare sebelum masuk ke kluster Anda.
