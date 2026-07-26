# Panduan Reloader dengan Pattern Vault & External Secrets Operator (ESO)

Dokumen ini memuat panduan lengkap mengenai arsitektur, instalasi, dan cara kerja **Stakater Reloader** yang terintegrasi dengan **External Secrets Operator (ESO)** dan **HashiCorp Vault** di kluster Kubernetes ini.

---

## 1. Masalah yang Diselesaikan

Secara default di Kubernetes:
1. Saat data di **HashiCorp Vault** diubah, **External Secrets Operator (ESO)** akan memperbarui resource `Secret` di Kubernetes secara otomatis.
2. Namun, **Pod/Deployment yang sedang berjalan TIDAK secara otomatis membaca perubahan secret tersebut** (terutama jika secret diinjeksi via `envFrom` / `secretRef`).
3. Akibatnya, pengembang harus melakukan `kubectl rollout restart` secara manual setiap kali ada perubahan kredensial/secret di Vault.

Dengan hadirnya **Stakater Reloader**, setiap perubahan pada Kubernetes `Secret` (yang dipicu oleh Vault & ESO) akan secara otomatis memicu **rolling restart** pada Pod/Deployment terkait tanpa *downtime*.

---

## 2. Arsitektur & Cara Kerja (End-to-End Workflow)

```
┌─────────────────┐       (1) Sync       ┌──────────────────────────┐
│ HashiCorp Vault │ ───────────────────> │ External Secrets Operator│
└─────────────────┘                      └──────────────────────────┘
                                                       │
                                                       │ (2) Update Secret
                                                       ▼
┌─────────────────┐       (4) Rollout    ┌──────────────────────────┐
│ Pod / Workload  │ <─────────────────── │ Kubernetes Secret        │
└─────────────────┘       Restart        └──────────────────────────┘
         ▲                                             │
         │                                             │ (3) Detect Change
         └─────────────────────────────────────────────┘
                      Stakater Reloader
```

1. **Vault (Upstream Secret Store)**: Menyimpan kredensial/secret aplikasi (misal `secret/data/ci/credentials` atau `secret/data/backend/sample-api`).
2. **External Secrets Operator (ESO)**: Mengambil data dari Vault melalui `ClusterSecretStore` dan secara berkala mereflikakannya menjadi resource `Secret` Kubernetes (misal `sample-api-secrets`).
3. **Stakater Reloader Controller**: Memantau event perubahan (*add/update/delete*) pada seluruh `Secret` dan `ConfigMap` di kluster Kubernetes.
4. **Automatic Rolling Restart**: Begitu Reloader mendeteksi perubahan hash pada `Secret`, Reloader langsung memicu *rolling update* pada Deployment/Argo Rollout yang mereferensikan secret tersebut.

---

## 3. Detail Implementasi di Server Ini

Semua komponen Reloader disimpan dan dikelola secara mandiri melalui **Harbor (Private Registry)** dan **ArgoCD**:

### 1. Registrasi Container Image & Helm Chart di Harbor
* **Container Image**: `harbor.frengky.xyz/library/reloader:v1.4.19`
* **Helm Chart OCI**: `oci://harbor.frengky.xyz/helm-repos/reloader:2.2.14`

### 2. ArgoCD Application Manifest (`kubernetes/applications/infrastructure/reloader.yaml`)
Reloader didaftarkan ke pola GitOps ArgoCD dengan manifest berikut:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: reloader
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default
  source:
    repoURL: harbor-registry-tls.harbor.svc.cluster.local
    chart: helm-repos/reloader
    targetRevision: "2.2.14"
    helm:
      parameters:
        - name: reloader.deployment.image.name
          value: "harbor.frengky.xyz/library/reloader"
        - name: reloader.deployment.image.tag
          value: "v1.4.19"
        - name: reloader.autoReloadAll
          value: "true"
  destination:
    server: https://kubernetes.default.svc
    namespace: reloader
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

## 4. Opsi Anotasi pada Workload (Deployment / Rollout)

Terdapat dua pendekatan untuk mengaktifkan otomatisasi reload pada aplikasi:

### Metode A: Global Auto-Reload (Default di Server Ini)
Karena parameter `reloader.autoReloadAll: "true"` diaktifkan pada Reloader, seluruh Deployment/StatefulSet yang menggunakan `secretRef`, `envFrom`, atau `volumeMounts` dari Secret/ConfigMap akan secara **otomatis direload** saat secret berubah.

### Metode B: Anotasi Spesifik pada Chart / Deployment
Jika ingin menentukan secara eksplisit pada manifest Deployment/Argo Rollout:

1. **Auto Reload Seluruh Secret Terkait**:
   ```yaml
   metadata:
     annotations:
       reloader.stakater.com/auto: "true"
   ```

2. **Reload Hanya untuk Secret Spesifik**:
   ```yaml
   metadata:
     annotations:
       secret.reloader.stakater.com/reload: "sample-api-secrets"
   ```

---

## 5. Cara Pengujian Integrasi (Vault → ESO → Reloader → Pod)

Untuk memverifikasi bahwa alur otomatisasi berfungsi dengan sempurna:

1. **Ubah Nilai Secret di Vault**:
   ```bash
   vault kv put secret/ci/credentials APP_VERSION="2.0.0" DB_PASSWORD="newpassword123"
   ```

2. **Cek Sync ExternalSecrets**:
   External Secrets Operator akan meng-update k8s secret:
   ```bash
   kubectl get externalsecrets -A
   ```

3. **Cek Log Reloader**:
   Amati log Reloader saat mendeteksi perubahan secret:
   ```bash
   kubectl logs -n reloader -l app.kubernetes.io/name=reloader --tail=20 -f
   ```
   *Log akan menampilkan informasi:*
   `Changes detected in secret: sample-api-secrets in namespace: backend, triggering reload for deployment: sample-api`

4. **Verifikasi Pod Rolling Restart**:
   ```bash
   kubectl get pods -n backend -w
   ```
   Pod lama akan di-terminate secara bertahap dan digantikan oleh Pod baru yang langsung membaca secret terbaru dari Vault.

---

## 6. Lokasi File & Manifest Terkait

| File | Fungsi |
| :--- | :--- |
| `kubernetes/applications/infrastructure/reloader.yaml` | Manifest ArgoCD Application untuk Reloader |
| `helm-charts/charts/generic-app/templates/deployment.yaml` | Template Helm Chart mikroservis yang mendukung Reloader |
| `docs/reloader-vault-integration.md` | Dokumentasi arsitektur dan panduan setup ini |
