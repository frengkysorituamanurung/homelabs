# Observability Platform — Troubleshooting

## Common Failure Scenarios

### 1. Alloy Pod CrashLoopBackOff

**Symptom**: Alloy pod restarts repeatedly, logs show config parse errors.

**Diagnosis**:
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy -c alloy --tail=50
```

**Common Causes**:
- Alloy config syntax error (check `stage.template` Go template syntax)
- Missing `ToLower` function → use `strings.ToLower` or inline Go template
- Invalid regex in `stage.regex` or `discovery.relabel`

**Recovery**: Fix the config in `infrastructure/alloy/flux/helmrelease.yaml`, commit, push, and wait for Flux reconcile.

### 2. Loki "entry too far behind" Errors

**Symptom**: Alloy logs show `server returned HTTP status 400: entry too far behind`.

**Cause**: Old log files from previous pod runs have timestamps older than Loki's `reject_old_samples_max_age` (168h).

**Recovery**: The `stage.drop { older_than = "168h" }` stage in Alloy config drops old entries. If still occurring, increase `reject_old_samples_max_age` in Loki config or restart Alloy to clear position files.

### 3. VictoriaMetrics "too long query" Errors

**Symptom**: VictoriaMetrics logs show `too long query; got X bytes; mustn't exceed -search.maxQueryLen`.

**Cause**: Dashboard queries with many pod names exceed the default 16384 byte limit.

**Recovery**: Set `search.maxQueryLen: "65536"` in vmsingle `extraArgs`. Already configured.

### 4. Grafana Datasource "data source not found"

**Symptom**: Alert rules fail with `data source not found`.

**Cause**: Alert rule references a stale datasource UID (e.g., `P4169E866C3094E38`).

**Recovery**: Update all alert rules to use correct UIDs: `VictoriaMetrics`, `Loki`, `Tempo`. Already fixed in alerts-configmap.yaml.

### 5. Telegram Notification "400 Bad Request"

**Symptom**: Grafana alertmanager logs show `webhook response status 400 Bad Request`.

**Cause**: Telegram message exceeds 4096 character limit, or HTML parse mode fails on special characters.

**Recovery**: Set `parse_mode: "None"` and simplify message template. Already fixed.

### 6. Tempo Trace Not Found (404)

**Symptom**: `GET /api/traces/{traceId}` returns 404.

**Cause**: Trace hasn't been flushed to storage yet (ingester holds traces in memory for `complete_block_timeout`).

**Recovery**: Wait 30-60 seconds for trace to be flushed. Check Tempo ingester logs for errors.

### 7. Alloy OTLP Receiver Not Listening

**Symptom**: Traefik traces not appearing in Tempo.

**Diagnosis**:
```bash
kubectl exec -n monitoring deploy/grafana-production -c grafana -- \
  wget -qO- http://alloy.monitoring.svc.cluster.local:12345/metrics | grep otelcol_receiver_accepted_spans
```

**Common Causes**:
- Alloy Service missing OTLP ports → check `extraPorts` in HelmRelease
- Traefik can't reach Alloy → check DNS resolution and network policy
- Alloy config missing `otelcol.receiver.otlp` block

### 8. Loki Memberlist DNS Resolution Failure

**Symptom**: Loki logs show `Failed to resolve loki-memberlist.monitoring.svc.cluster.local`.

**Cause**: Loki is configured in SingleBinary mode but still tries to join memberlist. This is harmless in single-node mode.

**Recovery**: No action needed. Loki operates normally in single-node mode.<|end|>