# Observability Platform — Known Limitations

## Uninstrumented Applications

The following applications do **not** emit OpenTelemetry traces:

| Application | Namespace | Reason | Mitigation |
|---|---|---|---|
| `sample-api` | backend | Go binary, no OTel SDK | Monitored via Traefik ingress spans + logs |
| `test-gitops` | backend | Go binary, no OTel SDK | Monitored via Traefik ingress spans + logs |
| `hello-world` | frontend | Nginx static, no OTel SDK | Monitored via Traefik ingress spans + logs |
| `service-a` | production/staging | Nginx static, no OTel SDK | Monitored via Traefik ingress spans + logs |
| `mcp-bridge` | backend | Go binary with Datadog tracer (disabled) | Monitored via Traefik ingress spans + logs; `DD_TRACE_ENABLED=false` |
| `finance-frontend` | development | Nginx static | Monitored via Traefik ingress spans + logs |
| `finance-landing` | frontend | Nginx static | Monitored via Traefik ingress spans + logs |

### Applications with Partial Instrumentation

| Application | Namespace | Status | Details |
|---|---|---|---|
| `finance-backend` | development | Partial | Emits `trace_id` and `span_id` in JSON logs but does not send OTLP spans. Trace-to-logs correlation works via Loki derived fields. Full OTLP instrumentation requires adding `go.opentelemetry.io/otel` SDK to the Go source code. |

## Missing Metrics

- **Application-level metrics**: Only `finance-backend` exposes `/metrics` endpoint with custom metrics (`finance_app_info`, `http_requests_total`). Other Go apps (sample-api, test-gitops, mcp-bridge) do not expose Prometheus metrics.
- **Database metrics**: CloudNativePG exporter metrics available only for CNPG-managed clusters. Umami PostgreSQL and Immich PostgreSQL do not have dedicated exporters.
- **Redis/Valkey metrics**: No Redis exporter deployed. Redis memory usage is estimated via container metrics.
- **Qdrant metrics**: Qdrant exposes metrics on port 6333 but not currently scraped.

## Unsupported Correlation Paths

- **Trace-to-Metrics**: Tempo metrics-generator creates span metrics and service graphs, but these are only available for Traefik ingress spans (the only instrumented service).
- **Logs-to-Traces**: Loki derived fields match trace IDs in JSON logs, but only works for applications that include `trace_id` or `TraceId` in their log output.
- **Metrics-to-Traces**: Not supported (no exemplars configured in VictoriaMetrics).

## Unimplemented Alerts

- **HPA scaling events**: No HPA resources deployed.
- **PersistentVolume capacity risk**: Alert exists but uses `kube_persistentvolumeclaim_status_phase` which may not fire for local-path PVCs.
- **Backup failure**: No reliable backup signal available.
- **Certificate expiration (public domains)**: Only Traefik wildcard cert monitored; Cloudflare Tunnel certs not monitored.
- **Application error rate (per-service)**: No application-level metrics available for most services.

## Known Limitations

1. **Single-node cluster**: All observability components run on a single node. No high availability.
2. **Local-path storage**: PVCs use local-path provisioner. No replication, no snapshots.
3. **Resource constraints**: Total observability stack uses ~390m CPU / ~1.5Gi RAM. May need tuning under heavy load.
4. **No automated backups**: PVC backups are manual. Consider implementing a backup cronjob.
5. **Traefik tracing sample rate**: Set to 100% (1.0). May need reduction for high-traffic scenarios.
6. **Loki reject_old_samples**: Set to 168h. Very old logs from long-running pods may be rejected.
7. **Alloy position files**: Stored in emptyDir (/tmp/alloy). Lost on pod restart. Alloy re-tails from end of file (acceptable).
8. **No Grafana SSO**: Grafana uses basic auth (admin/password from Vault). No OIDC/LDAP integration.
9. **No multi-tenancy**: All telemetry is in a single tenant (fake/single-tenant).
10. **OpenObserve**: Deployed but scaled to 0 replicas. Not actively used. Consider removing to free resources.

## Future Improvements

1. Add OpenTelemetry SDK instrumentation to Go applications (sample-api, test-gitops, mcp-bridge, finance-backend)
2. Deploy Redis exporter for Harbor and Flux CD Redis instances
3. Implement automated PVC backup cronjob (e.g., using Velero or k8s CronJob)
4. Add Grafana OIDC authentication via Vault or Keycloak
5. Reduce Traefik tracing sample rate to 10-20% for production
6. Add per-application SLO dashboards and alerts
7. Implement log-based alerting for specific error patterns
8. Add Tempo exemplars to VictoriaMetrics for metrics-to-traces correlation
9. Deploy Pyroscope for continuous profiling
10. Consider migrating to a multi-node setup for HA