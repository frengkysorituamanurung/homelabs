# Secret Management dengan HashiCorp Vault + External Secrets Operator (ESO)

Dokumen ini menjelaskan cara menyimpan dan mengelola secrets di cluster homelabs menggunakan Vault dan ESO.

## Arsitektur

```
Developer → vault kv put ... → Vault (vault.frengky.xyz)
                                      ↓
                          External Secrets Operator
                          (watches ExternalSecret CRDs)
                                      ↓
                          Kubernetes Secret (dibuat otomatis)
                                      ↓
                          Aplikasi membaca Secret
```

## Prerequisites

Pastikan komponen berikut sudah running:
1. **Vault** (namespace: `vault`) - `kubectl get pod -n vault`
2. **ESO** (namespace: `external-secrets`) - `kubectl get pod -n external-secrets`
3. **ClusterSecretStore** sudah dibuat - lihat `templates/vault-secret-store.yaml`

## Setup Awal Vault (Dev Mode)

### 1. Akses Vault
```bash
# Port-forward ke Vault UI
kubectl port-forward -n vault svc/vault 8200:8200

# Login di browser: http://localhost:8200
# Token: root (dev mode)
```

### 2. Aktifkan KV v2 Secret Engine
```bash
# Masuk ke Vault pod
kubectl exec -n vault -it vault-0 -- /bin/sh

# Enable KV v2 (sudah aktif di dev mode di path 'secret/')
vault secrets list
```

### 3. Buat Secret Token untuk ESO

ESO perlu token Vault untuk mengambil secrets:

```bash
# Di dalam Vault pod (dev mode, pakai root token)
kubectl exec -n vault -it vault-0 -- vault token create \
  -policy=default \
  -period=768h \
  -orphan \
  -format=json | jq -r '.auth.client_token'

# Buat Kubernetes Secret untuk ESO
kubectl create secret generic vault-token \
  -n external-secrets \
  --from-literal=token=<TOKEN_DARI_ATAS>
```

### 4. Apply ClusterSecretStore

```bash
kubectl apply -f secrets/templates/vault-secret-store.yaml

# Verifikasi
kubectl get clustersecretstore vault-backend
```

## Menyimpan Secrets ke Vault

### Format umum:
```bash
kubectl exec -n vault -it vault-0 -- vault kv put secret/<nama-app> <key>=<value>
```

### Secrets per Aplikasi:

#### Grafana
```bash
kubectl exec -n vault -it vault-0 -- vault kv put secret/grafana \
  adminUser=admin \
  adminPassword=<PASSWORD_KUAT>
```

#### Gitea
```bash
kubectl exec -n vault -it vault-0 -- vault kv put secret/gitea \
  adminPassword=<PASSWORD_KUAT>
```

#### Harbor
```bash
kubectl exec -n vault -it vault-0 -- vault kv put secret/harbor \
  adminPassword=<PASSWORD_KUAT>
```

#### Cloudflared
```bash
# Tunnel token dari Cloudflare dashboard
kubectl create secret generic cloudflared-token \
  -n cloudflare \
  --from-literal=token=<CLOUDFLARE_TUNNEL_TOKEN>
```

#### Gitea Runner
```bash
# Registration token dari Gitea Admin > Actions > Runners
kubectl create secret generic runner-token \
  -n gitea-runner \
  --from-literal=token=<GITEA_RUNNER_TOKEN>
```

## Menggunakan ExternalSecret

Setelah secret disimpan di Vault, buat ExternalSecret CR:

```bash
# Apply template
kubectl apply -f secrets/templates/grafana-secret.yaml

# Cek status
kubectl get externalsecret -n monitoring grafana-admin-secret

# Cek secret yang dibuat ESO
kubectl get secret -n monitoring grafana-admin-secret
```

## Verifikasi ESO

```bash
# Cek semua ExternalSecrets
kubectl get externalsecret -A

# Cek ClusterSecretStore status
kubectl get clustersecretstore

# Lihat events ESO
kubectl get events -n external-secrets
```

## Vault Policies (Production)

Untuk production, buat Vault policy yang restrictive:

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

# Buat token dengan policy
kubectl exec -n vault -it vault-0 -- vault token create \
  -policy=eso-reader \
  -period=8760h
```

## Migrasi Vault: Dev → Production

> ⚠️ **PENTING**: Dev mode menyimpan data di memory. Data hilang jika pod restart!

Ketika siap migrasi ke production:

1. Export semua secrets dari dev:
```bash
kubectl exec -n vault -it vault-0 -- vault kv list secret/
kubectl exec -n vault -it vault-0 -- vault kv get secret/grafana
# ... backup semua secrets
```

2. Update `charts/infra/vault/values.yaml`:
```yaml
server:
  dev:
    enabled: false  # Matikan dev mode
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

3. Unseal Vault dan re-import semua secrets.
