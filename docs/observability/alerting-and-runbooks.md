# Observability Platform — Alerting & Runbooks

## Severity Definitions

| Severity | Meaning | Response Time | Notification |
|---|---|---|---|
| **Critical** | Service down or data loss imminent | < 15 min | Telegram (immediate) |
| **Warning** | Degraded performance or resource pressure | < 1 hour | Telegram (grouped) |
| **Info** | Informational, no action required | Next business day | Telegram (batched) |

## Notification Routing

- **Contact Point**: Telegram-Alerts (bot: @mcpdokubot, chat ID: 6170551940)
- **Grouping**: By alertname, namespace, pod, job, reason
- **Group Wait**: 30s
- **Group Interval**: 5m
- **Repeat Interval**: 4h

## Alert Catalog

### Cluster-Pod-Health-Alerts

| Alert | UID | Severity | Expression | Threshold | Duration |
|---|---|---|---|---|---|
| Pod ImagePullBackOff or Container Crash Waiting | rule-v3-pod-waiting | Critical | `kube_pod_container_status_waiting_reason{reason=~"ImagePullBackOff\|CrashLoopBackOff\|..."}` | > 0 | 2m |
| Pod Container High Restart Spike | rule-v3-pod-restarts | Warning | `increase(kube_pod_container_status_restarts_total[15m])` | > 3 | 2m |
| Pod Container Terminated via OOMKilled | rule-v3-container-oom | Critical | `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}` | > 0 | 1m |
| Pod Container Unhealthy Phase | rule-v3-pod-unhealthy | Warning | `kube_pod_status_phase{phase=~"Failed\|Pending"}` | > 0 | 5m |
| Deployment Replica Mismatch | rule-v3-deployment-rollout | Critical | `kube_deployment_spec_replicas - kube_deployment_status_replicas_available` | > 0 | 5m |

### Cluster-Node-Resource-Alerts

| Alert | UID | Severity | Expression | Threshold | Duration |
|---|---|---|---|---|---|
| Kubernetes Node Not Ready | rule-v3-node-not-ready | Critical | `kube_node_status_condition{condition="Ready", status="true"}` | < 1 | 2m |
| Node RAM Memory > 90% | rule-v3-node-mem | Warning | `(MemTotal - MemAvailable) / MemTotal * 100` | > 90% | 5m |
| Node CPU > 85% | rule-v3-node-cpu | Warning | `100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` | > 85% | 5m |
| Node Root Storage < 15% free | rule-v3-node-disk | Critical | `avail_bytes / size_bytes * 100` | < 15% | 5m |

### Cluster-Services-Alerts

| Alert | UID | Severity | Expression | Threshold | Duration |
|---|---|---|---|---|---|
| TLS Certificate < 14 days | rule-v3-tls-expiring | Warning | `(traefik_tls_certs_not_after - time()) / 86400` | < 14 | 5m |
| Database/Redis RAM > 800MB | rule-v3-database-mem | Warning | `container_memory_working_set_bytes{pod=~".*(postgresql\|database\|redis).*"}` | > 800MB | 5m |
| Traefik 5xx > 5% | rule-v3-ingress-5xx | Critical | `rate(traefik_entrypoint_requests_total{code=~"5.."}[5m]) / rate(...[5m]) * 100` | > 5% | 3m |
| Ingress P95 > 2s | rule-v3-ingress-latency | Warning | `histogram_quantile(0.95, ...traefik_service_request_duration_seconds_bucket...)` | > 2s | 5m |
| Loki Error Logs > 50/min | rule-v3-loki-errors | Warning | `sum(rate({namespace=~"backend\|production\|..."} \|~ "error\|exception\|fatal\|panic" [5m])) * 60` | > 50/min | 5m |

### Observability-Platform-Alerts

| Alert | UID | Severity | Expression | Threshold | Duration |
|---|---|---|---|---|---|
| Alloy Collector Down | obs-alloy-down | Critical | `max(up{pod=~"alloy-.*"})` | < 1 | 2m |
| VictoriaMetrics Down | obs-victoriametrics-down | Critical | `max(up{pod=~"vmsingle-.*"})` | < 1 | 2m |
| Loki Down | obs-loki-down | Critical | `max(up{pod="loki-0"})` | < 1 | 2m |
| Tempo Down | obs-tempo-down | Critical | `max(up{pod="tempo-0"})` | < 1 | 2m |
| Scrape Target Down | obs-scrape-target-down | Warning | `up{cluster="homelabs"} == 0` | > 0 | 5m |
| Blackbox Probe Failed | obs-blackbox-probe-failed | Critical | `probe_success{cluster="homelabs"} == 0` | > 0 | 3m |
| OTel Export Failures | obs-otel-export-failed | Warning | `rate(loki_write_dropped_bytes_total) + rate(otelcol_exporter_send_failed_spans_total)` | > 0 | 5m |

## Runbook: Alert Response

### Critical Alerts

1. **Check Grafana** → Alerting → Alert Rules → find the firing alert
2. **Open the dashboard** linked in the alert annotation (runbook_url)
3. **Investigate** using the dashboard panels and correlated logs/traces
4. **Mitigate** using the appropriate recovery steps
5. **Verify** the alert resolves (check Telegram for ✅ RESOLVED message)

### Common Recovery Steps

| Alert | Recovery |
|---|---|
| Node Not Ready | Check `kubectl describe node homelabs`, restart k3s if needed |
| OOMKilled | Increase memory limits in HelmRelease, restart pod |
| ImagePullBackOff | Check Harbor registry, verify pull secret, check Vault |
| CrashLoopBackOff | Check pod logs: `kubectl logs -n <ns> <pod> --previous` |
| Disk < 15% | Clean old logs: `kubectl exec -n monitoring loki-0 -c loki -- rm -rf /var/loki/chunks/*` (careful!) |
| Scrape Target Down | Check pod health, verify Alloy config, restart Alloy |
| OTel Export Failures | Check Alloy logs, verify Tempo/Loki endpoints |