#!/bin/bash
# Talos Cluster Rebuild with VIP and Static IPs
# Generates separate configs for each node with static IP assignments

set -e

CLUSTER_NAME="talos-k8s-cluster"
VIP="192.168.1.10"
VIP_ENDPOINT="https://${VIP}:6443"
K8S_VERSION="1.31.2"

# Node definitions
NODE11_IP="192.168.1.11"
NODE12_IP="192.168.1.12"
NODE13_IP="192.168.1.13"
NODE14_IP="192.168.1.14"
GATEWAY="192.168.1.1"
NETMASK="24"

BACKUP_CONFIG_DIR="$HOME/.talos-secrets/pi-cluster-backup-$(date +%Y%m%d_%H%M%S)"
CONFIG_DIR="$HOME/.talos-secrets/pi-cluster"

echo "========================================="
echo "Talos Cluster with VIP and Static IPs"
echo "========================================="
echo "Cluster: $CLUSTER_NAME"
echo "VIP: $VIP"
echo "Endpoint: $VIP_ENDPOINT"
echo "Kubernetes: $K8S_VERSION"
echo ""
echo "Node IPs:"
echo "  Control Plane 1: $NODE11_IP (with storage)"
echo "  Control Plane 2: $NODE12_IP"
echo "  Control Plane 3: $NODE13_IP"
echo "  Worker:          $NODE14_IP"
echo "  Gateway:         $GATEWAY"
echo "  Netmask:         /$NETMASK"
echo ""

# Phase 1: Backup
echo "========================================="
echo "Phase 1: Backup Old Configuration"
echo "========================================="

if [ -d "$CONFIG_DIR" ] && [ "$(ls -A $CONFIG_DIR 2>/dev/null)" ]; then
    echo "Backing up existing configuration..."
    mkdir -p "$BACKUP_CONFIG_DIR"
    cp -r "$CONFIG_DIR/"* "$BACKUP_CONFIG_DIR/" 2>/dev/null || true
    echo "✓ Backup saved to: $BACKUP_CONFIG_DIR"
else
    echo "No existing configuration to backup (this is normal for fresh install)"
fi

if [ -f "$HOME/.kube/config" ]; then
    echo "Backing up kubeconfig..."
    cp "$HOME/.kube/config" "$HOME/.kube/config.old"
    echo "✓ Kubeconfig backed up"
else
    echo "No kubeconfig to backup (this is normal for fresh install)"
fi

echo ""

# Phase 2: Generate Base Configs
echo "========================================="
echo "Phase 2: Generate Base Configs with VIP"
echo "========================================="

rm -rf "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

echo "Generating Talos configuration with VIP endpoint..."
talosctl gen config "$CLUSTER_NAME" "$VIP_ENDPOINT" \
    --output-dir "$CONFIG_DIR" \
    --kubernetes-version "$K8S_VERSION"

if [ $? -eq 0 ]; then
    echo "✓ Generated base configs in: $CONFIG_DIR"
else
    echo "✗ Failed to generate configs"
    exit 1
fi

echo ""

# Phase 3: Create Node-Specific Configs
echo "========================================="
echo "Phase 3: Create Node-Specific Configs"
echo "========================================="
echo ""

# Create static IP + VIP patch for node 11
cat > /tmp/node11-patch.yaml <<EOF
machine:
  network:
    hostname: talos-cp1
    interfaces:
      - interface: end0
        addresses:
          - ${NODE11_IP}/${NETMASK}
        routes:
          - network: 0.0.0.0/0
            gateway: ${GATEWAY}
        vip:
          ip: ${VIP}
  kubelet:
    extraMounts:
      - destination: /var/lib/rancher/local-path-provisioner
        type: bind
        source: /var/lib/rancher/local-path-provisioner
        options:
          - bind
          - rshared
          - rw
  disks:
    - device: /dev/sdb
      partitions:
        - size: 0
          mountpoint: /var/mnt/storage
EOF

echo "Creating config for node 11 (${NODE11_IP} with storage)..."
talosctl machineconfig patch \
    "$CONFIG_DIR/controlplane.yaml" \
    --patch @/tmp/node11-patch.yaml \
    --output "$CONFIG_DIR/node11.yaml"

if [ $? -eq 0 ]; then
    echo "✓ Created: $CONFIG_DIR/node11.yaml"
else
    echo "✗ Failed to create node 11 config"
    exit 1
fi

# Create static IP + VIP patch for node 12
cat > /tmp/node12-patch.yaml <<EOF
machine:
  network:
    hostname: talos-cp2
    interfaces:
      - interface: end0
        addresses:
          - ${NODE12_IP}/${NETMASK}
        routes:
          - network: 0.0.0.0/0
            gateway: ${GATEWAY}
        vip:
          ip: ${VIP}
  kubelet:
    extraMounts:
      - destination: /var/lib/rancher/local-path-provisioner
        type: bind
        source: /var/lib/rancher/local-path-provisioner
        options:
          - bind
          - rshared
          - rw
EOF

echo "Creating config for node 12 (${NODE12_IP})..."
talosctl machineconfig patch \
    "$CONFIG_DIR/controlplane.yaml" \
    --patch @/tmp/node12-patch.yaml \
    --output "$CONFIG_DIR/node12.yaml"

if [ $? -eq 0 ]; then
    echo "✓ Created: $CONFIG_DIR/node12.yaml"
else
    echo "✗ Failed to create node 12 config"
    exit 1
fi

# Create static IP + VIP patch for node 13
cat > /tmp/node13-patch.yaml <<EOF
machine:
  network:
    hostname: talos-cp3
    interfaces:
      - interface: end0
        addresses:
          - ${NODE13_IP}/${NETMASK}
        routes:
          - network: 0.0.0.0/0
            gateway: ${GATEWAY}
        vip:
          ip: ${VIP}
  kubelet:
    extraMounts:
      - destination: /var/lib/rancher/local-path-provisioner
        type: bind
        source: /var/lib/rancher/local-path-provisioner
        options:
          - bind
          - rshared
          - rw
EOF

echo "Creating config for node 13 (${NODE13_IP})..."
talosctl machineconfig patch \
    "$CONFIG_DIR/controlplane.yaml" \
    --patch @/tmp/node13-patch.yaml \
    --output "$CONFIG_DIR/node13.yaml"

if [ $? -eq 0 ]; then
    echo "✓ Created: $CONFIG_DIR/node13.yaml"
else
    echo "✗ Failed to create node 13 config"
    exit 1
fi

# Create static IP patch for worker (no VIP)
cat > /tmp/node14-patch.yaml <<EOF
machine:
  network:
    hostname: talos-worker1
    interfaces:
      - interface: end0
        addresses:
          - ${NODE14_IP}/${NETMASK}
        routes:
          - network: 0.0.0.0/0
            gateway: ${GATEWAY}
  kubelet:
    extraMounts:
      - destination: /var/lib/rancher/local-path-provisioner
        type: bind
        source: /var/lib/rancher/local-path-provisioner
        options:
          - bind
          - rshared
          - rw
EOF

echo "Creating config for node 14 (${NODE14_IP} - worker)..."
talosctl machineconfig patch \
    "$CONFIG_DIR/worker.yaml" \
    --patch @/tmp/node14-patch.yaml \
    --output "$CONFIG_DIR/node14.yaml"

if [ $? -eq 0 ]; then
    echo "✓ Created: $CONFIG_DIR/node14.yaml"
else
    echo "✗ Failed to create node 14 config"
    exit 1
fi

# Clean up temp files
rm -f /tmp/node11-patch.yaml /tmp/node12-patch.yaml /tmp/node13-patch.yaml /tmp/node14-patch.yaml

echo ""
echo "✓ Phase 3 Complete"
echo ""
echo "========================================="
echo "Generated Configuration Files"
echo "========================================="
echo ""
echo "Node-specific configs (with static IPs + VIP):"
echo "  $CONFIG_DIR/node11.yaml - Control Plane 1 ($NODE11_IP with storage)"
echo "  $CONFIG_DIR/node12.yaml - Control Plane 2 ($NODE12_IP)"
echo "  $CONFIG_DIR/node13.yaml - Control Plane 3 ($NODE13_IP)"
echo "  $CONFIG_DIR/node14.yaml - Worker ($NODE14_IP)"
echo ""
echo "Base configs (preserved):"
echo "  $CONFIG_DIR/controlplane.yaml"
echo "  $CONFIG_DIR/worker.yaml"
echo "  $CONFIG_DIR/talosconfig"
echo "  $CONFIG_DIR/secrets.yaml"
echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. Apply node-specific configs:"
echo "   ./apply-static-ip-configs.sh"
echo ""
echo "2. Bootstrap cluster:"
echo "   export TALOSCONFIG=$CONFIG_DIR/talosconfig"
echo "   talosctl config endpoint $VIP"
echo "   talosctl config node $VIP"
echo "   talosctl bootstrap --nodes $VIP"
echo ""
echo "3. Get kubeconfig:"
echo "   talosctl kubeconfig --nodes $VIP --force"
echo ""
echo "4. Verify nodes:"
echo "   kubectl get nodes"
echo ""
