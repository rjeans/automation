# Fresh Talos Install with VIP

**Quick reference for installing Talos on freshly flashed SD cards with VIP configured.**

This guide uses **static IP configuration** - each node gets its own configuration file with a static IP assignment. This eliminates DHCP dependencies and DNS resolution issues that can prevent nodes from booting properly.

## Prerequisites

- 4x SD cards (32GB or larger)
- Raspberry Pi nodes with PoE HATs
- Docker installed (for building custom Talos image)
- Network with IPs: 192.168.1.11-14 available

## Step 1: Download Custom Talos Image with PoE HAT Support

Since you're using Raspberry Pi PoE HATs, you need a custom Talos image with the PoE overlay.

**Option A: Use Talos Image Factory API (Recommended)**

**Quick Method - Using Helper Script**:
```bash
cd /Users/rich/Library/CloudStorage/Dropbox/Development/pi-cluster/talos
./create-schematic.sh
```

This creates a schematic via the API and provides download commands.

**Manual Method - Using curl**:
1. Create schematic:
   ```bash
   cd /Users/rich/Library/CloudStorage/Dropbox/Development/pi-cluster
   curl -X POST --data-binary @raspberrypi/rpi_poe.yaml https://factory.talos.dev/schematics
   ```

   Example response:
   ```json
   {"id":"311558db2a6142614f225acec4c6adefb413a15fed76a022ff8f3ac50fceab0a"}
   ```

2. Download using the schematic ID:
   ```bash
   cd ~/Downloads
   wget https://factory.talos.dev/image/311558db2a6142614f225acec4c6adefb413a15fed76a022ff8f3ac50fceab0a/v1.11.3/metal-arm64.raw.xz
   xz -d metal-arm64.raw.xz
   ```

**Alternative - Web Interface**:
1. Go to: https://factory.talos.dev/
2. Paste your overlay from `raspberrypi/rpi_poe.yaml`
3. Click "Generate" and download the image

**Option B: Build Locally with Docker**

```bash
cd /Users/rich/Library/CloudStorage/Dropbox/Development/pi-cluster/talos
./build-talos-image.sh
```

This uses your local `raspberrypi/rpi_poe.yaml` overlay file and takes ~10 minutes.

**What the overlay does**:
- Configures PoE HAT fan control with temperature thresholds (65°C, 70°C, 75°C, 80°C)
- Disables Bluetooth and WiFi (use Ethernet only)
- Enables UART for debugging
- Includes vc4 graphics driver extension

**Time estimate**:
- Option A (Image Factory): ~5 minutes (download + decompress)
- Option B (Local build): ~10 minutes

## Step 2: Flash SD Cards

```bash
# Navigate to where you downloaded/built the image
cd ~/Downloads          # If using Image Factory
# OR
cd ~/Downloads/_out     # If using local build

# For each SD card:
diskutil list                    # Find your SD card (e.g., disk4)
diskutil unmountDisk /dev/diskN  # Replace N with your disk number

# Flash the image
# If using Image Factory download:
sudo dd if=<factory-downloaded-filename>.raw of=/dev/rdiskN bs=4M conv=fsync
# OR if built locally:
sudo dd if=sbc-rpi_generic-arm64.raw of=/dev/rdiskN bs=4M conv=fsync

diskutil eject /dev/diskN

# Repeat for all 4 cards
```

**Time estimate**: ~40 minutes (4 cards × ~10 min each)

## Step 3: Generate Cluster Configuration

Generate node-specific configurations with static IPs and VIP:

```bash
cd /Users/rich/Library/CloudStorage/Dropbox/Development/pi-cluster/talos

# Generate node-specific configs with static IPs + VIP
./rebuild-cluster-with-static-ips.sh
```

**Output**:
- Creates: `~/.talos-secrets/pi-cluster/`
- Node configs: `node11.yaml`, `node12.yaml`, `node13.yaml`, `node14.yaml`
- Each node has static IP (192.168.1.11-14), hostname, and VIP (control planes only)
- Base configs: `controlplane.yaml`, `worker.yaml`, `talosconfig`, `secrets.yaml`

**Configuration Details**:
- Node 11 (192.168.1.11): talos-cp1, control plane with 1TB USB storage
- Node 12 (192.168.1.12): talos-cp2, control plane
- Node 13 (192.168.1.13): talos-cp3, control plane
- Node 14 (192.168.1.14): talos-worker1, worker node
- VIP (192.168.1.10): Shared virtual IP for API server access
- Gateway: 192.168.1.1
- Netmask: /24

## Step 4: Boot Nodes

1. Insert SD cards into Raspberry Pis:
   - Node 11 (192.168.1.11) - with 1TB USB drive
   - Node 12 (192.168.1.12)
   - Node 13 (192.168.1.13)
   - Node 14 (192.168.1.14)

2. Power on all nodes

3. Wait 60-90 seconds for boot

4. Verify nodes are reachable:
   ```bash
   for node in 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14; do
       echo -n "Testing $node: "
       ping -c 2 -W 2 $node && echo "✓" || echo "✗"
   done
   ```

All nodes should be pingable (they boot into maintenance mode).

## Step 5: Apply Configurations

Apply the node-specific configurations with static IPs:

```bash
./apply-static-ip-configs.sh
```

**What happens**:
- Prompts for current DHCP IPs of each node (in case they booted with different IPs)
- Applies node-specific configs with static IPs:
  - `node11.yaml` → 192.168.1.11 (talos-cp1 with storage)
  - `node12.yaml` → 192.168.1.12 (talos-cp2)
  - `node13.yaml` → 192.168.1.13 (talos-cp3)
  - `node14.yaml` → 192.168.1.14 (talos-worker1)
- Waits 30 seconds between each node
- Verifies nodes are reachable on static IPs after configuration

**Time estimate**: ~10 minutes

## Step 6: Bootstrap Cluster

**Important**: VIP won't be active until after bootstrap completes. Bootstrap using a direct node IP first.

```bash
export TALOSCONFIG=~/.talos-secrets/pi-cluster/talosconfig

# STEP 1: Bootstrap using direct node IP (not VIP - it's not active yet)
talosctl config endpoint 192.168.1.11
talosctl config node 192.168.1.11

# Wait 3-5 minutes for all control plane services to start
# Check services are ready (you should see etcd, kubelet, etc.)
talosctl -n 192.168.1.11 get services

# Bootstrap etcd cluster
talosctl bootstrap --nodes 192.168.1.11
```

**Wait 2-3 minutes** for bootstrap to complete and VIP to activate.

```bash
# STEP 2: Verify VIP is now active
ping -c 3 192.168.1.10

# Check which node has the VIP
for node in 192.168.1.11 192.168.1.12 192.168.1.13; do
    echo "=== Node $node ==="
    talosctl -n $node get addresses | grep 192.168.1.10 || echo "VIP not here"
done

# STEP 3: Switch to VIP endpoint with node list for fallback
talosctl config endpoint 192.168.1.10
talosctl config nodes 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14
```

Now talosctl will use the VIP by default, with automatic fallback to individual nodes.

## Step 7: Get Kubernetes Access

```bash
# Retrieve kubeconfig
talosctl kubeconfig --nodes 192.168.1.10 --force

# Verify nodes (may take 2-3 minutes to show Ready)
kubectl get nodes
```

**Expected output**:
```
NAME                STATUS   ROLES           AGE   VERSION
talos-xxx-xxx       Ready    control-plane   3m    v1.31.2
talos-xxx-xxx       Ready    control-plane   3m    v1.31.2
talos-xxx-xxx       Ready    control-plane   3m    v1.31.2
talos-xxx-xxx       Ready    <none>          2m    v1.31.2
```

## Step 8: Verify VIP

```bash
# VIP should respond
ping -c 3 192.168.1.10

# Check which node has VIP
for node in 192.168.1.11 192.168.1.12 192.168.1.13; do
    echo "=== Node $node ==="
    talosctl -n $node get addresses | grep 192.168.1.10 || echo "VIP not here"
done
```

One control plane node should show the VIP address.

## Step 9: Deploy Applications (Optional)

If you want to deploy your applications via Flux:

```bash
# Bootstrap Flux
flux bootstrap github \
    --owner=rjeans \
    --repository=pi-cluster \
    --branch=main \
    --path=flux/clusters/talos \
    --personal

# Restore secrets (examples)
kubectl create secret generic talos-config \
    -n cluster-dashboard \
    --from-file=talosconfig=~/.talos-secrets/pi-cluster/talosconfig

kubectl create secret generic cloudflare-tunnel-token \
    -n cloudflare-tunnel \
    --from-literal=token="YOUR_TOKEN"

# Watch deployment
flux get kustomizations --watch
```

## Total Time Estimate

| Phase | Task | Duration |
|-------|------|----------|
| 1 | Get custom Talos image | ~5 min (Image Factory) |
| 2 | Flash SD cards | ~40 min |
| 3 | Generate configs with static IPs | 5 min |
| 4 | Boot nodes | 5 min |
| 5 | Apply static IP configs | 10 min |
| 6 | Bootstrap | 5 min |
| 7 | Get kubeconfig | 2 min |
| 8 | Verify VIP | 2 min |
| 9 | Deploy apps (optional) | 15 min |
| **Total** | **Fresh install** | **~90 min** |

*Add ~5 minutes if building locally instead of using Image Factory*

## Troubleshooting

### Control Plane Nodes Not Booting / DNS Errors

**Symptom**: Control plane nodes show continuous DNS request errors and won't boot properly.

**Solution**: This guide uses static IPs which should prevent these issues. If you still encounter DNS errors:

```bash
# 1. Verify your overlay includes PoE HAT configuration
cat raspberrypi/rpi_poe.yaml

# 2. Ensure SD cards were flashed with custom Talos image
# 3. Check that gateway (192.168.1.1) is correct for your network
# 4. Verify static IPs .11-.14 are not in use by other devices

# If needed, regenerate configs and reapply:
./rebuild-cluster-with-static-ips.sh
./apply-static-ip-configs.sh
```

### Node Not Reachable

```bash
# Check node has IP from DHCP/static assignment
# Check network cables
# Check node is powered on (PoE HAT LEDs)

# For static IP nodes, verify on correct IP:
ping -c 3 192.168.1.11
ping -c 3 192.168.1.12
ping -c 3 192.168.1.13
ping -c 3 192.168.1.14
```

### Config Apply Fails

```bash
# Ensure node is in maintenance mode
# Node should be pingable
# Try again - nodes may still be booting

# Check current DHCP IP of nodes:
# Look in router DHCP lease table
# Or use: nmap -p 50000 192.168.1.0/24

# Apply config using current IP:
talosctl apply-config --insecure \
    --nodes <current-ip> \
    --file ~/.talos-secrets/pi-cluster/node11.yaml
```

### VIP Not Responding

```bash
# Check VIP is configured on at least one node
for node in 192.168.1.11 192.168.1.12 192.168.1.13; do
    talosctl -n $node get addresses
done

# Check for errors in VIP configuration
talosctl -n 192.168.1.11 get machineconfig -o yaml | grep -A5 "vip:"
```

### Bootstrap Fails: "bootstrap is not available yet"

**Symptom**: Error when running `talosctl bootstrap`: `rpc error: code = FailedPrecondition desc = bootstrap is not available yet`

**Cause**: Control plane services (etcd, kubelet) haven't fully started yet after applying configs.

**Solution**:
```bash
# 1. Check which services are running (should see etcd and kubelet)
talosctl -n 192.168.1.11 get services

# If you only see base services (apid, machined, containerd), wait 3-5 more minutes

# 2. Check for errors in logs
talosctl -n 192.168.1.11 dmesg | tail -30

# 3. Once you see etcd and kubelet services, retry bootstrap
talosctl bootstrap --nodes 192.168.1.11

# Only bootstrap ONCE - don't run again if already successful
```

## Key Differences from Rebuild

**Fresh Install**:
- ✅ No backup needed
- ✅ No `talosctl reset` needed
- ✅ Nodes boot directly into maintenance mode
- ✅ Slightly faster (no reset step)

**Rebuild**:
- 📦 Backs up existing config
- 🔄 Requires `talosctl reset` to wipe nodes
- 🗄️ May have existing data to preserve
- ⏱️ Takes slightly longer

## Next Steps

After fresh install:

1. **Test VIP failover**: Reboot node with VIP, watch it move
2. **Deploy applications**: Use Flux for GitOps
3. **Set up monitoring**: Deploy metrics and dashboards
4. **Configure backups**: Set up backup procedures
5. **Document**: Update cluster documentation

## References

- Main VIP Guide: [../docs/talos-vip-rebuild.md](../docs/talos-vip-rebuild.md)
- Script Documentation: [README.md](README.md)
- Talos Documentation: https://www.talos.dev/latest/

---

**Last Updated**: 2025-11-05
**Talos Version**: v1.11.3
**Kubernetes Version**: v1.31.2
