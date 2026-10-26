# Observability Platform — Dashboards

## Dashboard Catalog

All 15 dashboards are in `infrastructure/grafana/dashboards/` and provisioned via ConfigMaps.

### Core Observability (7 dashboards)

| # | Dashboard | UID | Purpose | Key Panels |
|---|---|---|---|---|
| 1 | Home Server Overview | `homelab-home-dashboard` | Primary landing dashboard | Node readiness, CPU/RAM/disk, probes, alerts, network, TLS cert, recent events |
| 2 | Kubernetes Cluster & Workloads | `k8s-workloads-health` | Workload health | Running/pending/failed pods, deployments, statefulsets, top pods by memory/CPU, API server |
| 3 | Node & Infrastructure | `physical-server-monitoring` | Host hardware | CPU breakdown, load, RAM/swap, disk I/O, network throughput, errors/drops |
| 4 | Application Monitoring (Golden Signals) | `app-http-golden-signals` | App performance | RPS, 5xx/4xx error %, P95 latency, synthetic probes, finance-backend uptime |
| 5 | Logs & Troubleshooting | `loki-logs-explorer` | Log investigation | Log ingestion rate, error/warning rates, top error pods, live log stream |
| 6 | Distributed Tracing (Tempo & OTel) | `distributed-tracing-tempo` | Trace investigation | OTLP spans received/exported, service graph, P95 latency, recent traces table |
| 7 | Observability Stack Health | `observability-stack-health` | Self-monitoring | Component UP/DOWN status, scrape targets, ingestion rates, resource usage |

### Platform & Add-ons (8 dashboards)

| Dashboard | UID | Purpose |
|---|---|---|
| Cluster & Node Performance Command Center | `cluster-node-overview` | Node CPU/RAM/network/disk overview |
| CloudNativePG Overview | `cnpg-overview` | PostgreSQL cluster health |
| Database & Cache Health | `database-cache-health` | PostgreSQL, Redis, Qdrant memory |
| DevOps Platform Services Overview | `devops-services-overview` | Flux, Harbor, Vault, n8n memory/CPU |
| Internet Speed & Network Connectivity | `internet-network-connectivity` | Internet download/upload speed |
| Kubernetes Cluster Events & OOMKilled Tracker | `k8s-events-failures` | OOMKilled, restart spikes, waiting pods |
| Security, SSL Certificates & Vault | `security-certificates-vault` | TLS cert expiry, Vault memory |
| Traefik Ingress Traffic & Domain Latency | `ingress-traffic-latency` | Ingress RPS, status codes, latency |

## Investigation Workflows

### Investigating an Unhealthy Pod

1. Open **Dashboard 2 (Kubernetes Cluster & Workloads)**
2. Check "Failed Pods" and "Pending / Unschedulable" stat panels
3. Look at "Container Restart Rate & Waiting Containers" time series
4. Open **Dashboard 5 (Logs & Troubleshooting)**
5. Set namespace/pod filters, search for error/exception/panic
6. Check Loki for `level=error` logs with structured metadata `trace_id`
7. If trace_id present, click "Inspect Trace in Tempo" to open trace waterfall

### Investigating a Slow Request

1. Open **Dashboard 4 (Application Monitoring)** → check P95 Response Latency
2. Open **Dashboard 6 (Distributed Tracing)** → check Service Graph P95 Latency
3. In Grafana Explore → Tempo → search by service name or trace ID
4. Inspect span waterfall for slow spans
5. Click "Logs for this span" to see correlated logs
6. Check Traefik access logs in Loki for the same trace_id

### Searching Application Logs

1. Open **Dashboard 5 (Logs & Troubleshooting)**
2. Set Namespace, Pod, and Level filters
3. Use Search Text box for keywords or trace IDs
4. Or open Grafana Explore → Loki → use LogQL:
   - Errors: `{cluster="homelabs", namespace="backend"} |~ "(?i)(error|exception|fatal)"`
   - By trace ID: `{cluster="homelabs"} |= "trace_id_value"`
   - K8s events: `{cluster="homelabs", source="k8s-events"} |= "type=Warning"`