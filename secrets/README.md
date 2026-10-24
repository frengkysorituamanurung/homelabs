# Secret Management with HashiCorp Vault + External Secrets Operator (ESO)

This document explains how to store and manage secrets in the homelabs cluster using Vault and ESO.

## Architecture

```
Developer → vault kv put ... → Vault (vault.frengky.xyz)
                                      ↓
                          External Secrets Operator
                          (watches ExternalSecret CRDs)
                                      ↓
                          Kubernetes Secret (created automatically)
                                      ↓
                          Application reads Secret
```

## Prerequisites

Make sure the following components are running:
1. **Vault** (namespace: `vault`) - `kubectl get pod -n vault`
2. **ESO** (namespace: `external-secrets`) - `kubectl get pod -n external-secrets`
3. **ClusterSecretStore** already created - see `templates/vault-secret-store.yaml`

## Initial Vault Setup (Dev Mode)

### 1. Access Vault
```bash
# Port-forward to Vault UI
kubectl port-forward -n vault svc/vault 8200:8200

# Login in browser: http://localhost:8200
# Token: root (dev mode)
```

### 2. Enable KV v2 Secret Engine
```bash
# Enter Vault pod
kubectl exec -n vault -it vault-0 -- /bin/sh

# Enable KV v2 (already active in dev mode at path 'secret/')
vault secrets list
```

### 3. Create Secret Token for ESO

ESO needs a Vault token to fetch secrets:

```bash
# Inside Vault pod (dev mode, use root token)
kubectl exec -n vault -it vault-0 -- vault token create \
  -policy=default \
  -period=768h \
  -orphan \
  -format=json | jq -r '.auth.client_token'

# Create Kubernetes Secret for ESO
kubectl create secret generic vault-token \
  -n external-secrets \
  --from-literal=token=<TOKEN_FROM_ABOVE>
```

### 4. Apply ClusterSecretStore

```bash
kubectl apply -f secrets/templates/vault-secret-store.yaml

# Verify
kubectl get clustersecretstore vault-backend
```

## Storing Secrets in Vault

### General format:
```bash
kubectl exec -n vault -it vault-0 -- vault kv put secret/<app-name> <key>=<value>
```

### Secrets per Application:

#### Grafana
```bash
kubectl exec -n vault -it vault-0 -- vault kv put secret/grafana \
  adminUser=admin \
  adminPassword=<STRONG_PASSWORD>
```

#### Harbor
```bash
kubectl exec -n vault -it vault-0 -- vault kv put secret/harbor \
  adminPassword=<STRONG_PASSWORD>
```

#### OpenObserve
```bash
kubectl exec -n vault -it vault-0 -- sh -c "
  VAULT_ADDR=http://127.0.0.1:8200
  VAULT_TOKEN=<ROOT_TOKEN>
  export VAULT_ADDR VAULT_TOKEN
  vault kv put secret/openobserve \
    rootEmail='admin@frengky.xyz' \
    rootPassword='<STRONG_PASSWORD>' \
    webUrl='https://openobserve.frengky.xyz'
"
```

#### Cloudflared
```bash
# Tunnel token from Cloudflare dashboard
kubectl create secret generic cloudflared-token \
  -n cloudflare \
  --from-literal=token=<CLOUDFLARE_TUNNEL_TOKEN>
```

## Using ExternalSecret

After the secret is stored in Vault, create an ExternalSecret CR:

```bash
# Apply template
kubectl apply -f secrets/templates/grafana-secret.yaml

# Check status
kubectl get externalsecret -n monitoring grafana-admin-secret

# Check secret created by ESO
kubectl get secret -n monitoring grafana-admin-secret
```

## Verifying ESO

```bash
# Check all ExternalSecrets
kubectl get externalsecret -A

# Check ClusterSecretStore status
kubectl get clustersecretstore

# View ESO events
kubectl get events -n external-secrets
```

## Vault Policies (Production)

For production, create a restrictive Vault policy:

```hcl
# vault-policy-eso.hcl
path "secret/data/*" {
  capabilities = ["read"]
}

path "secret/metadata/*" {
  capabilities = ["list"]
}
```

```bash
# Apply policy
kubectl exec -n vault -it vault-0 -- vault policy write eso-reader - <<EOF
path "secret/data/*" {
  capabilities = ["read"]
}
path "secret/metadata/*" {
  capabilities = ["list"]
}
EOF

# Create token with policy
kubectl exec -n vault -it vault-0 -- vault token create \
  -policy=eso-reader \
  -period=8760h
```

## Migrating Vault: Dev → Production

> ⚠️ **IMPORTANT**: Dev mode stores data in memory. Data is lost if the pod restarts!

When ready to migrate to production:

1. Export all secrets from dev:
```bash
kubectl exec -n vault -it vault-0 -- vault kv list secret/
kubectl exec -n vault -it vault-0 -- vault kv get secret/grafana
# ... backup all secrets
```

2. Update `charts/infra/vault/values.yaml`:
```yaml
server:
  dev:
    enabled: false  # Disable dev mode
  standalone:
    enabled: true
    config: |
      ui = true
      listener "tcp" {
        tls_disable = 1
        address = "[::]:8200"
      }
      storage "file" {
        path = "/vault/data"
      }
```

3. Unseal Vault and re-import all secrets.
