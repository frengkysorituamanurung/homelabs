# Canary Deployment Guide (Argo Rollouts removed)

Argo Rollouts has been removed from this cluster. Canary/blue-green deployments
are no longer managed via Argo Rollouts.

If canary deployments are required in the future, consider Flux CD image
automation plus a manual rollout strategy, or a lightweight in-cluster tool.
```