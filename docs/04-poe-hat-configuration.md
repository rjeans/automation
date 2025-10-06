# PoE HAT Configuration and Fan Control

## Overview

This guide covers configuring Raspberry Pi PoE HAT fan control using a custom Talos image with device tree overlays.

## Prerequisites

- Raspberry Pi 4 with official PoE HAT installed
- Working Talos cluster
- `talosctl` configured with cluster access

## Custom Talos Image Configuration

### Image Factory Schematic

**Current Configuration:**
- **Schematic ID**: `3f2272fedf123e61d98b8732dd415b04c5673a1027859bfa69f90e5a34221a2f`
- **Version**: `v1.11.2`
- **Installer**: `factory.talos.dev/installer/3f2272fedf123e61d98b8732dd415b04c5673a1027859bfa69f90e5a34221a2f:v1.11.2`

**Overlay Configuration:**

The full configuration is stored in `raspberrypi/rpi_poe.yaml`:

```yaml
overlay:
  name: rpi_generic
  image: siderolabs/sbc-raspberrypi
  options:
    configTxt: |
      gpu_mem=128
      kernel=u-boot.bin
      arm_64bit=1
      arm_boost=1
      enable_uart=1
      dtoverlay=disable-bt
      dtoverlay=disable-wifi
      avoid_warnings=2
      dtoverlay=vc4-kms-v3d,noaudio
      dtoverlay=rpi-poe
      dtparam=poe_fan_temp0=65000,poe_fan_temp0_hyst=5000
      dtparam=poe_fan_temp1=70000,poe_fan_temp1_hyst=4999
      dtparam=poe_fan_temp2=75000,poe_fan_temp2_hyst=4999
      dtparam=poe_fan_temp3=80000,poe_fan_temp3_hyst=4999
```

### Fan Temperature Thresholds

The fan operates at 4 speed levels based on CPU temperature:

| Level | Temperature | Hysteresis | Fan Speed |
|-------|-------------|------------|-----------|
| 0     | 65°C        | 5°C        | Low       |
| 1     | 70°C        | ~5°C       | Medium    |
| 2     | 75°C        | ~5°C       | High      |
| 3     | 80°C        | ~5°C       | Maximum   |

**Temperature format**: Millidegrees Celsius (70000 = 70°C)

**Hysteresis**: Temperature drop before fan decreases speed (prevents oscillation)

## Creating Custom Image

### Option 1: Using Talos Image Factory Web UI

1. Go to https://factory.talos.dev
2. Select **Single Board Computer** → **Raspberry Pi Generic**
3. Choose **System Extensions**: `siderolabs/sbc-raspberrypi`
4. In **Customization** section, paste the contents of `raspberrypi/rpi_poe.yaml`
5. Click **Generate**
6. Note the **Schematic ID** provided

**Note**: The Web UI method may produce a different schematic ID than the curl method, but the functionality will be identical.

### Option 2: Using curl (Recommended)

```bash
# Use the configuration file in the repository
cd raspberrypi/
curl -X POST --data-binary @rpi_poe.yaml https://factory.talos.dev/schematics

# Returns the schematic ID, for example:
# {"id":"3f2272fedf123e61d98b8732dd415b04c5673a1027859bfa69f90e5a34221a2f"}
```

The schematic configuration is stored in `raspberrypi/rpi_poe.yaml` for version control.

## Upgrading Existing Cluster

### Rolling Upgrade (No Downtime)

**Important**: Use `--reboot-mode powercycle` for reliable PoE HAT configuration updates.

```bash
# Set talosconfig
export TALOSCONFIG=~/.talos-secrets/automation/talosconfig

# Set schematic and version
SCHEMATIC_ID="3f2272fedf123e61d98b8732dd415b04c5673a1027859bfa69f90e5a34221a2f"
TALOS_VERSION="v1.11.2"

# Upgrade control plane nodes (one at a time)
echo "Upgrading control plane node 1 (192.168.1.11)..."
talosctl upgrade --nodes 192.168.1.11 \
  --reboot-mode powercycle \
  --image factory.talos.dev/installer/${SCHEMATIC_ID}:${TALOS_VERSION}

# Wait for upgrade to complete (~2 minutes)
sleep 120

# Verify node is back online
kubectl get nodes

echo "Upgrading control plane node 2 (192.168.1.12)..."
talosctl upgrade --nodes 192.168.1.12 \
  --reboot-mode powercycle \
  --image factory.talos.dev/installer/${SCHEMATIC_ID}:${TALOS_VERSION}

sleep 120

echo "Upgrading control plane node 3 (192.168.1.13)..."
talosctl upgrade --nodes 192.168.1.13 \
  --reboot-mode powercycle \
  --image factory.talos.dev/installer/${SCHEMATIC_ID}:${TALOS_VERSION}

sleep 120

# Verify control plane is healthy
kubectl get nodes

# Upgrade worker node
echo "Upgrading worker node (192.168.1.14)..."
talosctl upgrade --nodes 192.168.1.14 \
  --reboot-mode powercycle \
  --image factory.talos.dev/installer/${SCHEMATIC_ID}:${TALOS_VERSION}

sleep 90

# Verify all nodes upgraded successfully
echo "=== Upgrade Complete ==="
kubectl get nodes -o wide
talosctl version
```

**Expected timeline:**
- Control plane node 1: ~2 minutes
- Control plane node 2: ~2 minutes
- Control plane node 3: ~2 minutes
- Worker node: ~1.5 minutes
- **Total: ~8-9 minutes**

### Monitoring Upgrade Progress

```bash
# Watch node status during upgrade
watch kubectl get nodes

# Check specific node status
talosctl -n 192.168.1.11 version

# View upgrade logs (on the node being upgraded)
talosctl -n 192.168.1.11 dmesg --follow
```

## Fresh Install with Custom Image

If building a new cluster or re-flashing SD cards:

```bash
# Download custom image
SCHEMATIC_ID=3f2272fedf123e61d98b8732dd415b04c5673a1027859bfa69f90e5a34221a2f
TALOS_VERSION=v1.11.2

cd ~/Downloads
curl -LO https://factory.talos.dev/image/${SCHEMATIC_ID}/${TALOS_VERSION}/metal-arm64.raw.xz

# Decompress
xz -d metal-arm64.raw.xz

# Flash SD card
diskutil list  # find your SD card
diskutil unmountDisk /dev/diskN
sudo dd if=metal-arm64.raw of=/dev/rdiskN bs=4M conv=fsync
diskutil eject /dev/diskN
```

Then follow [02-cluster-rebuild.md](./02-cluster-rebuild.md) for cluster setup.

## Verifying PoE Configuration

### Check Device Tree Overlay

```bash
# Verify PoE overlay is loaded
talosctl -n 192.168.1.11 read /sys/firmware/devicetree/base/hat/product

# Should return: "PoE+ HAT" or similar
```

### Check Fan Status

```bash
# View cooling device information
talosctl -n 192.168.1.11 read /sys/class/thermal/cooling_device0/type
talosctl -n 192.168.1.11 read /sys/class/thermal/cooling_device0/cur_state

# View current CPU temperature
talosctl -n 192.168.1.11 read /sys/class/thermal/thermal_zone0/temp

# Result is in millidegrees (e.g., 65000 = 65°C)
```

### Monitor Fan Behavior

```bash
# Create a simple monitoring script
cat > scripts/monitor-poe-fan.sh <<'EOF'
#!/bin/bash
echo "Monitoring PoE fan on all nodes..."
echo "Temperature threshold: 65°C (fan starts)"
echo ""

for node in 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14; do
    echo "=== Node: $node ==="
    temp=$(talosctl -n $node read /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    if [ -n "$temp" ]; then
        temp_c=$((temp / 1000))
        echo "Temperature: ${temp_c}°C"
    fi

    fan_state=$(talosctl -n $node read /sys/class/thermal/cooling_device0/cur_state 2>/dev/null)
    if [ -n "$fan_state" ]; then
        echo "Fan state: $fan_state (0=off, 1-4=speed levels)"
    fi
    echo ""
done
EOF

chmod +x scripts/monitor-poe-fan.sh
./scripts/monitor-poe-fan.sh
```

## Customizing Fan Thresholds

To adjust fan behavior, create a new schematic with different temperature values:

### More Aggressive Cooling (Earlier activation)
```yaml
dtparam=poe_fan_temp0=60000,poe_fan_temp0_hyst=1000  # Start at 60°C
dtparam=poe_fan_temp1=65000,poe_fan_temp1_hyst=3000  # Medium at 65°C
dtparam=poe_fan_temp2=70000,poe_fan_temp2_hyst=3000  # High at 70°C
dtparam=poe_fan_temp3=75000,poe_fan_temp3_hyst=2000  # Max at 75°C
```

### Quieter Operation (Later activation)
```yaml
dtparam=poe_fan_temp0=75000,poe_fan_temp0_hyst=2000  # Start at 75°C
dtparam=poe_fan_temp1=78000,poe_fan_temp1_hyst=3000  # Medium at 78°C
dtparam=poe_fan_temp2=82000,poe_fan_temp2_hyst=3000  # High at 82°C
dtparam=poe_fan_temp3=85000,poe_fan_temp3_hyst=2000  # Max at 85°C
```

**Note**: After changing thresholds, generate a new schematic and upgrade the cluster.

## Troubleshooting

### Fan Not Working

**Check PoE HAT is detected:**
```bash
talosctl -n 192.168.1.11 read /sys/firmware/devicetree/base/hat/product
```

**Verify overlay is loaded:**
```bash
talosctl -n 192.168.1.11 dmesg | grep -i poe
```

**Expected output:**
```
rpi-poe-fan: probe of fan succeed
```

### Fan Always On or Always Off

**Check current temperature:**
```bash
talosctl -n 192.168.1.11 read /sys/class/thermal/thermal_zone0/temp
```

**Verify thresholds are applied:**
```bash
talosctl -n 192.168.1.11 read /boot/config.txt | grep poe_fan
```

### Upgrade Failed

**Check node status:**
```bash
kubectl get nodes
talosctl -n 192.168.1.11 version
```

**View upgrade errors:**
```bash
talosctl -n 192.168.1.11 logs controller-runtime
talosctl -n 192.168.1.11 dmesg | tail -50
```

**Rollback if needed:**
```bash
# Reboot to previous version (if upgrade hasn't finished)
talosctl -n 192.168.1.11 reboot
```

## Version Updates

When upgrading Talos versions:

1. Regenerate schematic with new version:
   ```bash
   cd raspberrypi/
   curl -X POST --data-binary @rpi_poe.yaml https://factory.talos.dev/schematics
   # Note the new schematic ID
   ```

2. Update installer image in upgrade commands:
   ```bash
   talosctl upgrade --nodes <node> \
     --reboot-mode powercycle \
     --image factory.talos.dev/installer/<new-schematic-id>:v1.12.0
   ```

## Reference

- **Current Schematic ID**: `3f2272fedf123e61d98b8732dd415b04c5673a1027859bfa69f90e5a34221a2f`
- **Current Version**: `v1.11.2`
- **Configuration File**: `raspberrypi/rpi_poe.yaml`
- **Talos Image Factory**: https://factory.talos.dev
- **Raspberry Pi PoE HAT Documentation**: https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#poe-hat
- **Talos SBC Extensions**: https://github.com/siderolabs/extensions

## Backup Current Configuration

```bash
# Document your current schematic
cat > ~/.talos-secrets/automation/SCHEMATIC.md <<EOF
# Talos Custom Image Configuration

**Schematic ID**: 3f2272fedf123e61d98b8732dd415b04c5673a1027859bfa69f90e5a34221a2f
**Version**: v1.11.2
**Created**: $(date)

**Purpose**: PoE HAT fan control with temperature-based speed regulation

**Installer Image**:
factory.talos.dev/installer/3f2272fedf123e61d98b8732dd415b04c5673a1027859bfa69f90e5a34221a2f:v1.11.2

**Configuration**: See raspberrypi/rpi_poe.yaml and docs/04-poe-hat-configuration.md
EOF

# Backup to external drive with secrets
cp ~/.talos-secrets/automation/SCHEMATIC.md /Volumes/YourBackupDrive/
```

---

**Last Updated**: 2025-10-06
**Talos Version**: v1.11.2
**Tested On**: Raspberry Pi 4 with Official PoE HAT
