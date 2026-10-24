# 📊 Grafana Monitoring Dashboard Setup & Guide

This document describes the architecture, how it works, the JSON file structure, and both automatic and manual setup steps for the **4 Advanced Grafana Dashboards** on this Kubernetes cluster.

---

## 🏗️ 1. Cluster Monitoring Architecture

This cluster's monitoring is powered by a modern observability stack:

- **Metrics Engine**: [VictoriaMetrics](http://vmsingle-victoria-metrics-single-server.monitoring.svc.cluster.local:8428) (Prometheus-compatible TSDB).
- **Log Engine**: [Grafana Loki](http://loki.monitoring.svc.cluster.local:3100) (Centralized Log Aggregator).
- **Metric & Log Scraper**: Grafana Alloy (Per-container/pod metrics & logs collector).
- **Visualization**: Grafana (`grafana.frengky.xyz`).

---

## 📂 2. Monitoring Dashboard Catalog

All dashboard JSON files are stored in the GitOps repository at:
`infrastructure/grafana/dashboards/`

| Dashboard File | Name & Purpose | Datasource | Key Metrics & Features |
| :--- | :--- | :--- | :--- |
| [`cluster-overview.json`](file:///root/server/gitops-repo/infrastructure/grafana/dashboards/cluster-overview.json) | **Cluster & Node Performance Command Center** | `VictoriaMetrics` | Node CPU/RAM/Swap, Top 10 Pod Consumers (Memory & CPU), Network Traffic In/Out (Bps), Disk Throughput (Read/Write). |
| [`k8s-workloads-health.json`](file:///root/server/gitops-repo/infrastructure/grafana/dashboards/k8s-workloads-health.json) | **Kubernetes Workloads & Pod Health** | `VictoriaMetrics` | Pod Running/Pending/Failed count, Container Restarts (24h tracker), Pod Memory/CPU vs Request vs Limits, PVC Disk Storage % Gauge. |
| [`loki-logs-explorer.json`](file:///root/server/gitops-repo/infrastructure/grafana/dashboards/loki-logs-explorer.json) | **Centralized Log Explorer & Error Tracker** | `Loki` | Log Ingestion Rate (lines/sec), Error Log Rate (errors/min), Warning Log Rate, Top Error-generating Pods, Real-time Live Log Console. |
| [`devops-services-overview.json`](file:///root/server/gitops-repo/infrastructure/grafana/dashboards/devops-services-overview.json) | **DevOps Platform Services Overview** | `VictoriaMetrics` | Monitoring footprint & performance of DevOps tools: **ArgoCD**, **Gitea & Runners**, **Harbor Registry**, **Vault**, and **n8n**. |
| [`internet-network-connectivity.json`](file:///root/server/gitops-repo/infrastructure/grafana/dashboards/internet-network-connectivity.json) | **Internet Speed & Network Connectivity** | `VictoriaMetrics` | Internet Download & Upload Speed (Mbps), Total Data Downloaded/Uploaded (GB), Network Packet Rate (pps), Drops & Errors, Top Pod Network Traffic. |
| [`database-cache-health.json`](file:///root/server/gitops-repo/infrastructure/grafana/dashboards/database-cache-health.json) | **Database & Cache Health** | `VictoriaMetrics` | Performance & RAM allocation for **PostgreSQL** (Gitea/Harbor), **Redis Caches** (Harbor/ArgoCD), and **Qdrant Vector DB**. |
| [`security-certificates-vault.json`](file:///root/server/gitops-repo/infrastructure/grafana/dashboards/security-certificates-vault.json) | **Security, SSL Certificates & Vault** | `VictoriaMetrics` | Days remaining countdown for Traefik TLS/SSL Certificate expiry (`*.frengky.xyz`), Vault Unsealer status, and ExternalSecrets operator footprint. |
| [`ingress-traffic-latency.json`](file:///root/server/gitops-repo/infrastructure/grafana/dashboards/ingress-traffic-latency.json) | **Traefik Ingress Traffic & Domain Latency** | `VictoriaMetrics` | Total Ingress Request Rate (RPS), Traefik Active Open Connections, HTTP Response Status Codes (2xx, 3xx, 4xx, 5xx), P50/P90/P99 Request Duration Latency (ms). |
| [`k8s-events-failures.json`](file:///root/server/gitops-repo/infrastructure/grafana/dashboards/k8s-events-failures.json) | **Kubernetes Cluster Events & OOMKilled Tracker** | `VictoriaMetrics` & `Loki` | OOMKilled Container Counter, Spike Restarts Timeline, Unhealthy Pod Waiting Reasons, and Real-time Log Stream Error/Failure Cluster. |

---

## ⚙️ 3. Automatic Provisioning Configuration (GitOps)

Dashboards are provisioned automatically using the **Grafana Sidecar Dashboard Provisioner** feature.

### How it works:
1. The Grafana Helm release is configured with `sidecar.dashboards.enabled: true` and `label: grafana_dashboard: "1"`.
2. Each dashboard JSON is wrapped into a Kubernetes `ConfigMap` carrying the label `grafana_dashboard: "1"`.
3. The sidecar container on the Grafana pod automatically detects new ConfigMaps and imports the dashboard JSON without needing to restart the pod.

### Manifest File:
The Kubernetes ConfigMap is combined at:
`infrastructure/grafana/dashboards-configmap.yaml`

---

## 🚀 4. Step-by-Step Setup Guide / Adding a New Dashboard

### Option A: Via the GitOps Repository (Recommended)

If you want to create or add a new dashboard JSON into the cluster via GitOps:

1. **Save the Dashboard JSON File**:
   Save your new dashboard JSON file into the folder:
   `infrastructure/grafana/dashboards/nama-dashboard.json`

2. **Generate / Update the ConfigMap**:
   Add a new ConfigMap to `dashboards-configmap.yaml`:
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
       <PASTE_DASHBOARD_JSON_CONTENT_HERE>
   ```

3. **Commit & Push to Git**:
   ```bash
   git add infrastructure/grafana/
   git commit -m "feat(grafana): add nama-dashboard JSON dashboard"
   git push origin main
   ```

---

### Option B: Manual Import via Grafana UI

1. Open Grafana in the browser: `https://grafana.frengky.xyz` (Login: `admin` / `<password>`).
2. In the left navigation menu, click **Dashboards** ➡️ **New** ➡️ **Import**.
3. Click **Upload dashboard JSON file** and select the `.json` file from the `infrastructure/grafana/dashboards/` folder.
4. Select the Datasource `VictoriaMetrics` (Prometheus) or `Loki`, then click **Import**.

---

### Option C: Manual Import via Grafana API (Terminal / Script)

Use the following cURL command from the server terminal to instantly import a dashboard JSON file:

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -u admin:changeme123 \
  -d "{\"dashboard\": $(cat /root/server/gitops-repo/infrastructure/grafana/dashboards/cluster-overview.json), \"overwrite\": true}" \
  http://10.43.55.39/api/dashboards/db
```

---

## 🔍 5. Troubleshooting & Verification

### 1. Checking the Dashboard ConfigMap in the Cluster:
```bash
kubectl get configmaps -n monitoring -l grafana_dashboard=1
```

### 2. Checking the Grafana Sidecar Provisioner Logs:
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard --tail=50
```

### 3. Checking the Grafana Datasource via API:
```bash
curl -s -u admin:changeme123 "http://10.43.55.39/api/datasources"
```
* **VictoriaMetrics**: `http://vmsingle-victoria-metrics-single-server.monitoring.svc.cluster.local:8428`
* **Loki**: `http://loki.monitoring.svc.cluster.local:3100`