# Observability Platform — Architecture

## Overview

This document describes the architecture of the K3s homelab observability platform deployed at `frengky.xyz`. The platform provides three pillars of observability — **metrics**, **logs**, and **traces** — with correlation, alerting, and dashboards built on Grafana.

## Architecture Diagram

```mermaid
graph TB
    subgraph "External Traffic"
        User[Public User / Admin]
        Tailscale[Tailscale VPN 100.120.133.63]
    end

    subgraph "Ingress"
        Traefik[Traefik Ingress Controller<br/>Port 80/443/9100 metrics<br/>OTLP tracing enabled]
    end

    subgraph "Observability Stack (monitoring namespace)"
        Alloy[Grafana Alloy<br/>DaemonSet<br/>Metrics + Logs + OTLP Receiver/Exporter]
        VM[VictoriaMetrics<br/>SingleBinary<br/>TSDB + Remote Write]
        Loki[Grafana Loki<br/>SingleBinary<br/>Log Storage + Indexing]
        Tempo[Grafana Tempo<br/>SingleBinary<br/>Trace Storage + Metrics Generator]
        Grafana[Grafana<br/>Dashboards + Alerting + Explore]
        NodeExp[Node Exporter<br/>DaemonSet]
        KSM[Kube-State-Metrics<br/>Deployment]
        BB[Blackbox Exporter<br/>Deployment]
    end

    subgraph "Workloads (all namespaces)"
        Pods[Application Pods<br/>stdout/stderr logs<br/>Prometheus metrics endpoints]
    end

    subgraph "External"
        Telegram[Telegram Bot<br/>@mcpdokubot]
        Vault[HashiCorp Vault<br/>Secret Management]
    end

    User -->|HTTPS| Traefik
    Tailscale -->|HTTPS| Traefik
    Traefik -->|Route| Pods
    Traefik -->|OTLP gRPC :4317| Alloy
    Traefik -->|Prometheus /metrics| Alloy

    Alloy -->|Prometheus remote_write| VM
    Alloy -->|Loki push API| Loki
    Alloy -->|OTLP gRPC :4317| Tempo

    NodeExp -->|Prometheus scrape| Alloy
    KSM -->|Prometheus scrape| Alloy
    BB -->|Prometheus scrape| Alloy
    Pods -->|Prometheus scrape| Alloy
    Pods -->|Container logs /var/log/pods| Alloy
    Pods -->|K8s Events| Alloy

    VM -->|Prometheus datasource| Grafana
    Loki -->|Loki datasource| Grafana
    Tempo -->|Tempo datasource| Grafana

    Tempo -->|Remote Write span metrics| VM
    Tempo -->|Remote Write service graphs| VM

    Grafana -->|Alert notifications| Telegram
    Vault -->|ESO sync| Grafana
    Vault -->|ESO sync| Alloy
EOF