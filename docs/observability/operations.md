# Observability Platform — Operations

## Daily Health Checks

```bash
# 1. Check all monitoring pods
kubectl get pods -n monitoring

# 2. Check HelmRelease status
kubectl get hr -n flux-system | grep -E "vmsingle|loki|tempo|alloy|grafana|node-exporter|kube-state-metrics"

# 3. Check scrape targets
kubectl exec -n monitoring vmsingle-victoria-metrics-single-server-0 -- \
  wget -qO- 'http://127.0.0.1:8428/api/v1/query?query=up{cluster="homelabs"}' | \
  python3 -c "import sys,json; r=json.load(sys.stdin)['data']['result']; print('UP:', sum(1 for x in r if x['value'][1]=='1'), 'DOWN:', sum(1 for x in r if x['value'][1]=='0'))"

# 4. Check Loki ingestion
kubectl exec -n monitoring deploy/grafana-production -c grafana -- \
  wget -qO- 'http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/labels'

# 5. Check Tempo traces
kubectl exec -n monitoring deploy/grafana-production -c grafana -- \
  wget -qO- 'http://tempo.monitoring.svc.cluster.local:3200/api/search?limit=1'

# 6. Check Grafana alerts
GF_PASS=$(kubectl get secret grafana-credentials -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl exec -n monitoring deploy/grafana-production -c grafana -- \
  wget -qO- "http://admin:${GF_PASS}@127.0.0.1:3000/api/prometheus/grafana/api/v1/rules" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print('Rules:', sum(len(g.get('rules',[])) for g in d.get('data',{}).get('groups',[])))"
```

## Routine Maintenance

### Weekly
- Review Grafana alert history for false positives
- Check VictoriaMetrics storage usage: `kubectl exec -n monitoring vmsingle-victoria-metrics-single-server-0 -- df -h /storage`
- Check Loki storage usage: `kubectl exec -n monitoring loki-0 -c loki -- du -sh /var/loki`
- Review dashboard usability feedback

### Monthly
- Review and tune alert thresholds based on observed baselines
- Check for new Grafana/Alloy/Loki/Tempo releases
- Review and clean up unused dashboards
- Verify backup integrity

## Upgrade & Rollback Procedures

### Upgrading a Component

1. Update chart version in HelmRelease YAML
2. Update image tag if needed
3. Commit and push to Git
4. Flux reconciles within 5 minutes
5. Verify: `kubectl get hr <name> -n flux-system`
6. Check pods: `kubectl get pods -n monitoring`

### Rolling Back

```bash
# Option 1: Revert Git commit
git revert HEAD
git push origin main

# Option 2: Suspend Flux and manually patch
kubectl patch ks <name> -n flux-system --type=merge -p '{"spec":{"suspend":true}}'
kubectl patch hr <name> -n flux-system --type=merge -p '{"spec":{"chart":{"spec":{"version":"<old-version>"}}}}'
```

## Capacity Planning

| Metric | Current | Threshold | Action |
|---|---|---|---|
| Node RAM Usage | ~82% | > 90% | Scale down non-essential workloads |
| VictoriaMetrics Storage | ~400MB / 10Gi | > 80% | Reduce retention or increase PVC |
| Loki Storage | ~20Gi / 20Gi | > 80% | Reduce retention or increase PVC |
| Tempo Storage | ~5Gi / 5Gi | > 80% | Reduce retention or increase PVC |
| CPU Usage | ~6% | > 80% | Review resource requests |

## Retention Management

| Component | Retention | Storage | Notes |
|---|---|---|---|
| VictoriaMetrics | 30 days | 10Gi | Adjust via `retentionPeriod` |
| Loki | 30 days | 20Gi | Adjust via `retention_period` |
| Tempo | 7 days | 5Gi | Adjust via `retention` |

## Security Maintenance

- Rotate Vault token used by ESO quarterly
- Review Alloy RBAC permissions annually
- Update Grafana admin password via Vault
- Review alert notification routing when team changes
- Audit dashboard access permissions quarterly