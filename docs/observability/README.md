# Observability Platform Documentation

## Overview

This directory contains comprehensive documentation for the K3s homelab observability platform at `frengky.xyz`.

## Architecture Summary

The platform implements three pillars of observability:

- **Metrics**: VictoriaMetrics (TSDB) + Grafana Alloy (scraper) + Node Exporter + Kube-State-Metrics
- **Logs**: Grafana Loki (storage) + Grafana Alloy (collector) + Kubernetes events
- **Traces**: Grafana Tempo (storage) + Grafana Alloy (OTLP receiver/exporter) + Traefik (instrumented ingress)

## Documentation Index

| Document | Description |
|---|---|
| [architecture.md](architecture.md) | System architecture, component responsibilities, data flow, storage design |
| [audit-report.md](audit-report.md) | Initial environment inventory, gaps, risks, before/after comparison |
| [installation.md](installation.md) | Prerequisites, deployment order, verification, upgrade, rollback |
| [configuration-reference.md](configuration-reference.md) | Component configuration, Helm values, alert thresholds |
| [dashboards.md](dashboards.md) | Dashboard catalog, investigation workflows, LogQL queries |
| [alerting-and-runbooks.md](alerting-and-runbooks.md) | Alert catalog, severity definitions, notification routing, runbooks |
| [troubleshooting.md](troubleshooting.md) | Common failure scenarios, diagnostic commands, recovery steps |
| [backup-and-recovery.md](backup-and-recovery.md) | Backup procedures, restoration, validation, limitations |
| [operations.md](operations.md) | Daily health checks, maintenance, capacity planning, upgrades |
| [known-limitations.md](known-limitations.md) | Uninstrumented apps, missing metrics, unsupported paths, future work |

## Quick Start

1. **Access Grafana**: https://grafana.frengky.xyz
2. **Primary Dashboard**: "1. Home Server Overview" (Core Observability folder)
3. **Investigate unhealthy pod**: Dashboard 2 → check Failed/Pending pods → Dashboard 5 → search logs
4. **Search logs**: Dashboard 5 → set namespace/pod filters → use Search Text box
5. **Investigate slow request**: Dashboard 4 → check P95 latency → Dashboard 6 → inspect traces in Tempo

## Key Endpoints

| Service | URL | Access |
|---|---|---|
| Grafana | https://grafana.frengky.xyz | Tailscale (private) |
| VictoriaMetrics | http://vmsingle.monitoring.svc:8428 | Internal |
| Loki | http://loki.monitoring.svc:3100 | Internal |
| Tempo | http://tempo.monitoring.svc:3200 | Internal |
| Alloy | http://alloy.monitoring.svc:12345 | Internal |
| Traefik Dashboard | https://traefik.frengky.xyz/dashboard/ | Tailscale (private) |