# Panduan Upgrade Versi Aplikasi & Helm Chart di Lingkungan GitOps

Dokumen ini menjelaskan langkah-langkah standar untuk meng-upgrade versi aplikasi dan Helm Chart di lingkungan kluster Kubernetes yang dikelola dengan **ArgoCD**, **Harbor (Private Registry)**, dan **GitOps Repository**.

Sebagai contoh, dokumen ini memuat panduan langkah demi langkah untuk meng-upgrade **Harbor** dari versi **v2.12.2** ke versi **v2.15.2** (atau versi terbaru lainnya).

---

## 1. Konsep Upgrade Aplikasi di Lingkungan GitOps

Di lingkungan kluster ini, aplikasi dikelola menggunakan pendekatan **GitOps** dan **Self-Hosted Registry**:
1. **OCI Helm Registry Internal**: Helm Chart disimpan di registry internal (`oci://harbor.frengky.xyz/helm-repos`).
2. **Container Image Mirroring**: Container Image aplikasi ditarik dari internet, lalu di-*push* ke Harbor internal (`harbor.frengky.xyz`).
3. **ArgoCD Application Sync**: ArgoCD memantau perubahan pada repository GitOps (`gitops-repo`) dan melakukan sinkronisasi otomatis (*rollout*) ke kluster Kubernetes.

---

## 2. Alur Langkah-Langkah Upgrade Versi Aplikasi (Contoh: Harbor v2.15.2)

### Langkah 1: Pengecekan Versi Saat Ini

Cek versi aplikasi dan pod yang sedang berjalan di kluster:
```bash
# Cek pod & image versi saat ini
kubectl get pods -n harbor -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

# Cek manifest ArgoCD saat ini
cat argocd/applications/infrastructure/harbor.yaml
```

---

### Langkah 2: Mirroring Container Image Baru dari Internet ke Harbor Internal

Untuk memastikan kluster tidak bergantung pada koneksi internet publik saat *runtime*, *pull* image komponen versi terbaru ke server lokal, berikan tag, lalu *push* ke Harbor internal.

1. **Login ke Harbor Internal**:
   ```bash
   docker login harbor.frengky.xyz -u admin -p Harbor12345
   ```

2. **Pull Image Versi Terbaru (v2.15.2) & Push ke Harbor**:
   ```bash
   # Komponen Utama Harbor
   IMAGES=(
     "goharbor/harbor-core:v2.15.2"
     "goharbor/harbor-portal:v2.15.2"
     "goharbor/harbor-jobservice:v2.15.2"
     "goharbor/harbor-db:v2.15.2"
     "goharbor/harbor-registryctl:v2.15.2"
     "goharbor/registry-photon:v2.15.2"
     "goharbor/redis-photon:v2.15.2"
     "goharbor/trivy-adapter-photon:v2.15.2"
   )

   for img in "${IMAGES[@]}"; do
     echo "Pulling $img..."
     docker pull "$img"
     
     # Tag image ke registry internal
     LOCAL_TAG="harbor.frengky.xyz/library/${img##*/}"
     docker tag "$img" "$LOCAL_TAG"
     
     echo "Pushing $LOCAL_TAG..."
     docker push "$LOCAL_TAG"
   done
   ```

---

### Langkah 3: Unduh & Publish Helm Chart Terbaru ke OCI Harbor Registry

1. **Tambahkan Repository Helm Resmi Upstream**:
   ```bash
   helm repo add harbor https://helm.goharbor.io
   helm repo update
   ```

2. **Unduh Package Helm Chart Versi Terbaru**:
   ```bash
   # Cari versi chart terbaru
   helm search repo harbor/harbor --versions | head -n 5

   # Unduh chart (misal versi chart 1.16.2 atau versi terbaru)
   helm pull harbor/harbor --version 1.16.2
   ```

3. **Login & Push Helm Chart ke OCI Registry Harbor Internal**:
   ```bash
   # Login ke OCI registry dengan Helm
   helm registry login harbor.frengky.xyz -u admin -p Harbor12345

   # Push file helm chart (.tgz) ke project helm-repos
   helm push harbor-1.16.2.tgz oci://harbor.frengky.xyz/helm-repos
   ```

---

### Langkah 4: Perbarui Konfigurasi Manifest di GitOps Repository

1. **Perbarui Version Target pada ArgoCD Application Spec**:
   Edit file `argocd/applications/infrastructure/harbor.yaml`:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: harbor
     namespace: argocd
   spec:
     sources:
       - repoURL: harbor-registry-tls.harbor.svc.cluster.local
         chart: helm-repos/harbor
         targetRevision: "1.16.2"  # <-- Update ke versi chart baru
         helm:
           valueFiles:
             - $values/infrastructure/harbor/values.yaml
   ```

2. **Perbarui Image Tag pada `values.yaml` (jika ada)**:
   Edit file `infrastructure/harbor/values.yaml` untuk menyesuaikan tag versi terbaru jika diperlukan:
   ```yaml
   # Contoh penyesuaian tag di values.yaml jika menggunakan tag kustom
   core:
     image:
       repository: harbor.frengky.xyz/library/harbor-core
       tag: v2.15.2
   ```

---

### Langkah 5: Commit & Push Perubahan ke GitOps Repository

Commit perubahan manifest yang sudah diperbarui ke repository GitOps agar ArgoCD dapat mendeteksi perubahan tersebut:

```bash
cd /root/server/gitops-repo

git add argocd/applications/infrastructure/harbor.yaml
git add infrastructure/harbor/values.yaml
git commit -m "chore(harbor): upgrade harbor helm chart to 1.16.2 (app v2.15.2)"
git push origin main
```

---

### Langkah 6: Trigger ArgoCD Sync & Verifikasi Deployment

1. **Trigger Sync ArgoCD**:
   ArgoCD akan secara otomatis melakukan sync. Jika ingin mempercepat, jalankan perintah:
   ```bash
   # Trigger refresh & sync via API / CLI
   kubectl annotate application harbor -n argocd argocd.argoproj.io/refresh=normal --overwrite
   ```

2. **Pantau Status Upgrade (Rolling Update)**:
   ```bash
   # Cek status rollout deployment
   kubectl rollout status deployment/harbor-core -n harbor
   kubectl rollout status deployment/harbor-jobservice -n harbor
   
   # Cek status pod di namespace harbor
   kubectl get pods -n harbor
   ```

3. **Verifikasi Fungsionalitas**:
   - Uji akses Web UI Harbor: `https://harbor.frengky.xyz`
   - Lakukan uji coba `docker login`, `docker pull`, dan `docker push` ke registry untuk memastikan service berjalan normal setelah versi diperbarui.

---

## 3. Checklist Penting Sebelum Upgrade

| Checklist | Deskripsi |
| :--- | :--- |
| **Backup Database** | Lakukan backup database PostgreSQL (`harbor-database`) sebelum melakukan major upgrade. |
| **Breaking Changes** | Periksa changelog resmi rilis Helm Chart / Aplikasi untuk memastikan tidak ada perubahan parameter `values.yaml` yang tidak kompatibel. |
| **Image Availability** | Pastikan semua sub-component image sudah berhasil di-*push* ke Harbor sebelum memicu sync ArgoCD. |
