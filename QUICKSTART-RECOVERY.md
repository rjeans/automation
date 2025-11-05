# Cluster Recovery Quick Start

**RTO**: ~45 minutes | **RPO**: Last git commit

Complete cluster rebuild from GitOps. Everything except secrets is automatically restored by Flux.

## Prerequisites

- ✅ Talos secrets backed up in `~/.talos-secrets/pi-cluster/`
- ✅ Git repository access (github.com/rjeans/pi-cluster)
- ✅ GitHub PAT with repo permissions
- ✅ SD cards with Talos image

## Phase 1: Rebuild Talos (20 min)

### 1.1 Configure talosctl
```bash
export TALOSCONFIG=~/.talos-secrets/pi-cluster/talosconfig
talosctl config endpoint 192.168.1.11
talosctl config node 192.168.1.11
```

### 1.2 Apply Node Configurations
```bash
cd /path/to/pi-cluster/talos

# Apply configs to all nodes (use scripts if available)
./apply-static-ip-configs.sh

# Or manually:
talosctl apply-config --insecure -n 192.168.1.11 \
    --file ~/.talos-secrets/pi-cluster/node11.yaml
# Repeat for .12, .13, .14 with appropriate configs
```

### 1.3 Bootstrap Cluster
```bash
# Wait 3-5 minutes for services to start
talosctl -n 192.168.1.11 get services  # Check for etcd + kubelet

# Bootstrap (ONCE ONLY)
talosctl bootstrap --nodes 192.168.1.11

# Wait 2-3 minutes for VIP to activate
ping 192.168.1.10  # VIP should respond

# Switch to VIP
talosctl config endpoint 192.168.1.10
talosctl config nodes 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14

# Get kubeconfig
talosctl kubeconfig --force

# Verify cluster
kubectl get nodes  # All should be Ready within 3-5 minutes
```

## Phase 2: Bootstrap Flux (5 min)

```bash
# Install Flux CLI if needed
brew install fluxcd/tap/flux

# Bootstrap Flux
export GITHUB_TOKEN=<your-pat>
flux bootstrap github \
    --owner=rjeans \
    --repository=pi-cluster \
    --branch=main \
    --path=flux/clusters/talos \
    --personal
```

Flux will automatically deploy:
- Traefik (ingress)
- Metrics Server
- Cloudflare Tunnel
- Local Path Provisioner (storage)
- Prometheus + Grafana (monitoring)
- Cluster Dashboard

## Phase 3: Restore Secrets (5 min)

### 3.1 Cluster Dashboard Secret
```bash
kubectl create secret generic talos-config \
    -n cluster-dashboard \
    --from-file=$HOME/.talos-secrets/pi-cluster/talosconfig
```

### 3.2 Cloudflare Tunnel Secret
```bash
kubectl create secret generic cloudflare-tunnel-token \
    -n cloudflare-tunnel \
    --from-literal=token=<your-cloudflare-token>
```

## Phase 4: Monitor Deployment (15 min)

```bash
# Watch Flux deploy everything
flux get kustomizations --watch

# Expected order:
# 1. flux-system (Ready immediately)
# 2. infrastructure (Ready in ~5 min)
# 3. apps (Ready in ~10 min)

# Check pods
kubectl get pods -A

# All pods should be Running within 15 minutes
```

## Verification

```bash
# Cluster health
kubectl get nodes              # All Ready
flux get kustomizations        # All Ready
kubectl get pods -A            # All Running

# Storage
kubectl get storageclass       # local-path (default)
kubectl get pvc -A             # Prometheus, Grafana, Alertmanager bound

# Monitoring
kubectl get pods -n monitoring # All Running
# Access: https://grafana.jeans-host.net

# Dashboard
kubectl get pods -n cluster-dashboard  # Running
# Access: https://dashboard.jeansy.org
```

## Troubleshooting

### Nodes not Ready
```bash
# Check kubelet logs
talosctl -n 192.168.1.11 logs kubelet
```

### Flux not reconciling
```bash
# Check Flux logs
flux logs --follow --level=error

# Force reconcile
flux reconcile kustomization infrastructure --with-source
```

### Storage not provisioning
```bash
# Check provisioner
kubectl logs -n local-path-storage deployment/local-path-provisioner

# Verify it's on talos-cp1
kubectl get pods -n local-path-storage -o wide
```

### Grafana pod pending
```bash
# Check PVC status
kubectl get pvc -n monitoring

# Check provisioner created PV
kubectl get pv
```

## Success!

Your cluster is now fully operational:
- ✅ HA control plane with VIP
- ✅ All infrastructure services running
- ✅ Storage provisioning working
- ✅ Monitoring stack deployed
- ✅ Applications running

**Total Time**: ~45 minutes (mostly automated via Flux)

## Backup Checklist

Keep these backed up outside the cluster:
- `~/.talos-secrets/pi-cluster/` (all files)
- GitHub PAT
- Cloudflare tunnel token
- This repository (git clone)

## Next Steps

1. Change Grafana password (default: admin/admin)
2. Test accessing services via Cloudflare Tunnel
3. Deploy additional applications via GitOps
4. Set up automated etcd backups
