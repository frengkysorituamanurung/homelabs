# Panduan Menambahkan Aplikasi Baru (Private Repo → GitHub Actions → Harbor → Flux CD)

Dokumen ini adalah panduan standar untuk menambahkan aplikasi baru ke homelab dengan pola:

- Source code di **repo GitHub private** (org/user).
- CI/CD di **GitHub Actions** (GitHub-hosted runner + Tailscale ephemeral).
- Image di **Harbor private**.
- Deploy via **Flux CD** di k3s homelab.

Contoh referensi: `sorivalabs/test-gitops`.

---

## 0. Prasyarat

- Akses push ke repo org/user GitHub.
- Akses admin ke Harbor (`harbor.frengky.xyz`).
- Akses kubectl + Flux ke cluster.
- Akses Vault (token ESO) untuk secret.
- Tailscale auth key (ephemeral, tag `tag:ci`).

---

## 1. Buat Repo Aplikasi (Private)

1. Buat repo baru (private) di GitHub, mis. `sorivalabs/my-app`.
2. Clone lokal:
   ```bash
   git clone git@github.com:sorivalabs/my-app.git
   cd my-app
   ```

---

## 2. Tulis Aplikasi + Dockerfile

Contoh struktur minimal:

```text
my-app/
├── .github/workflows/ci.yml
├── Dockerfile
├── go.mod / package.json / dll
├── main.go / src
└── README.md
```

Dockerfile (contoh Go):
```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod ./
COPY . .
RUN go build -o server .

FROM alpine:3.18
WORKDIR /app
COPY --from=builder /app/server .
EXPOSE 8080
CMD ["./server"]
```

Pastikan app listen di port yang akan dipakai (mis. `8080`).

---

## 3. Buat Robot Account di Harbor

Project: `backend` (atau project lain).

### CI pusher (push + pull)
```bash
curl -sk -u admin:Harbor12345 -H 'Content-Type: application/json' \
  -X POST https://harbor.frengky.xyz/api/v2.0/robots \
  -d '{
    "name": "ci-pusher-my-app",
    "duration": -1,
    "level": "project",
    "permissions": [{
      "kind": "project",
      "namespace": "backend",
      "access": [
        {"resource": "repository", "action": "push"},
        {"resource": "repository", "action": "pull"}
      ]
    }]
  }'
```

Simpan `name` (robot$backend+ci-pusher-my-app) dan `secret`.

### Cluster puller (pull only)
```bash
curl -sk -u admin:Harbor12345 -H 'Content-Type: application/json' \
  -X POST https://harbor.frengky.xyz/api/v2.0/robots \
  -d '{
    "name": "k8s-puller-my-app",
    "duration": -1,
    "level": "project",
    "permissions": [{
      "kind": "project",
      "namespace": "backend",
      "access": [
        {"resource": "repository", "action": "pull"}
      ]
    }]
  }'
```

---

## 4. Simpan Secret di Vault

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
VTOKEN=<vault-token>

# Harbor puller
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$VTOKEN \
  vault kv put secret/harbor-pull \
  username='robot$backend+k8s-puller-my-app' \
  password='<puller-secret>'

# (Opsional) CI secrets central store
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$VTOKEN \
  vault kv put secret/my-app/tailscale authKey='tskey-auth-...'
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$VTOKEN \
  vault kv put secret/my-app/harbor username='robot$backend+ci-pusher-my-app' password='<pusher-secret>'
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$VTOKEN \
  vault kv put secret/my-app/gitops token='<PAT>'
```

---

## 5. Set GitHub Secrets (repo app)

```bash
gh secret set HARBOR_PASSWORD --repo sorivalabs/my-app --body '<pusher-secret>'
gh secret set GITOPS_TOKEN --repo sorivalabs/my-app --body '<PAT-with-contents:write>'
gh secret set TAILSCALE_AUTHKEY --repo sorivalabs/my-app --body 'tskey-auth-...'
```

Catatan: username Harbor bisa di-hardcode di workflow (`robot$backend+ci-pusher-my-app`) untuk menghindari masalah ekspansi `$`.

---

## 6. Tambahkan Manifest di GitOps Repo (`homelabs`)

### 6.1 Chart vendored (generic-app)

Buat folder:
```text
k8s/clusters/production/applications/apps/production/backend/my-app/
├── Chart.yaml
└── values.yaml
```

`Chart.yaml`:
```yaml
apiVersion: v2
name: my-app
type: application
version: 1.0.0
dependencies:
  - name: generic-app
    version: 0.1.15
    repository: file://../../../../../../../../helm/charts/generic-app
```

### 6.2 Flux manifests

Buat folder:
```text
infrastructure/my-app/flux/
├── kustomization.yaml
├── helmrelease.yaml
└── externalsecret.yaml
```

`kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - externalsecret.yaml
  - helmrelease.yaml
```

`externalsecret.yaml` (harbor pull secret):
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: harbor-pull-secret
  namespace: backend
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: harbor-pull-secret
    creationPolicy: Owner
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {"auths":{"harbor.frengky.xyz":{"username":"{{ .username }}","password":"{{ .password }}","auth":"{{ printf "%s:%s" .username .password | b64enc }}"}}}
  data:
    - secretKey: username
      remoteRef:
        key: secret/data/harbor-pull
        property: username
    - secretKey: password
      remoteRef:
        key: secret/data/harbor-pull
        property: password
```

`helmrelease.yaml` (sesuaikan port/domain):
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: my-app
  namespace: flux-system
spec:
  interval: 5m
  chart:
    spec:
      chart: ./k8s/clusters/production/applications/apps/production/backend/my-app
      version: "1.0.0"
      sourceRef:
        kind: GitRepository
        name: homelabs
        namespace: flux-system
  releaseName: my-app
  targetNamespace: backend
  install:
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
  values:
    generic-app:
      baseNamespace: backend
      baseName: my-app
      environment: production
      disableSecrets: true
      image:
        repository: harbor.frengky.xyz/backend/my-app
        tag: "latest"
        pullPolicy: Always
      imagePullSecrets:
        - name: harbor-pull-secret
      service:
        enabled: true
        type: ClusterIP
        ports:
          - name: http
            port: 8080
      ingress:
        enabled: true
        hosts:
          - host: my-app.frengky.xyz
            path: /
            port: 8080
```

### 6.3 Register ke Flux

Buat `clusters/production/flux-system/pilot-my-app.yaml`:
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: my-app
  namespace: flux-system
spec:
  dependsOn:
    - name: flux-system
  interval: 5m
  path: ./infrastructure/my-app/flux
  prune: false
  wait: true
  sourceRef:
    kind: GitRepository
    name: homelabs
  timeout: 5m
```

Tambahkan ke `clusters/production/flux-system/kustomization.yaml`:
```yaml
  - pilot-my-app.yaml
```

---

## 7. Workflow CI (GitHub Actions)

File `.github/workflows/ci.yml` di repo app:

```yaml
name: CI/CD

on:
  push:
    branches: [main]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Connect to Tailscale
        uses: tailscale/github-action@v2
        with:
          authkey: ${{ secrets.TAILSCALE_AUTHKEY }}
          tags: tag:ci

      - name: Compute tag
        id: meta
        run: echo "tag=${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"

      - name: Login Harbor
        env:
          HARBOR_PASSWORD: ${{ secrets.HARBOR_PASSWORD }}
        run: |
          echo "$HARBOR_PASSWORD" | docker login harbor.frengky.xyz \
            -u 'robot$backend+ci-pusher-my-app' --password-stdin

      - name: Build & push
        run: |
          docker build -t harbor.frengky.xyz/backend/my-app:${{ steps.meta.outputs.tag }} .
          docker push harbor.frengky.xyz/backend/my-app:${{ steps.meta.outputs.tag }}

      - name: Update GitOps repo
        env:
          GITOPS_TOKEN: ${{ secrets.GITOPS_TOKEN }}
        run: |
          git clone "https://x-access-token:${GITOPS_TOKEN}@github.com/frengkysorituamanurung/homelabs.git" /tmp/homelabs
          cd /tmp/homelabs
          sed -i -E "s/tag: .*/tag: \"${{ steps.meta.outputs.tag }}\"/" infrastructure/my-app/flux/helmrelease.yaml
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add infrastructure/my-app/flux/helmrelease.yaml
          git diff --cached --quiet || git commit -m "chore(my-app): image ${{ steps.meta.outputs.tag }}"
          git push origin main
```

---

## 8. DNS / Akses

### Private (Tailscale)
- Cloudflare DNS: A record `my-app.frengky.xyz` → `100.120.133.63` (gray cloud).

### Public (Cloudflare Tunnel)
- Tambahkan Public Hostname di tunnel: `my-app.frengky.xyz` → `http://traefik.kube-system.svc.cluster.local:80`.

---

## 9. Validasi

```bash
# Cluster
kubectl get pods -n backend | grep my-app
kubectl get helmrelease my-app -n flux-system
kubectl get ingress -n backend | grep my-app

# Akses
curl -k https://my-app.frengky.xyz/health
```

---

## 10. Troubleshooting

| Masalah | Penyebab | Solusi |
|---|---|---|
| Tailscale step gagal | Auth key salah/expired | Buat auth key baru, update secret |
| Harbor login unauthorized | Username robot salah | Hardcode `robot$backend+ci-pusher-my-app` |
| ImagePullBackOff | Pull secret salah | Cek Vault/ESO/robot puller |
| CreateContainerConfigError: secret not found | `disableSecrets` tidak terapply | Set `disableSecrets: true` jika app tidak butuh secret |
| Flux tidak update | Commit gagal | Cek PAT & GitOps repo |
| App tidak bisa diakses | DNS/ingress salah | Cek ingress host & DNS |

---

## 11. Checklist

- [ ] Repo app private dibuat
- [ ] Dockerfile & kode app selesai
- [ ] Robot pusher & puller dibuat di Harbor
- [ ] Secret disimpan di Vault
- [ ] GitHub Secrets diset
- [ ] Tailscale auth key dibuat & diset
- [ ] Manifest Flux ditambahkan di `homelabs`
- [ ] Pilot Kustomization didaftarkan
- [ ] Workflow CI dibuat
- [ ] Push code → CI sukses
- [ ] Flux deploy sukses
- [ ] DNS/ingress dikonfigurasi
- [ ] App bisa diakses

---

## 12. Referensi

- `docs/test-gitops-implementation.md`
- `docs/private-app-github-actions-harbor.md`
- `docs/new-application-setup.md`
- `infrastructure/test-gitops/` (contoh implementasi)