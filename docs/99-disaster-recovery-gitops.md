# Disaster Recovery: Rebuild from GitOps

## Overview

This guide covers complete cluster recovery using GitOps. With Flux managing all infrastructure and applications, you can rebuild the entire cluster from scratch using only Git and local secrets.

**Recovery Time Objective (RTO)**: ~45 minutes
**Recovery Point Objective (RPO)**: Last git commit
**Prerequisites**: Local Talos secrets backup, Git repository access

## What Gets Restored Automatically

✅ **Infrastructure** (via Flux):
- Traefik ingress controller (v33.2.1)
- Metrics Server (v3.13.0)
- Cloudflare Tunnel
- cert-manager

✅ **Applications** (via Flux):
- n8n workflow automation (v1.15.12)
- cluster-dashboard monitoring
- PostgreSQL databases
- All ingress routes and network policies

✅ **Configuration**:
- Helm values
- Kubernetes manifests
- Resource configurations
- Dependencies and ordering

## What Requires Manual Steps

⚠️ **Must be restored manually**:
- Talos machine configurations (from local backup)
- Kubernetes secrets (talos-config, cloudflare-tunnel-token)
- Application data (n8n workflows, if not backed up)
- Persistent volume data

## Disaster Scenarios

### Scenario 1: Single Node Failure
**Recovery**: Replace node, apply Talos config, Flux auto-heals applications

### Scenario 2: Complete Cluster Loss
**Recovery**: Full rebuild following this guide

### Scenario 3: Git Repository Corruption
**Recovery**: Restore from git backup/mirror, rebuild cluster

### Scenario 4: Secrets Compromise
**Recovery**: Generate new secrets, rebuild cluster, rotate all credentials

## Pre-Disaster Preparation

### 1. Backup Talos Secrets

```bash
# Backup to encrypted external drive
BACKUP_DATE=$(date +%Y%m%d)
BACKUP_DIR="/Volumes/Backup/talos-automation-${BACKUP_DATE}"

mkdir -p "${BACKUP_DIR}"
cp -r ~/.talos-secrets/automation/* "${BACKUP_DIR}/"
chmod -R 600 "${BACKUP_DIR}"/*

# Verify backup
ls -la "${BACKUP_DIR}"
# Should contain: controlplane.yaml, worker.yaml, secrets.yaml, talosconfig
```

### 2. Backup Kubernetes Secrets

```bash
# Export critical secrets
kubectl get secret -n cluster-dashboard talos-config -o yaml > talos-config-secret.yaml
kubectl get secret -n cloudflare-tunnel cloudflare-tunnel-token -o yaml > cloudflare-secret.yaml

# Store securely (NOT in git)
mv *.yaml "${BACKUP_DIR}/"
```

### 3. Backup Application Data (Optional)

```bash
# Export n8n workflows via UI
# n8n → Workflows → Export All

# Or backup PostgreSQL database
kubectl exec -n n8n n8n-postgresql-0 -- sh -c \
  'PGPASSWORD=n8n-postgresql-password pg_dump -U n8n -d n8n' > n8n-backup.sql

mv n8n-backup.sql "${BACKUP_DIR}/"
```

### 4. Document Cluster State

```bash
# Save cluster configuration snapshot
kubectl get nodes -o yaml > "${BACKUP_DIR}/nodes.yaml"
flux get all -A > "${BACKUP_DIR}/flux-state.txt"
kubectl get pv,pvc -A -o yaml > "${BACKUP_DIR}/storage.yaml"
```

### 5. Test Backups Regularly

```bash
# Verify Talos configs are readable
talosctl validate -f "${BACKUP_DIR}/controlplane.yaml"
talosctl validate -f "${BACKUP_DIR}/worker.yaml"

# Verify secrets are valid YAML
kubectl apply --dry-run=client -f "${BACKUP_DIR}/talos-config-secret.yaml"
```

## Disaster Recovery Procedure

### Phase 1: Rebuild Talos Cluster (20 minutes)

#### Step 1.1: Restore Talos Secrets

```bash
# Restore from backup
BACKUP_DIR="/Volumes/Backup/talos-automation-YYYYMMDD"  # Use your backup date

mkdir -p ~/.talos-secrets/automation
cp "${BACKUP_DIR}"/* ~/.talos-secrets/automation/
chmod 600 ~/.talos-secrets/automation/*

# Verify files exist
ls -la ~/.talos-secrets/automation/
# Should have: controlplane.yaml, worker.yaml, secrets.yaml, talosconfig
```

#### Step 1.2: Reflash Nodes (if hardware destroyed)

```bash
# Download Talos image
curl -LO https://github.com/siderolabs/talos/releases/download/v1.11.2/metal-arm64.raw.xz
xz -d metal-arm64.raw.xz

# Flash each SD card
diskutil list
diskutil unmountDisk /dev/diskN
sudo dd if=metal-arm64.raw of=/dev/rdiskN bs=4M conv=fsync
diskutil eject /dev/diskN

# Repeat for all 4 nodes
```

#### Step 1.3: Boot Nodes and Verify Network

```bash
# Insert SD cards, power on nodes
# Wait 90 seconds for boot

# Verify network connectivity
ping -c 3 192.168.1.11  # Control plane 1
ping -c 3 192.168.1.12  # Control plane 2
ping -c 3 192.168.1.13  # Control plane 3
ping -c 3 192.168.1.14  # Worker 1
```

#### Step 1.4: Configure talosctl

```bash
# Set environment variable
export TALOSCONFIG=~/.talos-secrets/automation/talosconfig

# Configure endpoints (control plane nodes only)
talosctl config endpoint 192.168.1.11 192.168.1.12 192.168.1.13
talosctl config node 192.168.1.11

# Make permanent
echo 'export TALOSCONFIG=~/.talos-secrets/automation/talosconfig' >> ~/.zshrc
source ~/.zshrc
```

#### Step 1.5: Apply Talos Configurations

```bash
# Control plane nodes
talosctl apply-config --insecure \
  --nodes 192.168.1.11 \
  --file ~/.talos-secrets/automation/controlplane.yaml

sleep 30

talosctl apply-config --insecure \
  --nodes 192.168.1.12 \
  --file ~/.talos-secrets/automation/controlplane.yaml

sleep 30

talosctl apply-config --insecure \
  --nodes 192.168.1.13 \
  --file ~/.talos-secrets/automation/controlplane.yaml

sleep 30

# Verify first node is responding
talosctl version
```

#### Step 1.6: Bootstrap etcd

```bash
# Bootstrap ONLY on first control plane (ONCE!)
talosctl bootstrap --nodes 192.168.1.11

# Wait for etcd to start (2 minutes)
sleep 120

# Verify services
talosctl services
# Look for: etcd (Running), kubelet (Running)
```

#### Step 1.7: Get Kubernetes Access

```bash
# Retrieve kubeconfig
talosctl kubeconfig --force

# Verify control plane nodes
kubectl get nodes
# Expected: 3 nodes in Ready state (may take 2-3 minutes)

# Wait for all control plane nodes to be Ready
kubectl wait --for=condition=Ready nodes --all --timeout=5m
```

#### Step 1.8: Add Worker Node

```bash
# Apply worker configuration
talosctl apply-config --insecure \
  --nodes 192.168.1.14 \
  --file ~/.talos-secrets/automation/worker.yaml

# Wait for node to join
sleep 60

# Verify all nodes
kubectl get nodes -o wide
# Expected: 3 control-plane + 1 worker, all Ready
```

### Phase 2: Bootstrap Flux GitOps (5 minutes)

#### Step 2.1: Install Flux CLI (if needed)

```bash
# macOS
brew install fluxcd/tap/flux

# Or download binary
curl -s https://fluxcd.io/install.sh | sudo bash

# Verify installation
flux --version
```

#### Step 2.2: Bootstrap Flux

```bash
# Set GitHub credentials
export GITHUB_TOKEN=<your-github-token>
export GITHUB_USER=rjeans  # Your GitHub username

# Bootstrap Flux (idempotent - safe to re-run)
flux bootstrap github \
  --owner=${GITHUB_USER} \
  --repository=automation \
  --branch=main \
  --path=flux/clusters/talos \
  --personal \
  --private=false

# Wait for Flux to install itself
kubectl wait --for=condition=Ready kustomization/flux-system \
  -n flux-system --timeout=5m
```

#### Step 2.3: Verify Flux Installation

```bash
# Check Flux components
flux check

# Verify controllers are running
kubectl get pods -n flux-system
# Expected: source-controller, kustomize-controller, helm-controller, notification-controller

# Check Flux can see the Git repository
flux get sources git
# Expected: flux-system READY
```

### Phase 3: Restore Kubernetes Secrets (5 minutes)

#### Step 3.1: Restore Talos Config Secret (for cluster-dashboard)

```bash
# Option 1: From backup YAML
kubectl apply -f "${BACKUP_DIR}/talos-config-secret.yaml"

# Option 2: Recreate from talosconfig file
kubectl create namespace cluster-dashboard --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic talos-config \
  -n cluster-dashboard \
  --from-file=$HOME/.talos-secrets/pi-cluster/talosconfig

# Verify
kubectl get secret -n cluster-dashboard talos-config
```

#### Step 3.2: Restore Cloudflare Tunnel Token

```bash
# Option 1: From backup YAML
kubectl apply -f "${BACKUP_DIR}/cloudflare-secret.yaml"

# Option 2: Recreate from token
kubectl create namespace cloudflare-tunnel --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic cloudflare-tunnel-token \
  --from-literal=token=<your-cloudflare-tunnel-token> \
  -n cloudflare-tunnel

# Verify
kubectl get secret -n cloudflare-tunnel cloudflare-tunnel-token
```

### Phase 4: Flux Auto-Deploys Infrastructure (10 minutes)

#### Step 4.1: Watch Flux Reconciliation

```bash
# Watch Flux deploy infrastructure
flux get kustomizations --watch

# Expected order:
# 1. flux-system (Ready)
# 2. infrastructure (Progressing → Ready)
# 3. apps (Progressing → Ready)
```

#### Step 4.2: Monitor Infrastructure Deployment

```bash
# Watch Helm releases
flux get helmreleases -A --watch

# Expected:
# - traefik/traefik (Ready)
# - kube-system/metrics-server (Ready)

# Watch infrastructure pods
kubectl get pods -n traefik -w
kubectl get pods -n kube-system -w
kubectl get pods -n cloudflare-tunnel -w
```

#### Step 4.3: Verify Infrastructure Health

```bash
# Check all infrastructure is ready
kubectl get pods -n traefik
kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server
kubectl get pods -n cloudflare-tunnel

# Verify Traefik NodePort
kubectl get svc -n traefik traefik
# Expected: NodePort 30080 (HTTP) and 30443 (HTTPS)

# Test Traefik ingress
curl http://192.168.1.11:30080
# Expected: 404 (Traefik is working, no routes configured)
```

### Phase 5: Flux Auto-Deploys Applications (10 minutes)

#### Step 5.1: Watch Application Deployment

```bash
# Watch application Helm releases
flux get helmreleases -n n8n --watch

# Watch application pods
kubectl get pods -n n8n -w
kubectl get pods -n cluster-dashboard -w
```

#### Step 5.2: Monitor n8n Deployment

```bash
# n8n takes ~5 minutes to fully start
kubectl get pods -n n8n

# Watch for:
# 1. n8n-postgresql-0 (1/1 Running) - Database first
# 2. n8n-* (1/1 Running) - Application after DB ready

# Check logs if needed
kubectl logs -n n8n -l app.kubernetes.io/name=n8n -f
```

#### Step 5.3: Monitor cluster-dashboard Deployment

```bash
# cluster-dashboard should start quickly
kubectl get pods -n cluster-dashboard

# Verify Talos config is mounted
kubectl describe pod -n cluster-dashboard -l app=cluster-dashboard | grep talos-config
```

#### Step 5.4: Verify All Applications

```bash
# Check all Flux resources are ready
flux get all -A

# Verify all pods are running
kubectl get pods -A | grep -v Running | grep -v Completed
# Should only show headers (all pods Running)

# Check ingress routes
kubectl get ingressroute -A
```

### Phase 6: Restore Application Data (5 minutes)

#### Step 6.1: Restore n8n Workflows (Optional)

If you backed up n8n data:

```bash
# Option 1: Import workflows via UI
# 1. Access n8n at http://n8n.local:30080
# 2. Create owner account (first login)
# 3. Go to Workflows → Import
# 4. Upload workflow JSON files

# Option 2: Restore PostgreSQL database
kubectl cp n8n-backup.sql n8n/n8n-postgresql-0:/tmp/backup.sql

kubectl exec -n n8n n8n-postgresql-0 -- sh -c \
  'PGPASSWORD=n8n-postgresql-password psql -U n8n -d n8n -f /tmp/backup.sql'

# Restart n8n to pick up restored data
kubectl rollout restart deployment/n8n -n n8n
```

#### Step 6.2: Verify Application Access

```bash
# Test n8n access
curl -H "Host: n8n.local" http://192.168.1.11:30080/
# Expected: n8n login page HTML

# Test cluster-dashboard access
curl http://192.168.1.11:30080/
# Expected: Dashboard HTML or redirect

# Test external access (if configured)
curl https://dashboard.jeansy.org
# Expected: Dashboard page (via Cloudflare Tunnel)
```

### Phase 7: Verification and Health Checks (5 minutes)

#### Step 7.1: Complete Cluster Health Check

```bash
# Run health check script
./scripts/talos-health.sh

# Manual checks:
kubectl get nodes
kubectl get pods -A
flux get all -A

# All should show:
# - Nodes: Ready
# - Pods: Running
# - Flux: Ready/Applied
```

#### Step 7.2: Verify GitOps Workflow

```bash
# Test GitOps is working - make a small change
git pull origin main

# Verify Flux detected the change
flux logs --follow --level=info

# Flux should reconcile within 1 minute
```

#### Step 7.3: Test Application Functionality

```bash
# Test n8n
# 1. Login to n8n UI
# 2. Create test workflow
# 3. Execute workflow
# 4. Verify execution history

# Test cluster-dashboard
# 1. Open dashboard
# 2. Verify all nodes visible
# 3. Check metrics are updating
# 4. Verify temperature sensors working
```

## Recovery Checklist

Use this checklist during recovery:

```
Phase 1: Talos Cluster (20 min)
□ Restore Talos secrets from backup
□ Reflash SD cards (if needed)
□ Boot all nodes and verify network
□ Configure talosctl
□ Apply configurations to control plane nodes
□ Bootstrap etcd on first control plane
□ Get kubeconfig
□ Add worker node
□ Verify all nodes Ready

Phase 2: Flux Bootstrap (5 min)
□ Install Flux CLI
□ Bootstrap Flux from GitHub
□ Verify Flux controllers running
□ Check Git source is ready

Phase 3: Kubernetes Secrets (5 min)
□ Restore talos-config secret
□ Restore cloudflare-tunnel-token secret
□ Verify secrets created

Phase 4: Infrastructure Auto-Deploy (10 min)
□ Watch infrastructure Kustomization
□ Verify Traefik deployed
□ Verify Metrics Server deployed
□ Verify Cloudflare Tunnel deployed
□ Test Traefik ingress

Phase 5: Applications Auto-Deploy (10 min)
□ Watch apps Kustomization
□ Verify n8n deployed
□ Verify cluster-dashboard deployed
□ Check all pods Running

Phase 6: Application Data (5 min)
□ Restore n8n workflows (if backed up)
□ Verify application access
□ Test external access

Phase 7: Verification (5 min)
□ Run health checks
□ Test GitOps workflow
□ Test application functionality
□ Document recovery in git
```

## Common Recovery Issues

### Issue: Flux Won't Bootstrap

**Symptoms**: `flux bootstrap` fails with GitHub errors

**Solutions**:
```bash
# Verify GitHub token has correct permissions
# Required scopes: repo (all), admin:repo_hook

# Check network connectivity
curl -I https://github.com

# Try with --verbose flag
flux bootstrap github --verbose ...
```

### Issue: Infrastructure Stuck Reconciling

**Symptoms**: Infrastructure Kustomization shows "Progressing" forever

**Solutions**:
```bash
# Check what's blocking
flux logs --follow

# Describe the Kustomization
kubectl describe kustomization infrastructure -n flux-system

# Common causes:
# - Missing secrets (talos-config, cloudflare-tunnel-token)
# - Image pull errors (ARM compatibility)
# - Resource constraints (Pi CPU/memory)

# Force reconciliation
flux reconcile kustomization infrastructure --with-source
```

### Issue: Helm Releases Fail to Install

**Symptoms**: HelmRelease shows "Install Failed"

**Solutions**:
```bash
# Check Helm release status
flux get helmrelease -n <namespace> <name>

# View detailed error
kubectl describe helmrelease -n <namespace> <name>

# Common causes:
# - Chart repository unreachable
# - Invalid values in ConfigMap
# - Resource conflicts (already exists)

# Retry manually
flux reconcile helmrelease -n <namespace> <name>
```

### Issue: Pods CrashLooping

**Symptoms**: Pods show CrashLoopBackOff status

**Solutions**:
```bash
# Check pod logs
kubectl logs -n <namespace> <pod-name>

# Check pod events
kubectl describe pod -n <namespace> <pod-name>

# Common causes for n8n:
# - Missing talos-config secret → cluster-dashboard won't start
# - PostgreSQL not ready → n8n won't start
# - Resource limits too low → OOMKilled

# For cluster-dashboard specifically:
# Ensure talos-config secret exists:
kubectl get secret -n cluster-dashboard talos-config
```

### Issue: Ingress Not Working

**Symptoms**: Cannot access services via NodePort

**Solutions**:
```bash
# Verify Traefik is running
kubectl get pods -n traefik

# Check Traefik service
kubectl get svc -n traefik traefik
# Should show NodePort 30080 and 30443

# Test directly
curl http://192.168.1.11:30080

# Check IngressRoutes
kubectl get ingressroute -A

# View Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik
```

## Recovery Time Estimates

| Phase | Time | Critical Path |
|-------|------|---------------|
| 1. Talos Cluster | 20 min | SD card flashing (if needed) |
| 2. Flux Bootstrap | 5 min | GitHub API rate limits |
| 3. Kubernetes Secrets | 5 min | Manual secret creation |
| 4. Infrastructure Deploy | 10 min | Image pulls on ARM |
| 5. Application Deploy | 10 min | PostgreSQL initialization |
| 6. Data Restore | 5 min | Database import size |
| 7. Verification | 5 min | Testing |
| **Total RTO** | **~60 min** | From bare metal to production |

**Optimization opportunities**:
- Pre-downloaded container images: Save ~5 minutes
- Automated secret creation script: Save ~3 minutes
- Skip data restore: Save ~5 minutes
- **Optimized RTO: ~45 minutes**

## Testing Your Recovery Plan

### Monthly Drill (Recommended)

```bash
# 1. Document current state
flux get all -A > pre-drill-state.txt
kubectl get pods -A > pre-drill-pods.txt

# 2. Destroy cluster (not nodes, just kubernetes)
kubectl delete namespace n8n --force --grace-period=0
kubectl delete namespace cluster-dashboard --force --grace-period=0
kubectl delete namespace traefik --force --grace-period=0
flux uninstall --silent

# 3. Follow recovery procedure from Phase 2
# (Skip Phase 1 since nodes still exist)

# 4. Verify everything restored correctly
flux get all -A > post-drill-state.txt
diff pre-drill-state.txt post-drill-state.txt

# 5. Document lessons learned
git add docs/recovery-drill-$(date +%Y%m%d).md
git commit -m "docs: Recovery drill results"
```

### Quarterly Drill (Recommended)

Complete rebuild from bare metal:
1. Power off all Raspberry Pis
2. Reflash all SD cards
3. Follow complete recovery procedure (Phase 1-7)
4. Document time taken and issues encountered

## Post-Recovery Tasks

### 1. Update Documentation

```bash
# Record the recovery event
cat >> CLUSTER-HISTORY.md <<EOF

## $(date +%Y-%m-%d): Disaster Recovery Performed

**Reason**: [Complete cluster loss / Testing / etc.]
**Duration**: [X minutes]
**Data Loss**: [None / X workflows / etc.]
**Issues Encountered**: [List any problems]
**Resolution**: [How issues were resolved]

EOF

git add CLUSTER-HISTORY.md
git commit -m "docs: Record disaster recovery event"
git push
```

### 2. Rotate Compromised Secrets (if applicable)

If recovery was due to security incident:

```bash
# Generate new Talos secrets
talosctl gen secrets -o ~/.talos-secrets/automation/secrets.yaml

# Rebuild cluster with new secrets
# Follow Phase 1 completely

# Rotate application secrets
kubectl delete secret -n cloudflare-tunnel cloudflare-tunnel-token
# Create new Cloudflare Tunnel and token
kubectl create secret generic cloudflare-tunnel-token \
  --from-literal=token=<new-token> \
  -n cloudflare-tunnel
```

### 3. Verify Backups

```bash
# Update backup with new state
BACKUP_DATE=$(date +%Y%m%d)
./scripts/backup-secrets.sh "${BACKUP_DATE}"

# Test backup restore procedure
# (on a test cluster if available)
```

### 4. Review and Improve

- Document what worked well
- Document what needs improvement
- Update this guide with lessons learned
- Automate manual steps where possible

## Automation Opportunities

### Future Improvements

1. **Secret Management with SOPS** (Roadmap Phase 5):
   - Encrypt secrets in git
   - Eliminate manual secret restoration
   - Reduce Phase 3 to 1 minute

2. **Automated Backup Script**:
   ```bash
   #!/bin/bash
   # scripts/backup-all.sh
   # Automates all backup steps
   ```

3. **Recovery Script**:
   ```bash
   #!/bin/bash
   # scripts/disaster-recovery.sh
   # Automated recovery procedure
   ```

4. **Monitoring and Alerting**:
   - GitOps sync failure alerts
   - Backup verification checks
   - Recovery drill reminders

## References

- [Flux Disaster Recovery](https://fluxcd.io/flux/guides/disaster-recovery/)
- [Talos Disaster Recovery](https://www.talos.dev/latest/learn-more/disaster-recovery/)
- [GITOPS-ROADMAP.md](GITOPS-ROADMAP.md)
- [02-cluster-rebuild.md](02-cluster-rebuild.md)

---

**Last Updated**: 2025-10-17
**Tested**: Yes (October 2025)
**Average RTO**: 45-60 minutes
**Success Rate**: 100% (2/2 tests)
