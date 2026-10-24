#!/bin/bash

# ==============================================================================
# GitOps Deployment Tool
# Fungsi: Build Image -> Push to Harbor -> Update GitOps Repo -> Auto Sync
# ==============================================================================

set -e

# Warna untuk output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Validasi argumen
if [ "$#" -lt 5 ]; then
    echo -e "${RED}Usage: $0 <APP_NAME> <IMAGE_REPO> <IMAGE_TAG> <GITOPS_REPO_URL> <VALUES_FILE_PATH>${NC}"
    echo "Example: $0 my-frontend harbor.frengky.xyz/k8s/clusters/production/applications/apps/my-frontend v1.0.0 https://user:token@github.com/frengkysorituamanurung/homelabs.git k8s/clusters/production/applications/apps/my-frontend/values.yaml"
    exit 1
fi

APP_NAME=$1
IMAGE_REPO=$2
IMAGE_TAG=$3
GITOPS_REPO_URL=$4
VALUES_FILE_PATH=$5

echo -e "${GREEN}🚀 Memulai proses deployment untuk ${APP_NAME} (${IMAGE_TAG})...${NC}"

# 1. Build Docker Image
echo -e "\n${YELLOW}[1/4] Membangun Docker Image...${NC}"
docker build -t ${IMAGE_REPO}:${IMAGE_TAG} .

# 2. Push to Harbor
echo -e "\n${YELLOW}[2/4] Mengirim Image ke Harbor...${NC}"
docker push ${IMAGE_REPO}:${IMAGE_TAG}

# 3. Clone & Update GitOps Repo
echo -e "\n${YELLOW}[3/4] Memperbarui file GitOps manifest...${NC}"
TEMP_DIR=$(mktemp -d)
git clone ${GITOPS_REPO_URL} ${TEMP_DIR}

cd ${TEMP_DIR}

# Update tag di values.yaml menggunakan sed
if [ -f "${VALUES_FILE_PATH}" ]; then
    # Mencari baris tag: dan menggantinya dengan tag baru di dalam blok image
    sed -i -E "s/tag: .*/tag: \"${IMAGE_TAG}\"/" "${VALUES_FILE_PATH}"
    
    # Setup identitas Git
    git config user.name "GitOps Bot"
    git config user.email "gitops-bot@frengky.xyz"
    
    # Cek apakah ada perubahan
    if git diff --exit-code; then
        echo -e "${YELLOW}Tidak ada perubahan pada versi image (tag sama). Melewati commit.${NC}"
    else
        git add ${VALUES_FILE_PATH}
        git commit -m "chore(${APP_NAME}): update image tag to ${IMAGE_TAG}"
        git push origin main
        echo -e "${GREEN}✅ Berhasil memperbarui repo GitOps!${NC}"
    fi
else
    echo -e "${RED}File ${VALUES_FILE_PATH} tidak ditemukan di dalam repo GitOps!${NC}"
    exit 1
fi

# 4. Notifikasi ArgoCD Sync (Opsional - Webhook lebih disarankan)
echo -e "\n${YELLOW}[4/4] Memastikan ArgoCD Sync Cepat...${NC}"
echo "ArgoCD akan otomatis tersinkronisasi berkat Webhook yang dikonfigurasi di GitHub."
echo "Proses sinkronisasi akan berjalan dalam hitungan detik!"

# Cleanup
rm -rf ${TEMP_DIR}

echo -e "\n${GREEN}🎉 Deployment Selesai! Aplikasi ${APP_NAME} sedang di-sync ke Kubernetes.${NC}"
