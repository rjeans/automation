# Flux GitOps Commands Reference

This document provides essential Flux commands for monitoring and managing the GitOps system.

## Table of Contents
- [Quick Status Check](#quick-status-check)
- [Source Management](#source-management)
- [Kustomization Status](#kustomization-status)
- [HelmRelease Status](#helmrelease-status)
- [Reconciliation](#reconciliation)
- [Troubleshooting](#troubleshooting)
- [Logs and Events](#logs-and-events)

---

## Quick Status Check

### Check overall Flux system health
```bash
# Get all Flux resources status at a glance
flux get all

# Check specific namespace
flux get all -n flux-system
```

### Check if Flux controllers are running
```bash
kubectl get pods -n flux-system

# Expected pods:
# - helm-controller
# - kustomize-controller
# - notification-controller
# - source-controller
```

---

## Source Management

### Git Repository Status
```bash
# List all GitRepository sources
flux get sources git

# Get detailed status of main repository
flux get source git flux-system -n flux-system

# Check last sync time and revision
kubectl describe gitrepository flux-system -n flux-system
```

### Helm Repository Status
```bash
# List all Helm repositories
flux get sources helm

# Check specific Helm repo (e.g., traefik)
flux get source helm traefik -n flux-system

# Describe for more details
kubectl describe helmrepository traefik -n flux-system
```

### Force repository sync
```bash
# Sync Git repository immediately
flux reconcile source git flux-system

# Sync Helm repository
flux reconcile source helm traefik
```

---

## Kustomization Status

### View all Kustomizations
```bash
# List all Kustomizations with status
flux get kustomizations

# More detailed view
flux get kustomizations -A
```

### Check specific Kustomizations
```bash
# Infrastructure layer
flux get kustomization infrastructure -n flux-system

# Applications layer
flux get kustomization apps -n flux-system

# Get detailed information
kubectl describe kustomization infrastructure -n flux-system
```

### Check Kustomization health
```bash
# See if Kustomizations are ready
kubectl get kustomizations -n flux-system

# Expected STATUS: True for all Ready conditions
```

---

## HelmRelease Status

### View all HelmReleases
```bash
# List all Helm releases managed by Flux
flux get helmreleases -A

# Condensed view
flux get hr -A
```

### Check specific application HelmReleases
```bash
# Traefik ingress controller
flux get helmrelease traefik -n traefik

# N8N workflow automation
flux get helmrelease n8n -n n8n

# Cluster dashboard
flux get helmrelease cluster-dashboard -n cluster-dashboard

# Cloudflared tunnel
flux get helmrelease cloudflared -n cloudflare-tunnel

# Metrics server
flux get helmrelease metrics-server -n kube-system
```

### Detailed HelmRelease information
```bash
# Get full details including values and status
kubectl describe helmrelease traefik -n traefik

# See the actual Helm release
helm list -A
```

---

## Reconciliation

### Manual reconciliation (force sync)

#### Reconcile entire system
```bash
# Start from the source
flux reconcile source git flux-system

# Then reconcile infrastructure
flux reconcile kustomization infrastructure

# Then reconcile apps
flux reconcile kustomization apps
```

#### Reconcile specific HelmRelease
```bash
# Force reconcile a specific Helm release
flux reconcile helmrelease traefik -n traefik
flux reconcile helmrelease n8n -n n8n
flux reconcile helmrelease cluster-dashboard -n cluster-dashboard
flux reconcile helmrelease cloudflared -n cloudflare-tunnel
```

#### Reconcile with wait
```bash
# Wait for reconciliation to complete
flux reconcile source git flux-system --wait

# Reconcile and watch
flux reconcile kustomization apps --wait
```

---

## Troubleshooting

### Check for suspended resources
```bash
# Find suspended Kustomizations
kubectl get kustomizations -A -o json | jq '.items[] | select(.spec.suspend==true) | {name:.metadata.name, namespace:.metadata.namespace}'

# Find suspended HelmReleases
kubectl get helmreleases -A -o json | jq '.items[] | select(.spec.suspend==true) | {name:.metadata.name, namespace:.metadata.namespace}'
```

### Resume suspended resources
```bash
# Resume a Kustomization
flux resume kustomization infrastructure

# Resume a HelmRelease
flux resume helmrelease traefik -n traefik
```

### Check resource conditions
```bash
# Check why a Kustomization is failing
kubectl get kustomization infrastructure -n flux-system -o yaml | grep -A 10 conditions

# Check HelmRelease failure reasons
kubectl get helmrelease traefik -n traefik -o yaml | grep -A 10 conditions
```

### Verify CRDs are installed
```bash
# List Flux CRDs
kubectl get crds | grep fluxcd

# Expected CRDs:
# - gitrepositories.source.toolkit.fluxcd.io
# - helmcharts.source.toolkit.fluxcd.io
# - helmreleases.helm.toolkit.fluxcd.io
# - helmrepositories.source.toolkit.fluxcd.io
# - kustomizations.kustomize.toolkit.fluxcd.io
```

---

## Logs and Events

### View Flux controller logs
```bash
# All Flux controllers
flux logs --all-namespaces

# Specific controller logs
flux logs --kind=Kustomization --name=infrastructure
flux logs --kind=HelmRelease --name=traefik --namespace=traefik

# Follow logs in real-time
flux logs --follow --all-namespaces

# Last hour only
flux logs --since=1h
```

### Kubernetes events
```bash
# Flux-related events in flux-system
kubectl get events -n flux-system --sort-by='.lastTimestamp'

# Recent reconciliation events
kubectl get events -n flux-system --field-selector involvedObject.kind=Kustomization --sort-by='.lastTimestamp' | tail -20

# HelmRelease events
kubectl get events -n traefik --field-selector involvedObject.kind=HelmRelease --sort-by='.lastTimestamp'
```

### Check recent activity
```bash
# Last 10 Flux events across all namespaces
kubectl get events -A --field-selector reason=ReconciliationSucceeded --sort-by='.lastTimestamp' | tail -10

# Failed reconciliations
kubectl get events -A --field-selector reason=ReconciliationFailed --sort-by='.lastTimestamp'
```

---

## Common Workflows

### After making Git changes
```bash
# 1. Check if Flux has detected the change
flux get source git flux-system

# 2. Force sync if needed
flux reconcile source git flux-system

# 3. Watch the reconciliation
flux get kustomizations --watch

# 4. Check specific app deployment
kubectl get helmrelease -A
helm list -A
```

### Debugging a failed HelmRelease
```bash
# 1. Check HelmRelease status
flux get helmrelease traefik -n traefik

# 2. Get detailed conditions
kubectl describe helmrelease traefik -n traefik

# 3. Check controller logs
flux logs --kind=HelmRelease --name=traefik --namespace=traefik

# 4. Check Helm release status
helm list -n traefik
helm status traefik -n traefik

# 5. Force reconciliation
flux reconcile helmrelease traefik -n traefik
```

### Verify deployment after changes
```bash
# 1. Check source is up to date
flux get sources git

# 2. Check Kustomizations applied
flux get kustomizations

# 3. Check HelmReleases deployed
flux get helmreleases -A

# 4. Verify pods are running
kubectl get pods -A | grep -v "Running\|Completed"
```

---

## Useful Aliases

Add these to your `~/.bashrc` or `~/.zshrc`:

```bash
# Flux aliases
alias fga='flux get all'
alias fgk='flux get kustomizations'
alias fgh='flux get helmreleases -A'
alias fgs='flux get sources git'
alias fl='flux logs --all-namespaces --since=5m'
alias frs='flux reconcile source git flux-system'
alias fri='flux reconcile kustomization infrastructure'
alias fra='flux reconcile kustomization apps'

# Combined check
alias fcheck='flux get sources git && echo && flux get kustomizations && echo && flux get helmreleases -A'
```

---

## Quick Reference Card

| Command | Description |
|---------|-------------|
| `flux get all` | Show status of all Flux resources |
| `flux get sources git` | List Git repositories |
| `flux get kustomizations` | List Kustomizations |
| `flux get helmreleases -A` | List all Helm releases |
| `flux reconcile source git flux-system` | Force Git sync |
| `flux reconcile kustomization <name>` | Force Kustomization sync |
| `flux reconcile helmrelease <name> -n <ns>` | Force HelmRelease sync |
| `flux logs --follow` | Stream Flux logs |
| `kubectl get events -n flux-system` | See Flux events |
| `helm list -A` | List deployed Helm charts |

---

## Additional Resources

- [Flux Documentation](https://fluxcd.io/flux/)
- [Flux CLI Reference](https://fluxcd.io/flux/cmd/)
- [Troubleshooting Guide](https://fluxcd.io/flux/cheatsheets/troubleshooting/)
- [Flux GitHub](https://github.com/fluxcd/flux2)

---

## Cluster-Specific Information

### Current Cluster: Talos Kubernetes

**GitRepository:** `flux-system` (rjeans/automation)

**Kustomizations:**
- `flux-system` - Bootstrap and core Flux components
- `infrastructure` - Core infrastructure (Traefik, cert-manager, metrics-server, cloudflared)
- `apps` - Applications (n8n, cluster-dashboard)

**HelmReleases:**
- `traefik` (traefik namespace) - Ingress controller
- `cert-manager` (cert-manager namespace) - TLS certificate management
- `metrics-server` (kube-system namespace) - Cluster metrics
- `cloudflared` (cloudflare-tunnel namespace) - Cloudflare Tunnel
- `n8n` (n8n namespace) - Workflow automation
- `cluster-dashboard` (cluster-dashboard namespace) - Cluster monitoring dashboard

**Dashboard URL:** https://dashboard.jeansy.org
