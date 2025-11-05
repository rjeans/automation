# Talos Cluster Rebuild with VIP (Virtual IP)

**Last Updated**: 2025-11-05
**Status**: ✅ Ready for execution

## Overview

This guide provides a complete procedure for rebuilding the Talos Kubernetes cluster with a Virtual IP (VIP) for high availability. The VIP provides a single, stable endpoint for the Kubernetes API server that automatically fails over between control plane nodes.

## What is VIP and Why Use It?

**Virtual IP (VIP)**: A shared IP address (192.168.1.10) that "floats" between control plane nodes using leader election. Only one node owns the VIP at any time, providing:

- **High Availability**: If the node with the VIP fails, another control plane node takes over
- **Single Endpoint**: Access the cluster via one IP instead of picking specific nodes
- **Simplified Configuration**: Kubeconfig and talosconfig use one endpoint
- **No External Load Balancer Required**: VIP is managed by Talos itself

## Critical Design Requirement

⚠️ **IMPORTANT**: VIP **MUST** be configured at cluster generation time using:

```bash
talosctl gen config <cluster-name> https://<VIP_IP>:6443
```

**Why this matters**:
- Kubernetes certificates must include VIP in Subject Alternative Names (SANs)
- Etcd peer URLs must be correctly configured
- Network configuration is fundamental to cluster identity
- **Patching VIP onto an existing cluster will break networking**

This is why we need a complete rebuild rather than patching the existing cluster.

## Network Architecture

```
192.168.1.0/24 Network
├── 192.168.1.10  → VIP (floats between control plane nodes)
├── 192.168.1.11  → Control Plane Node 1 (with 1TB external storage)
├── 192.168.1.12  → Control Plane Node 2
├── 192.168.1.13  → Control Plane Node 3
└── 192.168.1.14  → Worker Node
```

**Primary Interface**: `end0` (Talos naming, not `eth0`)

## Pre-Rebuild Checklist

- [ ] No critical data on the cluster (or backed up)
- [ ] All nodes are accessible on the network (192.168.1.11-14)
- [ ] `talosctl` and `kubectl` are installed
- [ ] External 1TB USB drive on node 11 is connected (if applicable)
- [ ] Time allocated: ~1.5 hours for complete rebuild

## Rebuild Scripts Overview

This rebuild uses three automated scripts in sequence:

| Script | Purpose | Estimated Time |
|--------|---------|----------------|
| `rebuild-cluster-with-vip.sh` | Generate fresh configs with VIP endpoint | 5 minutes |
| `integrate-vip-config.sh` | Merge VIP network settings and patches | 5 minutes |
| `apply-new-configs.sh` | Apply configs to all nodes | 20 minutes |

**Total automation time**: ~30 minutes
**Manual verification time**: ~15 minutes
**Application redeployment via Flux**: ~15 minutes
**Complete rebuild**: ~1.5 hours

## Phase 1: Backup and Generate New Configurations

### Step 1.1: Run Rebuild Script

```bash
cd /Users/rich/Library/CloudStorage/Dropbox/Development/pi-cluster/talos
./rebuild-cluster-with-vip.sh
```

**What this does**:
1. Backs up existing configuration to `~/.talos-secrets/automation-old/`
2. Backs up existing kubeconfig to `~/.kube/config.old`
3. Generates fresh Talos configuration with VIP endpoint:
   ```bash
   talosctl gen config "talos-k8s-cluster" "https://192.168.1.10:6443" \
       --output-dir ~/.talos-secrets/automation-new \
       --kubernetes-version "1.31.2"
   ```

**Output files** (in `~/.talos-secrets/automation-new/`):
- `controlplane.yaml` - Base control plane configuration
- `worker.yaml` - Base worker configuration
- `talosconfig` - Talos CLI configuration
- `secrets.yaml` - Cluster secrets and certificates

### Step 1.2: Review Generated Configs (Optional)

```bash
# Review the generated controlplane config
cat ~/.talos-secrets/automation-new/controlplane.yaml | less

# Check that endpoint uses VIP
grep "192.168.1.10" ~/.talos-secrets/automation-new/controlplane.yaml
```

## Phase 2: Integrate VIP Network Configuration

### Step 2.1: Run Integration Script

```bash
./integrate-vip-config.sh
```

**What this does**:
1. Creates VIP network patch:
   ```yaml
   machine:
     network:
       interfaces:
         - interface: end0
           vip:
             ip: 192.168.1.10
   ```

2. Creates kubelet local-path patch (for persistent volumes):
   ```yaml
   machine:
     kubelet:
       extraMounts:
         - destination: /var/lib/rancher/local-path-provisioner
           type: bind
           source: /var/lib/rancher/local-path-provisioner
           options: [bind, rshared, rw]
   ```

3. Creates storage patch for node 11:
   ```yaml
   machine:
     disks:
       - device: /dev/sdb
         partitions:
           - size: 0
             mountpoint: /var/mnt/storage
   ```

4. Merges patches using `talosctl machineconfig patch` to create:
   - `controlplane-integrated.yaml` - For nodes 12 & 13 (VIP + kubelet)
   - `controlplane-node11.yaml` - For node 11 (VIP + kubelet + storage)
   - `worker-integrated.yaml` - For node 14 (kubelet only)

### Step 2.2: Verify Integrated Configs

```bash
# Check VIP is in controlplane config
grep -A3 "vip:" ~/.talos-secrets/automation-new/controlplane-integrated.yaml

# Check storage is in node 11 config
grep -A5 "disks:" ~/.talos-secrets/automation-new/controlplane-node11.yaml
```

## Phase 3: Reset Cluster Nodes

### Step 3.1: Prepare for Reset

**⚠️ WARNING**: This will completely wipe all nodes. Flux will redeploy everything afterwards.

Verify you have everything backed up:
```bash
# Check backups exist
ls -la ~/.talos-secrets/automation-old/
ls -la ~/.kube/config.old
```

### Step 3.2: Reset All Nodes

```bash
# Set up access to current cluster (if still accessible)
export TALOSCONFIG=~/.talos-secrets/automation-old/talosconfig

# Reset all nodes (wipes data, forces maintenance mode)
talosctl reset --nodes 192.168.1.11,192.168.1.12,192.168.1.13,192.168.1.14 \
    --graceful=false --reboot
```

**What happens**:
- Each node wipes its configuration
- Nodes reboot into maintenance mode
- Nodes are accessible via `--insecure` flag
- Takes 60-90 seconds per node

### Step 3.3: Verify Maintenance Mode

Wait 2-3 minutes, then verify all nodes are pingable:

```bash
for node in 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14; do
    echo -n "Testing $node: "
    if ping -c 2 -W 2 $node &>/dev/null; then
        echo "✓ Reachable"
    else
        echo "✗ Not reachable"
    fi
done
```

**All nodes must be reachable before proceeding.**

## Phase 4: Apply New Configurations

### Step 4.1: Run Apply Script

```bash
./apply-new-configs.sh
```

**What this does**:
1. Verifies all required config files exist
2. Checks each node is reachable
3. Applies configs in sequence:
   - Node 11: `controlplane-node11.yaml` (with storage)
   - Node 12: `controlplane-integrated.yaml`
   - Node 13: `controlplane-integrated.yaml`
   - Node 14: `worker-integrated.yaml`
4. Waits 30 seconds between each node for config processing

**Expected duration**: ~5 minutes for config application, 2-3 minutes for nodes to boot

### Step 4.2: Manual Alternative (If Script Fails)

If the script fails, apply configs manually:

```bash
# Apply to node 11 (with storage)
talosctl apply-config --insecure \
    --nodes 192.168.1.11 \
    --file ~/.talos-secrets/automation-new/controlplane-node11.yaml
sleep 30

# Apply to node 12
talosctl apply-config --insecure \
    --nodes 192.168.1.12 \
    --file ~/.talos-secrets/automation-new/controlplane-integrated.yaml
sleep 30

# Apply to node 13
talosctl apply-config --insecure \
    --nodes 192.168.1.13 \
    --file ~/.talos-secrets/automation-new/controlplane-integrated.yaml
sleep 30

# Apply to worker node 14
talosctl apply-config --insecure \
    --nodes 192.168.1.14 \
    --file ~/.talos-secrets/automation-new/worker-integrated.yaml
```

## Phase 5: Bootstrap Cluster with VIP

### Step 5.1: Configure Talosctl for VIP

```bash
# Point to new configuration
export TALOSCONFIG=~/.talos-secrets/automation-new/talosconfig

# Configure to use VIP as endpoint
talosctl config endpoint 192.168.1.10

# Set VIP as default node
talosctl config node 192.168.1.10

# Make permanent
echo 'export TALOSCONFIG=~/.talos-secrets/automation-new/talosconfig' >> ~/.zshrc
source ~/.zshrc
```

### Step 5.2: Bootstrap Cluster

```bash
# Bootstrap etcd cluster using VIP
talosctl bootstrap --nodes 192.168.1.10
```

**What happens**:
- Initializes etcd on control plane nodes
- Establishes etcd quorum (2 of 3 nodes required)
- Starts Kubernetes control plane services

**Wait 2-3 minutes** for services to start.

### Step 5.3: Verify Bootstrap

```bash
# Check talosctl can reach cluster via VIP
talosctl -n 192.168.1.10 version

# Check services are running
talosctl -n 192.168.1.10 services
# Should show: etcd (Running), kubelet (Running), containerd (Running)

# Check etcd cluster
talosctl -n 192.168.1.10 etcd members
# Should show 3 members, all LEARNER initially, then one becomes LEADER
```

## Phase 6: Access Kubernetes

### Step 6.1: Get Kubeconfig

```bash
# Retrieve kubeconfig using VIP
talosctl kubeconfig --nodes 192.168.1.10 --force

# Verify
kubectl config current-context
# Should show: admin@talos-k8s-cluster
```

### Step 6.2: Verify Cluster

```bash
# Check nodes (may take 2-3 minutes for all to be Ready)
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system

# All pods should be Running or Completed
```

**Expected output**:
```
NAME                        STATUS   ROLES           AGE   VERSION
talos-n7p-g4v              Ready    control-plane   5m    v1.31.2
talos-vkr-2wp              Ready    control-plane   5m    v1.31.2
talos-zx8-m3n              Ready    control-plane   5m    v1.31.2
talos-abc-123              Ready    <none>          4m    v1.31.2
```

## Phase 7: Verify VIP Functionality

### Step 7.1: Test VIP Connectivity

```bash
# VIP should respond to ping
ping -c 3 192.168.1.10

# VIP should respond to API requests
kubectl cluster-info
# Should show: Kubernetes control plane is running at https://192.168.1.10:6443
```

### Step 7.2: Identify VIP Owner

```bash
# Check which node currently owns the VIP
for node in 192.168.1.11 192.168.1.12 192.168.1.13; do
    echo "=== Node $node ==="
    talosctl -n $node get addresses | grep 192.168.1.10 || echo "VIP not on this node"
done
```

**Expected output**: One node will show the VIP address, others will not.

### Step 7.3: Test VIP Failover

```bash
# Identify which node has the VIP (from step 7.2)
# Let's say it's 192.168.1.11

# Reboot that node
talosctl -n 192.168.1.11 reboot

# Watch VIP connectivity (should stay up with brief interruption)
while true; do
    if kubectl get nodes &>/dev/null; then
        echo "$(date): ✓ API accessible via VIP"
    else
        echo "$(date): ✗ API not accessible"
    fi
    sleep 2
done
# Press Ctrl+C to stop

# After ~60 seconds, check VIP moved to another node
for node in 192.168.1.11 192.168.1.12 192.168.1.13; do
    echo "=== Node $node ==="
    talosctl -n $node get addresses | grep 192.168.1.10 || echo "VIP not on this node"
done
```

**Expected behavior**: VIP should move to another control plane node within 30-60 seconds.

## Phase 8: Finalize Configuration

### Step 8.1: Move New Config to Production

```bash
# Make the new config the production config
rm -rf ~/.talos-secrets/automation
mv ~/.talos-secrets/automation-new ~/.talos-secrets/automation

# Update shell to use correct path
sed -i.bak 's|automation-new|automation|g' ~/.zshrc
source ~/.zshrc
```

### Step 8.2: Update Repository (Optional)

```bash
cd /Users/rich/Library/CloudStorage/Dropbox/Development/pi-cluster

# Document the rebuild
cat >> CLUSTER-HISTORY.md <<EOF

## $(date +%Y-%m-%d): Cluster Rebuilt with VIP

- Rebuilt cluster from scratch with VIP on 192.168.1.10
- New secrets generated
- All configs include VIP in certificates
- Cluster endpoint: https://192.168.1.10:6443
- Kubernetes: v1.31.2
- Talos: v1.8.x

EOF

git add CLUSTER-HISTORY.md
git commit -m "docs: Record cluster rebuild with VIP"
git push
```

## Phase 9: Redeploy Applications via Flux

### Step 9.1: Bootstrap Flux

```bash
# Bootstrap Flux from your GitOps repository
flux bootstrap github \
    --owner=rjeans \
    --repository=automation \
    --branch=main \
    --path=flux/clusters/talos \
    --personal
```

**What this does**:
- Installs Flux controllers in `flux-system` namespace
- Connects to GitHub repository
- Starts monitoring for changes
- Begins deploying infrastructure and applications

### Step 9.2: Restore Secrets

Flux cannot deploy secrets from Git (security). Restore them manually:

```bash
# Cluster dashboard Talos config (if applicable)
kubectl create secret generic talos-config \
    -n cluster-dashboard \
    --from-file=$HOME/.talos-secrets/pi-cluster/talosconfig

# Cloudflare tunnel token (if applicable)
kubectl create secret generic cloudflare-tunnel-token \
    -n cloudflare-tunnel \
    --from-literal=token="YOUR_CLOUDFLARE_TUNNEL_TOKEN"

# n8n PostgreSQL password (if applicable)
kubectl create secret generic n8n-postgres-secret \
    -n n8n \
    --from-literal=password="YOUR_POSTGRES_PASSWORD"

# n8n encryption key (if applicable)
kubectl create secret generic n8n-encryption-key \
    -n n8n \
    --from-literal=key="YOUR_N8N_ENCRYPTION_KEY"
```

### Step 9.3: Watch Flux Deploy Everything

```bash
# Watch Flux reconcile and deploy
flux get kustomizations --watch

# Watch all HelmReleases
flux get helmreleases -A

# Watch pods come up
watch kubectl get pods -A
```

**Expected deployment order**:
1. Infrastructure (5-10 min):
   - Traefik (Ingress)
   - Metrics Server
   - cert-manager
   - Cloudflare Tunnel
2. Applications (5-10 min):
   - PostgreSQL (for n8n)
   - n8n
   - cluster-dashboard

**Total time**: ~15-20 minutes

### Step 9.4: Verify Application Deployment

```bash
# Check all applications are running
kubectl get pods -A | grep -v "Running\|Completed" | grep -v "NAMESPACE"
# Should return no results (all pods Running or Completed)

# Test ingress
curl -H "Host: dashboard.jeansy.org" http://192.168.1.11:30080
# Should return HTML or redirect

# Test via Cloudflare Tunnel
curl https://dashboard.jeansy.org
# Should be accessible
```

## Troubleshooting

### VIP Not Responding

```bash
# Check VIP configuration on control plane nodes
for node in 192.168.1.11 192.168.1.12 192.168.1.13; do
    echo "=== $node ==="
    talosctl -n $node get addresses
done

# Check network interfaces
talosctl -n 192.168.1.11 get links

# Verify VIP is in machine config
talosctl -n 192.168.1.11 get machineconfig -o yaml | grep -A5 "vip:"
```

### Nodes Not Forming Cluster

```bash
# Check etcd status
talosctl -n 192.168.1.10 etcd members

# Check service status on each control plane node
for node in 192.168.1.11 192.168.1.12 192.168.1.13; do
    echo "=== $node ==="
    talosctl -n $node service etcd status
done

# Check for errors
talosctl -n 192.168.1.11 logs etcd
```

### Kubernetes API Not Accessible

```bash
# Check API server is running
kubectl get pods -n kube-system | grep apiserver

# Check certificate includes VIP
talosctl -n 192.168.1.11 get machineconfig -o yaml | grep -A10 "certSANs"
# Should include 192.168.1.10

# Test direct node access
kubectl --server=https://192.168.1.11:6443 get nodes
```

### Flux Not Deploying

```bash
# Check Flux pods
kubectl get pods -n flux-system

# Check Flux logs
flux logs --follow --level=error

# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization infrastructure --with-source
```

## Recovery Scripts

If a node fails and needs recovery:

### `recover-node.sh`

Applies configuration to a node in maintenance mode:

```bash
./talos/recover-node.sh <node-ip> [config-file]

# Example: Recover control plane node 11
./talos/recover-node.sh 192.168.1.11 ~/.talos-secrets/automation/controlplane-node11.yaml
```

### `reset-sd-card.sh`

Removes machine config from SD card to force maintenance mode (Mac only):

```bash
# Insert SD card into Mac
./talos/reset-sd-card.sh

# Follow prompts to select the SD card volume
```

**Note**: macOS cannot read Linux filesystems (ext4/xfs) that Talos uses. This script has limited utility. For reliable reset, use `talosctl reset` remotely.

## Time Estimates

| Phase | Task | Duration |
|-------|------|----------|
| 1 | Generate configs | 5 min |
| 2 | Integrate VIP config | 5 min |
| 3 | Reset nodes | 5 min |
| 4 | Apply configs | 10 min |
| 5 | Bootstrap | 5 min |
| 6 | Kubernetes access | 2 min |
| 7 | Verify VIP | 5 min |
| 8 | Finalize | 3 min |
| 9 | Redeploy apps (Flux) | 15 min |
| **Total** | **Complete rebuild** | **~55 min** |

Add ~30 minutes for troubleshooting and verification: **Total ~1.5 hours**

## Post-Rebuild Verification Checklist

- [ ] All 4 nodes show `Ready` in `kubectl get nodes`
- [ ] VIP (192.168.1.10) responds to ping
- [ ] Can access Kubernetes via VIP: `kubectl --server=https://192.168.1.10:6443 get nodes`
- [ ] VIP fails over when active node reboots
- [ ] Flux is deployed and reconciling: `flux get kustomizations`
- [ ] All infrastructure pods Running: `kubectl get pods -n traefik,metrics-server,cloudflare-tunnel`
- [ ] All application pods Running: `kubectl get pods -n n8n,cluster-dashboard`
- [ ] Can access applications via ingress
- [ ] Can access applications via Cloudflare Tunnel
- [ ] New configuration backed up to secure location

## Security Considerations

✅ **VIP configured at generation** - Certificates include VIP in SANs
✅ **New secrets generated** - Old secrets are invalidated
✅ **Secrets stored locally only** - Not in Git repository
✅ **Restrictive permissions** - `chmod 600` on all secret files
✅ **Backup secured** - Old configs saved to `automation-old`

## References

- [Talos VIP Documentation](https://www.talos.dev/latest/talos-guides/network/vip/)
- [Talos Cluster Configuration](https://www.talos.dev/latest/reference/configuration/)
- [Kubernetes High Availability](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)
- [Project GitOps Guide](GITOPS-QUICKSTART.md)
- [Disaster Recovery Guide](99-disaster-recovery-gitops.md)

---

**Documentation Version**: 1.0
**Last Updated**: 2025-11-05
**Tested On**: Talos v1.8.x, Kubernetes v1.31.2
**Author**: Automated cluster rebuild process
