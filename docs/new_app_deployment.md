# New Application Deployment Guide (End-to-End GitOps via Gitea)

This document describes the step-by-step process for deploying a new application from scratch (example: **`sample-api`** in the **`backend`** namespace) using the centralized GitOps pipeline with **Gitea** and **Gitea Actions**.

---

## Stage 1: Harbor Registry & Base Images Setup

So that the CI/CD runner can push the built Docker image, the project folder in Harbor must be created first.

### 1. Creating a New Project in Harbor
Run the following command in your host terminal to automatically create the `backend` project via the Harbor API:
```bash
curl -s -X POST -u admin:Harbor12345 \
  -H "Content-Type: application/json" \
  -d '{"project_name": "backend", "public": true}' \
  -k https://harbor.frengky.xyz/api/v2.0/projects
```

### 2. Pre-seeding Base Images (For Offline/WSL Environment)
To prevent *network timeout* errors in the runner pod (due to egress restrictions), pull the required base images on your host computer and push them to Harbor:
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

## Stage 2: Credential Setup in HashiCorp Vault

Register your application's secret variables in Vault. Thanks to the **Zero-Config Secrets** feature in the Helm chart `generic-app:0.1.5`, secrets are read dynamically based on the path format `<environment>/<namespace>/<app-name>`.

Run the following command in the CLI to write the secret to Vault (or do it via the Vault Web UI):
```bash
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=root \
  vault kv put secret/production/backend/sample-api APP_ENV=production
```

---

## Stage 3: Project Creation & Configuration in Gitea

### 1. Creating a New Repository via the Gitea API
Run the following command to create a new repository named `sample-api` inside the `devops` organization using your Gitea API token:
```bash
curl -s -X POST -H "Authorization: token 8b431296decb92dd20b5bc74c10117622dd03018" \
  -H "Content-Type: application/json" \
  -d '{"name": "sample-api", "private": false}' \
  https://gitea.frengky.xyz/api/v1/orgs/devops/repos
```

### 2. Registering Actions Secrets in Gitea
So that the Gitea Actions Runner can run and sync manifests back to GitOps, register the following secrets in **Repository Settings** -> **Actions** -> **Secrets**:

- **`GITOPS_TOKEN`**: Gitea Personal Access Token for the user `gitea_admin` with write access to the `devops/gitops` repository.
- **`VAULT_TOKEN`**: Access token to authenticate the runner to HashiCorp Vault.
- **`ARGOCD_TOKEN`**: Flux CD API access token to trigger manual syncs if needed.

---

## Stage 4: Writing Application Code & Triggering the Pipeline

Create a local project folder, create the following files, then commit and push to Gitea.

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

### 3. Gitea Actions Workflow File (`.github/workflows/ci.yml`)
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
          ./deployment-tools/scripts/build-and-deploy.sh "sample-api" "harbor.frengky.xyz/backend/sample-api" "k8s/clusters/production/applications/apps/production/backend/sample-api/values.yaml"
```

### 4. Push Code to Gitea
```bash
git init
git checkout -b main
git remote add origin https://gitea.frengky.xyz/devops/sample-api.git
git add .
git commit -m "feat: initialize Go sample-api with Dockerfile and Gitea Actions workflow"
git push -u origin main
```

---

## Stage 5: GitOps Configuration (`devops/gitops` Repo)

Add manifests and values in your `devops/gitops` repository.

### 1. File `k8s/clusters/production/applications/apps/production/backend/sample-api/Chart.yaml`
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

### 2. File `k8s/clusters/production/applications/apps/production/backend/sample-api/values.yaml`
```yaml
generic-app:
  baseNamespace: backend
  baseName: sample-api
  environment: production
  image:
    repository: harbor.frengky.xyz/backend/sample-api
    tag: "latest" # Automatically updated by the Gitea Actions pipeline
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
Register it in Flux CD via the *App of Apps* pattern:
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
    path: k8s/clusters/production/applications/apps/production/backend/sample-api
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

Push all the changes above to the `devops/gitops` repository's `main` branch. Flux CD will automatically detect them, create the `backend` namespace if it doesn't exist yet, and deploy the application with secrets integrated from Vault!

---

## Stage 6: Case Study — Onboarding n8n (Public vs Private/Tailscale Access)

This section explains concretely how to deploy the **n8n** application (a workflow automation platform) on the homelab cluster. We will cover the process from pre-seeding the image, setting up the `devops/gitops` repository, through to network configuration for both access scenarios (Public vs Private).

### 1. Pre-seed the n8n Image to Harbor
Because the runner pod has restricted outbound internet access (egress timeout), we need to pull the official n8n image from Docker Hub on the host computer, tag it locally, and push it to the internal Harbor Registry.

Run the following commands on your host computer:
```bash
# Pull the official n8n image from Docker Hub
docker pull n8nio/n8n:latest

# Tag it to point at your local Harbor
docker tag n8nio/n8n:latest harbor.frengky.xyz/library/n8n:latest

# Push the image to Harbor
docker push harbor.frengky.xyz/library/n8n:latest
```

### 2. Credential Setup in HashiCorp Vault
The n8n application needs a database and an encryption key to store workflows securely. Write these secrets to Vault at the production path for the `tools` namespace:

```bash
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=root \
  vault kv put secret/production/tools/n8n \
  N8N_ENCRYPTION_KEY="kunci-enkripsi-sangat-rahasia-123" \
  N8N_USER_MANAGEMENT_DISABLED="false"
```

### 3. GitOps Repository Configuration (`devops/gitops`)

Create the Helm values and Flux CD application configuration files for n8n in your `devops/gitops` repository.

#### A. File `k8s/clusters/production/applications/apps/production/tools/n8n/Chart.yaml`
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

#### B. File `k8s/clusters/production/applications/apps/production/tools/n8n/values.yaml`
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

#### C. File `k8s/clusters/production/applications/production/n8n.yaml` (Flux CD Application)
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
    path: k8s/clusters/production/applications/apps/production/tools/n8n
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

### 4. Network Configuration & Access Path (Choose One)

Below are the configurations for restricting access (Tailscale-only) or opening access to the general public (via Cloudflare Tunnel).

#### OPTION A — Private Access (Tailscale-only — RECOMMENDED)
This scenario makes n8n accessible only when your device (Laptop/Phone) is connected to the Tailscale VPN, using the custom domain `n8n.frengky.xyz`.

1. **Ingress Configuration**: Keep the Traefik Ingress enabled in `values.yaml` (as above).
2. **DNS Setup in Cloudflare**:
   - Log in to your Cloudflare Dashboard.
   - Add a new DNS Record:
     - **Type**: `A`
     - **Name**: `n8n` (forming `n8n.frengky.xyz`)
     - **IPv4 Address**: `100.120.133.63` (Your Host Tailscale IP)
     - **Proxy Status**: **DNS-Only (Gray Cloud)** ⚠️ *Do not enable the orange proxy!*
3. **TLS Termination**: Traefik automatically serves the valid wildcard certificate `*.frengky.xyz` already fetched by `cert-manager`. HTTPS runs securely without SSL warnings.

#### OPTION B — Public Access (Internet-facing via Cloudflare Tunnel)
This scenario makes n8n accessible to the general public on the internet via a secure Cloudflare Tunnel route.

1. **Ingress Configuration**: Keep the Traefik Ingress enabled in `values.yaml`.
2. **Cloudflare Tunnel Setup**:
   - Log in to the **Cloudflare Zero Trust** dashboard -> **Access** -> **Tunnels**.
   - Select your active homelab tunnel, then choose **Edit**.
   - Add a **Public Hostname**:
     - **Subdomain**: `n8n`
     - **Domain**: `frengky.xyz`
     - **Service Type**: `HTTP`
     - **URL**: `http://traefik.kube-system.svc.cluster.local:80` (Forwarding to Traefik Ingress) or point directly to the n8n Service at `http://n8n.tools.svc.cluster.local:5678`.
3. **DNS Setup in Cloudflare**:
   - Cloudflare will automatically manage the `n8n.frengky.xyz` DNS record as **Proxied (Orange Cloud)** pointing to the tunnel CNAME.
   - Traffic will be filtered through the Cloudflare WAF before entering your cluster.