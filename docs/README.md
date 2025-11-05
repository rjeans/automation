# Documentation Index

This directory contains comprehensive documentation for the Talos Kubernetes cluster with GitOps management.

## 🚀 Quick Start

**New to this cluster?** Start here:

1. **[Network Planning](00-network-plan.md)** - Understand the network architecture
2. **[Prerequisites](01-prerequisites.md)** - Install required tools
3. **[Cluster Rebuild](02-cluster-rebuild.md)** - Build the Talos cluster
   - **[VIP Rebuild](talos-vip-rebuild.md)** - For HA with Virtual IP (recommended)
4. **[GitOps Quick Start](GITOPS-QUICKSTART.md)** - Bootstrap Flux and deploy everything

**Disaster recovery?** → [99-disaster-recovery-gitops.md](99-disaster-recovery-gitops.md)

## 📚 Documentation Structure

### Core Setup Guides

| Document | Status | Description |
|----------|--------|-------------|
| [00-network-plan.md](00-network-plan.md) | ✅ Current | IP addressing, DNS, network architecture |
| [01-prerequisites.md](01-prerequisites.md) | ✅ Current | Required software and tools installation |
| [02-cluster-rebuild.md](02-cluster-rebuild.md) | ✅ Updated | Talos cluster rebuild (manual layer only) |
| [talos-vip-rebuild.md](talos-vip-rebuild.md) | ✅ **NEW** | Talos cluster rebuild with VIP for HA |
| [03-storage-local-path.md](03-storage-local-path.md) | ✅ Current | Local path provisioner configuration |
| [04-poe-hat-configuration.md](04-poe-hat-configuration.md) | ✅ Current | Raspberry Pi PoE HAT fan control |

### Infrastructure Guides (GitOps Managed)

> **⚠️ Note**: These guides show legacy manual installation. All infrastructure is now managed by Flux.
> For current deployment, see [GITOPS-QUICKSTART.md](GITOPS-QUICKSTART.md)

| Document | Status | Description |
|----------|--------|-------------|
| [05-ingress-traefik.md](05-ingress-traefik.md) | ⚠️ Reference | Traefik ingress (now Flux-managed) |
| [07-n8n-deployment.md](07-n8n-deployment.md) | ⚠️ Reference | n8n deployment (now Flux-managed) |

### GitOps Documentation (Current Method)

| Document | Status | Description |
|----------|--------|-------------|
| [GITOPS-QUICKSTART.md](GITOPS-QUICKSTART.md) | ✅ **Primary** | Quick reference for GitOps operations |
| [GITOPS-ROADMAP.md](GITOPS-ROADMAP.md) | ✅ **Primary** | Complete 7-phase GitOps implementation guide |
| [GITOPS-ARCHITECTURE.md](GITOPS-ARCHITECTURE.md) | ✅ **Primary** | Visual diagrams and workflow explanations |
| [GITOPS-IMPLEMENTATION-SUMMARY.md](GITOPS-IMPLEMENTATION-SUMMARY.md) | ✅ Complete | Record of what was implemented |
| [99-disaster-recovery-gitops.md](99-disaster-recovery-gitops.md) | ✅ **Essential** | Complete cluster rebuild from GitOps |

## 🎯 Common Tasks

### Initial Cluster Setup

```bash
# 1. Rebuild Talos cluster (bare metal)
# Follow: 02-cluster-rebuild.md

# 2. Bootstrap GitOps
# Follow: GITOPS-QUICKSTART.md
flux bootstrap github --owner=rjeans --repository=automation ...

# 3. Restore secrets
kubectl create secret generic talos-config \
    -n cluster-dashboard \
    --from-file=$HOME/.talos-secrets/pi-cluster/talosconfig
kubectl create secret generic cloudflare-tunnel-token -n cloudflare-tunnel ...

# 4. Watch Flux deploy everything
flux get kustomizations --watch
```

**Total time**: ~45 minutes (automated)

### Disaster Recovery

```bash
# Complete recovery from scratch
# Follow: 99-disaster-recovery-gitops.md

# Summary:
# - Phase 1: Rebuild Talos (20 min)
# - Phase 2: Bootstrap Flux (5 min)
# - Phase 3: Restore secrets (5 min)
# - Phase 4-5: Flux auto-deploys (15 min)
# - Total: ~45 minutes
```

### Modify Infrastructure

```bash
# All infrastructure is GitOps-managed
# Example: Update Traefik

vim flux/clusters/talos/infrastructure/traefik/values-configmap.yaml
git commit -m "feat: Update Traefik config"
git push

# Flux applies changes within 1 minute
```

### Deploy New Application

```bash
# Add new app to Flux
mkdir -p flux/clusters/talos/apps/myapp
# Create helmrelease.yaml or deployment.yaml
git add flux/clusters/talos/apps/myapp
git commit -m "feat: Add myapp"
git push

# Flux deploys automatically
flux get helmrelease myapp --watch
```

## 🏗️ Cluster Architecture

### Current State (October 2025)

**Infrastructure**:
- ✅ Talos Linux v1.11.2 (3 control plane + 1 worker)
- ✅ Kubernetes v1.34.0
- ✅ Flux v2.7.2 (GitOps)
- ✅ Traefik v33.2.1 (Ingress)
- ✅ Metrics Server v3.13.0
- ✅ Cloudflare Tunnel (External access)
- ✅ cert-manager v1.16.2 (TLS certificates)

**Applications**:
- ✅ n8n v1.113.3 (Workflow automation)
- ✅ cluster-dashboard (Custom monitoring)
- ✅ PostgreSQL (Database for n8n)

**Storage**:
- ✅ Local Path Provisioner (Dynamic PVs)
- ✅ 1TB external drive on node .11

**Networking**:
- Network: 192.168.1.0/24
- Control plane VIP: 192.168.1.10 (HA failover, **to be implemented**)
- Control plane nodes: 192.168.1.11, 192.168.1.12, 192.168.1.13
- Worker node: 192.168.1.14
- NodePort ingress: 30080 (HTTP), 30443 (HTTPS)
- External domain: dashboard.jeansy.org (via Cloudflare Tunnel)

### Management Philosophy

**GitOps First**: Everything in Git
- Infrastructure: `flux/clusters/talos/infrastructure/`
- Applications: `flux/clusters/talos/apps/`
- Flux config: `flux/clusters/talos/flux-system/`

**Secrets**: Local only (NOT in Git)
- Talos configs: `~/.talos-secrets/automation/`
- Kubernetes secrets: Created manually, not committed
- Future: SOPS encryption (Roadmap Phase 5)

**Declarative**: Flux manages state
- Continuous reconciliation (1-minute interval)
- Automatic drift correction
- Dependency management
- Health checks

## 📖 Reading Guide

### For New Users

**Day 1**: Understand the architecture
1. [Network Plan](00-network-plan.md) - 15 min read
2. [GitOps Architecture](GITOPS-ARCHITECTURE.md) - 20 min read
3. [Prerequisites](01-prerequisites.md) - 30 min setup

**Day 2**: Build the cluster
1. [Cluster Rebuild](02-cluster-rebuild.md) - 30 min
2. [GitOps Quick Start](GITOPS-QUICKSTART.md) - 45 min
3. Test the GitOps workflow

**Day 3**: Understand operations
1. [GitOps Roadmap](GITOPS-ROADMAP.md) - Deep dive
2. [Disaster Recovery](99-disaster-recovery-gitops.md) - Study
3. Practice making changes via Git

### For Existing Users

**Daily Operations**:
- [GITOPS-QUICKSTART.md](GITOPS-QUICKSTART.md) - Common commands
- `flux get all -A` - Check cluster state
- `git log` - See recent changes

**Troubleshooting**:
- Check Flux logs: `flux logs --follow`
- Check pod status: `kubectl get pods -A`
- Review specific guides (05, 07) for component details

**Making Changes**:
1. Edit files in `flux/` directory
2. Commit and push to Git
3. Watch Flux apply: `flux get kustomizations --watch`

### For Emergency Recovery

**Go directly to**:
1. [99-disaster-recovery-gitops.md](99-disaster-recovery-gitops.md)
2. Follow the checklist
3. ~45 minutes to full recovery

## 🔧 Maintenance

### Regular Tasks

**Monthly**:
- Review Flux reconciliation logs
- Check for available updates
- Test disaster recovery procedure (dry run)
- Verify backups

**Quarterly**:
- Update Talos Linux version
- Update Kubernetes version (via Talos)
- Update Flux version
- Full disaster recovery drill

**As Needed**:
- Update application versions via GitOps
- Adjust resource limits
- Add new applications
- Modify network policies

### Update Procedures

**Update Infrastructure Component**:
```bash
# Example: Update Traefik
vim flux/clusters/talos/infrastructure/traefik/helmrelease.yaml
# Change version: "33.2.1" → "33.3.0"
git commit -m "feat: Upgrade Traefik to v33.3.0"
git push
# Flux applies automatically
```

**Update Application**:
```bash
# Example: Update n8n
vim flux/clusters/talos/apps/n8n/helmrelease.yaml
# Change version: "1.15.12" → "1.16.0"
git commit -m "feat: Upgrade n8n to v1.16.0"
git push
# Flux applies automatically
```

**Update Talos**:
```bash
# Major version upgrade - requires planning
# See Talos documentation for upgrade path
talosctl upgrade --nodes <node-ip> --image ...
```

## 🚨 Troubleshooting

### Common Issues

**Flux not reconciling**:
```bash
flux logs --follow --level=error
kubectl describe kustomization -n flux-system infrastructure
```

**Helm release failing**:
```bash
flux get helmrelease -n <namespace> <name>
kubectl describe helmrelease -n <namespace> <name>
```

**Pods not starting**:
```bash
kubectl get pods -n <namespace>
kubectl logs -n <namespace> <pod-name>
kubectl describe pod -n <namespace> <pod-name>
```

**Secrets missing**:
```bash
# Check if secret exists
kubectl get secret -n <namespace>

# Recreate from backup
kubectl create secret generic <name> --from-file=...
```

### Get Help

1. **Check documentation** in this directory
2. **Review Flux logs**: `flux logs --follow`
3. **Check pod events**: `kubectl get events -A --sort-by='.lastTimestamp'`
4. **Review Git history**: `git log --oneline`
5. **Disaster recovery guide**: [99-disaster-recovery-gitops.md](99-disaster-recovery-gitops.md)

## 📁 Archive

The `archive/` directory contains historical documentation that is no longer current but may be useful for reference:

- [archive/02-talos-installation.md](archive/02-talos-installation.md) - Original installation guide (replaced by 02-cluster-rebuild.md)
- [archive/README.md](archive/README.md) - Archive index

## 🔗 External References

- [Talos Linux Documentation](https://www.talos.dev/latest/)
- [Flux Documentation](https://fluxcd.io/docs/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [n8n Documentation](https://docs.n8n.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## 📝 Contributing

When updating documentation:

1. **Keep GitOps-first**: Emphasize GitOps workflow, legacy methods as reference only
2. **Update dates**: Mark "Last Updated" at bottom of changed files
3. **Test procedures**: Verify commands work before documenting
4. **Link related docs**: Cross-reference between guides
5. **Update this index**: Add new documents to the tables above

---

**Documentation Last Updated**: 2025-11-05
**Cluster Version**: Kubernetes v1.31.2 on Talos v1.8.x
**GitOps**: Flux v2.7.2
**Management**: Fully GitOps-managed cluster
**VIP Status**: Documentation and scripts ready, implementation pending
