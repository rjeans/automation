# Network Planning Template

## Cluster Network Configuration

### Node IP Addresses

Cluster network configuration:

| Hostname | Role | MAC Address | IP Address | Status |
|----------|------|-------------|------------|--------|
| rpi-cp01 | Control Plane | | 192.168.1.11 | ✅ Configured |
| rpi-cp02 | Control Plane | | 192.168.1.12 | ⬜ Not configured |
| rpi-worker01 | Worker | | 192.168.1.13 | ⬜ Not configured |
| rpi-worker02 | Worker | | 192.168.1.14 | ⬜ Not configured |

**Network Details**:
- **Subnet**: 192.168.1.0/24
- **Gateway**: 192.168.1.1
- **DNS Servers**: 192.168.1.1, 8.8.8.8, 1.1.1.1

### How to Find MAC Addresses

**Option 1**: Check your router's DHCP client list
- Log into your router admin interface
- Look for connected devices
- Note the MAC address for each Pi

**Option 2**: Boot Pis temporarily with Raspberry Pi OS
- Flash SD card with Raspberry Pi OS
- Boot each Pi
- Run: `ip link show eth0`
- Note the MAC address shown

**Option 3**: Read from the Pi label (if available)

### DHCP Reservations

Configure your router to assign static IPs based on MAC addresses:

**Example configuration** (varies by router):
```
MAC: XX:XX:XX:XX:XX:01 → IP: 192.168.1.11 → Hostname: rpi-cp01
MAC: XX:XX:XX:XX:XX:02 → IP: 192.168.1.12 → Hostname: rpi-cp02
MAC: XX:XX:XX:XX:XX:03 → IP: 192.168.1.13 → Hostname: rpi-worker01
MAC: XX:XX:XX:XX:XX:04 → IP: 192.168.1.14 → Hostname: rpi-worker02
```

## Kubernetes Service Network

**Talos defaults** (usually no need to change):
- **Pod CIDR**: 10.244.0.0/16
- **Service CIDR**: 10.96.0.0/12

**Ensure these don't conflict with**:
- Your local network (192.168.x.x)
- Any VPN networks you use

## Port Requirements

Talos and Kubernetes will handle these automatically, but for reference:

### Talos Ports
- **50000/tcp**: Talos API (apid)
- **50001/tcp**: Trustd API

### Kubernetes Control Plane
- **6443/tcp**: Kubernetes API server
- **2379-2380/tcp**: etcd
- **10250/tcp**: Kubelet API
- **10251/tcp**: kube-scheduler
- **10252/tcp**: kube-controller-manager

### Kubernetes Workers
- **10250/tcp**: Kubelet API
- **30000-32767/tcp**: NodePort Services

All cluster nodes should allow all traffic between them.

## External Access Planning

### Load Balancer VIP (Optional)
If you want a single IP for the control plane:
- **VIP**: 192.168.1.10
- Configure in Talos with kube-vip or similar

### Ingress Access
Plan how external traffic will reach your cluster:

**Option 1: NodePort** (simplest for home lab)
- Access via: `http://<any-node-ip>:30000-32767`
- Configure ingress-nginx or Traefik with NodePort service

**Option 2: LoadBalancer with MetalLB**
- Assign IP range for LoadBalancer services
- Example range: 192.168.1.200-192.168.1.210
- Configure MetalLB in L2 mode

**Option 3: Host Networking** (advanced)
- Ingress controller runs on host network
- Binds to ports 80/443 on specific nodes
- Use DNS to point to those nodes

### DNS Planning

**Internal DNS** (optional but recommended):
- Add entries in your router/DNS server:
  ```
  rpi-cp01.local      → 192.168.1.11
  rpi-cp02.local      → 192.168.1.12
  rpi-worker01.local  → 192.168.1.13
  rpi-worker02.local  → 192.168.1.14
  k8s.local           → 192.168.1.11 (or VIP 192.168.1.10)
  ```

**External DNS** (for internet access):
- If exposing services to internet, plan domains
- Example: `n8n.yourdomain.com` → your public IP
- Configure port forwarding on router
- Use cert-manager with Let's Encrypt for HTTPS

## Network Diagram

```
Internet
    |
    | (Port forward 80/443)
    |
[Router/Gateway] 192.168.1.1
    |
    +--- [Switch]
            |
            +--- [rpi-cp01]     192.168.1.11 (Control Plane + etcd)
            +--- [rpi-cp02]     192.168.1.12 (Control Plane + etcd)
            +--- [rpi-worker01] 192.168.1.13 (Worker)
            +--- [rpi-worker02] 192.168.1.14 (Worker)
```

## Security Considerations

### Firewall Rules
If your router supports it, consider:
- Isolate cluster on VLAN (optional)
- Block external access to Talos API (port 50000)
- Block external access to Kubernetes API (port 6443) unless needed
- Only expose ingress ports (80/443) if needed

### Network Policies
Will be configured later in Kubernetes:
- Restrict pod-to-pod communication
- Isolate namespaces
- Control egress traffic

## Verification Checklist

Before proceeding with installation:

- [ ] IP addresses don't conflict with existing devices
- [ ] DHCP reservations configured in router
- [ ] MAC addresses documented
- [ ] DNS entries planned (if using)
- [ ] Pod/Service CIDRs don't conflict with local network
- [ ] Physical network cables connected
- [ ] Switch has power and all ports working
- [ ] All nodes can reach internet
- [ ] Gateway and DNS servers confirmed

## Notes

Document any special considerations for your network:

```
# Example:
# - Using UniFi Dream Machine Pro for routing
# - VLANs: VLAN 10 for cluster, VLAN 1 for management
# - Separate WiFi network for management access
```

---

## Next Steps

Once network is planned and configured:
- **[01-prerequisites.md](./01-prerequisites.md)** - Complete prerequisites checklist
- **[02-talos-installation.md](./02-talos-installation.md)** - Install Talos Linux
