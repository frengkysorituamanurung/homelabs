# GitOps Cert-Manager & Wildcard Let's Encrypt SSL (Tailscale Only Access)

Dokumentasi ini menjelaskan konfigurasi, arsitektur, dan alur kerja (*workflow*) untuk implementasi **cert-manager** menggunakan Let's Encrypt (DNS-01 Challenge via Cloudflare) dalam pola **GitOps (ArgoCD)** agar subdomain `*.frengky.xyz` dapat diakses secara privat via Tailscale secara aman (HTTPS tanpa SSL warning).

---

## 📖 Latar Belakang & Motivasi

Sebelumnya, aplikasi seperti GitLab, ArgoCD, Grafana, dll., diakses secara publik menggunakan Cloudflare Tunnel dan dilindungi oleh Cloudflare Access. Untuk memindahkan akses agar sepenuhnya bersifat privat (hanya bisa diakses saat terhubung ke **Tailscale**):
1. Domain DNS dipindahkan dari Cloudflare Proxy (Orange Cloud) menjadi **DNS-Only (Gray Cloud)** dan diarahkan ke IP private Tailscale host (`100.120.133.63`).
2. Karena trafik tidak lagi melewati Edge Proxy Cloudflare, enkripsi SSL/TLS harus diterminasi langsung di dalam cluster (pada Ingress Controller/Traefik).
3. Untuk menghindari peringatan *"Not Secure"* di browser tanpa perlu mengimpor sertifikat manual ke setiap device, kita menggunakan **cert-manager** untuk menerbitkan sertifikat resmi gratis dari **Let's Encrypt** menggunakan metode **DNS-01 Challenge**.

---

## 🌐 Workaround Kendala Network Egress (Pod Egress Timeout)

Dalam cluster ini, pod yang berjalan di dalam CNI network (`10.42.0.0/16`) mengalami kendala rute keluar (outbound TCP port 80/443 timeout), sedangkan host utama memiliki akses internet normal. Hal ini menyebabkan controller `cert-manager` mengalami timeout saat mencoba mendaftar ke server Let's Encrypt directory (`acme-v02.api.letsencrypt.org`).

### Solusi: Host Network Workaround
Untuk mengatasi masalah ini, manifest deployment controller `cert-manager` dipatch secara deklaratif di GitOps:
* **`hostNetwork: true`**: Memaksa pod `cert-manager` berjalan di network namespace host utama (sehingga memiliki akses internet langsung).
* **`dnsPolicy: ClusterFirstWithHostNet`**: Memastikan pod tetap dapat menyelesaikan DNS internal Kubernetes (seperti membaca rahasia token API Cloudflare) sembari menggunakan network host.

---

## 🛠️ Struktur File GitOps

Seluruh komponen dideklarasikan di dalam repositori GitOps:

### 1. ArgoCD Application Manifest
Dideklarasikan di `argocd/applications/infrastructure/cert-manager.yaml`. Manifest ini mendaftarkan aplikasi cert-manager ke ArgoCD.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default
  source:
    path: infrastructure/cert-manager
    repoURL: http://gitlab-http.gitlab.svc.cluster.local/devops/gitops.git
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

### 2. K3s Deployment Manifests
Terdapat di direktori `infrastructure/cert-manager/`:
* **`cert-manager.yaml`**: Manifest resmi `cert-manager v1.15.1` yang telah disesuaikan dengan konfigurasi `hostNetwork: true` pada deployment controller utama.
* **`cert-manager-manifests.yaml`**: Berisi konfigurasi `ClusterIssuer` (konektor Let's Encrypt) dan `Certificate` (definisi sertifikat wildcard `*.frengky.xyz`).
* **`tlsstore-default.yaml`**: Konfigurasi Traefik `default` TLSStore agar otomatis menyajikan sertifikat wildcard `wildcard-frengky-xyz-tls` dari namespace `kube-system` sebagai sertifikat SSL default untuk semua router HTTPS.

---

## 🔑 Setup Awal & Pemeliharaan

### 1. Kebutuhan Token API Cloudflare
Untuk melakukan DNS-01 Challenge, buat API Token di Cloudflare Profile dengan izin:
* **Zone** ➔ **Zone** ➔ **Read** (Wajib, agar cert-manager bisa mencari Zone ID)
* **Zone** ➔ **DNS** ➔ **Edit** (Wajib, agar cert-manager bisa membuat TXT challenge)

Terapkan token tersebut ke Kubernetes cluster secara manual (jangan masukkan token ini ke Git!):
```bash
kubectl create secret generic cloudflare-api-token-secret \
  --from-literal=api-token="YOUR_CLOUDFLARE_API_TOKEN" \
  -n cert-manager
```

### 2. DNS Setup di Cloudflare
Hapus rute Cloudflare Tunnel yang mengarah ke subdomain, lalu ganti dengan **A Record** DNS-Only (Gray Cloud) ke IP Tailscale:
* **Host**: `gitlab`, `argocd`, `grafana`, `vault`, `harbor`, `glance`
* **Target IP**: `100.120.133.63` (IP Tailscale Server)
* **Proxy Status**: Gray Cloud (DNS Only)

### 3. Monitoring Sertifikat
Gunakan perintah berikut untuk memantau siklus hidup sertifikat:
```bash
# Cek apakah sertifikat berstatus READY: True
kubectl get certificate -n kube-system

# Cek status order cert-manager
kubectl get orders -n kube-system

# Cek log jika terjadi kendala verifikasi DNS-01
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager --tail=100
```
