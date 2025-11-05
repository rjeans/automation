#!/bin/bash
# Talos Node Recovery Script
# Use this to recover a control plane node that won't boot due to bad config

NODE_IP="${1:-192.168.1.11}"
CONFIG_FILE="${2:-$HOME/.talos-secrets/pi-cluster/controlplane.yaml}"

echo "========================================="
echo "Talos Node Recovery Script"
echo "========================================="
echo "Node IP: $NODE_IP"
echo "Config: $CONFIG_FILE"
echo ""

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

echo "Step 1: Checking if node is reachable..."
if ping -c 1 -W 2 $NODE_IP &>/dev/null; then
    echo "✓ Node is pingable"

    echo ""
    echo "Step 2: Attempting to apply config in insecure mode..."
    echo "This will work if the node is in maintenance/reset mode."

    talosctl apply-config --insecure --nodes $NODE_IP --file "$CONFIG_FILE"

    if [ $? -eq 0 ]; then
        echo "✓ Config applied successfully!"
        echo ""
        echo "Step 3: Waiting for node to restart (30 seconds)..."
        sleep 30

        echo ""
        echo "Step 4: Checking node health..."
        talosctl -n $NODE_IP health --wait-timeout 2m

        echo ""
        echo "✓ Recovery complete!"
    else
        echo "✗ Failed to apply config in insecure mode"
        echo ""
        echo "The node needs to be in maintenance mode. Please:"
        echo "1. Power off the node"
        echo "2. Remove the SD card"
        echo "3. Run: ./reset-sd-card.sh <mount-point>"
        echo "4. Reinsert SD card and power on"
        echo "5. Run this script again"
    fi
else
    echo "✗ Node is not reachable"
    echo ""
    echo "Please ensure:"
    echo "1. Node is powered on"
    echo "2. Node is on the network (check physical connection)"
    echo "3. If node won't boot, remove SD card and run: ./reset-sd-card.sh"
fi
