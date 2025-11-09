#!/bin/bash
# Regenerate Node Configs WITHOUT Regenerating Certificates
# This patches existing node configs with updated settings (like storage)
# while preserving all PKI/certificates

set -e

# Get the script directory to reference patch files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR="$HOME/.talos-secrets/pi-cluster"

# Source shared library for config generation
source "$SCRIPT_DIR/lib/config-generator.sh"

# Node definitions
NODE11_IP="192.168.1.11"
NODE12_IP="192.168.1.12"
NODE13_IP="192.168.1.13"
NODE14_IP="192.168.1.14"
GATEWAY="192.168.1.1"
NETMASK="24"
VIP="192.168.1.10"

echo "========================================="
echo "Regenerate Node Configs (Keep Certs)"
echo "========================================="
echo ""
echo "This will:"
echo "  ✓ Update node configs with new patches (storage, etc.)"
echo "  ✓ Preserve all existing certificates and secrets"
echo "  ✓ Keep the same cluster identity"
echo ""
echo "Node configs to regenerate:"
echo "  - node11.yaml ($NODE11_IP with 1TB Longhorn storage)"
echo "  - node12.yaml ($NODE12_IP with 1TB Longhorn storage)"
echo "  - node13.yaml ($NODE13_IP with 256GB Longhorn storage)"
echo "  - node14.yaml ($NODE14_IP - no storage)"
echo ""

# Verify existing configs exist
if [ ! -f "$CONFIG_DIR/controlplane.yaml" ] || [ ! -f "$CONFIG_DIR/worker.yaml" ]; then
    echo "ERROR: Base configs not found in $CONFIG_DIR"
    echo "Expected files:"
    echo "  - $CONFIG_DIR/controlplane.yaml"
    echo "  - $CONFIG_DIR/worker.yaml"
    echo ""
    echo "Run ./rebuild-cluster-with-static-ips.sh first to create initial configs."
    exit 1
fi

# Verify patch files exist
if [ ! -f "$SCRIPT_DIR/patches/node-11-storage.yaml" ]; then
    echo "ERROR: Storage patch files not found in $SCRIPT_DIR/patches/"
    exit 1
fi

echo "Using existing base configs from: $CONFIG_DIR"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "========================================="
echo "Regenerating Node Configs"
echo "========================================="
echo ""

# Backup existing node configs
BACKUP_DIR="$CONFIG_DIR/backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for node in node11 node12 node13 node14; do
    if [ -f "$CONFIG_DIR/${node}.yaml" ]; then
        cp "$CONFIG_DIR/${node}.yaml" "$BACKUP_DIR/${node}.yaml"
        echo "Backed up: ${node}.yaml"
    fi
done
echo "✓ Backups saved to: $BACKUP_DIR"
echo ""

# Generate control plane configs using shared library
generate_controlplane_config "1" "$NODE11_IP" "$GATEWAY" "$NETMASK" "$VIP" \
    "$CONFIG_DIR/controlplane.yaml" "$CONFIG_DIR/node11.yaml" "$SCRIPT_DIR"

if [ $? -ne 0 ]; then
    echo "✗ Failed to create node11.yaml"
    exit 1
fi

generate_controlplane_config "2" "$NODE12_IP" "$GATEWAY" "$NETMASK" "$VIP" \
    "$CONFIG_DIR/controlplane.yaml" "$CONFIG_DIR/node12.yaml" "$SCRIPT_DIR"

if [ $? -ne 0 ]; then
    echo "✗ Failed to create node12.yaml"
    exit 1
fi

generate_controlplane_config "3" "$NODE13_IP" "$GATEWAY" "$NETMASK" "$VIP" \
    "$CONFIG_DIR/controlplane.yaml" "$CONFIG_DIR/node13.yaml" "$SCRIPT_DIR"

if [ $? -ne 0 ]; then
    echo "✗ Failed to create node13.yaml"
    exit 1
fi

# Generate worker config using shared library
generate_worker_config "1" "$NODE14_IP" "$GATEWAY" "$NETMASK" \
    "$CONFIG_DIR/worker.yaml" "$CONFIG_DIR/node14.yaml"

if [ $? -ne 0 ]; then
    echo "✗ Failed to create node14.yaml"
    exit 1
fi

echo ""
echo "✓ Node Config Regeneration Complete!"
echo ""
echo "========================================="
echo "Updated Configuration Files"
echo "========================================="
echo ""
echo "Node-specific configs (with stable disk IDs):"
echo "  $CONFIG_DIR/node11.yaml - Control Plane 1 (1TB Longhorn storage)"
echo "  $CONFIG_DIR/node12.yaml - Control Plane 2 (1TB Longhorn storage)"
echo "  $CONFIG_DIR/node13.yaml - Control Plane 3 (256GB Longhorn storage)"
echo "  $CONFIG_DIR/node14.yaml - Worker (no storage)"
echo ""
echo "Preserved (unchanged):"
echo "  $CONFIG_DIR/controlplane.yaml - Base control plane config with certs"
echo "  $CONFIG_DIR/worker.yaml - Base worker config with certs"
echo "  $CONFIG_DIR/talosconfig - Client config"
echo "  $CONFIG_DIR/secrets.yaml - Cluster secrets & PKI"
echo ""
echo "Backups:"
echo "  $BACKUP_DIR/"
echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "Apply updated configs to your nodes:"
echo ""
echo "  # Option 1: Apply to all nodes (safest - one at a time)"
echo "  talosctl apply-config -n $NODE11_IP -e $NODE11_IP --file $CONFIG_DIR/node11.yaml"
echo "  # Wait for node to stabilize, then:"
echo "  talosctl apply-config -n $NODE12_IP -e $NODE12_IP --file $CONFIG_DIR/node12.yaml"
echo "  talosctl apply-config -n $NODE13_IP -e $NODE13_IP --file $CONFIG_DIR/node13.yaml"
echo "  talosctl apply-config -n $NODE14_IP -e $NODE14_IP --file $CONFIG_DIR/node14.yaml"
echo ""
echo "  # Option 2: Use the apply script"
echo "  ./apply-node-configs.sh"
echo ""
echo "Note: Nodes will reboot when storage configs are applied."
echo "The disks will be wiped and formatted for Longhorn."
echo ""
