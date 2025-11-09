#!/bin/bash
# Common functions for generating Talos node configurations
# Shared between rebuild-cluster-with-static-ips.sh and regenerate-node-configs.sh

# Generate a control plane node config with network, storage, and patches
# Args: node_number, ip_address, gateway, netmask, vip, base_config, output_file, script_dir
generate_controlplane_config() {
    local node_num="$1"
    local node_ip="$2"
    local gateway="$3"
    local netmask="$4"
    local vip="$5"
    local base_config="$6"
    local output_file="$7"
    local script_dir="$8"

    local hostname="talos-cp${node_num}"
    local temp_network="/tmp/node1${node_num}-network.yaml"

    # Determine storage patch file
    local storage_patch="${script_dir}/patches/node-1${node_num}-storage.yaml"

    # Create network configuration patch
    cat > "$temp_network" <<EOF
machine:
  network:
    hostname: ${hostname}
    interfaces:
      - interface: end0
        addresses:
          - ${node_ip}/${netmask}
        routes:
          - network: 0.0.0.0/0
            gateway: ${gateway}
        vip:
          ip: ${vip}
EOF

    echo "Generating ${output_file} (Control Plane ${node_num} with Longhorn storage)..."

    # Apply patches: network + storage (iSCSI is in the schematic now, not a patch)
    talosctl machineconfig patch \
        "$base_config" \
        --patch @"$temp_network" \
        --patch @"$storage_patch" \
        --output "$output_file"

    local result=$?
    rm -f "$temp_network"
    return $result
}

# Generate a worker node config with network only (no storage, no VIP)
# Args: node_number, ip_address, gateway, netmask, base_config, output_file
generate_worker_config() {
    local node_num="$1"
    local node_ip="$2"
    local gateway="$3"
    local netmask="$4"
    local base_config="$5"
    local output_file="$6"

    local hostname="talos-worker${node_num}"
    local temp_network="/tmp/node1${node_num}-network.yaml"

    # Create network configuration patch
    cat > "$temp_network" <<EOF
machine:
  network:
    hostname: ${hostname}
    interfaces:
      - interface: end0
        addresses:
          - ${node_ip}/${netmask}
        routes:
          - network: 0.0.0.0/0
            gateway: ${gateway}
EOF

    echo "Generating ${output_file} (Worker ${node_num} - no storage)..."

    # Apply network patch only
    talosctl machineconfig patch \
        "$base_config" \
        --patch @"$temp_network" \
        --output "$output_file"

    local result=$?
    rm -f "$temp_network"
    return $result
}
