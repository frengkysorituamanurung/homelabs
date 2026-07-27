# 📊 Documentation Setup & Panduan Dashboard Monitoring Grafana

Dokumen ini menjelaskan arsitektur, cara kerja, struktur file JSON, dan langkah setup otomatis maupun manual untuk **4 Dashboard Advanced Grafana** pada cluster Kubernetes ini.

---

## 🏗️ 1. Arsitektur Monitoring Cluster

Monitoring cluster ini didukung oleh stack observabilitas modern:
- **Metrics Engine**: [VictoriaMetrics](http://vmsingle-victoria-metrics-single-server.monitoring.svc.cluster.local:8428) (Prometheus-compatible TSDB).
- **Log Engine**: [Grafana Loki](http://loki.monitoring.svc.cluster.local:3100) (Centralized Log Aggregator).
- **Metric & Log Scraper**: Grafana Alloy (Collector metrics & logs per container/pod).
- **Visualization**: Grafana (`grafana.frengky.xyz`).

---

## 📂 2. Katalog Dashboard Monitoring

Seluruh file JSON dashboard disimpan di dalam repository GitOps pada direktori:
`kubernetes/production/grafana/dashboards/`

| File Dashboard | Name & Purpose | Datasource | Key Metrics & Features |
| :--- | :--- | :--- | :--- |
| [`cluster-overview.json`](file:///root/server/gitops-repo/kubernetes/production/grafana/dashboards/cluster-overview.json) | **Cluster & Node Performance Command Center** | `VictoriaMetrics` | Node CPU/RAM/Swap, Top 10 Pod Consumers (Memory & CPU), Network Traffic In/Out (Bps), Disk Throughput (Read/Write). |
| [`k8s-workloads-health.json`](file:///root/server/gitops-repo/kubernetes/production/grafana/dashboards/k8s-workloads-health.json) | **Kubernetes Workloads & Pod Health** | `VictoriaMetrics` | Pod Running/Pending/Failed count, Container Restarts (24h tracker), Pod Memory/CPU vs Request vs Limits, PVC Disk Storage % Gauge. |
| [`loki-logs-explorer.json`](file:///root/server/gitops-repo/kubernetes/production/grafana/dashboards/loki-logs-explorer.json) | **Centralized Log Explorer & Error Tracker** | `Loki` | Log Ingestion Rate (lines/sec), Error Log Rate (errors/min), Warning Log Rate, Top Error-generating Pods, Real-time Live Log Console. |
| [`devops-services-overview.json`](file:///root/server/gitops-repo/kubernetes/production/grafana/dashboards/devops-services-overview.json) | **DevOps Platform Services Overview** | `VictoriaMetrics` | Monitoring footprint & performansi tool DevOps: **ArgoCD**, **Gitea & Runners**, **Harbor Registry**, **Vault**, dan **n8n**. |
| [`internet-network-connectivity.json`](file:///root/server/gitops-repo/kubernetes/production/grafana/dashboards/internet-network-connectivity.json) | **Internet Speed & Network Connectivity** | `VictoriaMetrics` | Kecepatan Internet Download & Upload (Mbps), Total Data Downloaded/Uploaded (GB), Network Packet Rate (pps), Drops & Errors, Top Pod Network Traffic. |

---

## ⚙️ 3. Konfigurasi Provisioning Otomatis (GitOps)

Dashboard di-provisioning secara otomatis menggunakan fitur **Grafana Sidecar Dashboard Provisioner**.

### Cara Kerja:
1. Grafana Helm release dikonfigurasi dengan `sidecar.dashboards.enabled: true` dan `label: grafana_dashboard: "1"`.
2. Setiap dashboard JSON dibungkus ke dalam `ConfigMap` Kubernetes yang memiliki label `grafana_dashboard: "1"`.
3. Sidecar container pada pod Grafana secara otomatis mendeteksi ConfigMap baru dan langsung meng-import dashboard JSON tersebut tanpa perlu restart pod.

### Manifest File:
File ConfigMap Kubernetes digabungkan di:
`kubernetes/production/grafana/dashboards-configmap.yaml`

---

## 🚀 4. Panduan Langkah Demi Langkah Setup / Menambah Dashboard Baru

### Opsi A: Melalui Repository GitOps (Direkomendasikan)

Jika Anda ingin membuat atau menambahkan dashboard JSON baru ke dalam cluster via GitOps:

1. **Simpan File JSON Dashboard**:
   Simpan file JSON dashboard baru Anda ke dalam folder:
   `kubernetes/production/grafana/dashboards/nama-dashboard.json`

2. **Generate / Update ConfigMap**:
   Tambahkan ConfigMap baru ke dalam `dashboards-configmap.yaml`:
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: grafana-dashboard-nama-dashboard
     namespace: monitoring
     labels:
       grafana_dashboard: "1"
   data:
     nama-dashboard.json: |
       <PASTE_ISI_JSON_DASHBOARD_DI_SINI>
   ```

3. **Commit & Push ke Git**:
   ```bash
   git add kubernetes/production/grafana/
   git commit -m "feat(grafana): add nama-dashboard JSON dashboard"
   git push origin main
   ```

---

### Opsi B: Import Manual via Grafana UI

1. Buka Grafana di browser: `https://grafana.frengky.xyz` (Login: `admin` / `<password>`).
2. Di menu navigasi sebelah kiri, klik **Dashboards** ➡️ **New** ➡️ **Import**.
3. Klik **Upload dashboard JSON file** dan pilih file `.json` dari folder `kubernetes/production/grafana/dashboards/`.
4. Pilih Datasource `VictoriaMetrics` (Prometheus) atau `Loki`, lalu klik **Import**.

---

### Opsi C: Import Manual via Grafana API (Terminal / Script)

Gunakan perintah cURL berikut dari terminal server untuk meng-import file JSON dashboard secara instant:

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -u admin:changeme123 \
  -d "{\"dashboard\": $(cat /root/server/gitops-repo/kubernetes/production/grafana/dashboards/cluster-overview.json), \"overwrite\": true}" \
  http://10.43.55.39/api/dashboards/db
```

---

## 🔍 5. Troubleshooting & Verifikasi

### 1. Memeriksa ConfigMap Dashboard di Cluster:
```bash
kubectl get configmaps -n monitoring -l grafana_dashboard=1
```

### 2. Memeriksa Log Sidecar Provisioner Grafana:
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard --tail=50
```

### 3. Memeriksa Datasource Grafana via API:
```bash
curl -s -u admin:changeme123 "http://10.43.55.39/api/datasources"
```
* **VictoriaMetrics**: `http://vmsingle-victoria-metrics-single-server.monitoring.svc.cluster.local:8428`
* **Loki**: `http://loki.monitoring.svc.cluster.local:3100`
