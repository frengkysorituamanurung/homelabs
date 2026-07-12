# Argo Rollouts Canary Deployment Guide

This document describes the **Replica-Based Canary Deployment** strategy configured for services in this environment, using `sample-api` as the reference implementation.

---

## 📌 Concept & Design

In this setup, we use a **Single Service & Single Ingress** pattern for canary testing:

1. **One Ingress / Domain**: Regular users access the application via the production URL (e.g., `http://api.frengky.xyz`).
2. **One Service**: The main Kubernetes Service (e.g., `sample-api`) targets pods from **both** the Stable and Canary ReplicaSets.
3. **Replica-based Traffic Splitting**: Traffic is split based on the ratio of active pods. For example:
   - If there is 1 Stable Pod and 1 Canary Pod running concurrently, Kubernetes will load-balance traffic roughly **50/50** between the old and new versions on the main domain.
   - If there are 4 Stable Pods and 1 Canary Pod, the traffic split will be **80/20**.

---

## 🛠️ Helm Chart Configuration (`generic-app`)

The `generic-app` Helm chart (v0.1.10+) supports two Canary modes:
1. **Multi-Service Canary**: Generates separate `-active` and `-preview` services/ingresses (configured when `canary.stableService` and `canary.canaryService` are defined).
2. **Single-Service Canary**: Generates a single main service and ingress, allowing Kubernetes to split traffic at the pod level (configured by leaving `stableService` and `canaryService` blank).

### Configuration in `values.yaml`:

To enable Single-Service Canary for your application, update the `values.yaml` in your GitOps repository:

```yaml
generic-app:
  # ... other settings
  ingress:
    enabled: true
    hosts:
      - host: api.frengky.xyz
        path: /
        port: 8080
  deploymentStrategy:
    type: Canary
    canary:
      # Leave stableService and canaryService undefined for Single-Service mode.
      steps:
        - setWeight: 20
        - pause: {} # Pause indefinitely for manual validation
        - setWeight: 50
        - pause: { duration: 10s }
```

---

## 🕹️ Operations Guide

When you push a new image tag to GitLab, Argo CD will trigger a canary release. The rollout will proceed through the defined steps and pause at step 1.

Use the following commands to check, promote, or abort the deployment.

### 1. Check Rollout Status
To view the progression of the rollout and the distribution of replicas:
```bash
# Using kubectl
kubectl get rollout sample-api -n backend

# Using Argo Rollouts CLI (if installed)
kubectl argo rollouts get rollout sample-api -n backend
```

### 2. Promote the Rollout (Approve Release)
If the new version behaves correctly on the main domain and you want to release it to 100% of users:
```bash
kubectl argo rollouts promote sample-api -n backend
```
*Argo Rollouts will progress to the next step, scale down the stable (old) ReplicaSet to 0, and make the new version the sole stable version.*

### 3. Abort the Rollout (Rollback)
If users report issues with the new version and you want to immediately roll back:
```bash
kubectl argo rollouts abort sample-api -n backend
```
*Argo Rollouts will scale the new ReplicaSet down to 0 and restore 100% of traffic to the old version.*

### 4. Reset/Retry after Abort
If you aborted a rollout and want to reset the status to healthy (so you can trigger a new update later):
```bash
kubectl argo rollouts retry rollout sample-api -n backend
```
