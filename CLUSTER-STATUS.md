# Cluster Status

**Last Updated**: 2025-11-06

## Stack

- **OS**: Talos Linux v1.11.3
- **Kubernetes**: v1.31.2
- **GitOps**: Flux CD v2.x
- **Nodes**: 3 control plane + 1 worker
- **VIP**: 192.168.1.10 (HA endpoint)

## Running Services

### Infrastructure (Flux-Managed)
- Traefik (ingress)
- Metrics Server
- Cloudflare Tunnel
- Local Path Provisioner (storage)
- Prometheus + Grafana + Alertmanager (monitoring)

### Applications (Flux-Managed)
- Cluster Dashboard v1.0.10

## Network
- VIP: 192.168.1.10 (HA endpoint)
- Control Plane: .11, .12, .13
- Worker: .14
- Storage: /var/mnt/storage on talos-cp1 (.11)

## Storage
- StorageClass: local-path (default)
- PVCs: Prometheus (20Gi), Grafana (5Gi), Alertmanager (5Gi)
- All provisioning on talos-cp1

## Monitoring
- Grafana: https://grafana.jeans-host.net (admin/admin)
- Prometheus + Alertmanager running
- Node exporters on all nodes

## Repository Structure

```
├── flux/                      # GitOps - Source of truth
│   └── clusters/talos/
│       ├── infrastructure/    # Traefik, storage, monitoring
│       └── apps/              # cluster-dashboard
├── charts/                    # Local Helm charts (required by Flux)
├── talos/                     # Talos configs and scripts
└── docs/                      # Documentation
```

## Secrets (NOT in Git)

Stored in `~/.talos-secrets/pi-cluster/`:
- talosconfig, node configs, secrets.yaml

Kubernetes secrets (manual):
```bash
# cluster-dashboard
kubectl create secret generic talos-config -n cluster-dashboard \
    --from-file=$HOME/.talos-secrets/pi-cluster/talosconfig

# cloudflare-tunnel
kubectl create secret generic cloudflare-tunnel-token -n cloudflare-tunnel \
    --from-literal=token=<token>
```

## GitOps Workflow

1. Edit manifests in `flux/`
2. Commit and push
3. Flux auto-applies within 1 minute

```bash
# Monitor
flux get kustomizations
flux logs --follow

# Force reconcile
flux reconcile kustomization apps --with-source
```

## Recent Fixes (2025-11-06)

1. **Storage**: Added nodeSelector to provisioner + helper pods → all storage ops on talos-cp1
2. **Flux Dependencies**: Proper kustomization ordering + CRD health checks → clean deploys
3. **Circular Dependency**: Temporarily disabled Prometheus during infrastructure setup → resolved

## Health Checks

```bash
flux get kustomizations    # All Ready
kubectl get nodes          # All Ready
kubectl get pods -A        # All Running
```

## Production Status

✅ HA (VIP + 3 control planes)
✅ GitOps (Flux)
✅ Storage (local-path on dedicated node)
✅ Monitoring (Prometheus/Grafana)
✅ Ingress (Traefik)
✅ External Access (Cloudflare Tunnel)
⚠️ Change Grafana password from default
⚠️ Set up automated backups (etcd, PVCs)

## Documentation

- [talos/FRESH-INSTALL.md](talos/FRESH-INSTALL.md) - Fresh install
- [docs/talos-vip-rebuild.md](docs/talos-vip-rebuild.md) - VIP setup
- [docs/GITOPS-QUICKSTART.md](docs/GITOPS-QUICKSTART.md) - GitOps workflow
- [docs/99-disaster-recovery-gitops.md](docs/99-disaster-recovery-gitops.md) - Disaster recovery
