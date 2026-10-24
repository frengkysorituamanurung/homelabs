# GitOps Cert-Manager & Wildcard Let's Encrypt SSL (Tailscale Only Access)

This document explains the configuration, architecture, and workflow for implementing **cert-manager** using Let's Encrypt (DNS-01 Challenge via Cloudflare) in a **GitOps (Flux CD)** pattern, so that the `*.frengky.xyz` subdomains can be accessed privately via Tailscale securely (HTTPS without SSL warnings).

---

## 📖 Background & Motivation

Previously, applications such as GitLab, Flux CD, Grafana, etc., were accessed publicly using Cloudflare Tunnel and protected by Cloudflare Access. To move access to be fully private (only accessible when connected to **Tailscale**):
1. DNS records were moved from Cloudflare Proxy (Orange Cloud) to **DNS-Only (Gray Cloud)** and pointed to the private Tailscale host IP (`100.120.133.63`).
2. Because traffic no longer passes through the Cloudflare Edge Proxy, SSL/TLS encryption must be terminated directly inside the cluster (on the Ingress Controller/Traefik).
3. To avoid *"Not Secure"* warnings in the browser without having to import a certificate manually on every device, we use **cert-manager** to issue official free certificates from **Let's Encrypt** using the **DNS-01 Challenge** method.

---

## 🌐 Network Egress Constraint Workaround (Pod Egress Timeout)

In this cluster, pods running in the CNI network (`10.42.0.0/16`) experience outbound routing issues (outbound TCP port 80/443 timeout), while the main host has normal internet access. This causes the `cert-manager` controller to time out when trying to register with the Let's Encrypt directory server (`acme-v02.api.letsencrypt.org`).

### Solution: Host Network Workaround

To overcome this issue, the `cert-manager` controller deployment manifest is patched declaratively in GitOps:
* **`hostNetwork: true`**: Forces the `cert-manager` pod to run in the main host's network namespace (so it has direct internet access).
* **`dnsPolicy: ClusterFirstWithHostNet`**: Ensures the pod can still resolve internal Kubernetes DNS (such as reading the Cloudflare API token secret) while using the host network.

---

## 🛠️ GitOps File Structure

All components are declared in the GitOps repository:

### 1. Flux CD Application Manifest
Declared in `k8s/clusters/production/applications/infrastructure/cert-manager.yaml`. This manifest registers the cert-manager application with Flux CD.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default
  source:
    path: infrastructure/cert-manager
    repoURL: http://gitlab-http.gitlab.svc.cluster.local/devops/gitops.git
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

### 2. K3s Deployment Manifests
Located in the `infrastructure/cert-manager/` directory:
* **`cert-manager.yaml`**: The official `cert-manager v1.15.1` manifest, adjusted with the `hostNetwork: true` configuration on the main controller deployment.
* **`cert-manager-manifests.yaml`**: Contains the `ClusterIssuer` configuration (Let's Encrypt connector) and the `Certificate` definition (wildcard `*.frengky.xyz` certificate).
* **`tlsstore-default.yaml`**: Traefik `default` TLSStore configuration so it automatically serves the wildcard `wildcard-frengky-xyz-tls` certificate from the `kube-system` namespace as the default SSL certificate for all HTTPS routers.

---

## 🔑 Initial Setup & Maintenance

### 1. Cloudflare API Token Requirement
To perform the DNS-01 Challenge, create an API Token in the Cloudflare Profile with permissions:
* **Zone** ➔ **Zone** ➔ **Read** (Required, so cert-manager can look up the Zone ID)
* **Zone** ➔ **DNS** ➔ **Edit** (Required, so cert-manager can create the TXT challenge)

Apply the token to the Kubernetes cluster manually (do not commit this token to Git!):
```bash
kubectl create secret generic cloudflare-api-token-secret \
  --from-literal=api-token="YOUR_CLOUDFLARE_API_TOKEN" \
  -n cert-manager
```

### 2. DNS Setup in Cloudflare
Remove the Cloudflare Tunnel routes pointing to subdomains, then replace them with a **DNS-Only (Gray Cloud) A Record** to the Tailscale IP:
* **Host**: `gitlab`, `argocd`, `grafana`, `vault`, `harbor`, `glance`
* **Target IP**: `100.120.133.63` (Tailscale Server IP)
* **Proxy Status**: Gray Cloud (DNS Only)

### 3. Certificate Monitoring
Use the following commands to monitor the certificate lifecycle:
```bash
# Check whether the certificate status is READY: True
kubectl get certificate -n kube-system

# Check cert-manager order status
kubectl get orders -n kube-system

# Check logs if DNS-01 verification issues occur
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager --tail=100
```