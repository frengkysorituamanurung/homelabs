# Observability Platform — Configuration Reference

## VictoriaMetrics (vmsingle)

- **Retention**: 30 days (`retentionPeriod: 30d`)
- **Memory**: `memory.allowedPercent: 40`
- **Max Query Length**: 65536 bytes (`search.maxQueryLen`)
- **Storage**: 10Gi PVC (local-path)
- **Service**: ClusterIP on port 8428

## Loki

- **Retention**: 30 days (`retention_period: 720h`)
- **Ingestion Rate**: 8 MB/s (`ingestion_rate_mb: 8`)
- **Per-Stream Rate Limit**: 4 MB/s (`per_stream_rate_limit: 4MB`)
- **Compactor**: Enabled, runs every 10m, retention deletion delay 2h
- **Storage**: 20Gi PVC (local-path)
- **Reject Old Samples**: true, max age 168h

## Tempo

- **Retention**: 7 days (`retention: 168h`)
- **Receivers**: OTLP gRPC (4317), OTLP HTTP (4318), Jaeger, Zipkin
- **Metrics Generator**: Enabled (service graphs, span metrics, local blocks)
- **Remote Write**: VictoriaMetrics at `http://vmsingle:8428/api/v1/write`
- **Storage**: 5Gi PVC (local-path)

## Alloy

- **OTLP Receiver**: gRPC :4317, HTTP :4318 (exposed via Service)
- **OTLP Exporter**: Tempo at `tempo.monitoring.svc.cluster.local:4317`
- **Log Processing**: CRI parsing, JSON extraction (trace_id, span_id, method, path, status, level), level template, structured metadata
- **Drop Old Logs**: `older_than: 168h`
- **Resources**: 100m CPU / 256Mi RAM request, 1 CPU / 1Gi limit

## Grafana

- **Datasources**: VictoriaMetrics (default), Loki, Tempo
- **Trace-to-Logs**: Loki derived fields matching trace_id/TraceId, links to Tempo
- **Trace-to-Metrics**: VictoriaMetrics span metrics queries
- **Service Map**: VictoriaMetrics datasource
- **Alerting**: Provisioned from ConfigMap (cluster-rules.yaml, telegram-notifiers.yaml)
- **Dashboards**: Sidecar provisioner, searchNamespace: ALL, label: grafana_dashboard

## Traefik

- **Tracing**: Enabled, OTLP gRPC to Alloy, 100% sample rate
- **Service Name**: `traefik-ingress`
- **Access Logs**: JSON format, all headers kept
- **Metrics**: Prometheus on port 9100

## Alert Rules

All alert rules are in `infrastructure/grafana/alerts-configmap.yaml` and provisioned via Grafana sidecar.

### Thresholds

| Alert | Threshold | Duration | Severity |
|---|---|---|---|
| Node RAM > 90% | 90% | 5m | Warning |
| Node CPU > 85% | 85% | 5m | Warning |
| Node Disk < 15% free | 15% | 5m | Critical |
| Node Not Ready | 0 ready | 2m | Critical |
| Pod Waiting (ImagePull/CrashLoop) | > 0 | 2m | Critical |
| Pod Restarts > 3 in 15m | 3 | 2m | Warning |
| OOMKilled | > 0 | 1m | Critical |
| Pod Unhealthy (Failed/Pending) | > 0 | 5m | Warning |
| Deployment Replica Mismatch | > 0 | 5m | Critical |
| TLS Cert < 14 days | 14 days | 5m | Warning |
| Ingress 5xx > 5% | 5% | 3m | Critical |
| Ingress P95 > 2s | 2s | 5m | Warning |
| Loki Error Logs > 50/min | 50/min | 5m | Warning |
| Alloy Down | up < 1 | 2m | Critical |
| VictoriaMetrics Down | up < 1 | 2m | Critical |
| Loki Down | up < 1 | 2m | Critical |
| Tempo Down | up < 1 | 2m | Critical |
| Scrape Target Down | up == 0 | 5m | Warning |
| Blackbox Probe Failed | probe_success == 0 | 3m | Critical |
| OTel Export Failures | dropped > 0 | 5m | Warning |