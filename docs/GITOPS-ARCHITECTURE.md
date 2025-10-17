# GitOps Architecture Overview

## The Big Picture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Developer Workflow                          │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                    1. Edit YAML files locally
                    2. git commit -m "feat: update n8n"
                    3. git push
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         GitHub Repository                           │
│  github.com/rjeans/automation                                       │
│                                                                       │
│  flux/clusters/talos/                                               │
│  ├── infrastructure/    ← Core services (Traefik, etc.)             │
│  ├── apps/              ← Applications (n8n, dashboard)             │
│  └── sources/           ← Helm repos, Git repos                     │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Flux polls every 1 minute
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Flux Controllers (flux-system)                    │
│                                                                       │
│  ┌─────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ Source          │  │ Kustomize        │  │ Helm             │  │
│  │ Controller      │  │ Controller       │  │ Controller       │  │
│  │                 │  │                  │  │                  │  │
│  │ • Fetches from  │  │ • Applies YAML   │  │ • Manages Helm   │  │
│  │   Git           │  │   manifests      │  │   releases       │  │
│  │ • Downloads     │  │ • Runs kubectl   │  │ • Runs helm      │  │
│  │   Helm charts   │  │   apply          │  │   upgrade        │  │
│  └─────────────────┘  └──────────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Applies changes
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster (Talos)                       │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Infrastructure Namespace                                      │  │
│  │  • Traefik (Ingress)                                         │  │
│  │  • Metrics Server                                            │  │
│  │  • Cloudflare Tunnel                                         │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Application Namespaces                                        │  │
│  │  • n8n (n8n namespace)                                       │  │
│  │  • Cluster Dashboard (cluster-dashboard namespace)           │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Continuous monitoring
                                    ▼
                        Flux validates resource health
                        Detects drift from Git state
                        Auto-corrects manual changes
```

## Reconciliation Loop

```
    ┌─────────────────────────────────────────────────┐
    │                                                 │
    │  1. Flux checks Git for new commits            │
    │     (Every 1 minute)                            │
    │                                                 │
    └────────────────┬────────────────────────────────┘
                     │
                     ▼
    ┌─────────────────────────────────────────────────┐
    │                                                 │
    │  2. Compare Git state vs Cluster state          │
    │     (Detect differences)                        │
    │                                                 │
    └────────────────┬────────────────────────────────┘
                     │
                     ▼
            ┌────────┴────────┐
            │                 │
            ▼                 ▼
    ┌───────────────┐  ┌──────────────┐
    │ No changes    │  │ Changes      │
    │ detected      │  │ detected     │
    │               │  │              │
    │ → Wait 1 min  │  │ → Apply      │
    └───────────────┘  └──────┬───────┘
                              │
                              ▼
    ┌─────────────────────────────────────────────────┐
    │                                                 │
    │  3. Download manifests from Git                 │
    │     Fetch Helm charts if needed                 │
    │                                                 │
    └────────────────┬────────────────────────────────┘
                     │
                     ▼
    ┌─────────────────────────────────────────────────┐
    │                                                 │
    │  4. Apply changes to cluster                    │
    │     (kubectl apply / helm upgrade)              │
    │                                                 │
    └────────────────┬────────────────────────────────┘
                     │
                     ▼
    ┌─────────────────────────────────────────────────┐
    │                                                 │
    │  5. Validate health of resources                │
    │     Check if pods are ready                     │
    │     Verify services are accessible              │
    │                                                 │
    └────────────────┬────────────────────────────────┘
                     │
                     ▼
            ┌────────┴────────┐
            │                 │
            ▼                 ▼
    ┌───────────────┐  ┌──────────────┐
    │ Success       │  │ Failure      │
    │               │  │              │
    │ → Mark Ready  │  │ → Retry      │
    │ → Wait 1 min  │  │ → Alert      │
    └───────────────┘  └──────────────┘
            │                 │
            └────────┬────────┘
                     │
                     ▼
                Back to Step 1
```

## Resource Hierarchy

Flux uses a dependency tree to ensure correct deployment order:

```
flux-system (Flux itself)
    │
    ├── GitRepository (flux-system)
    │   └── Points to: github.com/rjeans/automation
    │
    ├── HelmRepository (traefik)
    │   └── Points to: https://traefik.github.io/charts
    │
    ├── HelmRepository (n8n)
    │   └── Points to: https://8gears.container-registry.com/chartrepo/library
    │
    ├── Kustomization (infrastructure)
    │   │   Depends on: Nothing (deployed first)
    │   │   Path: ./flux/clusters/talos/infrastructure
    │   │
    │   ├── HelmRelease (traefik)
    │   │   └── Depends on: HelmRepository/traefik
    │   │
    │   ├── HelmRelease (metrics-server)
    │   │   └── Depends on: HelmRepository/metrics-server
    │   │
    │   └── Kustomization (cloudflare-tunnel)
    │       └── Depends on: Nothing
    │
    └── Kustomization (apps)
        │   Depends on: Kustomization/infrastructure
        │   Path: ./flux/clusters/talos/apps
        │
        ├── HelmRelease (n8n)
        │   └── Depends on: HelmRepository/n8n, Kustomization/infrastructure
        │
        └── Kustomization (cluster-dashboard)
            └── Depends on: Kustomization/infrastructure
```

## Before and After GitOps

### Before GitOps (Manual)

```
Developer                  Cluster
    │                         │
    │ 1. Edit YAML            │
    │ 2. kubectl apply        │
    ├────────────────────────►│
    │                         │
    │ 3. helm upgrade         │
    ├────────────────────────►│
    │                         │
    │ (Maybe commit to Git?)  │
    │                         │
    │                         │ Someone runs kubectl edit
    │                         │ (Drift from Git!)
    │                         │
```

**Problems**:
- Manual steps required
- Git may not match cluster
- No audit trail
- Can't rebuild from Git alone
- Manual changes not tracked

### After GitOps (Automated)

```
Developer                  GitHub                 Flux                   Cluster
    │                         │                     │                       │
    │ 1. Edit YAML            │                     │                       │
    │ 2. git commit/push      │                     │                       │
    ├────────────────────────►│                     │                       │
    │                         │                     │                       │
    │                         │ 3. Flux polls       │                       │
    │                         │◄────────────────────┤                       │
    │                         │                     │                       │
    │                         │ 4. New commit found │                       │
    │                         ├────────────────────►│                       │
    │                         │                     │                       │
    │                         │                     │ 5. Apply to cluster   │
    │                         │                     ├──────────────────────►│
    │                         │                     │                       │
    │                         │                     │ 6. Monitor health     │
    │                         │                     │◄──────────────────────┤
    │                         │                     │                       │
    │                         │                     │                       │
    │                         │                     │                       │
    │                         │                     │    Someone runs       │
    │                         │                     │    kubectl edit       │
    │                         │                     │◄──────────────────────┤
    │                         │                     │                       │
    │                         │                     │ 7. Detect drift       │
    │                         │                     │    and revert         │
    │                         │                     ├──────────────────────►│
    │                         │                     │                       │
```

**Benefits**:
- No manual kubectl/helm commands
- Git is always source of truth
- Full audit trail
- Can rebuild from Git alone
- Automatic drift correction

## File Organization

Your repository structure with GitOps:

```
automation/
│
├── flux/                                # GitOps configuration
│   └── clusters/
│       └── talos/                       # Cluster-specific config
│           │
│           ├── flux-system/             # Flux's own config (auto-generated)
│           │   ├── gotk-components.yaml
│           │   └── gotk-sync.yaml
│           │
│           ├── sources/                 # Where to fetch from
│           │   ├── git-repository.yaml  # This repo
│           │   └── helm-repositories.yaml
│           │
│           ├── infrastructure/          # Core services (layer 1)
│           │   ├── kustomization.yaml   # Flux Kustomization
│           │   │
│           │   ├── traefik/
│           │   │   ├── namespace.yaml
│           │   │   ├── helmrelease.yaml # Flux HelmRelease CRD
│           │   │   └── values.yaml
│           │   │
│           │   ├── metrics-server/
│           │   │   └── helmrelease.yaml
│           │   │
│           │   └── cloudflare-tunnel/
│           │       └── kustomization.yaml
│           │
│           └── apps/                    # Applications (layer 2)
│               ├── kustomization.yaml
│               │
│               ├── n8n/
│               │   ├── helmrelease.yaml
│               │   ├── values.yaml
│               │   └── kustomization.yaml
│               │
│               └── cluster-dashboard/
│                   └── kustomization.yaml # References kubernetes/apps/cluster-dashboard
│
├── kubernetes/                          # Original manifests (still used!)
│   ├── core/
│   │   ├── traefik/
│   │   │   └── values.yaml
│   │   └── cloudflare-tunnel/
│   │       └── deployment.yaml
│   │
│   └── apps/
│       ├── n8n/
│       │   ├── values.yaml
│       │   ├── ingress-external.yaml
│       │   └── network-policy.yaml
│       │
│       └── cluster-dashboard/
│           ├── deployment.yaml
│           ├── ingress-external.yaml
│           └── ...
│
└── docs/
    ├── GITOPS-ROADMAP.md                # Detailed guide
    ├── GITOPS-QUICKSTART.md             # Quick implementation
    └── GITOPS-ARCHITECTURE.md           # This file
```

## Key Flux Custom Resources

### GitRepository

Tells Flux where your Git repo is:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: automation
  namespace: flux-system
spec:
  interval: 1m              # How often to check for new commits
  url: https://github.com/rjeans/automation
  ref:
    branch: main
```

### HelmRepository

Tells Flux where Helm charts are:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: traefik
  namespace: flux-system
spec:
  interval: 1h              # How often to check for new chart versions
  url: https://traefik.github.io/charts
```

### Kustomization (Flux type)

Tells Flux to apply Kubernetes manifests:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m             # How often to reconcile
  sourceRef:
    kind: GitRepository
    name: automation
  path: ./kubernetes/apps   # Path in Git repo
  prune: true               # Delete resources removed from Git
  wait: true                # Wait for resources to be ready
```

### HelmRelease

Tells Flux to install/upgrade a Helm chart:

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
  values:
    # Your custom values
```

## Common Workflows

### 1. Deploy New Application

```bash
# 1. Create Flux Kustomization
cat > flux/clusters/talos/apps/myapp/kustomization.yaml <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: myapp
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./kubernetes/apps/myapp
  prune: true
EOF

# 2. Create Kubernetes manifests
mkdir -p kubernetes/apps/myapp
# Add your deployment.yaml, service.yaml, etc.

# 3. Commit and push
git add flux/clusters/talos/apps/myapp/ kubernetes/apps/myapp/
git commit -m "feat: Add myapp"
git push

# 4. Watch Flux deploy it (no kubectl apply needed!)
flux get kustomization myapp --watch
```

### 2. Update Application

```bash
# 1. Edit manifest
vim kubernetes/apps/cluster-dashboard/deployment.yaml
# Change image tag, replicas, etc.

# 2. Commit and push
git commit -am "feat: Update cluster-dashboard to v1.2.0"
git push

# 3. Watch Flux apply the change
flux get kustomization cluster-dashboard --watch

# No kubectl apply needed!
```

### 3. Rollback

```bash
# 1. Revert the Git commit
git revert HEAD
git push

# 2. Flux automatically rolls back
flux get kustomizations --watch

# That's it!
```

### 4. Emergency Manual Change

```bash
# If you absolutely must make a manual change in an emergency:

# 1. Suspend Flux for that resource
flux suspend kustomization apps

# 2. Make manual change
kubectl edit deployment n8n -n n8n

# 3. Fix the issue

# 4. Update Git to match your manual change
vim kubernetes/apps/n8n/deployment.yaml
git commit -am "fix: Emergency fix for n8n"
git push

# 5. Resume Flux
flux resume kustomization apps
```

## Monitoring GitOps Health

```bash
# Overall status
flux get all -A

# Check Git sync
flux get sources git

# Check Helm repos
flux get sources helm

# Check Kustomizations
flux get kustomizations

# Check HelmReleases
flux get helmreleases -A

# View logs
flux logs --all-namespaces --follow
```

## Success Indicators

You know GitOps is working when:

1. **Green status**: `flux get all -A` shows everything as "Ready"
2. **No manual kubectl**: Haven't used `kubectl apply` in weeks
3. **Git is truth**: Cluster state matches Git exactly
4. **Drift reverted**: Manual changes automatically corrected
5. **Fast recovery**: Can rebuild cluster from Git in minutes
6. **Audit trail**: Every change has a Git commit
7. **Collaboration**: Team uses PRs for infrastructure changes

## Troubleshooting Flow

```
Is Flux working?
    │
    ├─ No → flux check
    │         │
    │         └─ Check Flux pods: kubectl get pods -n flux-system
    │
    └─ Yes → Can Flux reach Git?
              │
              ├─ No → flux get sources git
              │         │
              │         └─ Check GitHub token, network
              │
              └─ Yes → Is resource deploying?
                        │
                        ├─ No → flux describe kustomization <name>
                        │         flux describe helmrelease <name>
                        │         │
                        │         └─ Check logs:
                        │             kubectl logs -n flux-system deploy/kustomize-controller
                        │             kubectl logs -n flux-system deploy/helm-controller
                        │
                        └─ Yes → Is resource healthy?
                                  │
                                  └─ Check Kubernetes:
                                      kubectl get pods -A
                                      kubectl describe pod <name>
```

---

This architecture ensures your entire Kubernetes cluster is:
- **Declarative**: Described in YAML
- **Version-controlled**: Every change in Git
- **Automated**: No manual intervention
- **Recoverable**: Rebuild from Git alone
- **Auditable**: Complete change history
- **Consistent**: No configuration drift
