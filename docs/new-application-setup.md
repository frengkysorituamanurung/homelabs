# Adding a New Application (Flux CD) — Example: Uptime Kuma

This guide is the standard procedure for onboarding a new application into the
`frengky.xyz` homelab now that GitOps is managed by **Flux CD**.

It uses **Uptime Kuma** as a concrete example. Adapt names/paths for other apps.

---

## 0. Prerequisites

- `kubectl` access to the cluster (cluster-admin).
- `flux` CLI installed locally.
- Push access to `https://github.com/frengkysorituamanurung/homelabs.git`.
- If the app needs secrets: Vault + ESO already running (`vault-backend` ClusterSecretStore).

---

## 1. Choose the Deployment Pattern

| Pattern | When to use | Example |
|---|---|---|
| **Upstream Helm (OCI or HTTPS)** | Chart published upstream | Uptime Kuma (OCI: `ghcr.io/...`) |
| **Vendored local chart** | Custom chart in `helm/charts/*` | garage, generic-app |
| **Plain manifests** | No chart, raw YAML | cloudflared, n8n |

For Uptime Kuma we use **upstream Helm via OCI** (cleanest, no vendored chart).

---

## 2. Create the Application Directory

```bash
mkdir -p infrastructure/uptime-kuma/flux
```

Layout:

```
infrastructure/uptime-kuma/
├── values.yaml          # Helm values (optional if inlined)
└── flux/
    ├── helmrepository.yaml
    ├── helmrelease.yaml
    └── kustomization.yaml
```

---

## 3. Create the HelmRepository (OCI)

`infrastructure/uptime-kuma/flux/helmrepository.yaml`:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: uptime-kuma
  namespace: flux-system
spec:
  type: oci
  interval: 24h
  url: oci://ghcr.io/louislam/uptime-kuma  # adjust to real chart repo
```

> If the chart is hosted on an HTTPS Helm repo instead, omit `type: oci` and use the HTTPS URL.

---

## 4. Create the HelmRelease

`infrastructure/uptime-kuma/flux/helmrelease.yaml`:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: uptime-kuma
  namespace: flux-system
spec:
  interval: 5m
  chart:
    spec:
      chart: uptime-kuma        # chart name in the repo
      version: "2.x"            # pin a version or range
      sourceRef:
        kind: HelmRepository
        name: uptime-kuma
        namespace: flux-system
  releaseName: uptime-kuma
  targetNamespace: uptime-kuma
  install:
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
  values:
    ingress:
      enabled: true
      hosts:
        - host: status.frengky.xyz
          paths:
            - path: /
              pathType: Prefix
    persistence:
      enabled: true
      size: 1Gi
```

Tips:
- For large value files, put them in `infrastructure/uptime-kuma/values.yaml` and use `valuesFrom` (ConfigMap) instead of inlining.
- Pin versions; avoid `latest`.

---

## 5. Create the Kustomization (for the flux dir)

`infrastructure/uptime-kuma/flux/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrepository.yaml
  - helmrelease.yaml
```

---

## 6. Register in the Top-Level Kustomization

Edit `clusters/production/flux-system/kustomization.yaml` and add:

```yaml
  - infrastructure/uptime-kuma/flux
```

Or, if using a dedicated Flux Kustomization resource, create
`clusters/production/flux-system/uptime-kuma.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: uptime-kuma
  namespace: flux-system
spec:
  dependsOn:
    - name: flux-system
  interval: 5m
  path: ./infrastructure/uptime-kuma/flux
  prune: false
  wait: true
  sourceRef:
    kind: GitRepository
    name: homelabs
  timeout: 5m
```

and add `clusters/production/flux-system/uptime-kuma.yaml` to the top-level `kustomization.yaml` resources.

---

## 7. Add Secrets (if needed)

1. Store in Vault:
   ```bash
   kubectl exec -n vault -it vault-0 -- vault kv put secret/uptime-kuma \
     adminPassword=<STRONG_PASSWORD>
   ```
2. Create an ExternalSecret in `infrastructure/uptime-kuma/flux/externalsecret.yaml` using `secrets/templates/` as a reference.
3. Add it to `kustomization.yaml` resources.

---

## 8. Add Ingress / DNS

- The Helm values above create an Ingress for `status.frengky.xyz`.
- For **private** (Tailscale) access: create a Gray-cloud A record in Cloudflare → `100.120.133.63`.
- For **public** access: add a Public Hostname in Cloudflare Tunnel → `http://traefik.kube-system.svc.cluster.local:80`.

---

## 9. Commit and Reconcile

```bash
git add infrastructure/uptime-kuma clusters/production/flux-system
git commit -m "feat: add uptime-kuma via Flux"
git push origin main

flux reconcile source git homelabs
flux reconcile kustomization flux-system -n flux-system
```

---

## 10. Validate

```bash
flux get kustomizations -n flux-system | grep uptime-kuma
flux get helmreleases -n flux-system | grep uptime-kuma
kubectl get pods -n uptime-kuma
kubectl get ingress -n uptime-kuma
```

Check the UI at `https://status.frengky.xyz`.

---

## 11. Rollback

```bash
# Suspend
flux suspend kustomization uptime-kuma -n flux-system

# Remove entirely
flux delete kustomization uptime-kuma -n flux-system
# delete the files from Git and push
```

---

## Checklist for Any New App

- [ ] Directory created under `infrastructure/<app>/flux/`
- [ ] `HelmRepository` (or `GitRepository` source) defined
- [ ] `HelmRelease` with pinned version, `releaseName`, `targetNamespace`
- [ ] Values inlined or referenced via ConfigMap
- [ ] Secrets via Vault + ESO (no plaintext in Git)
- [ ] Ingress + DNS configured (private vs public)
- [ ] Registered in top-level `kustomization.yaml`
- [ ] Committed and pushed
- [ ] Reconciled and validated (`flux get ...`, pod/ingress checks)
- [ ] Documented in `docs/` if non-trivial
```