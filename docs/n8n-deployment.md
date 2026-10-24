# n8n Installation Documentation (Private Access via Tailscale)

This document describes the installation, deployment architecture, and security configuration for **n8n** on the `frengky.xyz` homelab Kubernetes cluster. n8n is deployed using the **GitOps (ArgoCD)** pattern and is configured to be accessible only securely (HTTPS) when connected to **Tailscale**.

---

## 🛠️ Architecture Overview & Access Pattern

Access to n8n is configured privately using the **Tailscale-only** model to keep automation data and workflows secure:

1. **New Namespace**: A dedicated `n8n` namespace is created.
2. **Domain/DNS**: The subdomain `n8n.frengky.xyz` is pointed directly at the Host Tailscale IP (`100.120.133.63`) in Cloudflare (DNS-Only / Gray Cloud). Traffic from outside the Tailscale mesh network cannot naturally route to this CGNAT Tailscale IP.
3. **Traefik Ingress**: The Ingress is configured using Ingress Class `traefik` for internal routing.
4. **SSL/TLS**: SSL is automatically served by Traefik using the default TLSStore wildcard certificate (`wildcard-frengky-xyz-tls`) issued by Let's Encrypt via cert-manager DNS-01 Challenge.
5. **Network Security (DNS & Tailscale Routing)**: Because the K3s service load balancer is deployed with `externalTrafficPolicy: Cluster`, the original Tailscale client IP is translated (NAT) into the internal cluster IP (load balancer pod IP). Therefore, the IP whitelist middleware cannot be applied because it would block valid traffic with a Forbidden error. Access restriction is fully performed at the network/DNS layer by pointing the domain `n8n.frengky.xyz` exclusively at the Host Tailscale IP (`100.120.133.63`).

---

## 📁 GitOps Manifest Structure

Manifest files are stored in the GitOps repository (`gitops-repo`) with the following structure:

```
gitops-repo/
├── kubernetes/
│   ├── applications/
│   │   └── production/
│   │       └── n8n.yaml            # ArgoCD Application definition
│   └── production/
│       └── n8n/
│           ├── deployment.yaml     # n8n deployment & env configuration
│           ├── service.yaml        # Internal cluster service
│           ├── pvc.yaml            # Persistent storage (SQLite DB)
│           └── ingress.yaml        # Traefik routing rules & whitelist
└── docs/
    └── n8n-deployment.md           # This document
```

### 1. ArgoCD Application (`k8s/clusters/production/applications/production/n8n.yaml`)
ArgoCD manages the lifecycle of this deployment automatically from the path `k8s/clusters/production/applications/apps/production/n8n`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: n8n
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  project: default
  source:
    repoURL: http://gitea-http.gitea.svc.cluster.local:3000/devops/gitops.git
    path: k8s/clusters/production/applications/apps/production/n8n
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: n8n
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 2. Persistent Storage (`k8s/clusters/production/applications/apps/production/n8n/pvc.yaml`)
n8n stores workflow data, credentials, and executions in a local SQLite database. A Persistent Volume Claim (PVC) is allocated using the built-in K3s storage class (`local-path`):
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: n8n-pvc
  namespace: n8n
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
```

### 3. n8n Deployment (`k8s/clusters/production/applications/apps/production/n8n/deployment.yaml`)
The n8n deployment uses the official image `n8nio/n8n:latest`. Pod security is tightened with a `securityContext` so it runs as user `1000` (node) to match permissions on the mounted folder `/home/node/.n8n`.
```yaml
apiVersion: k8s/clusters/production/applications/apps/v1
kind: Deployment
metadata:
  name: n8n
  namespace: n8n
  labels:
    app: n8n
spec:
  replicas: 1
  selector:
    matchLabels:
      app: n8n
  template:
    metadata:
      labels:
        app: n8n
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: n8n
          image: docker.io/n8nio/n8n:latest
          ports:
            - containerPort: 5678
              name: http
          env:
            - name: N8N_HOST
              value: "n8n.frengky.xyz"
            - name: N8N_PORT
              value: "5678"
            - name: N8N_PROTOCOL
              value: "https"
            - name: NODE_ENV
              value: "production"
            - name: N8N_WEBHOOK_URL
              value: "https://n8n.frengky.xyz/"
            - name: N8N_ENCRYPTION_KEY
              value: "n8n-encryption-key-for-frengky-xyz"
          volumeMounts:
            - name: n8n-storage
              mountPath: /home/node/.n8n
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "1Gi"
              cpu: "1000m"
      volumes:
        - name: n8n-storage
          persistentVolumeClaim:
            claimName: n8n-pvc
```

### 4. Service (`k8s/clusters/production/applications/apps/production/n8n/service.yaml`)
The internal cluster service of type `ClusterIP` exposes n8n's port 5678 to the ingress controller:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: n8n
  namespace: n8n
  labels:
    app: n8n
spec:
  ports:
    - port: 5678
      targetPort: 5678
      name: http
  selector:
    app: n8n
  type: ClusterIP
```

### 5. Ingress (`k8s/clusters/production/applications/apps/production/n8n/ingress.yaml`)
This Ingress routes the domain `n8n.frengky.xyz` to the n8n service:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: n8n
  namespace: n8n
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  ingressClassName: traefik
  rules:
    - host: n8n.frengky.xyz
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: n8n
                port:
                  number: 5678
```

---

## 🔍 Access Verification & Testing

To make sure n8n is running normally and is only accessible via Tailscale:

1. **Verify Pod & Service**:
   ```bash
   kubectl get pods,svc,ingress -n n8n
   ```
   Make sure the pod status is `Running` (1/1) and the `n8n` ingress has been created with host `n8n.frengky.xyz`.

2. **Test DNS Resolution**:
   Make sure the domain `n8n.frengky.xyz` resolves to the Host Tailscale IP:
   ```bash
   nslookup n8n.frengky.xyz
   # Output should return: 100.120.133.63
   ```

3. **Test HTTP Access (With Tailscale Active)**:
   Access `https://n8n.frengky.xyz` via a browser on a device connected to Tailscale. You will immediately see the n8n setup page with a valid SSL certificate (*secured*).

4. **Security Test (Without Tailscale)**:
   Disconnect Tailscale on the test device, then try to access `https://n8n.frengky.xyz`. The browser will not be able to load the page because the IP `100.120.133.63` cannot be reached from the public internet. Additionally, if accessed from an external network connected to the host, the Traefik middleware `tailscale-whitelist` will reject the request with a `Forbidden` response if the client IP is not recognized.