#!/bin/bash
set -e

# Ambil token dari Vault
SECRETS_JSON=$(wget -qO- --header="X-Vault-Token: $VAULT_TOKEN" http://vault.vault.svc.cluster.local:8200/v1/secret/data/ci/credentials)
ARGOCD_TOKEN=$(echo "$SECRETS_JSON" | grep -o '"argocd_token":"[^"]*' | grep -o '[^"]*$')
GITOPS_TOKEN=$(echo "$SECRETS_JSON" | grep -o '"gitops_token":"[^"]*' | grep -o '[^"]*$')

# Download argocd-sync tool from Gitea
git clone "http://gitea_admin:${GITOPS_TOKEN}@gitea-http.gitea.svc.cluster.local:3000/devops/deployment-tools.git"
cp deployment-tools/scripts/argocd-sync.sh .
chmod +x argocd-sync.sh

# Dapatkan file yang berubah pada commit HEAD
CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD)

for file in $CHANGED_FILES; do
  if [[ $file =~ ^kubernetes/(production|staging|development)/([^/]+)/ ]]; then
    APP_DIR="${BASH_REMATCH[2]}"
    MATCHED_FILE=$(grep -rl "kubernetes/.*/$APP_DIR" kubernetes/applications/ | head -n 1)
    if [[ -n "$MATCHED_FILE" ]]; then
      APP_NAME=$(grep -E "^  name:" "$MATCHED_FILE" | awk '{print $2}')
      echo "Memicu sinkronisasi untuk ArgoCD App: $APP_NAME"
      ./argocd-sync.sh "http://argocd-server.argocd.svc.cluster.local:80" "$ARGOCD_TOKEN" "$APP_NAME"
    fi
  fi
done
