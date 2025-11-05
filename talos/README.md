# Building a High-Availability Kubernetes Cluster on Raspberry Pi with Talos Linux

A complete guide to deploying a production-grade Kubernetes cluster on Raspberry Pi hardware using Talos Linux with VIP (Virtual IP) for high availability.

## Overview

This guide walks you through building a 4-node Kubernetes cluster running on Raspberry Pi 4 devices with PoE (Power over Ethernet) HATs. The cluster uses:

- **Talos Linux v1.11.3** - Minimal, immutable Linux distribution designed for Kubernetes
- **Kubernetes v1.31.2** - Container orchestration
- **Static IP Configuration** - Eliminates DHCP dependencies and DNS issues
- **VIP (Virtual IP)** - Provides high-availability for the Kubernetes API server
- **3 Control Plane Nodes** - For redundancy and fault tolerance
- **1 Worker Node** - For running workloads

### Architecture

```
┌─────────────────────────────────────────────────────┐
│                 VIP: 192.168.1.10                   │
│            (Kubernetes API Endpoint)                │
└─────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
   ┌────▼────┐      ┌────▼────┐      ┌────▼────┐
   │ CP Node │      │ CP Node │      │ CP Node │
   │   .11   │      │   .12   │      │   .13   │
   │  + 1TB  │      │         │      │         │
   └─────────┘      └─────────┘      └─────────┘
                          │
                    ┌─────▼─────┐
                    │  Worker   │
                    │    .14    │
                    └───────────┘
```

## Prerequisites

### Hardware
- 4x Raspberry Pi 4 (4GB+ RAM recommended)
- 4x Raspberry Pi PoE HAT (for power and cooling)
- 4x 32GB+ microSD cards (high quality, Class 10 or better)
- 1x 1TB USB drive (for persistent storage on control plane node 1)
- PoE-enabled network switch
- 4x Ethernet cables

### Software
- macOS, Linux, or Windows with WSL
- Docker Desktop installed
- `talosctl` CLI installed
- `kubectl` CLI installed
- Basic familiarity with Kubernetes concepts

### Network
- Available IP addresses: 192.168.1.10-14
- Gateway: 192.168.1.1 (adjust for your network)
- Internet connectivity for downloading images

---

## Part 1: Prepare the Talos Image

Talos requires a custom image to support Raspberry Pi PoE HATs. We'll use the Talos Image Factory to create one.

### Step 1.1: Create Your Overlay Configuration

The overlay configuration tells Talos how to configure the Raspberry Pi hardware. This file already exists in the repository at `raspberrypi/rpi_poe.yaml`:

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
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/vc4
```

This configuration:
- Enables PoE HAT with 4-stage fan control (65°C, 70°C, 75°C, 80°C)
- Disables Bluetooth and WiFi (cluster uses Ethernet only)
- Enables UART for debugging
- Includes vc4 graphics driver

### Step 1.2: Generate the Talos Image

**Option A: Using Image Factory API (Recommended - 5 minutes)**

```bash
cd /Users/rich/Library/CloudStorage/Dropbox/Development/pi-cluster/talos
./create-schematic.sh
```

This script:
1. Submits your overlay to the Talos Image Factory API
2. Returns a schematic ID
3. Provides download commands

Example output:
```
✓ Schematic Created!

Schematic ID: 311558db2a6142614f225acec4c6adefb413a15fed76a022ff8f3ac50fceab0a

Download command:
cd ~/Downloads
wget https://factory.talos.dev/image/311558db.../v1.11.3/metal-arm64.raw.xz
xz -d metal-arm64.raw.xz
```

Run the provided download commands to get your custom image.

**Option B: Build Locally with Docker (Alternative - 10 minutes)**

If you prefer to build the image locally:

```bash
./build-talos-image.sh
```

This builds the image using Docker and saves it to `~/Downloads/_out/sbc-rpi_generic-arm64.raw`.

---

## Part 2: Flash SD Cards

Now we'll flash all 4 SD cards with the custom Talos image.

### Step 2.1: Identify Your SD Card

```bash
diskutil list
```

Look for your SD card (e.g., `/dev/disk4`). **Be very careful** - flashing the wrong disk will destroy data!

### Step 2.2: Flash Each SD Card

```bash
# Navigate to where you downloaded the image
cd ~/Downloads          # If using Image Factory
# OR
cd ~/Downloads/_out     # If built locally

# For each SD card:
diskutil unmountDisk /dev/diskN    # Replace N with your disk number
sudo dd if=metal-arm64.raw of=/dev/rdiskN bs=4M conv=fsync
diskutil eject /dev/diskN
```

**Important**: Use `/dev/rdiskN` (with the 'r') for faster writes.

Repeat this process for all 4 SD cards. This takes about 10 minutes per card (40 minutes total).

**Tip**: Label each SD card so you know which node it belongs to:
- SD Card 1: Control Plane 1 (node 11)
- SD Card 2: Control Plane 2 (node 12)
- SD Card 3: Control Plane 3 (node 13)
- SD Card 4: Worker (node 14)

---

## Part 3: Generate Cluster Configuration

Talos uses YAML files to configure each node. We'll generate node-specific configurations with static IPs and VIP.

### Step 3.1: Generate Node Configurations

```bash
cd /Users/rich/Library/CloudStorage/Dropbox/Development/pi-cluster/talos
./rebuild-cluster-with-static-ips.sh
```

This script:
1. **Backs up** any existing configuration (if present)
2. **Generates base configs** with VIP as the API endpoint
3. **Creates node-specific configs** with static IPs for each node

### Step 3.2: Understand the Configuration

The script creates these files in `~/.talos-secrets/pi-cluster/`:

```
~/.talos-secrets/pi-cluster/
├── node11.yaml          # Control plane 1 (192.168.1.11) + 1TB storage
├── node12.yaml          # Control plane 2 (192.168.1.12)
├── node13.yaml          # Control plane 3 (192.168.1.13)
├── node14.yaml          # Worker (192.168.1.14)
├── controlplane.yaml    # Base template
├── worker.yaml          # Base template
├── talosconfig          # CLI configuration
└── secrets.yaml         # Cluster secrets and certificates
```

Each node configuration includes:
- **Static IP address** (no DHCP required)
- **Hostname** (talos-cp1, talos-cp2, talos-cp3, talos-worker1)
- **VIP configuration** (control planes only)
- **Gateway and routing** (192.168.1.1)
- **Kubelet mounts** for persistent volumes
- **Storage mount** (node 11 only - for 1TB USB drive)

---

## Part 4: Deploy the Cluster

Now we'll boot the nodes and apply the configurations.

### Step 4.1: Insert SD Cards and Boot

1. **Insert SD cards** into each Raspberry Pi:
   - Node 11: Control Plane 1 (with 1TB USB drive attached)
   - Node 12: Control Plane 2
   - Node 13: Control Plane 3
   - Node 14: Worker

2. **Connect Ethernet cables** from each Pi to your PoE switch

3. **Power on** - The PoE HATs will power the Pis automatically

4. **Wait 60-90 seconds** for nodes to boot into maintenance mode

### Step 4.2: Verify Nodes Are Reachable

```bash
for node in 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14; do
    echo -n "Testing $node: "
    ping -c 2 -W 2 $node && echo "✓" || echo "✗"
done
```

All nodes should be pingable. They boot into maintenance mode on DHCP IPs initially.

**If nodes aren't reachable**:
- Check PoE switch is powered and working
- Verify Ethernet cables are connected
- Check PoE HAT LEDs are lit
- Wait another minute - nodes may still be booting

### Step 4.3: Apply Node Configurations

```bash
./apply-static-ip-configs.sh
```

The script will:
1. **Prompt for current IPs** - If nodes got different DHCP IPs, enter them. Otherwise, press Enter to use defaults.
2. **Apply configs** - Sends each node its specific configuration
3. **Wait between nodes** - 30 seconds for each node to reinitialize
4. **Verify connectivity** - Tests that nodes respond on their static IPs

This process takes about 10 minutes total.

### Step 4.4: Monitor Node Status

After applying configs, give nodes 2-3 minutes to fully initialize, then check:

```bash
# Test static IPs
for node in 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14; do
    echo -n "$node: "
    ping -c 2 $node > /dev/null 2>&1 && echo "✓ Reachable" || echo "✗ Not reachable"
done
```

All nodes should now respond on their static IPs.

---

## Part 5: Bootstrap Kubernetes

With all nodes configured, we'll bootstrap the Kubernetes cluster. **Important**: The VIP won't be active until after bootstrap completes, so we must bootstrap using a direct node IP first.

### Step 5.1: Configure talosctl and Wait for Services

```bash
export TALOSCONFIG=~/.talos-secrets/pi-cluster/talosconfig

# Configure to use node 11 directly (not VIP - it's not active yet)
talosctl config endpoint 192.168.1.11
talosctl config node 192.168.1.11

# Wait 3-5 minutes after applying configs for control plane services to start
# Check that etcd and kubelet services are running
talosctl -n 192.168.1.11 get services
```

**You should see these services before proceeding**:
- `apid`, `machined`, `containerd` (base system)
- `etcd` (required for bootstrap)
- `kubelet` (Kubernetes agent)
- `trustd`, `cri` (container runtime)

If you only see base services, wait 3-5 more minutes for control plane services to start.

### Step 5.2: Bootstrap the Cluster

```bash
# Bootstrap using direct node IP
talosctl bootstrap --nodes 192.168.1.11
```

This initializes the etcd cluster and starts Kubernetes control plane components.

**What happens during bootstrap**:
1. etcd cluster formation begins
2. Kubernetes control plane starts on all 3 control plane nodes
3. VIP elects a leader (one control plane node takes the VIP)
4. Control plane components communicate via localhost initially
5. After ~2-3 minutes, VIP becomes active and cluster is ready

**Wait 2-3 minutes** for bootstrap to complete and VIP to activate.

### Step 5.3: Switch to VIP Endpoint

Once bootstrap is complete, the VIP will be active. Switch talosctl to use it:

```bash
# Verify VIP is now active
ping -c 3 192.168.1.10

# Check which node has the VIP
for node in 192.168.1.11 192.168.1.12 192.168.1.13; do
    echo "=== Node $node ==="
    talosctl -n $node get addresses | grep 192.168.1.10 || echo "VIP not here"
done

# Switch to VIP endpoint with node list for fallback
talosctl config endpoint 192.168.1.10
talosctl config nodes 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14
```

Now `talosctl` will use the VIP by default, with automatic fallback to individual nodes if the VIP is unavailable.

### Step 5.4: Verify etcd Health

```bash
talosctl -n 192.168.1.10 etcd members
```

You should see 3 etcd members listed.

---

## Part 6: Access the Cluster

### Step 6.1: Get kubeconfig

```bash
talosctl kubeconfig --nodes 192.168.1.10 --force
```

This retrieves the Kubernetes configuration and saves it to `~/.kube/config`.

### Step 6.2: Verify Cluster Nodes

```bash
kubectl get nodes
```

Expected output (may take 2-3 minutes for all nodes to show as Ready):

```
NAME            STATUS   ROLES           AGE   VERSION
talos-cp1       Ready    control-plane   3m    v1.31.2
talos-cp2       Ready    control-plane   3m    v1.31.2
talos-cp3       Ready    control-plane   3m    v1.31.2
talos-worker1   Ready    <none>          2m    v1.31.2
```

### Step 6.3: Verify Cluster Components

```bash
# Check system pods
kubectl get pods -n kube-system

# Check control plane endpoints
kubectl get endpoints -n default kubernetes
```

All pods should be Running, and you should see all 3 control plane IPs in the endpoints.

---

## Part 7: Verify VIP Functionality

The VIP provides high availability - if one control plane node fails, the VIP moves to another node automatically.

### Step 7.1: Test VIP Connectivity

```bash
# VIP should respond to ping
ping -c 3 192.168.1.10

# Verify you can reach the API server
kubectl cluster-info
```

### Step 7.2: Find VIP Owner

```bash
for node in 192.168.1.11 192.168.1.12 192.168.1.13; do
    echo "=== Node $node ==="
    talosctl -n $node get addresses | grep 192.168.1.10 || echo "VIP not here"
done
```

Exactly one control plane node should show the VIP address.

### Step 7.3: Test VIP Failover (Optional)

To test high availability:

```bash
# Find which node has the VIP (from previous step)
# Reboot that node
talosctl -n <vip-node-ip> reboot

# Watch the VIP move to another node
watch -n 1 'kubectl get nodes'
```

Within 30-60 seconds, the VIP should move to another control plane node and the cluster remains accessible.

---

## Part 8: Deploy Your First Application

Let's verify the cluster works by deploying a simple application.

### Step 8.1: Deploy whoami Service

```bash
# Create a test deployment
kubectl create deployment whoami --image=traefik/whoami
kubectl expose deployment whoami --port=80 --type=NodePort

# Get the NodePort
kubectl get svc whoami
```

### Step 8.2: Test the Service

```bash
# Get the assigned NodePort (e.g., 30080)
NODE_PORT=$(kubectl get svc whoami -o jsonpath='{.spec.ports[0].nodePort}')

# Test the service on any node
curl http://192.168.1.11:$NODE_PORT
curl http://192.168.1.14:$NODE_PORT
```

You should see a response showing hostname and IP information.

### Step 8.3: Clean Up

```bash
kubectl delete svc whoami
kubectl delete deployment whoami
```

---

## Part 9: Install Essential Cluster Components

### Step 9.1: Install Local Path Provisioner (Storage)

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml

# Set as default storage class
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Step 9.2: Verify Storage

```bash
# Check storage class
kubectl get storageclass

# Create test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
EOF

# Verify PVC is bound
kubectl get pvc test-pvc

# Clean up
kubectl delete pvc test-pvc
```

### Step 9.3: Install Flux for GitOps (Optional)

If you want to manage your cluster with GitOps:

```bash
flux bootstrap github \
    --owner=<your-github-username> \
    --repository=pi-cluster \
    --branch=main \
    --path=flux/clusters/talos \
    --personal
```

---

## Troubleshooting

### DNS Errors During Boot

**Symptom**: Control plane nodes show continuous DNS request errors on console.

**Solution**: This is why we use static IPs. If you still see DNS errors:
1. Verify gateway (192.168.1.1) is correct for your network
2. Check that IPs .11-.14 are not already in use by other devices
3. Ensure SD cards were flashed with the custom Talos image (with PoE overlay)

### Nodes Not Reachable After Config Apply

```bash
# Run diagnostics
./diagnose-boot.sh

# Check each node individually
for node in 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14; do
    echo "Testing $node..."
    ping -c 2 $node
done
```

**If a node isn't reachable**:
1. Check PoE HAT LED is lit (power indicator)
2. Check Ethernet link lights
3. Wait another minute - node may still be initializing
4. Check DHCP leases in your router to find current IP
5. Try recovering: `./recover-node.sh <node-ip>`

### VIP Not Working

**Symptom**: Can't reach 192.168.1.10 or bootstrap fails.

**Check VIP configuration**:
```bash
# Verify VIP is on exactly one control plane node
for node in 192.168.1.11 192.168.1.12 192.168.1.13; do
    echo "=== Node $node ==="
    talosctl -n $node get addresses | grep 192.168.1.10 || echo "VIP not here"
done

# Check interface configuration
talosctl -n 192.168.1.11 get machineconfig -o yaml | grep -A5 "vip:"
```

### Bootstrap Fails: "bootstrap is not available yet"

**Symptom**: Error `rpc error: code = FailedPrecondition desc = bootstrap is not available yet`

**Cause**: Control plane services (etcd, kubelet) haven't fully started yet after applying configs.

**Solution**:
```bash
# 1. Check which services are running (should see etcd and kubelet)
talosctl -n 192.168.1.11 get services

# If you only see base services (apid, machined, containerd), wait 3-5 more minutes

# 2. Check for errors in logs
talosctl -n 192.168.1.11 dmesg | tail -30
talosctl -n 192.168.1.11 logs controller-runtime

# 3. Once you see etcd and kubelet services, retry bootstrap
talosctl bootstrap --nodes 192.168.1.11

# Only bootstrap ONCE - if already bootstrapped, this will fail
```

### Bootstrap Fails: Other Errors

```bash
# Check etcd service status
talosctl -n 192.168.1.11 service etcd status

# Check logs
talosctl -n 192.168.1.11 logs etcd

# Check all control plane services
talosctl -n 192.168.1.11 get services
```

### Nodes Stuck in "NotReady"

```bash
# Check kubelet logs
talosctl -n 192.168.1.11 logs kubelet

# Check if CNI is installed (should be automatic)
kubectl get pods -n kube-system -l k8s-app=flannel

# Restart a stuck node
talosctl -n <node-ip> reboot
```

---

## Maintenance and Operations

### Upgrading Talos

```bash
# Check current version
talosctl version

# Upgrade control plane nodes one at a time
talosctl upgrade --nodes 192.168.1.11 \
    --image factory.talos.dev/installer/<schematic-id>:v1.12.0

# Wait for node to come back online, then repeat for other nodes
```

### Upgrading Kubernetes

```bash
# Check available versions
talosctl upgrade-k8s --nodes 192.168.1.10

# Upgrade Kubernetes
talosctl upgrade-k8s --to 1.32.0 --nodes 192.168.1.10
```

### Adding a Worker Node

1. Flash SD card with Talos image
2. Update `rebuild-cluster-with-static-ips.sh` to add new node config
3. Regenerate configs: `./rebuild-cluster-with-static-ips.sh`
4. Boot new node and apply config
5. Node will automatically join the cluster

### Backup and Recovery

**Backup etcd**:
```bash
talosctl -n 192.168.1.11 etcd snapshot backup.db
```

**Backup configuration**:
```bash
# Configs are already backed up with timestamps
ls -la ~/.talos-secrets/pi-cluster-backup-*
```

---

## Advanced Configuration

### Customizing Network Settings

Edit `rebuild-cluster-with-static-ips.sh`:

```bash
NODE11_IP="192.168.1.11"    # Change node IPs
NODE12_IP="192.168.1.12"
NODE13_IP="192.168.1.13"
NODE14_IP="192.168.1.14"
VIP="192.168.1.10"          # Change VIP
GATEWAY="192.168.1.1"       # Change gateway for your network
NETMASK="24"                # Change subnet mask
```

### Using Different Talos/Kubernetes Versions

```bash
# Create schematic with different version
./create-schematic.sh v1.10.0

# Or build locally
./build-talos-image.sh v1.10.0

# Edit rebuild script for Kubernetes version
# In rebuild-cluster-with-static-ips.sh, line 10:
K8S_VERSION="1.30.0"
```

### Monitoring Setup

Install Prometheus and Grafana:

```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
kubectl create namespace monitoring
helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring

# Access Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000 (admin/prom-operator)
```

---

## Performance Considerations

### Raspberry Pi 4 Limitations

- **CPU**: ARM Cortex-A72 (4 cores @ 1.5GHz)
- **RAM**: 4-8GB (cluster uses ~2GB per node for system)
- **Storage**: SD card I/O is limited (use USB for heavy workloads)
- **Network**: Gigabit Ethernet (shared with USB bus)

### Optimization Tips

1. **Use USB storage for databases** - SD cards wear out with heavy writes
2. **Limit resource requests** - Don't over-commit the limited RAM
3. **Use PodDisruptionBudgets** - Prevent too many pods from failing simultaneously
4. **Enable CPU/Memory limits** - Prevent runaway pods
5. **Use node affinity** - Keep heavy workloads on specific nodes

---

## Cost Breakdown

Building this cluster costs approximately:

| Item | Quantity | Unit Price | Total |
|------|----------|------------|-------|
| Raspberry Pi 4 (8GB) | 4 | $75 | $300 |
| Raspberry Pi PoE HAT | 4 | $20 | $80 |
| 64GB microSD card | 4 | $12 | $48 |
| 1TB USB 3.0 SSD | 1 | $80 | $80 |
| PoE Switch (5-port) | 1 | $60 | $60 |
| Ethernet cables | 4 | $3 | $12 |
| **Total** | | | **$580** |

Compare this to cloud Kubernetes:
- Managed Kubernetes: ~$200-300/month
- This cluster pays for itself in 2-3 months
- No ongoing cloud costs
- Full control over hardware

---

## What You've Learned

By completing this guide, you've:

✅ Built a production-grade Kubernetes cluster from scratch
✅ Configured high availability with VIP
✅ Used static IP configuration for stability
✅ Deployed Talos Linux on Raspberry Pi hardware
✅ Mastered node configuration and bootstrapping
✅ Implemented storage solutions
✅ Learned Kubernetes troubleshooting
✅ Set up monitoring and operations workflows

---

## Next Steps

Now that your cluster is running, consider:

1. **Deploy real applications** - Move your services to the cluster
2. **Set up Ingress** - Install Traefik or NGINX for HTTP routing
3. **Implement GitOps** - Use Flux or ArgoCD for deployments
4. **Add monitoring** - Full Prometheus/Grafana stack
5. **Configure backups** - Automated etcd and PVC backups
6. **SSL/TLS** - Cert-manager for automatic certificates
7. **External storage** - NFS or Longhorn for distributed storage
8. **Service mesh** - Linkerd or Istio for advanced networking

---

## Resources

### Documentation
- **Talos Linux**: https://www.talos.dev/latest/
- **Talos VIP Guide**: https://www.talos.dev/latest/talos-guides/network/vip/
- **Kubernetes Docs**: https://kubernetes.io/docs/
- **Image Factory**: https://factory.talos.dev/

### Community
- **Talos Slack**: https://slack.dev.talos-systems.io/
- **Kubernetes Slack**: https://slack.k8s.io/
- **Reddit r/kubernetes**: https://reddit.com/r/kubernetes
- **Reddit r/homelab**: https://reddit.com/r/homelab

### Tools Used in This Guide
- `talosctl` - Talos management CLI
- `kubectl` - Kubernetes CLI
- `flux` - GitOps toolkit
- `helm` - Kubernetes package manager

---

## Conclusion

You now have a fully functional, highly available Kubernetes cluster running on affordable Raspberry Pi hardware. This cluster is suitable for:

- **Learning Kubernetes** - Hands-on experience with real hardware
- **Development** - Local testing environment
- **Home automation** - Run Home Assistant, n8n, etc.
- **Personal services** - Self-hosted applications
- **CI/CD pipelines** - GitLab, Jenkins, Argo Workflows
- **Edge computing** - Distributed applications

The cluster is production-ready for home/small business use and provides valuable experience with enterprise Kubernetes patterns.

---

**Author**: Rich Jeans
**Last Updated**: November 5, 2025
**Talos Version**: v1.11.3
**Kubernetes Version**: v1.31.2
**Repository**: https://github.com/rjeans/pi-cluster

---

## Quick Reference Commands

```bash
# Cluster status
kubectl get nodes
kubectl get pods -A

# Node management
talosctl dashboard -n 192.168.1.10
talosctl health -n 192.168.1.10
talosctl version -n 192.168.1.10

# Logs
talosctl logs -n 192.168.1.11 kubelet
talosctl dmesg -n 192.168.1.11

# Reboot/shutdown
talosctl reboot -n 192.168.1.11
talosctl shutdown -n 192.168.1.11

# Config management
export TALOSCONFIG=~/.talos-secrets/pi-cluster/talosconfig
talosctl config endpoint 192.168.1.10
talosctl config node 192.168.1.10
```
