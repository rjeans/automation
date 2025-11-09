#!/bin/bash
# Apply Updated Node Configs to Running Cluster
# Applies configs one node at a time with health checks

set -e

CONFIG_DIR="$HOME/.talos-secrets/pi-cluster"

NODE11_IP="192.168.1.11"
NODE12_IP="192.168.1.12"
NODE13_IP="192.168.1.13"
NODE14_IP="192.168.1.14"

echo "========================================="
echo "Apply Updated Node Configs"
echo "========================================="
echo ""
echo "This will apply updated configs to each node:"
echo "  - Node 11 ($NODE11_IP) - Control Plane 1 + Storage"
echo "  - Node 12 ($NODE12_IP) - Control Plane 2 + Storage"
echo "  - Node 13 ($NODE13_IP) - Control Plane 3 + Storage"
echo "  - Node 14 ($NODE14_IP) - Worker"
echo ""
echo "WARNING:"
echo "  ⚠ Nodes will REBOOT when storage configs are applied"
echo "  ⚠ Storage disks will be WIPED and reformatted"
echo "  ⚠ Each node will be updated one at a time for safety"
echo ""

# Verify configs exist
for node in node11 node12 node13 node14; do
    if [ ! -f "$CONFIG_DIR/${node}.yaml" ]; then
        echo "ERROR: $CONFIG_DIR/${node}.yaml not found"
        echo "Run ./regenerate-node-configs.sh first"
        exit 1
    fi
done

read -p "Continue with applying configs? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "========================================="
echo "Applying Configurations"
echo "========================================="
echo ""

# Apply to node 11
echo "Applying config to node 11 ($NODE11_IP)..."
echo "  - Storage: 1TB JMicron will be wiped and mounted at /var/mnt/longhorn"
echo ""
talosctl apply-config -n $NODE11_IP -e $NODE11_IP \
    --file "$CONFIG_DIR/node11.yaml"

if [ $? -eq 0 ]; then
    echo "✓ Config applied to node 11"
    echo ""
    echo "Waiting 60 seconds for node to reinitialize..."
    sleep 60

    echo "Checking node 11 health..."
    if talosctl -n $NODE11_IP -e $NODE11_IP version > /dev/null 2>&1; then
        echo "✓ Node 11 is responding"
    else
        echo "⚠ Node 11 not responding yet (may still be rebooting)"
    fi
else
    echo "✗ Failed to apply config to node 11"
    echo "Stopping. Fix node 11 before continuing."
    exit 1
fi

echo ""
echo "---"
echo ""

# Apply to node 12
echo "Applying config to node 12 ($NODE12_IP)..."
echo "  - Storage: 1TB WDC will be wiped and mounted at /var/mnt/longhorn"
echo ""
talosctl apply-config -n $NODE12_IP -e $NODE12_IP \
    --file "$CONFIG_DIR/node12.yaml"

if [ $? -eq 0 ]; then
    echo "✓ Config applied to node 12"
    echo ""
    echo "Waiting 60 seconds for node to reinitialize..."
    sleep 60

    echo "Checking node 12 health..."
    if talosctl -n $NODE12_IP -e $NODE12_IP version > /dev/null 2>&1; then
        echo "✓ Node 12 is responding"
    else
        echo "⚠ Node 12 not responding yet (may still be rebooting)"
    fi
else
    echo "✗ Failed to apply config to node 12"
    echo "Stopping. Fix node 12 before continuing."
    exit 1
fi

echo ""
echo "---"
echo ""

# Apply to node 13
echo "Applying config to node 13 ($NODE13_IP)..."
echo "  - Storage: 256GB JMicron will be wiped and mounted at /var/mnt/longhorn"
echo ""
talosctl apply-config -n $NODE13_IP -e $NODE13_IP \
    --file "$CONFIG_DIR/node13.yaml"

if [ $? -eq 0 ]; then
    echo "✓ Config applied to node 13"
    echo ""
    echo "Waiting 60 seconds for node to reinitialize..."
    sleep 60

    echo "Checking node 13 health..."
    if talosctl -n $NODE13_IP -e $NODE13_IP version > /dev/null 2>&1; then
        echo "✓ Node 13 is responding"
    else
        echo "⚠ Node 13 not responding yet (may still be rebooting)"
    fi
else
    echo "✗ Failed to apply config to node 13"
    echo "Stopping. Fix node 13 before continuing."
    exit 1
fi

echo ""
echo "---"
echo ""

# Apply to node 14 (worker - no storage)
echo "Applying config to node 14 ($NODE14_IP - worker, no storage changes)..."
echo ""
talosctl apply-config -n $NODE14_IP -e $NODE14_IP \
    --file "$CONFIG_DIR/node14.yaml"

if [ $? -eq 0 ]; then
    echo "✓ Config applied to node 14"
    echo ""
    echo "Waiting 30 seconds for node to apply config..."
    sleep 30

    echo "Checking node 14 health..."
    if talosctl -n $NODE14_IP -e $NODE14_IP version > /dev/null 2>&1; then
        echo "✓ Node 14 is responding"
    else
        echo "⚠ Node 14 not responding yet (may still be applying config)"
    fi
else
    echo "✗ Failed to apply config to node 14"
fi

echo ""
echo "========================================="
echo "Configuration Application Complete"
echo "========================================="
echo ""
echo "Wait 2-3 minutes for all nodes to fully stabilize, then verify:"
echo ""
echo "  # Check all nodes are up"
echo "  kubectl get nodes"
echo ""
echo "  # Verify storage mounts on each control plane node"
echo "  talosctl -n $NODE11_IP -e $NODE11_IP get mounts | grep longhorn"
echo "  talosctl -n $NODE12_IP -e $NODE12_IP get mounts | grep longhorn"
echo "  talosctl -n $NODE13_IP -e $NODE13_IP get mounts | grep longhorn"
echo ""
echo "Next: Deploy Longhorn via Flux"
echo ""
