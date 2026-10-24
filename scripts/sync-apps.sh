#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd "${SCRIPT_DIR}/.." &> /dev/null && pwd )"

# 1. Ambil token dari Vault jika ada
if [ -n "$VAULT_TOKEN" ]; then
    SECRETS_JSON=$(wget -qO- --header="X-Vault-Token: $VAULT_TOKEN" http://vault.vault.svc.cluster.local:8200/v1/secret/data/ci/credentials 2>/dev/null || true)
    ARGOCD_TOKEN=$(echo "$SECRETS_JSON" | grep -o '"argocd_token":"[^"]*' | grep -o '[^"]*$' || true)
fi

# Locate argocd-sync.sh script
if [ -f "/workspace/argocd-sync.sh" ]; then
    ARGOCD_SYNC_CMD="/workspace/argocd-sync.sh"
elif [ -f "$SCRIPT_DIR/argocd-sync.sh" ]; then
    ARGOCD_SYNC_CMD="$SCRIPT_DIR/argocd-sync.sh"
else
    echo "argocd-sync.sh tidak ditemukan lokal, mengunduh dari Gitea..."
    GITOPS_TOKEN=$(echo "$SECRETS_JSON" | grep -o '"gitops_token":"[^"]*' | grep -o '[^"]*$' || true)
    wget -qO /tmp/argocd-sync.sh "http://gitea_admin:${GITOPS_TOKEN}@gitea-http.gitea.svc.cluster.local:3000/devops/deployment-tools/raw/branch/main/scripts/argocd-sync.sh" 2>/dev/null || true
    ARGOCD_SYNC_CMD="/tmp/argocd-sync.sh"
fi
chmod +x "$ARGOCD_SYNC_CMD" 2>/dev/null || true

# Dapatkan file yang berubah pada commit HEAD
cd "$REPO_ROOT"
CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD)

if [ -z "$CHANGED_FILES" ]; then
    echo "No changed files detected in HEAD commit."
    exit 0
fi

echo "Perubahan file terdeteksi pada commit:"
echo "$CHANGED_FILES"
echo "----------------------------------------"

declare -A TO_SYNC_APPS
declare -A PATH_TO_APP_NAME
declare -A VALUE_FILE_TO_APP_NAME

# Pre-build mapping dari seluruh file Application YAML di k8s/clusters/production/apps/
for app_file in $(find "${REPO_ROOT}/k8s/clusters/production/apps" -type f -name "*.yaml"); do
    APP_NAME=$(grep -E "^\s*name:" "$app_file" | head -n 1 | awk '{print $2}')
    APP_PATH=$(grep -E "^\s*path:" "$app_file" | head -n 1 | awk '{print $2}')
    
    if [ -n "$APP_NAME" ]; then
        REL_APP_FILE="${app_file#${REPO_ROOT}/}"
        PATH_TO_APP_NAME["$REL_APP_FILE"]="$APP_NAME"

        if [ -n "$APP_PATH" ]; then
            PATH_TO_APP_NAME["$APP_PATH"]="$APP_NAME"
        fi
        
        VALUE_FILES=$(grep -E "^\s*-\s*\$values/" "$app_file" | awk -F'$values/' '{print $2}' || true)
        for vf in $VALUE_FILES; do
            VALUE_FILE_TO_APP_NAME["$vf"]="$APP_NAME"
        done
    fi
done

# Matching file yang berubah ke ArgoCD Application
for file in $CHANGED_FILES; do
    MATCHED=false
    
    # 1. Matching path persis atau prefix path aplikasi
    for app_path in "${!PATH_TO_APP_NAME[@]}"; do
        if [[ "$file" == "$app_path"* ]] || [[ "$file" == *"$app_path"* ]]; then
            APP_NAME="${PATH_TO_APP_NAME[$app_path]}"
            TO_SYNC_APPS["$APP_NAME"]=1
            MATCHED=true
            echo "Match file '$file' -> App: $APP_NAME (via path '$app_path')"
            break
        fi
    done
    
    # 2. Matching dengan valueFiles (misal $values/infrastructure/harbor/values.yaml)
    if [ "$MATCHED" = false ]; then
        for vf in "${!VALUE_FILE_TO_APP_NAME[@]}"; do
            if [[ "$file" == "$vf" ]]; then
                APP_NAME="${VALUE_FILE_TO_APP_NAME[$vf]}"
                TO_SYNC_APPS["$APP_NAME"]=1
                MATCHED=true
                echo "Match file '$file' -> App: $APP_NAME (via valueFile '$vf')"
                break
            fi
        done
    fi

    # 3. Fallback Heuristic untuk struktur bertingkat (misal apps/production/backend/sample-api/values.yaml)
    if [ "$MATCHED" = false ]; then
        if [[ $file =~ ^apps/(production|staging|development)/([^/]+)/([^/]+)/ ]] || [[ $file =~ ^infrastructure/([^/]+)/([^/]+)/ ]]; then
            DIR_NAME="${BASH_REMATCH[3]}"
            MATCHED_FILE=$(find "${REPO_ROOT}/k8s/clusters/production/apps" -type f -name "*${DIR_NAME}*.yaml" | head -n 1)
            if [ -n "$MATCHED_FILE" ]; then
                APP_NAME=$(grep -E "^\s*name:" "$MATCHED_FILE" | head -n 1 | awk '{print $2}')
                if [ -n "$APP_NAME" ]; then
                    TO_SYNC_APPS["$APP_NAME"]=1
                    MATCHED=true
                    echo "Match file '$file' -> App: $APP_NAME (via fallback sub-directory '$DIR_NAME')"
                fi
            fi
        elif [[ $file =~ ^apps/(production|staging|development)/([^/]+)/ ]] || [[ $file =~ ^infrastructure/([^/]+)/ ]]; then
            DIR_NAME="${BASH_REMATCH[2]}"
            MATCHED_FILE=$(find "${REPO_ROOT}/k8s/clusters/production/apps" -type f -name "*${DIR_NAME}*.yaml" | head -n 1)
            if [ -n "$MATCHED_FILE" ]; then
                APP_NAME=$(grep -E "^\s*name:" "$MATCHED_FILE" | head -n 1 | awk '{print $2}')
                if [ -n "$APP_NAME" ]; then
                    TO_SYNC_APPS["$APP_NAME"]=1
                    MATCHED=true
                    echo "Match file '$file' -> App: $APP_NAME (via fallback directory '$DIR_NAME')"
                fi
            fi
        fi
    fi
done

if [ ${#TO_SYNC_APPS[@]} -eq 0 ]; then
    echo "Tidak ada ArgoCD Application yang cocok dengan file yang diubah."
    exit 0
fi

# Jalankan sync dan rollout restart untuk setiap aplikasi yang terdeteksi berubah
for app_name in "${!TO_SYNC_APPS[@]}"; do
    echo "=================================================="
    echo "Memicu Auto-Sync & Rollout Restart untuk ArgoCD App: $app_name"
    echo "=================================================="
    "$ARGOCD_SYNC_CMD" "http://argocd-server.argocd.svc.cluster.local:80" "$ARGOCD_TOKEN" "$app_name"
done

echo "Seluruh aplikasi ArgoCD yang mengalami perubahan berhasil di-sync dan di-rollout!"
