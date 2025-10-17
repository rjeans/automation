# Kubernetes Manifests Directory

## ⚠️ Important Notice

**This directory is no longer the source of truth for cluster configuration.**

As of October 17, 2025, this cluster is managed by **FluxCD using GitOps principles**.

## 🔄 Migration to GitOps

All Kubernetes resources are now managed by Flux from the [`flux/clusters/talos/`](../flux/clusters/talos/) directory.

### What This Means

- **Don't manually edit files here** - They won't be applied to the cluster
- **Edit files in `flux/` instead** - Flux automatically applies changes from there
- **Git is the source of truth** - All cluster state is defined in the flux/ directory

## 📂 Current Purpose

This directory is kept for:

1. **Reference** - Original manifest examples
2. **Development** - cluster-dashboard application source code
3. **Documentation** - Historical context

## 🚀 Active GitOps Structure

The cluster is now managed from:

```
flux/clusters/talos/
├── infrastructure/        # Core services (Traefik, Metrics Server, etc.)
│   ├── traefik/
│   ├── metrics-server/
│   └── cloudflare-tunnel/
└── apps/                  # Applications (n8n, cluster-dashboard)
    ├── n8n/
    └── cluster-dashboard/
```

## 🔍 What's Actually Used

### Still Active

- `kubernetes/apps/cluster-dashboard/app/` - **Go application source code** (used for development)
- `kubernetes/apps/cluster-dashboard/chart/` - **Helm chart** (reference, not deployed via Helm)

### Not Used (Archived)

- `kubernetes/core/traefik/values.yaml` - Copied to `flux/.../traefik/values-configmap.yaml`
- `kubernetes/core/cloudflare-tunnel/deployment.yaml` - Copied to `flux/.../cloudflare-tunnel/`
- `kubernetes/apps/n8n/values.yaml` - Copied to `flux/.../n8n/values-configmap.yaml`
- `kubernetes/apps/n8n/ingress-*.yaml` - Copied to `flux/.../n8n/`
- `kubernetes/apps/cluster-dashboard/*.yaml` - Copied to `flux/.../cluster-dashboard/`

## 📖 How to Make Changes

### Before GitOps (Old Way)
```bash
# ❌ Don't do this anymore
vim kubernetes/apps/n8n/values.yaml
kubectl apply -f kubernetes/apps/n8n/values.yaml
```

### With GitOps (New Way)
```bash
# ✅ Do this instead
vim flux/clusters/talos/apps/n8n/values-configmap.yaml
git commit -m "Update n8n configuration"
git push

# Flux automatically applies within 1 minute!
```

## 🗑️ Cleanup Status

Files marked for potential removal:
- `kubernetes/apps/n8n/ingress-catchall.yaml` - Unused (can be deleted)
- `kubernetes/apps/n8n/ingress-local.yaml` - Unused (can be deleted)
- All `kubernetes/apps/cluster-dashboard/*.yaml` except chart/ and app/ - Duplicated in flux/ (can be archived)

## 📚 Documentation

For GitOps implementation details, see:
- [GITOPS-ROADMAP.md](../docs/GITOPS-ROADMAP.md) - Comprehensive guide
- [GITOPS-QUICKSTART.md](../docs/GITOPS-QUICKSTART.md) - Quick reference
- [GITOPS-ARCHITECTURE.md](../docs/GITOPS-ARCHITECTURE.md) - Visual diagrams
- [GITOPS-IMPLEMENTATION-SUMMARY.md](../docs/GITOPS-IMPLEMENTATION-SUMMARY.md) - What was done

## 🎯 Quick Reference

| Task | Command |
|------|---------|
| Check Flux status | `flux get all -A` |
| Force reconciliation | `flux reconcile kustomization flux-system --with-source` |
| View Flux logs | `flux logs --all-namespaces --follow` |
| List managed apps | `flux get helmreleases -A` |

## ⚡ Emergency Procedures

If Flux is broken and you need to make manual changes:

```bash
# 1. Suspend Flux
flux suspend kustomization apps

# 2. Make manual fix
kubectl edit deployment n8n -n n8n

# 3. Update Git to match manual change
vim flux/clusters/talos/apps/n8n/...
git commit && git push

# 4. Resume Flux
flux resume kustomization apps
```

---

**Last Updated**: October 17, 2025
**Cluster Management**: FluxCD GitOps
**Source of Truth**: [`flux/clusters/talos/`](../flux/clusters/talos/)
