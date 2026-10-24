# Grafana Dashboards & Monitoring Setup

Panduan lengkap mengenai arsitektur monitoring, setup otomatis via GitOps ConfigMap, serta dokumentasi 4 Dashboard Advanced Grafana dapat dilihat di dokumen berikut:

📄 [**GRAFANA_MONITORING_SETUP.md**](file:///root/server/gitops-repo/docs/GRAFANA_MONITORING_SETUP.md)

## Struktur Folder:
- `dashboards/`: Berisi file JSON dashboard murni (tanpa icon/emoji).
  - [`cluster-overview.json`](file:///root/server/gitops-repo/infrastructure/grafana/dashboards/cluster-overview.json)
  - [`k8s-workloads-health.json`](file:///root/server/gitops-repo/infrastructure/grafana/dashboards/k8s-workloads-health.json)
  - [`loki-logs-explorer.json`](file:///root/server/gitops-repo/infrastructure/grafana/dashboards/loki-logs-explorer.json)
  - [`devops-services-overview.json`](file:///root/server/gitops-repo/infrastructure/grafana/dashboards/devops-services-overview.json)
- `dashboards-configmap.yaml`: Manifest ConfigMap Kubernetes yang dibaca secara otomatis oleh Sidecar Grafana (`label: grafana_dashboard: "1"`).
- `values.yaml`: Helm values untuk Grafana release di cluster.
