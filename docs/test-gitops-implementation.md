# Implementasi End-to-End: `sorivalabs/test-gitops`

Dokumen ini mendokumentasikan implementasi nyata untuk repo private `sorivalabs/test-gitops`:
- App: Go API dengan 4 endpoint.
- CI: GitHub Actions (GitHub-hosted runner) + Tailscale ephemeral.
- Registry: Harbor private (`harbor.frengky.xyz/backend/test-gitops`).
- Deploy: Flux CD di k3s homelab.

---

## 1. Repository Aplikasi

Repo: `https://github.com/sorivalabs/test-gitops` (private)

Struktur:
```text
test-gitops/
├── .github/workflows/ci.yml
├── Dockerfile
├── go.mod
├── main.go
└── README.md
```

### Endpoint
- `GET /health`
- `GET /users`
- `POST /users` body `{"name":"..."}`
- `GET /users/{id}`

---

## 2. Harbor

### Project
- `backend` (sudah ada)

### Robot Account
- CI pusher:
  - Username: `robot$backend+ci-pusher-test-gitops`
  - Secret: disimpan di GitHub Secrets `HARBOR_PASSWORD`
- Cluster puller:
  - Username: `robot$backend+k8s-puller-test-gitops`
  - Secret: disimpan di Vault `secret/harbor-pull`

Image:
```text
harbor.frengky.xyz/backend/test-gitops:<git-sha>
```

---

## 3. GitHub Secrets (repo `sorivalabs/test-gitops`)

Set dengan `gh secret set`:

```bash
gh secret set HARBOR_USERNAME --repo sorivalabs/test-gitops --body 'robot$backend+ci-pusher-test-gitops'
gh secret set HARBOR_PASSWORD --repo sorivalabs/test-gitops --body '<pusher-secret>'
gh secret set GITOPS_TOKEN --repo sorivalabs/test-gitops --body '<PAT-with-contents:write>'
```

### Tailscale Auth Key (wajib dibuat manual)
1. Buka Tailscale Admin Console → Settings → Keys.
2. Create Auth Key:
   - Reusable: yes
   - Ephemeral: yes
   - Tags: `tag:ci`
3. Simpan di GitHub Secrets:
   ```bash
   gh secret set TAILSCALE_AUTHKEY --repo sorivalabs/test-gitops --body 'tskey-auth-...'
   ```

ACL Tailscale (contoh):
```json
{
  "tagOwners": {
    "tag:ci": ["autogroup:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["tag:ci"],
      "dst": ["tag:server:443", "tag:server:80"]
    }
  ]
}
```

---

## 4. GitOps Repo (`frengkysorituamanurung/homelabs`)

### File yang ditambahkan
- `infrastructure/test-gitops/flux/kustomization.yaml`
- `infrastructure/test-gitops/flux/helmrelease.yaml`
- `infrastructure/test-gitops/flux/externalsecret.yaml`
- `k8s/clusters/production/applications/apps/production/backend/test-gitops/Chart.yaml`
- `clusters/production/flux-system/pilot-test-gitops.yaml`
- Update `clusters/production/flux-system/kustomization.yaml`

### HelmRelease
- Chart: `./k8s/.../backend/test-gitops` (vendored generic-app)
- Image: `harbor.frengky.xyz/backend/test-gitops:<tag>`
- `imagePullSecrets: harbor-pull-secret`
- Ingress: `test-gitops.frengky.xyz`

### ExternalSecret
- Vault path: `secret/data/harbor-pull`
- Target secret: `harbor-pull-secret` (type dockerconfigjson)

---

## 5. Vault

Secret puller disimpan di Vault:
```bash
vault kv put secret/harbor-pull \
  username='robot$backend+k8s-puller-test-gitops' \
  password='<puller-secret>'
```

---

## 6. Alur CI/CD

1. Push ke `main` di `sorivalabs/test-gitops`.
2. GitHub Actions (GitHub-hosted runner):
   - Connect Tailscale (ephemeral).
   - Build image.
   - Push ke Harbor: `harbor.frengky.xyz/backend/test-gitops:<sha>`.
   - Clone `homelabs`, update tag, commit & push.
3. Flux mendeteksi perubahan GitOps repo.
4. Flux deploy pod, pull image dari Harbor dengan `harbor-pull-secret`.
5. App tersedia di `https://test-gitops.frengky.xyz` (jika DNS/ingress dikonfigurasi).

---

## 7. DNS / Ingress

Untuk akses:
- Private (Tailscale): A record `test-gitops.frengky.xyz` → `100.120.133.63` (gray cloud).
- Public (Cloudflare Tunnel): tambahkan public hostname di tunnel.

---

## 8. Troubleshooting

| Masalah | Penyebab | Solusi |
|---|---|---|
| Tailscale step gagal | Auth key salah/expired | Buat auth key baru, update secret |
| ImagePullBackOff | Pull secret salah | Cek Vault/ESO/robot puller |
| Flux tidak update | Tag tidak berubah/commit gagal | Cek GitOps repo commit & `flux reconcile` |
| App tidak bisa diakses | DNS/ingress salah | Cek ingress host & DNS |

---

## 9. File yang Diubah di Repo `homelabs`

- `infrastructure/test-gitops/flux/*`
- `k8s/clusters/production/applications/apps/production/backend/test-gitops/*`
- `clusters/production/flux-system/pilot-test-gitops.yaml`
- `clusters/production/flux-system/kustomization.yaml`
- `helm/charts/generic-app/*` (support imagePullSecrets)