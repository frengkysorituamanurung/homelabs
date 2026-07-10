# GitOps Helm Charts Mirroring ke Harbor (Air-Gapped / Private Registry)

Dokumentasi ini menjelaskan konfigurasi dan alur kerja (*workflow*) yang diterapkan untuk mengatasi masalah limitasi akses *outbound internet* (kegagalan TCP `DeadlineExceeded` saat ArgoCD mencoba menarik Helm Chart dari *registry* eksternal).

## Latar Belakang Masalah
Pod di dalam cluster mengalami kendala resolusi TCP *outbound* (internet keluar), yang mengakibatkan `argocd-repo-server` tidak dapat melakukan `helm pull` dari *registry* publik seperti GitHub, HashiCorp, Prometheus Community, dll. Jika *sync* dibiarkan gagal, ArgoCD tidak akan memperbarui *state* cluster dan aplikasi akan stuck di status `Unknown` atau `ComparisonError`. 

## Solusi: Air-Gapped GitOps Pattern
Alih-alih mengandalkan internet untuk mengunduh Helm Chart secara real-time, kita mengimplementasikan pola **Private Registry Mirroring**:
1. Menyalin (mem-pull) seluruh *external* Helm chart `.tgz` melalui *host server* (yang memiliki akses internet normal).
2. Memasukkan (*push*) chart tersebut ke dalam *project* `helm-repos` di Harbor lokal kita (sebagai OCI artifacts).
3. Mengkonfigurasi ArgoCD agar menjadikan Harbor lokal sebagai sumber (*Single Source of Truth*) Helm Chart.

Keuntungan:
- **Zero Internet Dependency:** ArgoCD kini berjalan 100% *offline* (berkomunikasi antar-pod di cluster via `harbor-core.harbor.svc.cluster.local`).
- **Keamanan (Enterprise Grade):** Kebal terhadap pemadaman (downtime) pihak ketiga.
- **Kinerja:** Proses sinkronisasi menjadi instan (dalam hitungan milidetik).

## Konfigurasi yang Dilakukan

### 1. Migrasi Charts ke Harbor
Menggunakan _script_ otomatis, seluruh dependensi Helm chart ditarik (*pull*) dengan versi spesifik dan di-*push* ke OCI registry Harbor lokal:
```bash
helm pull hashicorp/vault --version 0.29.1
helm push vault-0.29.1.tgz oci://harbor.frengky.xyz/helm-repos
# (Dilakukan untuk seluruh chart seperti argo-cd, grafana, loki, kube-state-metrics, dll)
```

### 2. Pendaftaran Secret Repository di ArgoCD
Harbor harus didaftarkan di dalam namespace `argocd` sebagai *repository* berjenis `helm` (OCI). Rahasia ini memberitahu ArgoCD cara untuk masuk ke Harbor via HTTP internal:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: harbor-helm-repos
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  name: harbor-helm-repos
  url: harbor-core.harbor.svc.cluster.local   # Menggunakan DNS Internal (bukan domain Cloudflare)
  type: helm
  enableOCI: "true"
  insecure: "true"
  username: admin
  password: <harbor_password>
```

### 3. Pembaruan Manifest GitOps (ArgoCD Application)
Seluruh file manifest ArgoCD (seperti `apps/monitoring/grafana.yaml`) telah di-_update_ sehingga blok `source` mengarah ke Harbor lokal dengan prefix `helm-repos/` untuk *chart name*-nya:
```yaml
spec:
  source:
    # SEBELUMNYA: repoURL: https://grafana.github.io/helm-charts (chart: grafana)
    repoURL: harbor-core.harbor.svc.cluster.local
    chart: helm-repos/grafana
    targetRevision: 8.10.4
```

## Proses Sync
Jika *sync* gagal di ArgoCD, komponen yang sedang berjalan di Kubernetes akan tetap aman (*tidak terganggu*). ArgoCD akan mencoba lagi dalam siklus sinkronisasi otomatis. Dengan konfigurasi Harbor internal ini, kemungkinan kegagalan karena masalah jaringan (konektivitas) sangatlah minimal.
