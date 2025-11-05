# Cluster Recovery Quick Start

**RTO**: ~45 minutes | **RPO**: Last git commit

Complete cluster rebuild from GitOps. Everything except secrets is automatically restored by Flux.

## Prerequisites

- ✅ Talos secrets backed up in `~/.talos-secrets/pi-cluster/`
- ✅ Git repository access (github.com/rjeans/pi-cluster)
- ✅ GitHub PAT with repo permissions
- ✅ SD cards with Talos image

## Phase 1: Rebuild Talos (20 min)

### 1.1 Boot Nodes in Maintenance Mode

**Option A: Fresh SD cards** (SD cards freshly flashed):
1. Insert SD cards into Raspberry Pis
2. Power on via PoE
3. Wait 60-90 seconds for nodes to boot
4. Nodes will be in **maintenance mode** with temporary DHCP IPs

**Option B: Reset existing cluster** (nodes currently running):

**⚠️ WARNING**: On Raspberry Pi, `talosctl reset` wipes the boot partition, making nodes unbootable. You MUST reflash SD cards after reset.

For disaster recovery from a running cluster, you have two choices:

1. **Power off and reflash** (recommended):
   ```bash
   # Gracefully shutdown nodes
   talosctl shutdown -n 192.168.1.11,192.168.1.12,192.168.1.13,192.168.1.14

   # Remove SD cards and reflash with Talos image
   # Then follow Option A
   ```

2. **Use reset** (requires reflashing):
   ```bash
   # Reset wipes boot partition - nodes won't boot after this!
   talosctl reset --graceful --reboot -n 192.168.1.14  # worker
   talosctl reset --graceful --reboot -n 192.168.1.13  # cp3
   talosctl reset --graceful --reboot -n 192.168.1.12  # cp2
   talosctl reset --graceful --reboot -n 192.168.1.11  # cp1

   # Nodes will fail to boot - must reflash SD cards
   # Then follow Option A
   ```

**For disaster recovery**: Just power off, reflash SD cards, and follow Option A.

**Important**: You must apply configs while nodes are in maintenance mode, before they become a proper cluster.

### 1.2 Find Maintenance Mode IPs (if needed)

If nodes got different DHCP IPs, check your router or use:
```bash
# Nodes should respond on their configured static IPs if already set
# Or check DHCP leases in your router
# Typical DHCP range: 192.168.1.100-200

# Test if nodes respond on expected IPs
for ip in 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14; do
    echo -n "$ip: "
    ping -c 2 -W 2 $ip > /dev/null 2>&1 && echo "✓" || echo "✗"
done
```

### 1.3 Apply Node Configurations

```bash
export TALOSCONFIG=~/.talos-secrets/pi-cluster/talosconfig
cd /path/to/pi-cluster/talos

# Apply configs to all nodes (use scripts if available)
./apply-static-ip-configs.sh
# Script will prompt for current IPs if they differ from defaults

# Or manually with --insecure flag (nodes in maintenance mode):
talosctl apply-config --insecure -n 192.168.1.11 \
    --file ~/.talos-secrets/pi-cluster/node11.yaml

talosctl apply-config --insecure -n 192.168.1.12 \
    --file ~/.talos-secrets/pi-cluster/node12.yaml

talosctl apply-config --insecure -n 192.168.1.13 \
    --file ~/.talos-secrets/pi-cluster/node13.yaml

talosctl apply-config --insecure -n 192.168.1.14 \
    --file ~/.talos-secrets/pi-cluster/node14.yaml

# Wait 30 seconds between each for reinitialization
```

**After applying configs**: Nodes will reinitialize with their static IPs and proper configuration.

### 1.4 Configure talosctl Endpoint

```bash
# Point talosctl at node 11 (direct IP, not VIP yet)
talosctl config endpoint 192.168.1.11
talosctl config node 192.168.1.11
```

### 1.5 Wait for Services and Bootstrap Cluster

```bash
# Wait 3-5 minutes for control plane services to start
talosctl -n 192.168.1.11 get services  # Check for etcd + kubelet

# Bootstrap etcd cluster (ONCE ONLY, on first control plane node)
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

## Backup Your Secrets

Run the backup script regularly:
```bash
./scripts/backup-secrets.sh
```

This backs up:
- All Talos configs from `~/.talos-secrets/pi-cluster/`
- Kubernetes secrets (talos-config, cloudflare-tunnel-token)
- Creates restore instructions

**Also keep backed up:**
- GitHub PAT
- This repository (git clone)

**Encrypt your backup:**
```bash
# Recommended: Encrypt with GPG
cd ~/cluster-backups
tar -czf - backup-YYYYMMDD-HHMMSS | gpg -c > cluster-backup.tar.gz.gpg

# Restore:
gpg -d cluster-backup.tar.gz.gpg | tar -xzf -
```

## Next Steps

1. Change Grafana password (default: admin/admin)
2. Test accessing services via Cloudflare Tunnel
3. Deploy additional applications via GitOps
4. Set up automated etcd backups
