# Observability Platform — Audit Report

## Initial Environment Inventory

### Cluster Topology

| Item | Value |
|---|---|
| Cluster name | `homelabs` |
| Kubernetes version | v1.36.2+k3s1 |
| Nodes | 1 (control-plane, WSL2 Ubuntu 26.04) |
| CPU | 16 cores |
| Memory | ~16 GiB |
| Disk | ~1 TB (local-path storage class) |
| CNI | Flannel (VXLAN) |
| Ingress | Traefik v3.7.4 |
| GitOps | Flux CD |
| Secret Management | HashiCorp Vault + External Secrets Operator |

### Existing Observability Components (Before)

| Component | Namespace | Version | Status |
|---|---|---|---|
| Grafana | monitoring | 12.3.1 | ✅ Running |
| VictoriaMetrics | monitoring | v1.154.0 | ✅ Running |
| Loki | monitoring | 3.6.16 | ✅ Running |
| Grafana Alloy | monitoring | v1.21.2 | ✅ Running |
| Node Exporter | monitoring | v1.12.1 | ✅ Running |
| Kube-State-Metrics | monitoring | v2.20.0 | ✅ Running |
| Blackbox Exporter | monitoring | v0.29.1 | ✅ Running |
| OpenObserve | openobserve | v0.91.1 | ✅ Running (scaled to 0) |

### Identified Gaps (Before Implementation)

| # | Gap | Severity | Status |
|---|---|---|---|
| 1 | No distributed tracing backend (Tempo/Jaeger) | High | ✅ Fixed |
| 2 | No OTLP receiver for traces | High | ✅ Fixed |
| 3 | Traefik tracing not enabled | High | ✅ Fixed |
| 4 | Grafana has no Tempo datasource | High | ✅ Fixed |
| 5 | No trace-to-logs correlation | Medium | ✅ Fixed |
| 6 | Loki JSON log parsing not extracting trace_id | Medium | ✅ Fixed |
| 7 | Alert rules used invalid datasource UIDs (P4169...) | High | ✅ Fixed |
| 8 | Telegram notifier used hardcoded token placeholder | High | ✅ Fixed |
| 9 | DatasourceNoData alerts firing (bad expressions) | Medium | ✅ Fixed |
| 10 | Alloy service missing OTLP ports | Medium | ✅ Fixed |
| 11 | No observability stack self-monitoring dashboard | Low | ✅ Fixed |
| 12 | No distributed tracing dashboard | Low | ✅ Fixed |
| 13 | Traefik metrics scrape returning 404 (no /metrics path) | Medium | ✅ Fixed |
| 14 | Loki reject_old_samples too strict (168h) | Low | ✅ Fixed |
| 15 | No node readiness alert | Medium | ✅ Fixed |
| 16 | No deployment rollout alert | Medium | ✅ Fixed |
| 17 | No OTel export failure alert | Low | ✅ Fixed |

### Resource Usage Before/After

| Component | CPU Request Before | CPU Request After | Memory Request Before | Memory Request After |
|---|---|---|---|---|
| VictoriaMetrics | 0m | 100m | 0Mi | 512Mi |
| Loki | 0m | 100m | 0Mi | 256Mi |
| Alloy | 110m | 100m | 306Mi | 256Mi |
| Grafana | 0m | 100m | 0Mi | 256Mi |
| Tempo | N/A (new) | 50m | N/A | 128Mi |
| Node Exporter | 0m | 20m | 0Mi | 24Mi |
| Kube-State-Metrics | 0m | 20m | 0Mi | 32Mi |
| **Total** | **~110m** | **~390m** | **~306Mi** | **~1.47Gi** |

### Security Considerations

- No observability endpoints exposed publicly (all ClusterIP)
- Grafana admin credentials stored in Vault, synced via ESO
- Telegram bot token stored in Vault, synced via ESO, injected via env var
- No secrets committed to Git
- Alloy RBAC uses minimal ClusterRole for pod/log discovery
- Tempo uses non-root security context (UID 10001)