# GitOps with Flux - Implementation Roadmap

## What is GitOps?

**GitOps** is a way of managing your infrastructure and applications where Git is the single source of truth. Instead of manually applying changes to your cluster with `kubectl apply` or `helm install`, you:

1. **Commit** desired state to Git (YAML manifests, Helm charts)
2. **Flux watches** your Git repository for changes
3. **Flux automatically applies** changes to your cluster
4. **Flux continuously reconciles** - if someone manually changes something in the cluster, Flux will revert it back to match Git

### Key Benefits

- **Rebuildable**: Entire cluster can be rebuilt from Git alone
- **Auditable**: Every change has a Git commit with author and timestamp
- **Recoverable**: Roll back by reverting Git commits
- **Consistent**: Drift detection ensures cluster matches Git
- **Collaborative**: Use pull requests for infrastructure changes
- **Automated**: No manual kubectl/helm commands needed

## Why Flux?

**Flux** is a CNCF graduated project (like Kubernetes itself) that implements GitOps patterns. It's:

- **Kubernetes-native**: Uses CRDs (Custom Resource Definitions)
- **Declarative**: Everything is described in YAML
- **Gitops-focused**: Built specifically for this use case
- **Helm-compatible**: Can manage Helm releases
- **Multi-source**: Can pull from multiple Git repos
- **Lightweight**: Minimal resource footprint

### Flux vs ArgoCD

Both are excellent, but Flux is:
- More CLI-driven and automatable
- Better for multi-cluster scenarios
- More minimalist (no UI by default)
- Better Helm integration

ArgoCD has a nice web UI but is heavier. For your infrastructure-as-code focus, Flux is ideal.

---

## Current State Analysis

### What You Have Now

**Infrastructure deployed manually**:
- Traefik (Helm) - Ingress controller
- n8n (Helm) - Workflow automation
- Cloudflare Tunnel (kubectl apply) - External access
- Cluster Dashboard (kubectl apply) - Monitoring
- Metrics Server (Helm) - Resource metrics

**Git repository structure**:
```
automation/
├── kubernetes/
│   ├── core/
│   │   ├── traefik/values.yaml
│   │   └── cloudflare-tunnel/deployment.yaml
│   └── apps/
│       ├── n8n/
│       │   ├── values.yaml
│       │   ├── ingress-external.yaml
│       │   └── network-policy.yaml
│       └── cluster-dashboard/
│           ├── deployment.yaml
│           ├── ingress-external.yaml
│           ├── rbac.yaml
│           └── ...
```

**The Gap**:
- Changes committed to Git but manually applied
- No automatic synchronization
- Manual Helm installs not tracked in cluster
- Drift can occur (manual changes not detected)

---

## GitOps Target State

### What You'll Have

**Flux manages everything**:
```
automation/
├── flux/
│   ├── flux-system/          # Flux's own configuration
│   │   ├── gotk-components.yaml
│   │   └── gotk-sync.yaml
│   ├── sources/              # Where to fetch manifests from
│   │   ├── git-repository.yaml
│   │   └── helm-repositories.yaml
│   ├── infrastructure/       # Core cluster services
│   │   ├── kustomization.yaml
│   │   ├── traefik/
│   │   │   └── helmrelease.yaml
│   │   ├── metrics-server/
│   │   │   └── helmrelease.yaml
│   │   └── cloudflare-tunnel/
│   │       └── kustomization.yaml
│   └── apps/                 # Applications
│       ├── kustomization.yaml
│       ├── n8n/
│       │   ├── helmrelease.yaml
│       │   ├── ingress.yaml
│       │   └── network-policy.yaml
│       └── cluster-dashboard/
│           └── kustomization.yaml
└── kubernetes/               # Existing manifests (will be referenced)
    ├── core/
    └── apps/
```

**The Transformation**:
- Git push → Flux automatically applies to cluster
- Helm releases managed by `HelmRelease` CRDs
- Everything reconciles every 10 minutes (configurable)
- Drift detection and automatic correction
- Health checks and notifications

---

## Implementation Roadmap

### Phase 1: Understanding Flux Concepts (No Changes Yet)

**Goal**: Learn the key concepts before touching your cluster

#### 1.1 Flux Architecture

Flux consists of several controllers:

1. **Source Controller**: Fetches from Git, Helm repos, S3 buckets
   - Watches for new commits
   - Downloads manifests and Helm charts
   - Makes them available to other controllers

2. **Kustomize Controller**: Applies Kubernetes manifests
   - Reads Kustomization resources
   - Applies YAML to cluster
   - Validates health of resources

3. **Helm Controller**: Manages Helm releases
   - Reads HelmRelease resources
   - Installs/upgrades Helm charts
   - Monitors release health

4. **Notification Controller**: Sends alerts
   - Git commit status updates
   - Slack/Discord notifications
   - Webhook triggers

#### 1.2 Key Custom Resources

**GitRepository**: Points to your Git repo
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: automation
  namespace: flux-system
spec:
  interval: 1m                    # Check for new commits every minute
  url: https://github.com/rjeans/automation
  ref:
    branch: main
```

**HelmRepository**: Points to Helm chart repos
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: traefik
  namespace: flux-system
spec:
  interval: 10m
  url: https://traefik.github.io/charts
```

**HelmRelease**: Declares desired Helm installation
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
    # Your custom values here (from kubernetes/core/traefik/values.yaml)
```

**Kustomization** (Flux kind, not kubectl): Applies manifests from Git
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-dashboard
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: automation
  path: ./kubernetes/apps/cluster-dashboard
  prune: true                     # Delete resources removed from Git
  wait: true                      # Wait for resources to be ready
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: cluster-dashboard
      namespace: cluster-dashboard
```

#### 1.3 Reconciliation Loop

The magic of GitOps:

1. **Flux checks Git** every interval (e.g., 1 minute)
2. **Detects changes**: New commit, tag, or branch
3. **Downloads manifests**: Clones repo, fetches Helm charts
4. **Applies to cluster**: Creates/updates/deletes resources
5. **Validates health**: Checks if deployments are ready
6. **Repeats continuously**: Ensures cluster matches Git

**Drift Detection**:
- If someone runs `kubectl edit deployment n8n`, Flux detects the difference
- Flux reverts the change back to what's in Git
- Result: Git is always the source of truth

---

### Phase 2: Install Flux (Read-Only Mode)

**Goal**: Install Flux and let it watch your repo without making changes yet

#### 2.1 Prerequisites

```bash
# Install flux CLI (if not already installed)
brew install fluxcd/tap/flux

# Check your cluster meets requirements
flux check --pre

# Check your GitHub access
export GITHUB_TOKEN=<your-token>
flux check --pre
```

#### 2.2 Bootstrap Flux

This single command:
- Installs Flux to your cluster
- Creates flux-system namespace
- Commits Flux's own config to your Git repo
- Configures Flux to watch your repo

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
1. Creates `flux/clusters/talos/flux-system/` in your repo
2. Installs Flux controllers to your cluster
3. Flux now watches `flux/clusters/talos/` for Flux resources
4. Commits are automatically applied to cluster

#### 2.3 Verify Installation

```bash
# Check Flux components
flux check

# Watch Flux reconcile
flux get all

# See Git repository status
flux get sources git

# View logs
flux logs --all-namespaces --follow
```

You now have Flux running, but it's not managing your apps yet.

---

### Phase 3: Migrate Core Infrastructure

**Goal**: Move Traefik, Metrics Server, and Cloudflare Tunnel to Flux management

#### 3.1 Create Directory Structure

```bash
mkdir -p flux/clusters/talos/{sources,infrastructure,apps}
```

#### 3.2 Define Helm Repositories

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

#### 3.3 Create Infrastructure Kustomization

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
```

#### 3.4 Migrate Traefik

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
  chart:
    spec:
      chart: traefik
      version: "33.2.1"
      sourceRef:
        kind: HelmRepository
        name: traefik
        namespace: flux-system
  install:
    createNamespace: false
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
  valuesFrom:
    - kind: ConfigMap
      name: traefik-values
      valuesKey: values.yaml
```

Create `flux/clusters/talos/infrastructure/traefik/values.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: traefik-values
  namespace: traefik
data:
  values.yaml: |
    # Content from kubernetes/core/traefik/values.yaml
```

Create `flux/clusters/talos/infrastructure/traefik/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - values.yaml
  - helmrelease.yaml
```

#### 3.5 Commit and Watch

```bash
git add flux/
git commit -m "feat: Add Traefik to Flux management"
git push

# Watch Flux reconcile
flux get helmreleases -A --watch

# Check Traefik specifically
flux get helmrelease traefik -n traefik
```

**What happens**:
1. Flux detects new commit
2. Reads HelmRelease resource
3. Fetches Traefik chart from Helm repo
4. Applies with your custom values
5. Monitors health

**Important**: You'll need to handle the existing Helm release:

```bash
# Option A: Let Flux adopt it (if versions match)
helm -n traefik annotate traefik meta.helm.sh/release-name=traefik
helm -n traefik annotate traefik meta.helm.sh/release-namespace=traefik

# Option B: Uninstall and let Flux reinstall
helm uninstall traefik -n traefik
# Wait for Flux to reconcile
```

#### 3.6 Repeat for Other Core Services

Follow same pattern for:
- Metrics Server
- Cloudflare Tunnel (as Kustomization, not Helm)

---

### Phase 4: Migrate Applications

**Goal**: Move n8n and cluster-dashboard to Flux

#### 4.1 Create Apps Kustomization

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

Note: `dependsOn` ensures infrastructure is ready before apps deploy.

#### 4.2 Migrate n8n

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
  postRenderers:
    - kustomize:
        patches:
          - target:
              kind: Deployment
              name: n8n
            patch: |
              - op: add
                path: /metadata/labels/dashboard.monitor
                value: "true"
```

Create `flux/clusters/talos/apps/n8n/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: n8n
resources:
  - values.yaml
  - helmrelease.yaml
  - ../../../kubernetes/apps/n8n/ingress-external.yaml
  - ../../../kubernetes/apps/n8n/network-policy.yaml
```

Note: This references your existing YAML files!

#### 4.3 Migrate Cluster Dashboard

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

This directly uses your existing manifests!

---

### Phase 5: Secrets Management

**Goal**: Securely store secrets in Git using SOPS

#### 5.1 Why Secrets Need Special Handling

Problem: Can't commit plain text secrets to Git (passwords, API keys, etc.)

Solution: **Mozilla SOPS** (Secrets OPerationS)
- Encrypts YAML values while keeping keys visible
- Uses age, GPG, AWS KMS, Azure Key Vault, or GCP KMS
- Flux can decrypt at apply time

#### 5.2 Install SOPS

```bash
brew install sops age
```

#### 5.3 Generate Encryption Key

```bash
# Generate age key
age-keygen -o ~/.config/sops/age/keys.txt

# Display public key (for .sops.yaml)
age-keygen -y ~/.config/sops/age/keys.txt
```

#### 5.4 Configure SOPS

Create `.sops.yaml` in repository root:

```yaml
creation_rules:
  - path_regex: .*.yaml
    encrypted_regex: ^(data|stringData)$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

#### 5.5 Create Encrypted Secret

```bash
# Create plain secret
kubectl create secret generic cloudflare-tunnel-token \
  -n cloudflare-tunnel \
  --from-literal=token=your-token-here \
  --dry-run=client -o yaml > cloudflare-secret.yaml

# Encrypt it
sops -e -i cloudflare-secret.yaml

# Commit encrypted version
git add cloudflare-secret.yaml
git commit -m "feat: Add encrypted Cloudflare tunnel token"
```

#### 5.6 Configure Flux to Decrypt

Create secret with age private key:

```bash
cat ~/.config/sops/age/keys.txt | \
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin
```

Update Kustomization to use SOPS:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  # ... existing config ...
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

**Important**: Never commit the private key (`keys.txt`) to Git! Store it securely (password manager, encrypted backup).

---

### Phase 6: Complete Automation

**Goal**: Achieve fully automated, rebuildable cluster

#### 6.1 Dependency Management

Control deployment order with `dependsOn`:

```yaml
# Apps depend on infrastructure
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  dependsOn:
    - name: infrastructure
  # ... rest of config
```

```yaml
# n8n depends on PostgreSQL
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: n8n
  namespace: n8n
spec:
  dependsOn:
    - name: postgresql
      namespace: n8n
  # ... rest of config
```

#### 6.2 Health Checks

Add health checks to ensure services are truly ready:

```yaml
spec:
  # ... other config ...
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: traefik
      namespace: traefik
    - apiVersion: v1
      kind: Service
      name: traefik
      namespace: traefik
```

#### 6.3 Notifications

Get notified of deployments:

Create `flux/clusters/talos/notifications/slack.yaml`:

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  type: slack
  channel: kubernetes-alerts
  secretRef:
    name: slack-webhook
---
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  providerRef:
    name: slack
  eventSeverity: info
  eventSources:
    - kind: Kustomization
      name: infrastructure
    - kind: HelmRelease
      namespace: '*'
```

#### 6.4 Image Automation (Optional)

Automatically update container images:

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: cluster-dashboard
  namespace: flux-system
spec:
  image: ghcr.io/rjeans/cluster-dashboard
  interval: 1m
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: cluster-dashboard
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: cluster-dashboard
  policy:
    semver:
      range: '>=1.0.0'
---
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: cluster-dashboard
  namespace: flux-system
spec:
  interval: 1m
  sourceRef:
    kind: GitRepository
    name: flux-system
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        name: fluxbot
        email: flux@users.noreply.github.com
      messageTemplate: 'chore: update cluster-dashboard to {{range .Updated.Images}}{{println .}}{{end}}'
    push:
      branch: main
  update:
    path: ./kubernetes/apps/cluster-dashboard
    strategy: Setters
```

---

### Phase 7: Disaster Recovery Testing

**Goal**: Prove you can rebuild from scratch

#### 7.1 Document Bootstrap Process

Create `docs/CLUSTER-BOOTSTRAP.md`:

```markdown
# Cluster Bootstrap from Scratch

## Prerequisites
1. Talos installed on all nodes
2. kubectl configured
3. flux CLI installed
4. GitHub personal access token

## Bootstrap Steps

1. Install Flux:
   ```bash
   flux bootstrap github \
     --owner=rjeans \
     --repository=automation \
     --branch=main \
     --path=flux/clusters/talos
   ```

2. Create SOPS secret:
   ```bash
   cat ~/.config/sops/age/keys.txt | \
   kubectl create secret generic sops-age \
     --namespace=flux-system \
     --from-file=age.agekey=/dev/stdin
   ```

3. Wait for reconciliation:
   ```bash
   flux get all --all-namespaces
   ```

That's it! Everything else is automatic.
```

#### 7.2 Test Recovery

```bash
# 1. Uninstall everything (scary!)
helm uninstall -n traefik traefik
helm uninstall -n n8n n8n
kubectl delete namespace cluster-dashboard cloudflare-tunnel

# 2. Trigger Flux reconciliation
flux reconcile kustomization flux-system --with-source

# 3. Watch everything come back
flux get all -A --watch

# 4. Verify all apps are healthy
kubectl get pods -A
```

If everything comes back automatically, you've achieved true GitOps!

---

## Reference: Directory Structure

```
automation/
├── flux/
│   └── clusters/
│       └── talos/
│           ├── flux-system/              # Flux's own config (managed by bootstrap)
│           │   ├── gotk-components.yaml
│           │   └── gotk-sync.yaml
│           ├── sources/                   # Git and Helm sources
│           │   ├── git-repository.yaml
│           │   └── helm-repositories.yaml
│           ├── infrastructure/            # Core services (deployed first)
│           │   ├── kustomization.yaml
│           │   ├── traefik/
│           │   │   ├── namespace.yaml
│           │   │   ├── values.yaml
│           │   │   ├── helmrelease.yaml
│           │   │   └── kustomization.yaml
│           │   ├── metrics-server/
│           │   │   └── helmrelease.yaml
│           │   └── cloudflare-tunnel/
│           │       ├── namespace.yaml
│           │       ├── secret.enc.yaml    # SOPS encrypted
│           │       ├── deployment.yaml
│           │       └── kustomization.yaml
│           ├── apps/                      # Applications (deployed after infrastructure)
│           │   ├── kustomization.yaml
│           │   ├── n8n/
│           │   │   ├── namespace.yaml
│           │   │   ├── values.yaml
│           │   │   ├── helmrelease.yaml
│           │   │   └── kustomization.yaml
│           │   └── cluster-dashboard/
│           │       └── kustomization.yaml  # References kubernetes/apps/cluster-dashboard
│           └── notifications/             # Alerts and notifications
│               ├── slack.yaml
│               └── kustomization.yaml
├── kubernetes/                            # Existing manifests (unchanged)
│   ├── core/
│   │   ├── traefik/
│   │   └── cloudflare-tunnel/
│   └── apps/
│       ├── n8n/
│       └── cluster-dashboard/
├── .sops.yaml                            # SOPS encryption config
└── docs/
    ├── GITOPS-ROADMAP.md                 # This document
    └── CLUSTER-BOOTSTRAP.md              # Recovery procedures
```

---

## Key Concepts Summary

### 1. Source of Truth
- Git is the only source of truth
- Manual changes are reverted by Flux
- To change cluster, change Git

### 2. Reconciliation Loop
- Flux checks Git every interval (default: 1m)
- Applies changes automatically
- Detects drift and corrects it
- Validates health of resources

### 3. Dependency Management
- Infrastructure deployed before apps
- Dependencies declared explicitly
- Health checks ensure readiness

### 4. Secrets Management
- SOPS encrypts sensitive data
- Safe to commit encrypted secrets to Git
- Flux decrypts at apply time
- Private key stored securely outside Git

### 5. Multi-Environment
- Same manifests, different overlays
- Can have `flux/clusters/dev/` and `flux/clusters/prod/`
- Each cluster watches its own path

---

## Migration Checklist

- [ ] Phase 1: Understand Flux concepts
- [ ] Phase 2: Install Flux with bootstrap
- [ ] Phase 3: Migrate Traefik to Flux
- [ ] Phase 3: Migrate Metrics Server to Flux
- [ ] Phase 3: Migrate Cloudflare Tunnel to Flux
- [ ] Phase 4: Migrate n8n to Flux
- [ ] Phase 4: Migrate cluster-dashboard to Flux
- [ ] Phase 5: Set up SOPS for secrets
- [ ] Phase 5: Encrypt Cloudflare tunnel token
- [ ] Phase 6: Configure health checks
- [ ] Phase 6: Set up notifications
- [ ] Phase 7: Document bootstrap procedure
- [ ] Phase 7: Test full cluster rebuild
- [ ] Phase 7: Verify all apps return to healthy state

---

## Common Commands Reference

```bash
# Check Flux status
flux check

# List all Flux resources
flux get all -A

# Force reconciliation
flux reconcile kustomization flux-system --with-source
flux reconcile helmrelease traefik -n traefik

# Watch reconciliation
flux get kustomizations --watch
flux get helmreleases -A --watch

# View logs
flux logs --level=error --all-namespaces
flux logs --kind=Kustomization --name=apps

# Suspend/resume reconciliation
flux suspend kustomization apps
flux resume kustomization apps

# Export current resource
flux export helmrelease traefik -n traefik

# Trace a resource back to Git
flux trace deployment traefik -n traefik
```

---

## Troubleshooting

### Flux can't clone repository
```bash
# Check git source
flux get sources git
flux describe source git flux-system

# Common issue: wrong credentials
# Fix: Update bootstrap with new token
```

### HelmRelease stuck in "not ready"
```bash
# Check release status
flux get helmrelease n8n -n n8n
flux describe helmrelease n8n -n n8n

# View Helm controller logs
kubectl logs -n flux-system deploy/helm-controller -f

# Common issue: values.yaml syntax error
# Fix: Validate YAML locally
```

### Kustomization fails to apply
```bash
# Check kustomization status
flux get kustomization infrastructure
flux describe kustomization infrastructure

# View kustomize controller logs
kubectl logs -n flux-system deploy/kustomize-controller -f

# Common issue: missing CRDs
# Fix: Ensure CRDs in separate kustomization deployed first
```

### Drift detected but not corrected
```bash
# Check if prune is enabled
flux export kustomization apps

# Ensure spec.prune: true
# Force reconciliation
flux reconcile kustomization apps --with-source
```

---

## Next Steps After GitOps

Once you have GitOps working:

1. **Multi-cluster**: Extend to dev/staging clusters
2. **PR Workflows**: Use Pull Request for infrastructure changes
3. **Image Automation**: Auto-update container images
4. **Policy Enforcement**: Use OPA Gatekeeper or Kyverno
5. **Progressive Delivery**: Canary deployments with Flagger
6. **Observability**: Integrate with Grafana for Flux metrics

---

## Resources

- **Flux Documentation**: https://fluxcd.io/docs/
- **Flux Best Practices**: https://fluxcd.io/flux/guides/
- **SOPS Guide**: https://fluxcd.io/flux/guides/mozilla-sops/
- **Flux Slack**: #flux on CNCF Slack
- **Example Repos**: https://github.com/fluxcd/flux2-kustomize-helm-example

---

## Questions to Consider

1. **How often should Flux check Git?**
   - Default: 1 minute
   - Production: 5-10 minutes
   - Trade-off: Responsiveness vs API rate limits

2. **Should everything be in one repo?**
   - Single repo (monorepo): Easier to start
   - Multiple repos: Better separation, team boundaries
   - Recommendation: Start with one, split later if needed

3. **What about manual hotfixes in emergencies?**
   - Manual kubectl changes work but are temporary
   - Flux will revert them on next sync
   - For emergencies: suspend Flux, fix, then commit to Git

4. **How to handle different environments (dev/prod)?**
   - Option 1: Branches (dev branch, main branch)
   - Option 2: Directories (flux/clusters/dev, flux/clusters/prod)
   - Option 3: Separate repos
   - Recommendation: Option 2 (directories) for simplicity

5. **What's the rollback strategy?**
   - `git revert` the commit
   - Flux automatically rolls back
   - For immediate rollback: suspend Flux, manually revert, then sync Git
