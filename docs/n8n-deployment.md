# Dokumentasi Instalasi n8n (Akses Privat via Tailscale)

Dokumen ini menjelaskan instalasi, arsitektur deployment, dan konfigurasi keamanan untuk **n8n** di cluster Kubernetes homelab `frengky.xyz`. n8n dideploy menggunakan pola **GitOps (ArgoCD)** dan dikonfigurasi agar hanya dapat diakses secara aman (HTTPS) ketika terhubung ke **Tailscale**.

---

## 🛠️ Ringkasan Arsitektur & Pola Akses

Pola akses untuk n8n dikonfigurasi secara privat menggunakan model **Tailscale-only** untuk menjaga keamanan data dan alur kerja automasi:

1. **Namespace Baru**: Dibuat namespace terdedikasi `n8n`.
2. **Domain/DNS**: Subdomain `n8n.frengky.xyz` diarahkan secara langsung ke IP Tailscale Host (`100.120.133.63`) di Cloudflare (DNS-Only / Gray Cloud). Trafik dari luar Tailscale mesh network secara alami tidak dapat merutekan ke IP CGNAT Tailscale ini.
3. **Traefik Ingress**: Ingress dikonfigurasi menggunakan Ingress Class `traefik` untuk routing internal.
4. **SSL/TLS**: SSL otomatis dilayani oleh Traefik menggunakan default TLSStore wildcard certificate (`wildcard-frengky-xyz-tls`) yang diterbitkan oleh Let's Encrypt melalui cert-manager DNS-01 Challenge.
5. **Keamanan Jaringan (DNS & Tailscale Routing)**: Karena K3s service load balancer dideploy menggunakan `externalTrafficPolicy: Cluster`, IP asli client Tailscale ditranslasikan (NAT) menjadi IP internal cluster (IP pod load balancer). Oleh karena itu, IP whitelist middleware tidak dapat diterapkan karena akan memblokir trafik valid dengan error Forbidden. Pembatasan akses sepenuhnya dilakukan di layer network/DNS dengan mengarahkan domain `n8n.frengky.xyz` secara eksklusif ke IP Tailscale Host (`100.120.133.63`).

---

## 📁 Struktur Manifest GitOps

File manifest disimpan di dalam repository GitOps (`gitops-repo`) dengan struktur berikut:

```
gitops-repo/
├── kubernetes/
│   ├── applications/
│   │   └── production/
│   │       └── n8n.yaml            # Definisi Aplikasi ArgoCD
│   └── production/
│       └── n8n/
│           ├── deployment.yaml     # Konfigurasi deployment & env n8n
│           ├── service.yaml        # Service internal cluster
│           ├── pvc.yaml            # Penyimpanan persisten (SQLite DB)
│           └── ingress.yaml        # Aturan routing Traefik & whitelist
└── docs/
    └── n8n-deployment.md           # Dokumen ini
```

### 1. Aplikasi ArgoCD (`k8s/clusters/production/apps/production/n8n.yaml`)
ArgoCD mengelola daur hidup deployment ini secara otomatis dari path `apps/production/n8n`:
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
    path: apps/production/n8n
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: n8n
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 2. Penyimpanan Persisten (`apps/production/n8n/pvc.yaml`)
n8n menyimpan data alur kerja (workflow), credentials, dan eksekusi pada database SQLite lokal. Persistent Volume Claim (PVC) dialokasikan menggunakan storage class bawaan K3s (`local-path`):
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: n8n-pvc
  namespace: n8n
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
```

### 3. Deployment n8n (`apps/production/n8n/deployment.yaml`)
Deployment n8n menggunakan image resmi `n8nio/n8n:latest`. Keamanan pod diperketat dengan `securityContext` agar berjalan sebagai user `1000` (node) agar sesuai dengan hak akses folder mount `/home/node/.n8n`.
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n
  namespace: n8n
  labels:
    app: n8n
spec:
  replicas: 1
  selector:
    matchLabels:
      app: n8n
  template:
    metadata:
      labels:
        app: n8n
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: n8n
          image: docker.io/n8nio/n8n:latest
          ports:
            - containerPort: 5678
              name: http
          env:
            - name: N8N_HOST
              value: "n8n.frengky.xyz"
            - name: N8N_PORT
              value: "5678"
            - name: N8N_PROTOCOL
              value: "https"
            - name: NODE_ENV
              value: "production"
            - name: N8N_WEBHOOK_URL
              value: "https://n8n.frengky.xyz/"
            - name: N8N_ENCRYPTION_KEY
              value: "n8n-encryption-key-for-frengky-xyz"
          volumeMounts:
            - name: n8n-storage
              mountPath: /home/node/.n8n
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "1Gi"
              cpu: "1000m"
      volumes:
        - name: n8n-storage
          persistentVolumeClaim:
            claimName: n8n-pvc
```

### 4. Service (`apps/production/n8n/service.yaml`)
Service internal cluster tipe `ClusterIP` mengekspos port 5678 n8n ke ingress controller:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: n8n
  namespace: n8n
  labels:
    app: n8n
spec:
  ports:
    - port: 5678
      targetPort: 5678
      name: http
  selector:
    app: n8n
  type: ClusterIP
```

### 5. Ingress (`apps/production/n8n/ingress.yaml`)
Ingress ini mengarahkan domain `n8n.frengky.xyz` ke service n8n:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: n8n
  namespace: n8n
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  ingressClassName: traefik
  rules:
    - host: n8n.frengky.xyz
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: n8n
                port:
                  number: 5678
```

---

## 🔍 Verifikasi Akses & Pengujian

Untuk memastikan bahwa n8n berjalan normal dan hanya dapat diakses melalui Tailscale:

1. **Verifikasi Pod & Service**:
   ```bash
   kubectl get pods,svc,ingress -n n8n
   ```
   Pastikan pod berstatus `Running` (1/1) dan ingress `n8n` telah terbuat dengan host `n8n.frengky.xyz`.

2. **Uji Resolusi DNS**:
   Pastikan resolve domain `n8n.frengky.xyz` mengarah ke IP Tailscale Host:
   ```bash
   nslookup n8n.frengky.xyz
   # Output harus mengembalikan: 100.120.133.63
   ```

3. **Uji Akses HTTP (Dengan Tailscale Aktif)**:
   Akses `https://n8n.frengky.xyz` via browser di perangkat yang terhubung ke Tailscale. Anda akan langsung melihat halaman setup n8n dengan sertifikat SSL valid (*secured*).

4. **Uji Keamanan (Tanpa Tailscale)**:
   Putuskan koneksi Tailscale pada perangkat penguji, lalu coba akses `https://n8n.frengky.xyz`. Browser tidak akan dapat memuat halaman karena IP `100.120.133.63` tidak dapat dijangkau dari internet publik. Selain itu, jika dicoba diakses melalui jaringan luar yang terhubung ke host, Traefik middleware `tailscale-whitelist` akan menolak request dengan respon `Forbidden` jika IP client tidak dikenali.
