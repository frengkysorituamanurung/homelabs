# Observability Platform — Installation Guide

## Prerequisites

- K3s cluster v1.36+ with Flux CD bootstrapped
- Helm repositories: `grafana`, `prometheus-community`, `victoriametrics`
- Vault + External Secrets Operator configured
- Git repository access (GitHub: frengkysorituamanurung/homelabs)

## Deployment Order

1. **VictoriaMetrics** (metrics backend) — `infrastructure/vmsingle/flux/`
2. **Loki** (log backend) — `infrastructure/loki/flux/`
3. **Tempo** (trace backend) — `infrastructure/tempo/flux/`
4. **Node Exporter + Kube-State-Metrics** — `infrastructure/node-exporter/`, `infrastructure/kube-state-metrics/`
5. **Alloy** (collector agent) — `infrastructure/alloy/flux/`
6. **Grafana** (visualization) — `infrastructure/grafana-production/flux/`
7. **Grafana Configs** (dashboards + alerts) — `infrastructure/grafana/`
8. **Traefik** (ingress + tracing) — `infrastructure/ingress/`

## Configuration Files

| File | Purpose |
|---|---|
| `infrastructure/vmsingle/flux/helmrelease.yaml` | VictoriaMetrics HelmRelease with retention and resource limits |
| `infrastructure/loki/flux/helmrelease.yaml` | Loki HelmRelease with compactor, retention, and ingestion limits |
| `infrastructure/tempo/flux/helmrelease.yaml` | Tempo HelmRelease with OTLP receivers and metrics-generator |
| `infrastructure/alloy/flux/helmrelease.yaml` | Alloy HelmRelease with full Alloy config (metrics, logs, traces) |
| `infrastructure/grafana-production/flux/helmrelease.yaml` | Grafana HelmRelease with datasources, sidecar, and alerting |
| `infrastructure/grafana/alerts-configmap.yaml` | Grafana alert rules and Telegram contact point |
| `infrastructure/grafana/dashboards-configmap.yaml` | Dashboard ConfigMaps (13 dashboards) |
| `infrastructure/ingress/traefik-helmchartconfig.yaml` | Traefik HelmChartConfig with tracing and JSON access logs |

## Verification

```bash
# Check all pods
kubectl get pods -n monitoring

# Check HelmReleases
kubectl get hr -n flux-system | grep -E "vmsingle|loki|tempo|alloy|grafana"

# Check datasources in Grafana
GF_PASS=$(kubectl get secret grafana-credentials -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl exec -n monitoring deploy/grafana-production -c grafana -- \
  wget -qO- "http://admin:${GF_PASS}@127.0.0.1:3000/api/datasources"

# Check Tempo traces
kubectl exec -n monitoring deploy/grafana-production -c grafana -- \
  wget -qO- "http://tempo.monitoring.svc.cluster.local:3200/api/search?limit=5"

# Check Loki logs
kubectl exec -n monitoring deploy/grafana-production -c grafana -- \
  wget -qO- "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/labels"

# Check Alloy OTLP metrics
kubectl exec -n monitoring deploy/grafana-production -c grafana -- \
  wget -qO- "http://alloy.monitoring.svc.cluster.local:12345/metrics" | grep otelcol_receiver_accepted_spans
```

## Upgrade Instructions

1. Update chart version in the respective HelmRelease YAML
2. Commit and push to Git
3. Flux will automatically reconcile within 5 minutes
4. Or force reconcile: `kubectl annotate hr <name> -n flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite`

## Rollback

```bash
# Revert to previous Git commit
git revert HEAD
git push origin main

# Or suspend Flux reconciliation
kubectl patch ks <name> -n flux-system --type=merge -p '{"spec":{"suspend":true}}'
```