# Cluster Rebuild Guide

> **⚠️ IMPORTANT**: This guide covers **manual Talos cluster rebuild only**.
>
> **For complete disaster recovery with GitOps**, see [99-disaster-recovery-gitops.md](99-disaster-recovery-gitops.md)
>
> The disaster recovery guide covers:
> - Automatic infrastructure restoration via Flux
> - Automatic application deployment via GitOps
> - Complete recovery procedure (~45 minutes)
>
> Use this manual guide only if you need to rebuild just the Talos layer without Flux.

## When to Rebuild

Rebuild the cluster when:
- Secrets have been compromised
- Major version upgrade of Talos
- Starting fresh after testing
- Cluster is in an unrecoverable state

## Pre-Rebuild Checklist

- [ ] Backup any data from the cluster (if needed)
- [ ] Document current cluster state
- [ ] Ensure you have the Talos image on SD cards
- [ ] All Raspberry Pis are accessible on the network

## Step 1: Destroy Existing Cluster

### Clean Up Old Secrets

```bash
# Remove old compromised secrets
rm -rf ~/.talos-secrets/automation/*

# Or completely remove and recreate
rm -rf ~/.talos-secrets/automation
mkdir -p ~/.talos-secrets/automation
chmod 700 ~/.talos-secrets/automation
```

### Reset Nodes (Optional but Recommended)

```bash
# If you can still access the cluster
export TALOSCONFIG=~/.talos-secrets/automation/talosconfig  # if it exists

# Reset each node (wipes all data)
talosctl reset --nodes 192.168.1.11 --graceful=false --reboot
talosctl reset --nodes 192.168.1.12 --graceful=false --reboot
talosctl reset --nodes 192.168.1.13 --graceful=false --reboot
talosctl reset --nodes 192.168.1.14 --graceful=false --reboot
```

**Alternative**: Re-flash SD cards with fresh Talos image (guaranteed clean slate)

## Step 2: Reflash SD Cards (Recommended)

```bash
cd ~/Downloads  # or wherever you have the image

# Decompress if needed
xz -d metal-arm64.raw.xz

# Flash each SD card
# macOS
diskutil list  # find your SD card
diskutil unmountDisk /dev/diskN
sudo dd if=metal-arm64.raw of=/dev/rdiskN bs=4M conv=fsync
diskutil eject /dev/diskN
```

Repeat for all 4 cards.

## Step 3: Boot Fresh Cluster

1. Insert SD cards into Raspberry Pis
2. Power on all nodes
3. Wait 60-90 seconds
4. Verify network connectivity:

```bash
ping -c 3 192.168.1.11
ping -c 3 192.168.1.12
ping -c 3 192.168.1.13
ping -c 3 192.168.1.14
```

## Step 4: Generate Fresh Configuration

**Generate completely new secrets and configs:**

```bash
# Generate fresh secrets
talosctl gen secrets -o ~/.talos-secrets/automation/secrets.yaml

# Generate machine configurations
talosctl gen config talos-k8s-cluster https://192.168.1.11:6443 \
  --with-secrets ~/.talos-secrets/automation/secrets.yaml \
  --output-types controlplane,worker,talosconfig \
  --output ~/.talos-secrets/automation/

# Set restrictive permissions
chmod 600 ~/.talos-secrets/automation/*
```

## Step 5: Configure talosctl

```bash
# Set talosconfig
export TALOSCONFIG=~/.talos-secrets/automation/talosconfig

# Configure endpoints (control plane nodes only - they run Talos API)
talosctl config endpoint 192.168.1.11 192.168.1.12 192.168.1.13

# Set default node
talosctl config node 192.168.1.11

# Add to shell profile
echo 'export TALOSCONFIG=~/.talos-secrets/automation/talosconfig' >> ~/.zshrc
source ~/.zshrc
```

**Note**: Endpoints are set to control plane nodes only (.11, .12, .13) because they run the Talos API. You can still target the worker node (.14) using `talosctl -n 192.168.1.14 <command>` when needed.

## Step 6: Apply Configurations

### Control Plane Nodes (3 nodes: .11, .12, .13)

```bash
# First control plane
talosctl apply-config --insecure \
  --nodes 192.168.1.11 \
  --file ~/.talos-secrets/automation/controlplane.yaml

sleep 30

# Second control plane
talosctl apply-config --insecure \
  --nodes 192.168.1.12 \
  --file ~/.talos-secrets/automation/controlplane.yaml

sleep 30

# Third control plane
talosctl apply-config --insecure \
  --nodes 192.168.1.13 \
  --file ~/.talos-secrets/automation/controlplane.yaml

sleep 30

# Verify
talosctl version
```

## Step 7: Bootstrap etcd

```bash
# Bootstrap only on first control plane (ONCE!)
talosctl bootstrap --nodes 192.168.1.11

# Wait ~2 minutes
sleep 120

# Check services
talosctl services
```

## Step 8: Get Kubernetes Access

```bash
# Get kubeconfig
talosctl kubeconfig --force

# Verify
kubectl get nodes
```

You should see all three control plane nodes in `Ready` state.

## Step 9: Add Worker Node

```bash
# Worker node (.14 only)
talosctl apply-config --insecure \
  --nodes 192.168.1.14 \
  --file ~/.talos-secrets/automation/worker.yaml

# Wait for node to join
sleep 30

# Verify all nodes
kubectl get nodes -o wide
```

## Step 10: Verify Cluster Health

```bash
# Check all nodes (should show 3 control-plane + 1 worker)
kubectl get nodes

# Check system pods
kubectl get pods -n kube-system

# Verify Talos services on all control plane nodes
talosctl -n 192.168.1.11 services
talosctl -n 192.168.1.12 services
talosctl -n 192.168.1.13 services

# Run health check script
./scripts/talos-health.sh
```

## Step 11: Backup Fresh Secrets

```bash
# Backup to encrypted external drive
cp -r ~/.talos-secrets/automation /Volumes/YourBackupDrive/talos-secrets-$(date +%Y%m%d)

# Verify backup
ls -la /Volumes/YourBackupDrive/talos-secrets-*
```

## Common Issues

### Nodes Won't Accept Configuration

```bash
# Ensure using --insecure flag for fresh install
talosctl apply-config --insecure --nodes <ip> --file <config>

# Check node is actually reachable
ping <node-ip>
```

### Bootstrap Fails

```bash
# Only bootstrap ONCE on one control plane node
# Check etcd isn't already running
talosctl -n 192.168.1.11 service etcd

# If stuck, reset and try again
talosctl reset --nodes 192.168.1.11 --graceful=false --reboot
```

### Nodes Show NotReady

This is normal! Talos includes Flannel CNI which should make nodes `Ready` automatically. If they stay `NotReady` for >5 minutes:

```bash
# Check CNI pods
kubectl get pods -n kube-system | grep flannel

# Check kubelet logs
talosctl -n <node-ip> logs kubelet
```

## Post-Rebuild Tasks

After successful Talos rebuild, you have two options:

### Option A: GitOps Deployment (Recommended)

Deploy all infrastructure and applications automatically via Flux:

```bash
# Follow the GitOps disaster recovery guide
# See: docs/99-disaster-recovery-gitops.md

# Quick summary:
# 1. Bootstrap Flux (5 minutes)
flux bootstrap github --owner=rjeans --repository=automation ...

# 2. Restore secrets (5 minutes)
kubectl create secret generic talos-config \
    -n cluster-dashboard \
    --from-file=$HOME/.talos-secrets/pi-cluster/talosconfig
kubectl create secret generic cloudflare-tunnel-token -n cloudflare-tunnel ...

# 3. Watch Flux auto-deploy everything (15 minutes)
flux get kustomizations --watch

# That's it! Flux deploys:
# - Traefik, Metrics Server, Cloudflare Tunnel
# - n8n, cluster-dashboard
# - All configurations and ingress routes
```

**Total time**: ~25 minutes for complete cluster with all applications

**See**: [99-disaster-recovery-gitops.md](99-disaster-recovery-gitops.md) for detailed instructions

### Option B: Manual Deployment (Legacy)

If you need to deploy infrastructure manually (not recommended):

1. **Update Git**:
   ```bash
   # Document cluster rebuild in git
   echo "$(date): Cluster rebuilt with fresh secrets" >> CLUSTER-HISTORY.md
   git add CLUSTER-HISTORY.md
   git commit -m "docs: Record cluster rebuild"
   ```

2. **Deploy Core Services** (Manual - see individual guides):
   - ~~Ingress~~ → Use Flux (see [GITOPS-QUICKSTART.md](GITOPS-QUICKSTART.md))
   - ~~Metrics Server~~ → Managed by Flux
   - ~~Cloudflare Tunnel~~ → Managed by Flux
   - Storage (if needed beyond local-path)

3. **Deploy Applications** (Manual - not recommended):
   - ~~n8n~~ → Managed by Flux (see [flux/clusters/talos/apps/n8n/](../flux/clusters/talos/apps/n8n/))
   - ~~cluster-dashboard~~ → Managed by Flux

**Note**: Manual deployment is discouraged. The cluster is designed for GitOps. See [GITOPS-ROADMAP.md](GITOPS-ROADMAP.md) for architecture details.

## Security Notes

✅ **New secrets generated** - old ones are useless
✅ **Stored locally only** - not in git
✅ **Backed up securely** - encrypted external drive
✅ **Clean slate** - no compromised material

## Time Estimate

- SD card reflash: ~20 minutes (all 4 cards)
- Configuration and bootstrap: ~10 minutes
- Total: **~30 minutes** for clean rebuild

---

**Ready to proceed with rebuild?** Start from [Step 1](#step-1-destroy-existing-cluster)
