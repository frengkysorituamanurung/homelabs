# Device & Infrastructure Documentation

This folder documents the physical/virtual device, network, k3s cluster, and security configuration for the `homelabs` server.

## Device Summary

| Item | Value |
|---|---|
| Hostname | `homelabs` |
| Platform | WSL2 on Windows (Linux kernel `6.18.33.2-microsoft-standard-WSL2`) |
| OS | Ubuntu 26.04 LTS (Resolute Raccoon) |
| Architecture | x86_64 |
| CPU | Intel Core i7-10870H @ 2.20GHz (16 threads) |
| Memory | ~15 GiB RAM + 4 GiB swap |
| Disk | ~1 TB (`/dev/sdd`), ~9% used |
| Primary IP (LAN) | `192.168.1.32/24` |
| Tailscale IP | `100.120.133.63` |
| Kubernetes | k3s `v1.36.2+k3s1` |
| Container runtime | containerd `2.3.2-k3s2` |

## Contents

- [network.md](./network.md) — network interfaces, routing, DNS, Tailscale, ingress
- [k3s.md](./k3s.md) — k3s configuration, components, storage, certificates
- [security.md](./security.md) — users, SSH, firewall, AppArmor, secrets management

## Access

- SSH: `ssh kyykozeeks@100.120.177.76` (historical) or via Tailscale
- k3s kubeconfig: `/etc/rancher/k3s/k3s.yaml`
- ArgoCD UI: `https://argocd.frengky.xyz` (via Tailscale/LAN)