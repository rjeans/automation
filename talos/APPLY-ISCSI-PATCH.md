# Adding iSCSI Tools Extension to Running Cluster

## Overview

Longhorn requires iSCSI tools to be installed on all nodes. This guide shows how to add the iSCSI tools extension to your running Talos cluster using the **factory schematic approach** (Talos v1.11+).

## What iSCSI Tools Provide

The `siderolabs/iscsi-tools` extension adds:
- `iscsiadm` - iSCSI initiator administration tool
- `open-iscsi` - iSCSI client for Linux

This is required for Longhorn to provide block storage to pods.

## Prerequisites

- Cluster is running and healthy
- Longhorn is deployed but pods are crashing with iSCSI errors
- Internet connectivity on all nodes (to download new installer image)

## Modern Approach: Factory Schematic (Recommended)

As of Talos v1.11+, system extensions should be included in the factory schematic rather than added as runtime patches.

### Step 1: Create New Schematic with iSCSI Tools

The iSCSI tools extension is already configured in [`raspberrypi/rpi_poe.yaml`](../raspberrypi/rpi_poe.yaml):

```yaml
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/vc4
      - siderolabs/iscsi-tools  # Required for Longhorn
```

Create the new schematic:

```bash
cd talos
./create-schematic.sh v1.11.3
```

This will:
- Submit the overlay configuration to Talos Image Factory
- Generate a new schematic ID with iSCSI tools included
- Save the schematic ID to `talos/.schematic-id`

### Step 2: Upgrade Nodes to New Schematic

Upgrade each control plane node **one at a time** to the new installer image:

#### Upgrade Node 11:
```bash
talosctl upgrade -n 192.168.1.11 -e 192.168.1.11 \
  --image factory.talos.dev/installer/$(cat talos/.schematic-id):v1.11.3
```

**What happens:**
1. Node downloads the new installer image with iSCSI tools (~500MB)
2. Node applies the upgrade and reboots
3. Takes 2-3 minutes to come back online

**Verify node is back:**
```bash
# Check node is responding
talosctl -n 192.168.1.11 -e 192.168.1.11 version

# Check node shows Ready in Kubernetes
kubectl get nodes

# Verify iSCSI extension is loaded
talosctl -n 192.168.1.11 -e 192.168.1.11 get extensions
```

#### Upgrade Node 12:
```bash
talosctl upgrade -n 192.168.1.12 -e 192.168.1.12 \
  --image factory.talos.dev/installer/$(cat talos/.schematic-id):v1.11.3
```

Wait 2-3 minutes, then verify with the commands above.

#### Upgrade Node 13:
```bash
talosctl upgrade -n 192.168.1.13 -e 192.168.1.13 \
  --image factory.talos.dev/installer/$(cat talos/.schematic-id):v1.11.3
```

Wait 2-3 minutes, then verify.

#### Optional: Upgrade Worker Node 14:
```bash
talosctl upgrade -n 192.168.1.14 -e 192.168.1.14 \
  --image factory.talos.dev/installer/$(cat talos/.schematic-id):v1.11.3
```

### Step 3: Verify iSCSI Tools are Installed

Check that the iSCSI extension is loaded on each node:

```bash
# Check extensions on all control planes
for node in 192.168.1.11 192.168.1.12 192.168.1.13; do
  echo "=== Node $node ==="
  talosctl -n $node -e $node get extensions | grep iscsi
done
```

You should see output like:
```
NAME                              VERSION   AUTHOR         DESCRIPTION
ghcr.io/siderolabs/iscsi-tools   v0.1.6    Sidero Labs    iSCSI tools for Talos Linux
```

### Step 4: Restart Longhorn Pods

After all nodes have the iSCSI extension, restart the Longhorn manager pods:

```bash
kubectl delete pods -n longhorn-system -l app=longhorn-manager
```

Wait for them to restart:

```bash
kubectl get pods -n longhorn-system -w
```

All pods should now enter `Running` state without iSCSI errors.

### Step 5: Verify Longhorn is Working

```bash
# Check HelmRelease status
flux get helmreleases -n longhorn-system

# Check all pods are running
kubectl get pods -n longhorn-system

# Check storage classes are available
kubectl get storageclass
```

You should see:
- All Longhorn pods in `Running` state
- `longhorn-ha (default)` storage class available
- `longhorn-standard` storage class available

## Alternative: Reflash SD Cards (For New Deployments)

If you prefer to reflash SD cards with the new image:

```bash
# Download the raw disk image
cd ~/Downloads
wget https://factory.talos.dev/image/$(cat ~/path/to/pi-cluster/talos/.schematic-id)/v1.11.3/metal-arm64.raw.xz
xz -d metal-arm64.raw.xz

# Flash to SD cards
diskutil list
diskutil unmountDisk /dev/diskN
sudo dd if=metal-arm64.raw of=/dev/rdiskN bs=4M conv=fsync
diskutil eject /dev/diskN
```

Then boot the nodes with the new SD cards.

## Troubleshooting

### Pods still crashing after upgrade

**Check if extension is loaded:**
```bash
talosctl -n 192.168.1.11 -e 192.168.1.11 get extensions
```

**Check Longhorn manager logs:**
```bash
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50
```

Look for errors mentioning `iscsiadm` or `open-iscsi`.

### Upgrade failing with "image not found"

Verify the schematic ID exists:
```bash
cat talos/.schematic-id
```

Test the installer image URL:
```bash
curl -I https://factory.talos.dev/installer/$(cat talos/.schematic-id):v1.11.3
```

### Node stuck during upgrade

Check node status:
```bash
talosctl -n 192.168.1.11 -e 192.168.1.11 dmesg | tail -50
```

Force reboot if necessary:
```bash
talosctl -n 192.168.1.11 -e 192.168.1.11 reboot
```

### Extension download failing

Verify internet connectivity from node:
```bash
talosctl -n 192.168.1.11 -e 192.168.1.11 get addresses
```

Check DNS resolution:
```bash
talosctl -n 192.168.1.11 -e 192.168.1.11 read /etc/resolv.conf
```

## What's Next

Once Longhorn is running:
1. Test creating a PVC with `longhorn-ha` storage class
2. Deploy workloads that need persistent storage (Prometheus, databases, etc.)
3. Monitor storage usage via Longhorn UI (can be exposed via Traefik)

## Storage Classes Available

After Longhorn is running, you'll have:

- **`longhorn-ha`** (default)
  - 3 replicas across all control planes
  - ~250GB total usable capacity
  - Use for: Critical data (Prometheus, databases)

- **`longhorn-standard`**
  - 2 replicas
  - ~1TB total usable capacity
  - Use for: Less critical workloads, development

## Why Factory Schematic vs Runtime Patches?

**Deprecated Approach (Talos v1.10 and earlier):**
- Used `machine.install.extensions` in machine config patches
- Generated deprecation warnings in Talos v1.11+
- Extensions applied at runtime, could cause issues

**Modern Approach (Talos v1.11+):**
- Extensions baked into the installer image via factory schematic
- Cleaner, more reliable
- No deprecation warnings
- Extensions guaranteed to be present on boot
