# Application Version & Helm Chart Upgrade Guide in a GitOps Environment

This document describes the standard steps to upgrade application versions and Helm Charts in a Kubernetes cluster environment managed with **ArgoCD**, **Harbor (Private Registry)**, and a **GitOps Repository**.

As an example, this document contains step-by-step guidance for upgrading **Harbor** from version **v2.12.2** to version **v2.15.2** (or another latest version).

---

## 1. Application Upgrade Concept in a GitOps Environment

In this cluster environment, applications are managed using the **GitOps** and **Self-Hosted Registry** approach:
1. **Internal OCI Helm Registry**: Helm Charts are stored in the internal registry (`oci://harbor.frengky.xyz/helm-repos`).
2. **Container Image Mirroring**: Application container images are pulled from the internet, then *pushed* to the internal Harbor (`harbor.frengky.xyz`).
3. **ArgoCD Application Sync**: ArgoCD monitors changes in the GitOps repository (`gitops-repo`) and automatically syncs (*rollout*) to the Kubernetes cluster.

---

## 2. Application Version Upgrade Steps (Example: Harbor v2.15.2)

### Step 1: Check Current Version

Check the currently running application version and pods in the cluster:
```bash
# Check current version pods & image
kubectl get pods -n harbor -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

# Check current ArgoCD manifest
cat k8s/clusters/production/applications/infrastructure/harbor.yaml
```

---

### Step 2: Mirror New Container Image from Internet to Internal Harbor

To ensure the cluster does not depend on public internet connectivity at *runtime*, pull the latest version component images to the local server, tag them, then *push* to internal Harbor.

1. **Login to Internal Harbor**:
   ```bash
   docker login harbor.frengky.xyz -u admin -p Harbor12345
   ```

2. **Pull Latest Version Images (v2.15.2) & Push to Harbor**:
   ```bash
   # Main Harbor components
   IMAGES=(
     "goharbor/harbor-core:v2.15.2"
     "goharbor/harbor-portal:v2.15.2"
     "goharbor/harbor-jobservice:v2.15.2"
     "goharbor/harbor-db:v2.15.2"
     "goharbor/harbor-registryctl:v2.15.2"
     "goharbor/registry-photon:v2.15.2"
     "goharbor/redis-photon:v2.15.2"
     "goharbor/trivy-adapter-photon:v2.15.2"
   )

   for img in "${IMAGES[@]}"; do
     echo "Pulling $img..."
     docker pull "$img"
     
     # Tag image to internal registry
     LOCAL_TAG="harbor.frengky.xyz/library/${img##*/}"
     docker tag "$img" "$LOCAL_TAG"
     
     echo "Pushing $LOCAL_TAG..."
     docker push "$LOCAL_TAG"
   done
   ```

---

### Step 3: Download & Publish Latest Helm Chart to OCI Harbor Registry

1. **Add Upstream Official Helm Repository**:
   ```bash
   helm repo add harbor https://helm.goharbor.io
   helm repo update
   ```

2. **Download Latest Helm Chart Package**:
   ```bash
   # Find the latest chart version
   helm search repo harbor/harbor --versions | head -n 5

   # Pull the chart (e.g. chart version 1.16.2 or latest)
   helm pull harbor/harbor --version 1.16.2
   ```

3. **Login & Push Helm Chart to Internal OCI Registry**:
   ```bash
   # Login to OCI registry with Helm
   helm registry login harbor.frengky.xyz -u admin -p Harbor12345

   # Push helm chart file (.tgz) to helm-repos project
   helm push harbor-1.16.2.tgz oci://harbor.frengky.xyz/helm-repos
   ```

---

### Step 4: Update Manifest Configuration in GitOps Repository

1. **Update Target Version in ArgoCD Application Spec**:
   Edit file `k8s/clusters/production/applications/infrastructure/harbor.yaml`:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: harbor
     namespace: argocd
   spec:
     sources:
       - repoURL: harbor-registry-tls.harbor.svc.cluster.local
         chart: helm-repos/harbor
         targetRevision: "1.16.2"  # <-- Update to new chart version
         helm:
           valueFiles:
             - $values/infrastructure/harbor/values.yaml
   ```

2. **Update Image Tag in `values.yaml` (if any)**:
   Edit file `infrastructure/harbor/values.yaml` to match the latest version tag if needed:
   ```yaml
   # Example tag adjustment in values.yaml if using custom tags
   core:
     image:
       repository: harbor.frengky.xyz/library/harbor-core
       tag: v2.15.2
   ```

---

### Step 5: Commit & Push Changes to GitOps Repository

Commit the updated manifest changes to the GitOps repository so ArgoCD can detect the changes:

```bash
cd /root/server/gitops-repo

git add k8s/clusters/production/applications/infrastructure/harbor.yaml
git add infrastructure/harbor/values.yaml
git commit -m "chore(harbor): upgrade harbor helm chart to 1.16.2 (app v2.15.2)"
git push origin main
```

---

### Step 6: Trigger ArgoCD Sync & Verify Deployment

1. **Trigger ArgoCD Sync**:
   ArgoCD will automatically sync. To speed it up, run:
   ```bash
   # Trigger refresh & sync via API / CLI
   kubectl annotate application harbor -n argocd argocd.argoproj.io/refresh=normal --overwrite
   ```

2. **Monitor Upgrade Status (Rolling Update)**:
   ```bash
   # Check deployment rollout status
   kubectl rollout status deployment/harbor-core -n harbor
   kubectl rollout status deployment/harbor-jobservice -n harbor
   
   # Check pod status in harbor namespace
   kubectl get pods -n harbor
   ```

3. **Functional Verification**:
   - Test Harbor Web UI access: `https://harbor.frengky.xyz`
   - Test `docker login`, `docker pull`, and `docker push` to the registry to ensure the service runs normally after the version update.

---

## 3. Important Checklist Before Upgrade

| Checklist | Description |
| :--- | :--- |
| **Database Backup** | Perform a backup of the PostgreSQL database (`harbor-database`) before a major upgrade. |
| **Breaking Changes** | Check the official changelog of the Helm Chart / Application release to ensure there are no incompatible `values.yaml` parameter changes. |
| **Image Availability** | Ensure all sub-component images have been successfully *pushed* to Harbor before triggering ArgoCD sync. |
