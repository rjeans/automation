#!/bin/bash
# Apply Node-Specific Configs with Static IPs
# Each node gets its own configuration file with static IP assignment

set -e

CONFIG_DIR="$HOME/.talos-secrets/pi-cluster"

echo "========================================="
echo "Apply Static IP Configurations"
echo "========================================="
echo ""
echo "This applies node-specific configs with:"
echo "  - Static IP addresses"
echo "  - VIP configuration (control plane only)"
echo "  - Unique hostnames"
echo ""

# Verify all node configs exist
for node in node11 node12 node13 node14; do
    if [ ! -f "$CONFIG_DIR/${node}.yaml" ]; then
        echo "ERROR: $CONFIG_DIR/${node}.yaml not found"
        echo "Run ./rebuild-cluster-with-static-ips.sh first"
        exit 1
    fi
done

# Confirm prerequisites
echo "Prerequisites:"
echo "1. All 4 nodes powered on with freshly flashed SD cards"
echo "2. Nodes in maintenance mode (may be on random DHCP IPs)"
echo "3. You know the current DHCP IPs of each node"
echo ""
echo "Note: After applying configs, nodes will use static IPs:"
echo "  - 192.168.1.11 (talos-cp1)"
echo "  - 192.168.1.12 (talos-cp2)"
echo "  - 192.168.1.13 (talos-cp3)"
echo "  - 192.168.1.14 (talos-worker1)"
echo ""
read -p "Are prerequisites met? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Exiting."
    exit 1
fi

echo ""
echo "========================================="
echo "Detect Nodes via DHCP"
echo "========================================="
echo ""
echo "We need to find the current DHCP IP of each node."
echo "Option 1: Check your router's DHCP lease table"
echo "Option 2: Use nmap to scan for Talos nodes: nmap -p 50000 192.168.1.0/24"
echo "Option 3: Enter IPs manually below"
echo ""

read -p "Enter current IP for node 11 (or press Enter to use 192.168.1.11 if already correct): " current_node11
read -p "Enter current IP for node 12 (or press Enter to use 192.168.1.12 if already correct): " current_node12
read -p "Enter current IP for node 13 (or press Enter to use 192.168.1.13 if already correct): " current_node13
read -p "Enter current IP for node 14 (or press Enter to use 192.168.1.14 if already correct): " current_node14

# Use defaults if not provided
current_node11="${current_node11:-192.168.1.11}"
current_node12="${current_node12:-192.168.1.12}"
current_node13="${current_node13:-192.168.1.13}"
current_node14="${current_node14:-192.168.1.14}"

echo ""
echo "========================================="
echo "Applying Configurations"
echo "========================================="
echo ""

# Apply to node 11
echo "Applying config to node 11 ($current_node11 -> 192.168.1.11)..."
talosctl apply-config --insecure \
    --nodes "$current_node11" \
    --file "$CONFIG_DIR/node11.yaml"

if [ $? -eq 0 ]; then
    echo "✓ Config applied to node 11"
else
    echo "✗ Failed to apply config to node 11"
    exit 1
fi

echo ""
echo "Waiting 30 seconds for node to reinitialize..."
sleep 30

# Apply to node 12
echo ""
echo "Applying config to node 12 ($current_node12 -> 192.168.1.12)..."
talosctl apply-config --insecure \
    --nodes "$current_node12" \
    --file "$CONFIG_DIR/node12.yaml"

if [ $? -eq 0 ]; then
    echo "✓ Config applied to node 12"
else
    echo "✗ Failed to apply config to node 12"
fi

echo ""
echo "Waiting 30 seconds for node to reinitialize..."
sleep 30

# Apply to node 13
echo ""
echo "Applying config to node 13 ($current_node13 -> 192.168.1.13)..."
talosctl apply-config --insecure \
    --nodes "$current_node13" \
    --file "$CONFIG_DIR/node13.yaml"

if [ $? -eq 0 ]; then
    echo "✓ Config applied to node 13"
else
    echo "✗ Failed to apply config to node 13"
fi

echo ""
echo "Waiting 30 seconds for node to reinitialize..."
sleep 30

# Apply to node 14 (worker)
echo ""
echo "Applying config to node 14 ($current_node14 -> 192.168.1.14)..."
talosctl apply-config --insecure \
    --nodes "$current_node14" \
    --file "$CONFIG_DIR/node14.yaml"

if [ $? -eq 0 ]; then
    echo "✓ Config applied to node 14"
else
    echo "✗ Failed to apply config to node 14"
fi

echo ""
echo "Waiting 60 seconds for all nodes to initialize..."
sleep 60

echo ""
echo "✓ Configuration Complete!"
echo ""
echo "========================================="
echo "Verify Nodes"
echo "========================================="
echo ""
echo "Testing node connectivity on static IPs..."
echo ""

for node in 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14; do
    echo -n "Node $node: "
    if ping -c 2 -W 2 $node > /dev/null 2>&1; then
        echo "✓ Reachable"
    else
        echo "✗ Not reachable (may still be booting)"
    fi
done

echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. Wait 2-3 minutes for all nodes to fully boot"
echo ""
echo "2. Configure talosctl to use VIP:"
echo "   export TALOSCONFIG=$CONFIG_DIR/talosconfig"
echo "   talosctl config endpoint 192.168.1.10"
echo "   talosctl config node 192.168.1.10"
echo ""
echo "3. Bootstrap cluster:"
echo "   talosctl bootstrap --nodes 192.168.1.10"
echo ""
echo "4. Get kubeconfig (wait 2-3 min after bootstrap):"
echo "   talosctl kubeconfig --nodes 192.168.1.10 --force"
echo ""
echo "5. Verify cluster:"
echo "   kubectl get nodes"
echo ""
