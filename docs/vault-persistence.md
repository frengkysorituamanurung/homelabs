# HashiCorp Vault Persistent Storage Setup & Operations

This document describes the persistent storage configuration for HashiCorp Vault, the unseal keys for this environment, and standard operation procedures for managing Vault.

---

## 📌 Background & Architecture
Previously, Vault was running in **Development Mode** (`server.dev.enabled = true`), which stores all secrets in-memory. Consequently, restarting the Vault pod or cluster caused all secrets to be lost.

To resolve this, Vault has been migrated to **Standalone Persistent Mode** using the Kubernetes local-path storage class.

- **Storage Type**: File-based persistent storage (`/vault/data`).
- **Disk Allocation**: 5Gi Persistent Volume Claim (`data-vault-0`).
- **Namespace**: `vault`

---

## 🔑 Unseal Keys & Root Token
Unlike Dev Mode, persistent Vault starts in a **Sealed** state upon pod restart. To decrypt the storage engine, Vault must be unsealed using Shamir's Secret Sharing keys.

> [!IMPORTANT]
> Keep these keys secure. You need at least **3 out of 5** keys to unseal the Vault.

### Key Shares:
1. `REPLACE_WITH_UNSEAL_KEY`
2. `REPLACE_WITH_UNSEAL_KEY`
3. `REPLACE_WITH_UNSEAL_KEY`
4. `REPLACE_WITH_UNSEAL_KEY`
5. `REPLACE_WITH_UNSEAL_KEY`

### Active Root Token:
- `REPLACE_WITH_VAULT_ROOT_TOKEN`

---

## 🛠️ Operations Guide

### 1. How to Unseal Vault (Manual)
If the Vault pod restarts, its readiness probe will fail and it will show `0/1 READY` because it is sealed. 

To unseal, run the following commands sequentially and provide 3 different unseal keys when prompted (or pass them directly):

```bash
kubectl exec -n vault -it vault-0 -- vault operator unseal REPLACE_WITH_UNSEAL_KEY
kubectl exec -n vault -it vault-0 -- vault operator unseal REPLACE_WITH_UNSEAL_KEY
kubectl exec -n vault -it vault-0 -- vault operator unseal REPLACE_WITH_UNSEAL_KEY
```

Once `Sealed` changes to `false`, the pod will become healthy and ready.

### 2. External Secrets Integration
The **External Secrets Operator (ESO)** reads secrets from Vault using the token defined in the `external-secrets` namespace:
- **Secret Name**: `vault-token`
- **Key**: `token`

If you ever regenerate the Vault Root Token, you must update this secret so ESO can continue syncing:
```bash
kubectl create secret generic vault-token -n external-secrets \
  --from-literal=token=<NEW_ROOT_TOKEN> \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 3. Populating Secrets
Secrets can be added directly via the Vault CLI inside the pod:
```bash
# Example: Adding secrets for sample-api
kubectl exec -n vault -it vault-0 -- vault kv put secret/production/backend/sample-api APP_ENV=production
```
Or you can run the pre-configured scratch script on the control plane:
```bash
bash /root/.gemini/antigravity-cli/brain/9709b6b2-1b93-4aed-a44a-8943029c7441/scratch/populate_vault.sh
```
