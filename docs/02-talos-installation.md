# Talos Linux Installation Guide

## Overview

This guide walks through installing Talos Linux on your Raspberry Pi cluster and bootstrapping a Kubernetes cluster.

## Prerequisites

Ensure you've completed:
- ✅ [01-prerequisites.md](./01-prerequisites.md)
- ✅ [00-network-plan.md](./00-network-plan.md)
- ✅ All Raspberry Pis have updated EEPROM
- ✅ Static IPs configured in DHCP

## Step 1: Download Talos Image

Download the latest Talos ARM64 image for Raspberry Pi from Talos Image Factory:

```bash
# Navigate to project directory
cd /path/to/automation

# Create downloads directory
mkdir -p downloads
cd downloads

# Set version and schematic ID
TALOS_VERSION=v1.11.0  # Check https://www.talos.dev for latest version
SCHEMATIC_ID=ee21ef4a5ef808a9b7484cc0dda0f25075021691c8c09a276591eedb638ea1f9  # Default RPi schematic

# Download the Image Factory image for Raspberry Pi
curl -LO https://factory.talos.dev/image/${SCHEMATIC_ID}/${TALOS_VERSION}/metal-arm64.raw.xz

# Decompress the image
xz -d metal-arm64.raw.xz
```

**About the Image**:
- Uses Talos Image Factory for reproducible builds
- Default schematic includes base Raspberry Pi support
- For GPU support (optional), you can generate a custom schematic with the `vc4` extension at https://factory.talos.dev

## Step 2: Flash SD Cards

Flash the Talos image to each microSD card.

### macOS

```bash
# From the downloads directory
cd /path/to/automation/downloads

# Find the disk identifier
diskutil list

# Unmount the disk (replace diskN with your SD card)
diskutil unmountDisk /dev/diskN

# Write the image (this will take several minutes)
sudo dd if=metal-arm64.raw of=/dev/rdiskN bs=4M conv=fsync

# Eject the card
diskutil eject /dev/diskN
```

### Linux

```bash
# From the downloads directory
cd /path/to/automation/downloads

# Find the disk identifier
lsblk

# Unmount the disk (replace sdX with your SD card)
sudo umount /dev/sdX*

# Write the image with progress
sudo dd if=metal-arm64.raw of=/dev/sdX bs=4M conv=fsync status=progress

# Sync and eject
sync
sudo eject /dev/sdX
```

**Repeat for all 4 SD cards**.

## Step 3: Boot Raspberry Pis

1. Insert SD cards into each Raspberry Pi
2. Connect Ethernet cables to switch
3. Power on all Raspberry Pis
4. Wait ~60-90 seconds for boot

The Pis should:
- Get DHCP addresses (or your static reservations)
- Show green LED activity
- Be reachable via Talos API on port 50000

## Step 4: Verify Network Connectivity

Verify that the Raspberry Pis are reachable on the network:

```bash
# Ping each node to verify network connectivity
ping -c 3 192.168.1.11
ping -c 3 192.168.1.12
ping -c 3 192.168.1.13
ping -c 3 192.168.1.14
```

All nodes should respond to ping requests, confirming they've booted successfully and are on the network.

**Note**: You cannot use `talosctl version` until after you generate and apply configuration in the next steps.

## Step 5: Generate Talos Configuration

Create cluster configuration files:

```bash
# Navigate to project directory
cd /Users/rich/Library/CloudStorage/Dropbox/Development/automation

# Generate secrets and configs
talosctl gen secrets -o talos/secrets/secrets.yaml

# Generate machine configurations
# Using first control plane IP as the cluster endpoint
talosctl gen config talos-k8s-cluster https://192.168.1.11:6443 \
  --with-secrets talos/secrets/secrets.yaml \
  --output-types controlplane,worker,talosconfig \
  --output talos/config/
```

This creates:
- `talos/config/controlplane.yaml` - Control plane node config
- `talos/config/worker.yaml` - Worker node config
- `talos/config/talosconfig` - talosctl client configuration
- `talos/secrets/secrets.yaml` - Cluster secrets (DO NOT COMMIT unencrypted)

**Important**: The cluster endpoint (`https://192.168.1.11:6443`) should point to your first control plane node. For HA setups, you can use a VIP or load balancer IP instead.

## Step 6: Customize Configuration (Optional)

### Create Configuration Patches

For Raspberry Pi specific settings, create patches:

```bash
cat > talos/patches/rpi-gpu.yaml <<EOF
machine:
  install:
    extensions:
      - siderolabs/vc4
  sysctls:
    vm.overcommit_memory: "1"
EOF
```

### Network Configuration (if not using DHCP)

Create patches for static IP configuration:

```bash
# Control plane node 1
cat > talos/patches/static-ip-cp01.yaml <<EOF
machine:
  network:
    hostname: rpi-cp01
    interfaces:
      - interface: eth0
        addresses:
          - 192.168.1.11/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
EOF

# Control plane node 2
cat > talos/patches/static-ip-cp02.yaml <<EOF
machine:
  network:
    hostname: rpi-cp02
    interfaces:
      - interface: eth0
        addresses:
          - 192.168.1.12/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
EOF

# Worker node 1
cat > talos/patches/static-ip-worker01.yaml <<EOF
machine:
  network:
    hostname: rpi-worker01
    interfaces:
      - interface: eth0
        addresses:
          - 192.168.1.13/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
EOF

# Worker node 2
cat > talos/patches/static-ip-worker02.yaml <<EOF
machine:
  network:
    hostname: rpi-worker02
    interfaces:
      - interface: eth0
        addresses:
          - 192.168.1.14/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
EOF
```

**Note**: If you're already using DHCP reservations for static IPs (recommended), you don't need these patches.

## Step 7: Configure talosctl

Before applying configurations, set up your talosctl client:

```bash
# Set the talosconfig for the current session
export TALOSCONFIG=/Users/rich/Library/CloudStorage/Dropbox/Development/automation/talos/config/talosconfig

# Configure endpoints (all cluster nodes for redundancy)
talosctl config endpoint 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14

# Set default node (primary control plane)
talosctl config node 192.168.1.11
```

**Important**: Add this to your shell profile so it persists across sessions:

```bash
echo 'export TALOSCONFIG=/Users/rich/Library/CloudStorage/Dropbox/Development/automation/talos/config/talosconfig' >> ~/.zshrc
source ~/.zshrc
```

**Note**: Including all nodes as endpoints allows talosctl to automatically failover to available nodes if the default is unreachable.

## Step 8: Apply Configuration to Control Plane Nodes

Now apply configuration to your control plane nodes:

```bash
# Apply to first control plane node (192.168.1.11)
talosctl apply-config --insecure \
  --nodes 192.168.1.11 \
  --file talos/config/controlplane.yaml

# Wait for node to apply config (~30 seconds)
sleep 30

# Verify the node is configured
talosctl version
```

Apply to the second control plane node:

```bash
# Apply to second control plane node (192.168.1.12)
talosctl apply-config --insecure \
  --nodes 192.168.1.12 \
  --file talos/config/controlplane.yaml

# Wait and verify
sleep 30
talosctl version
```

## Step 9: Bootstrap etcd

Bootstrap the Kubernetes cluster on the first control plane node:

```bash
# Bootstrap etcd (ONLY run this ONCE on the first control plane node)
talosctl bootstrap --nodes 192.168.1.11

# Wait ~2 minutes for bootstrap to complete
```

This starts etcd and the Kubernetes control plane components. **Important**: Only run bootstrap once, on one node!

## Step 10: Verify Control Plane

Wait for control plane to be ready (~2-5 minutes):

```bash
# Watch service status
talosctl services

# Wait for kubelet to be running
talosctl service kubelet

# Check etcd members (should show both control plane nodes after they sync)
talosctl etcd members
```

## Step 11: Get Kubernetes Access

Retrieve kubeconfig:

```bash
# Generate kubeconfig (merges into ~/.kube/config by default)
talosctl kubeconfig --force

# Verify access
kubectl get nodes
```

You should see your control plane node(s) in `Ready` state. Talos includes Flannel CNI by default, so nodes are ready immediately.

**Example output:**
```
NAME            STATUS   ROLES           AGE   VERSION
talos-xxx-xxx   Ready    control-plane   78s   v1.34.0
talos-xxx-xxx   Ready    control-plane   82s   v1.34.0
```

**Alternative**: Save to custom location:
```bash
talosctl kubeconfig --force --output kubeconfig
export KUBECONFIG=/Users/rich/Library/CloudStorage/Dropbox/Development/automation/kubeconfig
kubectl get nodes
```

## Step 12: Apply Worker Configurations

Add worker nodes to the cluster:

```bash
# Apply to worker node 1 (192.168.1.13)
talosctl apply-config --insecure \
  --nodes 192.168.1.13 \
  --file talos/config/worker.yaml

# Apply to worker node 2 (192.168.1.14)
talosctl apply-config --insecure \
  --nodes 192.168.1.14 \
  --file talos/config/worker.yaml

# Wait a bit for nodes to join
sleep 30

# Verify all nodes are visible
kubectl get nodes -o wide
```

## Step 13: Verify Cluster

```bash
# Check all nodes (should all be Ready)
kubectl get nodes

# Check system pods (Flannel CNI should be running)
kubectl get pods -n kube-system

# Verify Talos services on each control plane node
talosctl -n 192.168.1.11 services
talosctl -n 192.168.1.12 services

# Check etcd cluster members
talosctl -n 192.168.1.11 etcd members

# Verify versions
talosctl version
```

**Expected results:**
- All nodes show `Ready` status in kubectl
- Key services show `Running` state: `etcd`, `kubelet`, `apid`, `containerd`
- System pods are running: `kube-flannel-*`, `kube-apiserver-*`, `kube-controller-manager-*`, `kube-scheduler-*`, `etcd-*`
- etcd members shows both control plane nodes

## Step 14: Encrypt and Commit Secrets

**IMPORTANT**: Never commit unencrypted secrets!

```bash
# Encrypt cluster secrets
sops --encrypt talos/secrets/secrets.yaml > talos/secrets/secrets.enc.yaml

# Encrypt talosconfig (contains certificates and keys)
sops --encrypt talos/config/talosconfig > talos/config/talosconfig.enc.yaml

# Remove unencrypted files
rm talos/secrets/secrets.yaml
rm talos/config/talosconfig

# Verify encrypted files exist
ls -la talos/secrets/secrets.enc.yaml
ls -la talos/config/talosconfig.enc.yaml

# Add to git and commit
git add -A
git commit -m "Add encrypted Talos cluster configuration

- 4-node cluster: 2 control plane, 2 worker nodes
- Encrypted secrets and talosconfig with SOPS
- All nodes running and healthy"
```

**Note**: The `.sops.yaml` file automatically provides the age key, so you don't need to specify it manually. Keep your `age.key` file secure and backed up - you cannot decrypt these files without it!

## Step 15: Create Helper Scripts

Create convenience scripts:

```bash
cat > scripts/talos-health.sh <<'EOF'
#!/bin/bash
echo "Checking Talos cluster health..."
echo "=== Kubernetes Nodes ==="
kubectl get nodes
echo ""
echo "=== System Pods ==="
kubectl get pods -n kube-system
echo ""
echo "=== Talos Services (Control Plane 1) ==="
talosctl -n 192.168.1.11 services
echo ""
echo "=== etcd Members ==="
talosctl -n 192.168.1.11 etcd members
EOF

cat > scripts/get-kubeconfig.sh <<'EOF'
#!/bin/bash
talosctl kubeconfig --force
echo "Kubeconfig updated at: ~/.kube/config"
EOF

chmod +x scripts/*.sh
```

## Troubleshooting

### Node not reachable
- Check network connectivity: `ping 192.168.1.11`
- Verify SD card flashed correctly
- Check LED patterns on Pi
- Ensure EEPROM is updated
- Check DHCP assigned the correct IP

### Bootstrap fails
- Ensure only one node is bootstrapped
- Check etcd isn't already running: `talosctl service etcd`
- Reset if needed: `talosctl reset --graceful=false --reboot`

### Nodes don't join
- Verify network connectivity between nodes
- Check cluster secrets match
- Verify certificates are valid
- Check logs: `talosctl -n <node-ip> logs kubelet`

### Configuration changes not applying
- Use `--mode=staged` for safe changes: `talosctl apply-config --mode=staged`
- Check events: `talosctl -n <node-ip> events`
- View logs: `talosctl -n <node-ip> dmesg`

## Next Steps

Your Talos Kubernetes cluster is now running! However, nodes will show "NotReady" until a CNI plugin is installed.

Proceed to:
- **[03-core-services.md](./03-core-services.md)** - Install CNI, storage, and other core services

## Backup Reminder

Ensure you've backed up:
- ✅ `age.key` - Encryption key for secrets
- ✅ `talos/secrets/secrets.enc.yaml` - Encrypted cluster secrets
- ✅ `talos/config/talosconfig.enc.yaml` - Encrypted talosconfig
- ✅ Commit all encrypted configs to Git

## Reference

- [Talos Documentation](https://www.talos.dev/latest/)
- [Talos Raspberry Pi Guide](https://www.talos.dev/latest/talos-guides/install/single-board-computers/rpi_generic/)
- [Talos Configuration Reference](https://www.talos.dev/latest/reference/configuration/)
