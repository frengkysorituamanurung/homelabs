# Panduan Deployment Aplikasi Baru (End-to-End GitOps)

Dokumentasi ini menjelaskan langkah demi langkah untuk melakukan deploy aplikasi baru dari nol (contoh: **`sample-api`** di namespace **`backend`**) menggunakan pipeline GitOps terpusat.

---

## Tahap 1: Setup Harbor Registry & Base Images

Agar GitLab Runner dapat mendorong (*push*) image Docker hasil build, folder proyek di Harbor harus dibuat terlebih dahulu.

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

## Tahap 3: Pembuatan & Konfigurasi Project di GitLab

### 1. Membuat Project Baru via API GitLab
Jalankan perintah ini untuk membuat repositori baru bernama `sample-api` di dalam group `devops` (Group ID: `39`):
```bash
curl -s -X POST -H "PRIVATE-TOKEN: glpat-3qaTCBgL_BYX3yXPW9u0JW86MQp1OjEH.01.0w00mlepv" \
  -H "Content-Type: application/json" \
  -d '{"name": "sample-api", "namespace_id": 39, "visibility": "public"}' \
  http://gitlab-http.gitlab.svc.cluster.local/api/v4/projects
```

### 2. Mendaftarkan CI/CD Variables
Hubungkan project GitLab baru dengan Vault AppRole menggunakan perintah API berikut (ganti `<project-id>` dengan ID project yang dihasilkan, misal: `5`):
```bash
# Daftarkan VAULT_ROLE_ID
curl -s -X POST -H "PRIVATE-TOKEN: glpat-3qaTCBgL_BYX3yXPW9u0JW86MQp1OjEH.01.0w00mlepv" \
  -H "Content-Type: application/json" \
  -d '{"key": "VAULT_ROLE_ID", "value": "41f841a0-7d37-64d7-5489-f2f88387eb9d", "variable_type": "env_var"}' \
  "http://gitlab-http.gitlab.svc.cluster.local/api/v4/projects/<project-id>/variables"

# Daftarkan VAULT_SECRET_ID
curl -s -X POST -H "PRIVATE-TOKEN: glpat-3qaTCBgL_BYX3yXPW9u0JW86MQp1OjEH.01.0w00mlepv" \
  -H "Content-Type: application/json" \
  -d '{"key": "VAULT_SECRET_ID", "value": "ae5e3516-c8ff-1d2b-7129-0c68066a7cc5", "variable_type": "env_var"}' \
  "http://gitlab-http.gitlab.svc.cluster.local/api/v4/projects/<project-id>/variables"
```

---

## Tahap 4: Menulis Kode Aplikasi & Pemicuan Pipeline

Buat folder proyek lokal, buat file-file berikut, lalu lakukan commit dan push.

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

### 3. File `.gitlab-ci.yml`
```yaml
include:
  - project: 'devops/deployment-tools'
    file: '/templates/.gitlab-ci-template.yml'

variables:
  APP_NAME: "sample-api"
  IMAGE_REPO: "harbor.frengky.xyz/backend/sample-api"
  VALUES_PATH: "kubernetes/production/backend/sample-api/values.yaml"
```

### 4. Push Kode ke GitLab
```bash
git init
git checkout -b main
git remote add origin https://gitlab.frengky.xyz/devops/sample-api.git
git add .
git commit -m "feat: initialize Go sample-api"
git push -u origin main
```

---

## Tahap 5: Konfigurasi GitOps (`devops/gitops` Repo)

Tambahkan manifest dan values di repositori `devops/gitops` Anda.

### 1. File `kubernetes/production/backend/sample-api/Chart.yaml`
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

### 2. File `kubernetes/production/backend/sample-api/values.yaml`
```yaml
generic-app:
  baseNamespace: backend
  baseName: sample-api
  environment: production
  image:
    repository: harbor.frengky.xyz/backend/sample-api
    tag: "latest" # Otomatis diupdate oleh pipeline GitLab CI
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

### 3. File `kubernetes/applications/production/sample-api.yaml`
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
    repoURL: http://gitlab-http.gitlab.svc.cluster.local/devops/gitops.git
    path: kubernetes/production/backend/sample-api
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
