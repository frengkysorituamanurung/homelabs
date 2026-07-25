# Konfigurasi Traefik — frengky.xyz Homelab

Dokumen ini menjelaskan konfigurasi lengkap Traefik v3.7.4 sebagai Ingress Controller di k3s cluster `frengky.xyz`, mencakup entrypoints, providers, forwarded headers, middleware, SSL/TLS, dan cara melakukan perubahan konfigurasi.

---

## Versi & Info

```
Traefik Version : v3.7.4 (codename: langres)
Deployment      : k3s native (HelmChartConfig)
Namespace       : kube-system
```

---

## Cara Traefik Di-install di k3s

Traefik di k3s **tidak di-install via ArgoCD/Helm biasa**, melainkan dikelola oleh k3s itu sendiri melalui resource `HelmChartConfig`. File konfigurasi ada di:

```
helm-charts/traefik-helmchartconfig.yaml
```

Untuk apply perubahan:
```bash
kubectl apply -f /root/server/traefik-helmchartconfig.yaml
# atau jika sudah ada:
kubectl edit helmchartconfig traefik -n kube-system
```

---

## Konfigurasi Aktif Saat Ini

### HelmChartConfig (`traefik-helmchartconfig.yaml`)

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    additionalArguments:
      - "--api.insecure=true"
      # Trust Cloudflare as proxy - baca real client IP dari X-Forwarded-For
      - "--entrypoints.web.forwardedHeaders.trustedIPs=173.245.48.0/20,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,141.101.64.0/18,108.162.192.0/18,190.93.240.0/20,188.114.96.0/20,197.234.240.0/22,198.41.128.0/17,162.158.0.0/15,104.16.0.0/13,104.24.0.0/14,172.64.0.0/13,131.0.72.0/22,127.0.0.1/32,192.168.100.0/24,10.42.0.0/16"
      - "--entrypoints.websecure.forwardedHeaders.trustedIPs=173.245.48.0/20,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,141.101.64.0/18,108.162.192.0/18,190.93.240.0/20,188.114.96.0/20,197.234.240.0/22,198.41.128.0/17,162.158.0.0/15,104.16.0.0/13,104.24.0.0/14,172.64.0.0/13,131.0.72.0/22,127.0.0.1/32,192.168.100.0/24,10.42.0.0/16"
      # Enable access log untuk debug
      - "--accesslog=true"
      - "--accesslog.fields.headers.defaultmode=keep"
```

### Full Args yang Berjalan di Pod

```bash
--entryPoints.metrics.address=:9100/tcp
--entryPoints.traefik.address=:8080/tcp
--entryPoints.web.address=:8000/tcp
--entryPoints.websecure.address=:8443/tcp
--api.dashboard=true
--ping=true
--metrics.prometheus=true
--metrics.prometheus.entrypoint=metrics
--providers.kubernetescrd
--providers.kubernetescrd.allowEmptyServices=true
--providers.kubernetesingress
--providers.kubernetesingress.allowEmptyServices=true
--providers.kubernetesingress.ingressendpoint.publishedservice=kube-system/traefik
--entryPoints.websecure.http.tls=true
--log.level=INFO
--api.insecure=true
--accesslog=true
--accesslog.fields.headers.defaultmode=keep
--entrypoints.web.forwardedHeaders.trustedIPs=<cloudflare-ranges>
--entrypoints.websecure.forwardedHeaders.trustedIPs=<cloudflare-ranges>
```

---

## EntryPoints

| EntryPoint | Port (Internal) | Protokol | Keterangan |
|------------|----------------|----------|------------|
| `web` | `:8000` | HTTP | Traffic HTTP dari semua sumber |
| `websecure` | `:8443` | HTTPS/TLS | Traffic HTTPS, TLS enabled by default |
| `traefik` | `:8080` | HTTP | Dashboard & API Traefik |
| `metrics` | `:9100` | HTTP | Prometheus metrics endpoint |

> **Catatan Port:** k3s NodePort mapping: `8000→80`, `8443→443` di host. Jadi dari luar, akses ke port 80/443.

---

## Providers

Traefik dikonfigurasi dengan dua provider utama:

### 1. Kubernetes Ingress Provider (`--providers.kubernetesingress`)

Membaca resource `Ingress` standard Kubernetes:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
spec:
  ingressClassName: traefik  # wajib eksplisit di generic-app v0.1.12+
```

### 2. Kubernetes CRD Provider (`--providers.kubernetescrd`)

Membaca resource CRD Traefik seperti `IngressRoute`, `Middleware`, `TLSStore`, dll:
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
# atau
kind: Middleware
# atau
kind: TLSStore
```

---

## Forwarded Headers & IP Trust

Konfigurasi ini penting agar Traefik bisa membaca IP asli client dari header `X-Forwarded-For` ketika traffic melewati proxy (Cloudflare atau Cloudflare Tunnel).

```
# Cloudflare IP ranges yang di-trust
173.245.48.0/20
103.21.244.0/22
103.22.200.0/22
103.31.4.0/22
141.101.64.0/18
108.162.192.0/18
190.93.240.0/20
188.114.96.0/20
197.234.240.0/22
198.41.128.0/17
162.158.0.0/15
104.16.0.0/13
104.24.0.0/14
172.64.0.0/13
131.0.72.0/22

# Internal ranges
127.0.0.1/32       # Localhost
192.168.100.0/24   # LAN homelab
10.42.0.0/16       # k3s pod network
```

Fungsi: Ketika Cloudflare Tunnel meneruskan request ke Traefik, header `X-Forwarded-For` berisi IP asli client. Dengan trust list ini, Traefik tahu IP mana yang valid untuk dibaca.

---

## SSL/TLS

Traefik menggunakan **wildcard certificate** `*.frengky.xyz` yang dikelola oleh cert-manager.

### TLSStore (Default)

```yaml
apiVersion: traefik.io/v1alpha1
kind: TLSStore
metadata:
  name: default
  namespace: kube-system
spec:
  defaultCertificate:
    secretRef:
      name: wildcard-frengky-xyz-tls
```

Semua `IngressRoute` dengan entrypoint `websecure` otomatis menggunakan wildcard cert ini tanpa perlu konfigurasi tambahan.

Untuk Ingress biasa, gunakan annotation:
```yaml
annotations:
  traefik.ingress.kubernetes.io/router.entrypoints: websecure
```

---

## Middleware yang Ada

### `tailscale-whitelist` (IP Allowlist)

Tersedia di namespace: `traefik`, `argocd`, `harbor`, `monitoring`, `vault`

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: tailscale-whitelist
  namespace: traefik    # ganti sesuai namespace yang butuh
spec:
  ipAllowList:
    ipStrategy:
      depth: 1          # baca 1 hop dari X-Forwarded-For
    sourceRange:
      - 100.64.0.0/10   # Tailscale CGNAT range
      - 127.0.0.1/32    # Localhost
      - 192.168.100.0/24 # LAN
      - 10.42.0.0/16    # k3s pod network
```

Cara pakai di IngressRoute:
```yaml
spec:
  routes:
    - middlewares:
        - name: tailscale-whitelist
          namespace: traefik
```

> **Catatan:** Untuk apps dengan akses VPN-only, middleware ini **tidak wajib** jika DNS sudah diarahkan ke IP Tailscale (100.120.133.63). Middleware ini berguna sebagai layer tambahan jika diperlukan.

---

## Dashboard Traefik

Dashboard tersedia via IngressRoute (restricted to localhost/LAN):

```
URL Internal: http://traefik.frengky.xyz/dashboard/
```

IngressRoute-nya:
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: kube-system
spec:
  entryPoints:
    - web
  routes:
    - match: (Host(`traefik.frengky.xyz`) || Host(`localhost`)) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))
      kind: Rule
      services:
        - name: api@internal
          kind: TraefikService
```

Atau akses langsung via port-forward:
```bash
kubectl port-forward -n kube-system svc/traefik 9000:9000
# Buka: http://localhost:9000/dashboard/
```

---

## Cara Menambah Konfigurasi Baru

### Menambah Argument ke Traefik

Edit `HelmChartConfig`:
```bash
kubectl edit helmchartconfig traefik -n kube-system
```

Tambahkan di `spec.valuesContent.additionalArguments`:
```yaml
- "--new-argument=value"
```

k3s akan otomatis restart pod Traefik setelah perubahan.

### Menambah App Baru (VPN-only)

1. Tambahkan A record di Cloudflare DNS → `100.120.133.63` (DNS Only)
2. Buat Ingress dengan `ingressClassName: traefik`
3. Deploy via GitOps (ArgoCD)

### Menambah App Baru (Public via Tunnel)

1. Konfigurasi public hostname di Cloudflare Zero Trust dashboard
2. Service: `http://traefik.kube-system.svc.cluster.local:80`
3. Buat Ingress dengan `ingressClassName: traefik` (sama, tidak ada perbedaan)

---

## Monitoring & Debug

```bash
# Cek status pod Traefik
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# Lihat logs Traefik (access log + error)
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=100

# Cek semua Ingress di cluster
kubectl get ingress -A

# Cek konfigurasi aktif via API Traefik
kubectl port-forward -n kube-system svc/traefik 9000:9000 &
curl http://localhost:9000/api/http/routers | python3 -m json.tool | head -100

# Cek middleware terdaftar
kubectl get middleware -A

# Cek IngressRoutes
kubectl get ingressroutes -A

# Describe Traefik pod untuk lihat args lengkap
kubectl describe pod -n kube-system -l app.kubernetes.io/name=traefik
```

---

## Referensi Annotation Traefik untuk Ingress

```yaml
metadata:
  annotations:
    # Force HTTPS only
    traefik.ingress.kubernetes.io/router.entrypoints: websecure

    # Apply middleware (format: namespace-name@kubernetescrd)
    traefik.ingress.kubernetes.io/router.middlewares: traefik-tailscale-whitelist@kubernetescrd

    # Custom router priority
    traefik.ingress.kubernetes.io/router.priority: "10"

    # Strip prefix
    traefik.ingress.kubernetes.io/router.middlewares: default-strip-prefix@kubernetescrd
```
