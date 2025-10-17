# GitOps Quick Start Guide

This is a condensed, action-oriented guide for implementing GitOps with Flux. For detailed explanations and concepts, see [GITOPS-ROADMAP.md](./GITOPS-ROADMAP.md).

## Prerequisites

```bash
# 1. Install flux CLI
brew install fluxcd/tap/flux

# 2. Check cluster compatibility
flux check --pre

# 3. Set GitHub token
export GITHUB_TOKEN=<your-personal-access-token>
# Token needs: repo permissions (all)
```

## Step 1: Bootstrap Flux (5 minutes)

This installs Flux and connects it to your repository:

```bash
flux bootstrap github \
  --owner=rjeans \
  --repository=automation \
  --branch=main \
  --path=flux/clusters/talos \
  --personal \
  --read-write-key
```

**What this does**:
- Installs Flux to `flux-system` namespace
- Commits Flux config to your repo under `flux/clusters/talos/`
- Configures Flux to watch this path
- Any changes to `flux/clusters/talos/` will automatically apply to cluster

**Verify**:
```bash
flux check
kubectl get pods -n flux-system
```

## Step 2: Create Directory Structure

```bash
cd /Users/rich/Library/CloudStorage/Dropbox/Development/automation

mkdir -p flux/clusters/talos/{sources,infrastructure,apps,notifications}
```

## Step 3: Define Helm Repositories

Create `flux/clusters/talos/sources/helm-repositories.yaml`:

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: traefik
  namespace: flux-system
spec:
  interval: 1h
  url: https://traefik.github.io/charts
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: metrics-server
  namespace: flux-system
spec:
  interval: 1h
  url: https://kubernetes-sigs.github.io/metrics-server
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: n8n
  namespace: flux-system
spec:
  interval: 1h
  url: https://8gears.container-registry.com/chartrepo/library
```

```bash
git add flux/clusters/talos/sources/
git commit -m "feat: Add Helm repository sources for Flux"
git push

# Watch Flux discover the Helm repos
flux get sources helm --watch
```

## Step 4: Create Infrastructure Layer

Create `flux/clusters/talos/infrastructure/kustomization.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./flux/clusters/talos/infrastructure
  prune: true
  wait: true
  timeout: 5m
```

## Step 5: Migrate Traefik to Flux

Create directory:
```bash
mkdir -p flux/clusters/talos/infrastructure/traefik
```

Create `flux/clusters/talos/infrastructure/traefik/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: traefik
  labels:
    dashboard.monitor: "true"
```

Create `flux/clusters/talos/infrastructure/traefik/helmrelease.yaml`:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: traefik
  namespace: traefik
spec:
  interval: 10m
  timeout: 5m
  chart:
    spec:
      chart: traefik
      version: "33.2.1"
      sourceRef:
        kind: HelmRepository
        name: traefik
        namespace: flux-system
      interval: 1m
  install:
    crds: CreateReplace
    remediation:
      retries: 3
  upgrade:
    crds: CreateReplace
    remediation:
      retries: 3
  values:
    # Copy values from kubernetes/core/traefik/values.yaml
    deployment:
      replicas: 2
    service:
      type: NodePort
      nodePorts:
        web: 30080
        websecure: 30443
    # ... rest of your values
```

**Better approach** - Reference existing values file:

Create `flux/clusters/talos/infrastructure/traefik/values-configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: traefik-values
  namespace: traefik
data:
  values.yaml: |
    # Paste content from kubernetes/core/traefik/values.yaml here
```

Update `helmrelease.yaml` to use ConfigMap:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: traefik
  namespace: traefik
spec:
  interval: 10m
  chart:
    spec:
      chart: traefik
      version: "33.2.1"
      sourceRef:
        kind: HelmRepository
        name: traefik
        namespace: flux-system
  valuesFrom:
    - kind: ConfigMap
      name: traefik-values
      valuesKey: values.yaml
```

Create `flux/clusters/talos/infrastructure/traefik/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - values-configmap.yaml
  - helmrelease.yaml
```

**Commit and watch**:

```bash
git add flux/clusters/talos/infrastructure/
git commit -m "feat: Add Traefik to Flux management"
git push

# Watch Flux install Traefik
flux get helmreleases -A --watch

# Check specific status
flux get helmrelease traefik -n traefik

# View details if issues
flux describe helmrelease traefik -n traefik
```

**Handle existing Helm release**:

```bash
# Option A: Uninstall existing, let Flux reinstall
helm uninstall traefik -n traefik
# Wait 1-2 minutes for Flux to reconcile

# Option B: Let Flux adopt existing (advanced)
# This works if the chart version matches exactly
```

## Step 6: Migrate Metrics Server

Create `flux/clusters/talos/infrastructure/metrics-server/helmrelease.yaml`:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: metrics-server
  namespace: kube-system
spec:
  interval: 10m
  chart:
    spec:
      chart: metrics-server
      version: "3.13.0"
      sourceRef:
        kind: HelmRepository
        name: metrics-server
        namespace: flux-system
  values:
    args:
      - --kubelet-insecure-tls
      - --kubelet-preferred-address-types=InternalIP
```

```bash
git add flux/clusters/talos/infrastructure/metrics-server/
git commit -m "feat: Add metrics-server to Flux"
git push

# Uninstall existing
helm uninstall metrics-server -n kube-system

# Watch Flux reinstall
flux get helmrelease metrics-server -n kube-system --watch
```

## Step 7: Migrate Cloudflare Tunnel

Create `flux/clusters/talos/infrastructure/cloudflare-tunnel/kustomization.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cloudflare-tunnel
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./kubernetes/core/cloudflare-tunnel
  prune: true
  wait: true
```

This directly uses your existing manifest! No duplication needed.

```bash
git add flux/clusters/talos/infrastructure/cloudflare-tunnel/
git commit -m "feat: Add Cloudflare Tunnel to Flux"
git push
```

## Step 8: Create Apps Layer

Create `flux/clusters/talos/apps/kustomization.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m
  dependsOn:
    - name: infrastructure
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./flux/clusters/talos/apps
  prune: true
  wait: true
```

Note: `dependsOn` ensures infrastructure is ready before deploying apps.

## Step 9: Migrate n8n

Create `flux/clusters/talos/apps/n8n/helmrelease.yaml`:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: n8n
  namespace: n8n
spec:
  interval: 10m
  chart:
    spec:
      chart: n8n
      version: "1.15.12"
      sourceRef:
        kind: HelmRepository
        name: n8n
        namespace: flux-system
  install:
    createNamespace: true
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
  valuesFrom:
    - kind: ConfigMap
      name: n8n-values
      valuesKey: values.yaml
```

Create `flux/clusters/talos/apps/n8n/values-configmap.yaml` with content from `kubernetes/apps/n8n/values.yaml`.

Create `flux/clusters/talos/apps/n8n/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: n8n
resources:
  - values-configmap.yaml
  - helmrelease.yaml
  - ../../../kubernetes/apps/n8n/ingress-external.yaml
  - ../../../kubernetes/apps/n8n/network-policy.yaml
```

```bash
git add flux/clusters/talos/apps/n8n/
git commit -m "feat: Add n8n to Flux management"
git push

# Uninstall existing
helm uninstall n8n -n n8n

# Watch Flux reinstall
flux get helmrelease n8n -n n8n --watch
```

## Step 10: Migrate Cluster Dashboard

Create `flux/clusters/talos/apps/cluster-dashboard/kustomization.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-dashboard
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./kubernetes/apps/cluster-dashboard
  prune: true
  wait: true
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: cluster-dashboard
      namespace: cluster-dashboard
```

```bash
git add flux/clusters/talos/apps/cluster-dashboard/
git commit -m "feat: Add cluster-dashboard to Flux management"
git push

# Delete existing
kubectl delete -f kubernetes/apps/cluster-dashboard/

# Watch Flux recreate
flux get kustomization cluster-dashboard --watch
```

## Step 11: Verify Everything

```bash
# Check all Flux resources
flux get all -A

# Check specific layers
flux get kustomizations
flux get helmreleases -A

# Check health
kubectl get pods -A

# View continuous reconciliation
flux get kustomizations --watch
```

## Step 12: Test GitOps Workflow

Make a change to test automatic deployment:

```bash
# Edit a manifest
vim kubernetes/apps/cluster-dashboard/deployment.yaml
# Change replicas or add a label

# Commit and push
git add kubernetes/apps/cluster-dashboard/deployment.yaml
git commit -m "test: Change cluster-dashboard replicas"
git push

# Watch Flux apply the change automatically
flux get kustomization cluster-dashboard --watch

# See the change in cluster
kubectl get deployment cluster-dashboard -n cluster-dashboard
```

**Magic**: You didn't run `kubectl apply`! Flux did it automatically.

## Common Commands

```bash
# Force immediate reconciliation (don't wait for interval)
flux reconcile kustomization flux-system --with-source

# View logs for debugging
flux logs --level=error --all-namespaces
flux logs --kind=HelmRelease --name=traefik -n traefik

# Suspend/resume (for maintenance)
flux suspend kustomization apps
flux resume kustomization apps

# Check what Flux is managing
flux get sources all
flux get kustomizations
flux get helmreleases -A

# Trace a resource back to its Flux source
flux trace deployment traefik -n traefik
```

## Troubleshooting

### Flux can't find Git repository
```bash
flux get sources git
# If error, check GitHub token permissions
```

### HelmRelease stuck in "not ready"
```bash
flux describe helmrelease <name> -n <namespace>
kubectl logs -n flux-system deploy/helm-controller -f
```

### Kustomization fails
```bash
flux describe kustomization <name>
kubectl logs -n flux-system deploy/kustomize-controller -f
```

### Want to see what Flux will apply (dry-run)
```bash
# Use flux diff (requires flux CLI v2.3+)
flux diff kustomization apps --path ./flux/clusters/talos/apps
```

## Next Steps

Once basic GitOps is working:

1. **Add SOPS for secrets** - See Phase 5 in [GITOPS-ROADMAP.md](./GITOPS-ROADMAP.md)
2. **Set up notifications** - Get Slack alerts for deployments
3. **Add health checks** - Ensure apps are truly ready
4. **Test disaster recovery** - Delete everything, watch Flux rebuild
5. **Add image automation** - Auto-update container images

## Complete Directory Structure

After migration, you'll have:

```
automation/
├── flux/
│   └── clusters/
│       └── talos/
│           ├── flux-system/              # Managed by bootstrap
│           ├── sources/
│           │   └── helm-repositories.yaml
│           ├── infrastructure/
│           │   ├── kustomization.yaml
│           │   ├── traefik/
│           │   ├── metrics-server/
│           │   └── cloudflare-tunnel/
│           └── apps/
│               ├── kustomization.yaml
│               ├── n8n/
│               └── cluster-dashboard/
└── kubernetes/                           # Original manifests (still used!)
    ├── core/
    └── apps/
```

## Success Criteria

You've successfully implemented GitOps when:

- [ ] All infrastructure deploys automatically from Git
- [ ] Manual `kubectl apply` is no longer needed
- [ ] Git push triggers automatic cluster updates
- [ ] Flux reverts manual changes back to Git state
- [ ] `flux get all -A` shows all resources as "Ready"
- [ ] You can rebuild the entire cluster from Git alone

---

**Remember**: Git is now the source of truth. To change the cluster, change Git!
