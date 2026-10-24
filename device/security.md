# Security Configuration

## User Access

- Primary user: `kyykozeeks` (uid 1000)
- Root access: via `sudo` (password required)
- SSH: enabled (`sshd` running)
- X11 forwarding enabled

## Firewall

- No UFW installed.
- No explicit host firewall rules (iptables not configured via UFW).
- Network access controlled mainly by Tailscale ACLs and Cloudflare Tunnel.

## AppArmor

- AppArmor module is loaded.
- Container workloads run under default profiles.

## Kubernetes Security

- RBAC: default Kubernetes RBAC (ArgoCD, cert-manager, etc.)
- Secrets: managed via HashiCorp Vault + External Secrets Operator (ESO)
- TLS: cert-manager + Let's Encrypt (DNS-01)
- Image registry: Harbor (internal, TLS)

## Secret Management

- Secrets are not stored in Git.
- Vault stores application secrets.
- ESO syncs Vault secrets to Kubernetes Secrets.
- Templates are in `secrets/templates/`.

## Recommendations

- Enable a host firewall (UFW or nftables) for ports 22, 80, 443, 6443.
- Restrict SSH to Tailscale IPs or key-based auth only.
- Rotate exposed secrets (Vault root token, unseal keys, Telegram bot token, etc.).
- Use ExternalSecrets for all sensitive values; avoid hardcoding in manifests.