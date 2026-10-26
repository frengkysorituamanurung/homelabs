# Arsitektur Deployment Aplikasi Private (GitHub → GitHub Actions → Harbor → Flux CD)

Dokumen ini menjelaskan desain arsitektur untuk men-deploy aplikasi yang source codenya berada di **repo GitHub private**, dibuild oleh **GitHub Actions**, image-nya dipush ke **Harbor internal**, lalu dideploy ke **k3s homelab** melalui **Flux CD**.

Contoh app yang dimaksud: `https://github.com/frengkysorituamanurung/point-of-sales` (private).

---

## 1. Tujuan & Prinsip

### Tujuan
- Source code tetap **private** di GitHub.
- Build & test berjalan di **GitHub Actions**.
- Artifact image masuk ke **Harbor internal** (bukan Docker Hub / GHCR).
- Deployment ke cluster dilakukan **GitOps via Flux CD**.
- Cluster tetap tidak bergantung pada internet saat runtime (image sudah ada di Harbor).

### Prinsip
1. **Repo app private**, repo GitOps hanya berisi manifest + tag image.
2. **Harbor tetap private/VPN-only**; CI mengaksesnya dari dalam jaringan via self-hosted runner.
3. **Least privilege**: robot account terpisah untuk push (CI) dan pull (cluster).
4. **Immutable tag**: gunakan git SHA/semver, hindari `latest` di production.
5. **Secret tidak disimpan di Git**: Vault + ESO.

---

## 2. High-Level Architecture

```text
Developer
  │ git push (private app repo)
  ▼
GitHub Private App Repo
  │
  │ GitHub Actions (self-hosted runner di homelab)
  ├─ checkout source
  ├─ build Docker image
  ├─ push image → Harbor
  └─ update image tag → GitHub GitOps Repo (homelabs)
                            │
                            │ Flux CD watches branch main
                            ▼
                      k3s Cluster (homelabs)
                            │
                            ├─ Flux HelmRelease
                            ├─ pull image dari Harbor (imagePullSecret)
                            ├─ ExternalSecret (Vault → K8s Secret)
                            └─ Ingress (Traefik) + DNS
```

### Komponen

| Komponen | Peran |
|---|---|
| GitHub (Private App Repo) | Source code, Dockerfile, workflow CI |
| Self-hosted GitHub Runner | Build & push image ke Harbor internal |
| Harbor | Registry private, scan image, robot account |
| GitHub GitOps Repo (`homelabs`) | Source of truth manifest Flux |
| Flux CD | Reconcile manifest & deploy ke k3s |
| Vault + ESO | Secret runtime + credential Harbor pull |
| Traefik + Cloudflare/Tailscale | Akses aplikasi (public/private) |

---

## 3. Alur CI/CD End-to-End

1. Developer push commit ke branch `main` di **private app repo**.
2. GitHub Actions trigger workflow pada self-hosted runner.
3. Runner:
   - checkout source
   - build image
   - login Harbor dengan robot account **pusher**
   - push `harbor.frengky.xyz/<project>/<app>:<short-sha>`
4. Workflow clone GitOps repo (`homelabs`) dengan PAT.
5. Update tag image di manifest Flux (mis. `infrastructure/<app>/flux/helmrelease.yaml`).
6. Commit & push ke `main` GitOps repo.
7. Flux mendeteksi perubahan source → reconcile.
8. Flux HelmRelease rollout pod baru, pull image dari Harbor dengan `imagePullSecret`.
9. Pod jalan, ingress aktif, app dapat diakses.

---

## 4. Kenapa Self-Hosted Runner (Bukan GitHub-Hosted)?

Harbor Anda saat ini bersifat **VPN-only**:
- DNS `harbor.frengky.xyz` → `100.120.133.63` (Tailscale IP)
- Cloudflare: **DNS-only (gray cloud)**

Runner GitHub-hosted berada di internet dan **tidak bisa reach Harbor**.

### Opsi konektivitas CI → Harbor

| Opsi | Kelebihan | Kekurangan | Rekomendasi |
|---|---|---|---|
| Self-hosted runner di homelab | Harbor tetap private, akses internal | Perlu maintain runner | **Recommended** |
| Expose Harbor via Cloudflare Tunnel | Pakai runner GitHub-hosted | Attack surface besar, perlu Access policy | Tidak recommended |
| Build di GitHub-hosted lalu mirror manual | Sederhana | Tidak otomatis, rentan human error | Tidak recommended |

Self-hosted runner tetap termasuk **GitHub Actions**, hanya eksekusinya di jaringan Anda.

---

## 4.1 Alternatif: Harbor Public Registry + GitHub-Hosted Runner

Jika Anda tidak ingin memakai self-hosted runner (mis. karena limit job/runner), Anda bisa membuat **Harbor menjadi public registry** melalui Cloudflare Tunnel. Dengan begitu, GitHub-hosted runner dapat push image langsung.

### Arsitektur alternatif

```text
GitHub-hosted Runner (internet)
  │ docker push harbor.frengky.xyz/<project>/<app>:<sha>
  ▼
Cloudflare Edge (HTTPS, WAF, rate limit)
  │ Cloudflare Tunnel (outbound dari cluster)
  ▼
cloudflared pod → http://harbor.harbor.svc.cluster.local:80
  ▼
Harbor (auth: robot account)
```

Cluster tetap pull dari **internal Harbor** (`harbor.harbor.svc.cluster.local`) agar tidak keluar internet.

### Langkah singkat
1. Ubah DNS `harbor.frengky.xyz` dari gray cloud (Tailscale) ke orange cloud (CNAME tunnel).
2. Tambahkan Public Hostname di Cloudflare Tunnel:
   - `harbor.frengky.xyz` → `http://harbor.harbor.svc.cluster.local:80`
3. Pastikan `externalURL: https://harbor.frengky.xyz` di `infrastructure/harbor/values.yaml`.
4. Reconcile Harbor via Flux.
5. Gunakan workflow dengan `runs-on: ubuntu-latest`.

### Keamanan wajib (public Harbor)
- Admin password kuat (jangan default).
- Disable self-registration.
- Project tetap private.
- Robot account least-privilege (push/pull terpisah).
- Aktifkan Trivy scan.
- Cloudflare WAF + rate limiting.
- Tetap gunakan `imagePullSecret` di cluster.

### Workflow (GitHub-hosted)

```yaml
jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Compute tag
        id: meta
        run: echo "tag=${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
      - name: Login Harbor
        run: |
          echo "${{ secrets.HARBOR_PASSWORD }}" | docker login harbor.frengky.xyz \
            -u "${{ secrets.HARBOR_USERNAME }}" --password-stdin
      - name: Build & push
        run: |
          docker build -t harbor.frengky.xyz/backend/point-of-sales:${{ steps.meta.outputs.tag }} .
          docker push harbor.frengky.xyz/backend/point-of-sales:${{ steps.meta.outputs.tag }}
```

> Catatan: Opsi ini membuat Harbor internet-facing. Gunakan hanya jika hardening di atas diterapkan.

---

## 4.2 Tag `prod` + Digest-based Rollout (Tanpa Self-Hosted Runner)

Jika Anda tidak ingin self-hosted runner dan ingin tag image tetap `prod` (satu tag yang ditimpa setiap build), gunakan pendekatan **digest-based rollout** agar Kubernetes tetap melakukan redeploy.

### Konsep
- CI build & push image ke `harbor.frengky.xyz/<project>/<app>:prod`.
- CI juga ambil digest image (`sha256:...`).
- CI update GitOps repo dengan referensi immutable:
  ```text
  harbor.frengky.xyz/<project>/<app>@sha256:<digest>
  ```
- Tag tetap `prod` untuk manusia, tetapi digest berubah setiap build → Flux mendeteksi perubahan → rollout pod baru.

### Workflow (GitHub-hosted)

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

      - name: Login Harbor
        run: |
          echo "${{ secrets.HARBOR_PASSWORD }}" | docker login harbor.frengky.xyz \
            -u "${{ secrets.HARBOR_USERNAME }}" --password-stdin

      - name: Build & push :prod
        run: |
          docker build -t harbor.frengky.xyz/backend/point-of-sales:prod .
          docker push harbor.frengky.xyz/backend/point-of-sales:prod

      - name: Get digest
        id: digest
        run: |
          DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' harbor.frengky.xyz/backend/point-of-sales:prod | cut -d@ -f2)
          echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"

      - name: Update GitOps repo (digest)
        env:
          GITOPS_TOKEN: ${{ secrets.GITOPS_TOKEN }}
        run: |
          git clone "https://x-access-token:${GITOPS_TOKEN}@github.com/frengkysorituamanurung/homelabs.git" /tmp/homelabs
          cd /tmp/homelabs
          # contoh: update digest di values/helmrelease
          sed -i -E "s|image: .*|image: harbor.frengky.xyz/backend/point-of-sales@${{ steps.digest.outputs.digest }}|" infrastructure/point-of-sales/flux/helmrelease.yaml
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add infrastructure/point-of-sales/flux/helmrelease.yaml
          git diff --cached --quiet || git commit -m "chore(point-of-sales): update prod digest"
          git push origin main
```

### Catatan
- Pendekatan ini tetap GitOps (CI commit ke GitOps repo).
- Tidak butuh self-hosted runner.
- Tag `prod` tetap ada untuk referensi manusia, tetapi deployment memakai digest immutable.
- Jika Anda tidak ingin commit digest, alternatifnya commit timestamp annotation di pod template agar rollout terjadi.

---

## 4.3 GitHub-Hosted Runner + Tailscale Ephemeral (Harbor Tetap Private)

Jika Anda tidak ingin self-hosted runner tetapi Harbor tetap private, GitHub-hosted runner bisa sementara bergabung ke Tailscale saat job berjalan.

### Arsitektur

```text
GitHub-hosted Runner (ubuntu-latest)
  │ 1. Tailscale GitHub Action (auth key ephemeral)
  │    → runner jadi node sementara di tailnet
  │ 2. docker push harbor.frengky.xyz/... (via Tailscale)
  ▼
Tailscale mesh
  ▼
Homelab (harbor.frengky.xyz → 100.120.133.63)
  ▼
Harbor (private, auth robot account)
```

### Workflow

```yaml
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

      - name: Login Harbor
        run: |
          echo "${{ secrets.HARBOR_PASSWORD }}" | docker login harbor.frengky.xyz \
            -u "${{ secrets.HARBOR_USERNAME }}" --password-stdin

      - name: Build & push
        run: |
          docker build -t harbor.frengky.xyz/backend/point-of-sales:${{ github.sha }} .
          docker push harbor.frengky.xyz/backend/point-of-sales:${{ github.sha }}
```

### Prasyarat
- Auth key Tailscale (ephemeral, reusable) disimpan di GitHub Secrets: `TAILSCALE_AUTHKEY`.
- ACL Tailscale: `tag:ci` hanya boleh akses Harbor.
- Harbor tetap VPN-only (DNS gray cloud).

### Keuntungan
- Harbor tetap private.
- Tidak perlu self-hosted runner.
- Runner hanya sementara masuk tailnet, otomatis keluar setelah job selesai.

---

## 5. Desain Harbor

### Project
- Buat project private, contoh: `backend/point-of-sales` atau `apps/point-of-sales`.
- Aktifkan vulnerability scanning (Trivy).

### Robot Account (terpisah)
- `robot$ci-pusher-point-of-sales`
  - Permission: **push** ke project tertentu
  - Dipakai GitHub Actions
- `robot$k8s-puller`
  - Permission: **pull/read** ke project
  - Dipakai cluster (`imagePullSecret`)

### Penamaan image
```text
harbor.frengky.xyz/<project>/<app>:<git-short-sha>
```
Contoh:
```text
harbor.frengky.xyz/backend/point-of-sales:a1b2c3d
```

### Tag strategy
- Production: git short SHA atau semver (`v1.2.3`).
- Hindari `latest` di production.
- Simpan mapping tag → commit di GitOps repo (commit message).

---

## 6. Privasi Repo

### App repo (private)
- Tetap private.
- Workflow CI berjalan normal di private repo.
- Secret GitHub disimpan di repo settings (Actions secrets).

### GitOps repo (`homelabs`)
Dua skenario:

| Skenario | Konfigurasi |
|---|---|
| GitOps repo **public** (default saat ini) | Aman, hanya manifest & tag; tidak ada source code |
| GitOps repo **private** | Flux perlu credential (`secretRef` di `GitRepository`); CI pakai PAT untuk push |

Contoh Flux `GitRepository` untuk GitOps repo private:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: homelabs
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/frengkysorituamanurung/homelabs.git
  ref:
    branch: main
  secretRef:
    name: flux-github-token
```

Secret `flux-github-token` berisi `username` dan `password` (PAT read access).

---

## 7. Image Pull Secret (Private Harbor Project)

Karena project Harbor private, pod perlu `imagePullSecrets`.

### 7.1 Patch Chart `generic-app` (Recommended)

Tambahkan ke `helm/charts/generic-app/values.yaml` (opsional, default kosong):

```yaml
imagePullSecrets: []
```

Tambahkan ke template `deployment.yaml` (sebelum `containers:`):

```yaml
{{- if $values.imagePullSecrets }}
imagePullSecrets:
{{- toYaml $values.imagePullSecrets | nindent 6 }}
{{- end }}
```

Lalu di values app:

```yaml
imagePullSecrets:
  - name: harbor-pull-secret
```

### 7.2 Buat Secret via Vault + ESO

Simpan credential pull robot di Vault:

```bash
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=root \
  vault kv put secret/harbor-pull \
  username="robot\$k8s-puller" \
  password="<ROBOT_PASSWORD>"
```

Buat ExternalSecret (template dockerconfigjson):

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: harbor-pull-secret
  namespace: <app-namespace>
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

Alternatif cepat (tidak GitOps-friendly): `kubectl create secret docker-registry ...`.

---

## 8. Pattern Manifest di GitOps Repo (Flux Modern)

Gunakan pola yang sudah ada di repo (contoh `mcp-bridge`, `uptime-kuma`), bukan legacy Argo.

Struktur:

```text
infrastructure/<app>/
├── values.yaml
└── flux/
    ├── helmrepository.yaml
    ├── helmrelease.yaml
    └── kustomization.yaml
```

Daftarkan di `clusters/production/flux-system/kustomization.yaml`.

### Contoh `helmrelease.yaml`

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: point-of-sales
  namespace: flux-system
spec:
  interval: 5m
  chart:
    spec:
      chart: ./k8s/clusters/production/applications/apps/production/backend/point-of-sales
      version: "1.0.0"
      sourceRef:
        kind: GitRepository
        name: homelabs
        namespace: flux-system
  releaseName: point-of-sales
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
      baseName: point-of-sales
      environment: production
      image:
        repository: harbor.frengky.xyz/backend/point-of-sales
        tag: "a1b2c3d"   # diupdate otomatis oleh CI / Flux Image Automation
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
          - host: pos.frengky.xyz
            path: /
            port: 8080
```

---

## 9. Workflow GitHub Actions (Self-Hosted Runner)

File: `.github/workflows/ci.yml` di **private app repo**.

```yaml
name: CI/CD

on:
  push:
    branches: [main]

jobs:
  build-and-deploy:
    runs-on: [self-hosted, homelab]
    steps:
      - uses: actions/checkout@v4

      - name: Compute tag
        id: meta
        run: echo "tag=${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"

      - name: Login Harbor
        run: |
          echo "${{ secrets.HARBOR_PASSWORD }}" | docker login harbor.frengky.xyz \
            -u "${{ secrets.HARBOR_USERNAME }}" --password-stdin

      - name: Build & push
        run: |
          docker build -t harbor.frengky.xyz/backend/point-of-sales:${{ steps.meta.outputs.tag }} .
          docker push harbor.frengky.xyz/backend/point-of-sales:${{ steps.meta.outputs.tag }}

      - name: Update GitOps repo
        env:
          GITOPS_TOKEN: ${{ secrets.GITOPS_TOKEN }}
        run: |
          git clone "https://x-access-token:${GITOPS_TOKEN}@github.com/frengkysorituamanurung/homelabs.git" /tmp/homelabs
          cd /tmp/homelabs
          sed -i -E "s/tag: .*/tag: \"${{ steps.meta.outputs.tag }}\"/" infrastructure/point-of-sales/flux/helmrelease.yaml
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add infrastructure/point-of-sales/flux/helmrelease.yaml
          git diff --cached --quiet || git commit -m "chore(point-of-sales): image ${{ steps.meta.outputs.tag }}"
          git push origin main
```

### Secrets yang perlu diset (repo private app)
- `HARBOR_USERNAME` → robot pusher
- `HARBOR_PASSWORD`
- `GITOPS_TOKEN` → fine-grained PAT, `contents:write` hanya ke repo `homelabs`

---

## 10. Self-Hosted Runner (Ringkas)

> Jika Anda memilih alternatif Harbor public (§4.1), bagian ini tidak wajib. Self-hosted runner tetap direkomendasikan jika Harbor tetap private.

Opsi sederhana: jalankan GitHub Actions runner sebagai service di host homelab (bukan di cluster) agar punya akses Docker & jaringan Tailscale.

Langkah umum:
1. Buat runner di GitHub: Repo → Settings → Actions → Runners → New self-hosted runner.
2. Download & configure runner di host homelab.
3. Label runner dengan `homelab`.
4. Pastikan runner dapat:
   - `docker login/push` ke `harbor.frengky.xyz`
   - clone/push ke repo `homelabs`
5. (Opsional) jalankan runner sebagai systemd service agar auto-start.

Alternatif: deploy runner sebagai pod di cluster dengan docker socket hostPath, tapi lebih kompleks dan butuh hardening.

---

## 11. Alternatif: Flux Image Automation (Lebih Aman)

Jika CI tidak boleh punya write access ke GitOps repo:

- CI hanya build + push image ke Harbor.
- Flux `ImageRepository` memantau tag baru di Harbor.
- `ImagePolicy` memilih tag (semver/numerical).
- `ImageUpdateAutomation` commit perubahan tag ke GitOps repo (pakai deploy key).

Keuntungan:
- CI tidak menyimpan PAT GitOps.
- Deployment tetap GitOps-native.
- Audit trail lebih jelas.

Trade-off:
- Perlu install Flux image automation controllers.
- Konfigurasi tambahan.

---

## 12. Keamanan & Hardening

1. **Repo app tetap private**; secret GitHub tidak bocor ke log (gunakan `--password-stdin`).
2. **Harbor project private**; robot account least-privilege.
3. **Pisahkan robot account** push (CI) vs pull (cluster).
4. **Hindari `latest`**; pakai SHA/semver untuk reproducibility & rollback.
5. **Scan image** (Trivy) di Harbor sebelum deploy.
6. **Branch protection** di GitOps repo; bot hanya ubah tag.
7. **Rotate** PAT & robot account berkala.
8. **Jangan simpan credential di manifest**; gunakan Vault + ESO.
9. **Akses app**: pilih private (Tailscale) atau public (Cloudflare Tunnel) sesuai kebutuhan.
10. Jika GitOps repo private: gunakan deploy key read-only untuk Flux, write PAT hanya di CI (atau gunakan Flux Image Automation untuk menghilangkan write dari CI).

---

## 13. Checklist Implementasi

- [ ] Project & robot account dibuat di Harbor
- [ ] (Jika Harbor public) DNS/Tunnel public + WAF + rate limit aktif
- [ ] Self-hosted runner terpasang & berlabel `homelab` (jika Harbor private)
- [ ] Secrets diset di private app repo
- [ ] Workflow CI dibuat & diuji
- [ ] Manifest app ditambahkan di `infrastructure/<app>/`
- [ ] App diregister di `clusters/production/flux-system/kustomization.yaml`
- [ ] `harbor-pull-secret` dibuat via Vault+ESO
- [ ] Chart `generic-app` dipatch untuk `imagePullSecrets` (jika perlu)
- [ ] DNS/Ingress dikonfigurasi (private/public)
- [ ] Push code → verifikasi Flux rollout & akses app

---

## 14. Troubleshooting

| Masalah | Penyebab Umum | Solusi |
|---|---|---|
| ImagePullBackOff | Secret pull salah / robot expired | Cek `harbor-pull-secret`, robot account |
| CI gagal push Harbor | Runner tidak reach Harbor | Pastikan self-hosted runner & Tailscale aktif |
| Flux tidak update | Tag tidak berubah / commit gagal | Cek GitOps repo commit, `flux reconcile` |
| App tidak bisa diakses | DNS/ingress salah | Cek ingress host, DNS Cloudflare, Tailscale |
| Runner offline | Service runner mati | Restart runner / systemd service |

---

## 15. Referensi Pola di Repo Ini

- `infrastructure/mcp-bridge/flux/helmrelease.yaml` (app sederhana dengan generic-app)
- `infrastructure/service-a/flux/helmrelease.yaml` (image dari Harbor)
- `infrastructure/uptime-kuma/` (pola Flux modern)
- `secrets/templates/` (Vault + ESO)
- `docs/new-application-setup.md` (onboarding app Flux)
- `docs/new_app_deployment.md` (pipeline Gitea, referensi konsep)
- `docs/gitops-harbor-mirror.md` (Harbor sebagai registry internal)
- `docs/network-design.md` (public vs private access)

---

## 16. Contoh Pemakaian untuk `point-of-sales`

Jika app `point-of-sales`:
- Repo: `https://github.com/frengkysorituamanurung/point-of-sales` (private)
- Image: `harbor.frengky.xyz/backend/point-of-sales:<sha>`
- Namespace: `backend` (atau `production`)
- Domain: `pos.frengky.xyz` (pilih private/public)
- Port: sesuaikan dengan aplikasi (mis. `8080`)

Setelah info port/namespace/akses ditentukan, manifest dapat dibuat mengikuti pola di §8.