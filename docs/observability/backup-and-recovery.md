# Observability Platform — Backup & Recovery

## What Must Be Backed Up

| Component | Data | Location | Backup Method |
|---|---|---|---|
| VictoriaMetrics | Time series data | PVC `server-volume-vmsingle-...` (10Gi) | PVC snapshot or `vmbackup` |
| Loki | Log chunks + index | PVC `storage-loki-0` (20Gi) | PVC snapshot |
| Tempo | Trace blocks + WAL | PVC `storage-tempo-0` (5Gi) | PVC snapshot |
| Grafana | Dashboards, users, alert state | PVC `grafana-production` (5Gi) | PVC snapshot or Grafana API export |
| Configuration | All YAML/JSON manifests | Git repository | Git push (already version-controlled) |

## Backup Frequency

- **Configuration**: Continuous (Git commits)
- **PVC Data**: Weekly (manual snapshot or cronjob)
- **Grafana DB**: Daily (automated via Grafana API)

## Restoration Procedures

### Restore VictoriaMetrics

```bash
# 1. Scale down vmsingle
kubectl scale statefulset vmsingle-victoria-metrics-single-server -n monitoring --replicas=0

# 2. Restore PVC from snapshot
kubectl apply -f pvc-snapshot-restore.yaml

# 3. Scale up
kubectl scale statefulset vmsingle-victoria-metrics-single-server -n monitoring --replicas=1
```

### Restore Grafana

```bash
# 1. Scale down Grafana
kubectl scale deployment grafana-production -n monitoring --replicas=0

# 2. Restore PVC
kubectl apply -f grafana-pvc-restore.yaml

# 3. Scale up
kubectl scale deployment grafana-production -n monitoring --replicas=1

# 4. Verify dashboards
GF_PASS=$(kubectl get secret grafana-credentials -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl exec -n monitoring deploy/grafana-production -c grafana -- \
  wget -qO- "http://admin:${GF_PASS}@127.0.0.1:3000/api/search?type=dash-db" | python3 -c "import sys,json; print('Dashboards:', len(json.load(sys.stdin)))"
```

### Restore Loki

```bash
# 1. Scale down Loki
kubectl scale statefulset loki -n monitoring --replicas=0

# 2. Restore PVC
kubectl apply -f loki-pvc-restore.yaml

# 3. Scale up
kubectl scale statefulset loki -n monitoring --replicas=1
```

## Recovery Validation

After any restore:
1. Verify pods are Running: `kubectl get pods -n monitoring`
2. Verify data sources in Grafana
3. Run a test query against each datasource
4. Check alert rules are loaded
5. Verify Telegram notifications work

## Known Recovery Limitations

- No automated backup cronjob configured yet
- PVC snapshots require storage provider support (local-path doesn't support snapshots natively)
- Grafana alert state is stored in SQLite DB — included in PVC backup
- Tempo trace data is ephemeral (7-day retention) — full restore may lose recent traces
- Alloy position files are stored in `/tmp/alloy` (emptyDir) — lost on pod restart (acceptable, re-tails from end)