#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd "${SCRIPT_DIR}/.." &> /dev/null && pwd )"

# Ambil token dari Vault
SECRETS_JSON=$(wget -qO- --header="X-Vault-Token: $VAULT_TOKEN" http://vault.vault.svc.cluster.local:8200/v1/secret/data/ci/credentials)
ARGOCD_TOKEN=$(echo "$SECRETS_JSON" | grep -o '"argocd_token":"[^"]*' | grep -o '[^"]*$')

# Locate argocd-sync.sh: check workspace path first (set by workflow), then fall back to deployment-tools clone
if [ -f "/workspace/argocd-sync.sh" ]; then
    ARGOCD_SYNC_CMD="/workspace/argocd-sync.sh"
elif [ -f "$SCRIPT_DIR/argocd-sync.sh" ]; then
    ARGOCD_SYNC_CMD="$SCRIPT_DIR/argocd-sync.sh"
else
    echo "argocd-sync.sh not found, downloading from Gitea..."
    GITOPS_TOKEN=$(echo "$SECRETS_JSON" | grep -o '"gitops_token":"[^"]*' | grep -o '[^"]*$')
    wget -qO /tmp/argocd-sync.sh "http://gitea_admin:${GITOPS_TOKEN}@gitea-http.gitea.svc.cluster.local:3000/devops/deployment-tools/raw/branch/main/scripts/argocd-sync.sh"
    ARGOCD_SYNC_CMD="/tmp/argocd-sync.sh"
fi
chmod +x "$ARGOCD_SYNC_CMD"

# Dapatkan file yang berubah pada commit HEAD
cd "$REPO_ROOT"
CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD)

if [ -z "$CHANGED_FILES" ]; then
    echo "No changed files detected."
    exit 0
fi

echo "Changed files:"
echo "$CHANGED_FILES"

declare -A SEEN_APPS

for file in $CHANGED_FILES; do
  if [[ $file =~ ^kubernetes/(production|staging|development)/([^/]+)/ ]]; then
    APP_DIR="${BASH_REMATCH[2]}"

    # Skip jika app sudah diproses (hindari duplikasi sync)
    if [[ -n "${SEEN_APPS[$APP_DIR]}" ]]; then
      continue
    fi

    MATCHED_FILE=$(grep -rl "kubernetes/.*/$APP_DIR" "${REPO_ROOT}/kubernetes/applications/" 2>/dev/null | head -n 1)
    if [[ -n "$MATCHED_FILE" ]]; then
      APP_NAME=$(grep -E "^  name:" "$MATCHED_FILE" | awk '{print $2}')
      if [[ -n "$APP_NAME" ]]; then
        echo "Memicu sinkronisasi untuk ArgoCD App: $APP_NAME"
        "$ARGOCD_SYNC_CMD" "http://argocd-server.argocd.svc.cluster.local:80" "$ARGOCD_TOKEN" "$APP_NAME"
        SEEN_APPS[$APP_DIR]=1
      fi
    fi
  fi
done
