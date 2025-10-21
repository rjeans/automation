# Storage Setup with Local Path Provisioner

## Overview

Local Path Provisioner provides dynamic persistent volume provisioning using local storage on a single node. This setup uses an external 1TB SSD mounted on node .11 for all persistent storage needs.

## Architecture Decision

**Choice**: Local Path Provisioner with single external drive
**Alternative considered**: Longhorn (distributed storage)

### Why Local Path Provisioner?

For a personal home lab with one external drive:
- ✅ Simple, lightweight, minimal overhead
- ✅ Direct disk access - excellent performance
- ✅ No replication complexity
- ✅ Perfect for single-node stateful workloads
- ✅ Easy backup strategy (one location)

### Trade-offs

- ❌ No high availability - if node .11 fails, storage is unavailable
- ❌ All pods using storage must run on node .11
- ✅ Acceptable for personal use with backup strategy

## Prerequisites

- Talos Kubernetes cluster running
- External drive mounted on one node
- `kubectl` configured with cluster access

## Step 1: Mount External Drive on Node .11

### 1.1 Identify the External Drive

```bash
# Check available disks on node .11
talosctl -n 192.168.1.11 get disks

# Output should show your external drive (e.g., sdb, 1TB)
```

### 1.2 Wipe the Disk (if needed)

If the disk has existing data/partitions:

```bash
# Wipe disk to clean state
talosctl -n 192.168.1.11 wipe disk --drop-partition sdb

# Verify disk is clean
talosctl -n 192.168.1.11 get discoveredvolumes | grep sdb
```

### 1.3 Create Talos Patch for Disk Mount

The patch file is in `talos/patches/node-11-storage.yaml`:

```yaml
# External storage mount for node .11
# Device: /dev/sdb (1TB external drive)
machine:
  disks:
    - device: /dev/sdb
      partitions:
        - size: 0  # Use all available space
          mountpoint: /var/mnt/storage
```

### 1.4 Apply the Patch

```bash
# Apply disk mount configuration
talosctl -n 192.168.1.11 patch machineconfig --patch @talos/patches/node-11-storage.yaml

# Node will reboot to apply changes (~2 minutes)
```

### 1.5 Verify Mount

```bash
# Check mount status
talosctl -n 192.168.1.11 get mounts | grep storage

# List storage directory
talosctl -n 192.168.1.11 ls /var/mnt/storage

# Check disk space
talosctl -n 192.168.1.11 df | grep storage
```

## Step 2: Configure Talos for subPath Support

### 2.1 Understanding the Requirement

Talos Linux requires additional kubelet configuration to properly support `subPath` mounts with local-path-provisioner. Without this configuration, fsGroup permissions don't propagate correctly to subPath-mounted volumes, causing permission errors in applications.

### 2.2 Create Talos Kubelet Patch

The patch file `talos/patches/kubelet-local-path.yaml` configures kubelet with extraMounts:

```yaml
# Configure kubelet to properly handle subPath mounts for local-path-provisioner
# This is required for Talos to support subPath mounts with local-path-provisioner
# Without this, fsGroup permissions don't propagate correctly to subPath mounts
# Path must match the local-path-provisioner storage location
machine:
  kubelet:
    extraMounts:
      - destination: /var/lib/rancher/local-path-provisioner
        type: bind
        source: /var/lib/rancher/local-path-provisioner
        options:
          - bind
          - rshared
          - rw
```

### 2.3 Apply Kubelet Patch to All Nodes

This patch must be applied to **all cluster nodes** (both control plane and workers):

```bash
# Apply to all nodes
for node in 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14; do
  echo "Applying kubelet patch to node $node..."
  talosctl patch machineconfig --nodes $node \
    -p @talos/patches/kubelet-local-path.yaml \
    --mode=no-reboot
done
```

### 2.4 Restart Kubelet Services

After applying the patch, restart kubelet on all nodes to activate the configuration:

```bash
# Restart kubelet on all nodes
for node in 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14; do
  echo "Restarting kubelet on node $node..."
  talosctl service kubelet restart --nodes $node
done

# Wait for cluster to stabilize
sleep 30
kubectl get nodes
```

All nodes should show `Ready` status after kubelet restarts.

### 2.5 Verify Configuration

```bash
# Check that extraMounts is in the machine config
talosctl get machineconfig --nodes 192.168.1.11 -o yaml | grep -A 10 "extraMounts"
```

You should see the bind mount configuration in the output.

## Step 3: Deploy Local Path Provisioner

### 3.1 Install Local Path Provisioner

```bash
# Deploy the provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
```

### 3.2 Configure Storage Path

Update the ConfigMap to use our mounted storage:

```bash
# Get node hostname for node .11
NODE_11=$(kubectl get nodes -o wide | grep 192.168.1.11 | awk '{print $1}')

# Update config to use /var/mnt/storage
kubectl -n local-path-storage patch configmap local-path-config --type merge -p "{
  \"data\": {
    \"config.json\": \"{\\n  \\\"nodePathMap\\\":[\\n    {\\n      \\\"node\\\":\\\"${NODE_11}\\\",\\n      \\\"paths\\\":[\\\"/var/mnt/storage\\\"]\\n    },\\n    {\\n      \\\"node\\\":\\\"DEFAULT_PATH_FOR_NON_LISTED_NODES\\\",\\n      \\\"paths\\\":[\\\"/var/mnt/storage\\\"]\\n    }\\n  ]\\n}\"
  }
}"

# Restart provisioner to pick up changes
kubectl -n local-path-storage rollout restart deployment local-path-provisioner
```

### 3.3 Fix PodSecurity Labels

The helper pods need privileged access to create volumes:

```bash
# Label namespace to allow privileged pods
kubectl label namespace local-path-storage \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite
```

### 3.4 Set as Default StorageClass

```bash
# Make local-path the default StorageClass
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Verify
kubectl get storageclass
```

Expected output:
```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  5m
```

## Step 4: Test Storage

### 4.1 Create Test PVC and Pod

```bash
# Create test resources
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
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  nodeSelector:
    kubernetes.io/hostname: ${NODE_11}
  tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "echo 'Hello from storage!' > /data/test.txt && cat /data/test.txt && sleep 3600"]
    volumeMounts:
    - name: test-volume
      mountPath: /data
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: test-pvc
EOF
```

### 4.2 Verify Storage Works

```bash
# Check PVC is bound
kubectl get pvc test-pvc

# Check pod is running
kubectl get pod test-pod

# Verify data was written
kubectl exec test-pod -- cat /data/test.txt

# Verify data is on external drive
talosctl -n 192.168.1.11 ls /var/mnt/storage/
```

### 4.3 Cleanup Test Resources

```bash
kubectl delete pod test-pod
kubectl delete pvc test-pvc
```

## Usage for Applications

### Deploying Stateful Applications

All stateful applications (PostgreSQL, Redis, monitoring stack, etc.) must:

1. **Target node .11** with node selector:
   ```yaml
   nodeSelector:
     kubernetes.io/hostname: talos-7f2-ouz  # Node .11
   ```

2. **Tolerate control-plane taint**:
   ```yaml
   tolerations:
   - key: node-role.kubernetes.io/control-plane
     operator: Exists
     effect: NoSchedule
   ```

3. **Use local-path StorageClass**:
   ```yaml
   storageClassName: local-path
   ```

### Example: PostgreSQL with Local Path Storage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      nodeSelector:
        kubernetes.io/hostname: talos-7f2-ouz
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: postgres
        image: postgres:16-alpine
        env:
        - name: POSTGRES_PASSWORD
          value: "changeme"
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        ports:
        - containerPort: 5432
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: postgres-pvc
```

## Monitoring Storage Usage

### Check Available Space

```bash
# From host
talosctl -n 192.168.1.11 df | grep storage

# List all volumes
talosctl -n 192.168.1.11 ls /var/mnt/storage/
```

### View PVC Usage

```bash
# List all PVCs
kubectl get pvc -A

# Get detailed PVC info
kubectl describe pvc <pvc-name> -n <namespace>
```

## Backup Strategy

Since all data is on one node, backups are critical:

### Option 1: Velero with Restic

```bash
# Install Velero (coming in Phase 5)
# Backs up PVCs to S3/NFS automatically
```

### Option 2: Manual Backups

```bash
# Copy data from external drive
talosctl -n 192.168.1.11 copy /var/mnt/storage/pvc-xxx /backup/location/

# Or use rsync from within a pod
```

### Option 3: Application-Level Backups

- PostgreSQL: `pg_dump` to external location
- Application data: Export/backup via application-specific tools
- Files: Sync to cloud storage (S3, Backblaze, etc.)

## Troubleshooting

### PVC Stuck in Pending

**Check provisioner logs:**
```bash
kubectl -n local-path-storage logs -l app=local-path-provisioner
```

**Common causes:**
- Pod not scheduled (add node selector and toleration)
- PodSecurity blocking helper pods (label namespace as privileged)
- Storage path doesn't exist

### Pod Can't Start - Node Not Available

**Issue**: Pod scheduled to wrong node

**Solution**: Add node selector for node .11:
```yaml
nodeSelector:
  kubernetes.io/hostname: talos-7f2-ouz
tolerations:
- key: node-role.kubernetes.io/control-plane
  operator: Exists
  effect: NoSchedule
```

### Storage Full

**Check usage:**
```bash
talosctl -n 192.168.1.11 df | grep storage
```

**Clean up:**
```bash
# Delete unused PVCs
kubectl delete pvc <unused-pvc>

# Volumes are automatically cleaned up after PVC deletion
```

### Mount Not Persistent After Reboot

**Check patch is applied:**
```bash
talosctl -n 192.168.1.11 get machineconfig -o yaml | grep -A 5 disks
```

**Reapply if needed:**
```bash
talosctl -n 192.168.1.11 patch machineconfig --patch @talos/patches/node-11-storage.yaml
```

## Reinstalling Local Path Provisioner

If you need to reinstall (e.g., after cluster rebuild):

```bash
# 1. Deploy Local Path Provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

# 2. Get node .11 hostname
NODE_11=$(kubectl get nodes -o wide | grep 192.168.1.11 | awk '{print $1}')

# 3. Configure storage path
kubectl -n local-path-storage patch configmap local-path-config --type merge -p "{
  \"data\": {
    \"config.json\": \"{\\n  \\\"nodePathMap\\\":[\\n    {\\n      \\\"node\\\":\\\"${NODE_11}\\\",\\n      \\\"paths\\\":[\\\"/var/mnt/storage\\\"]\\n    },\\n    {\\n      \\\"node\\\":\\\"DEFAULT_PATH_FOR_NON_LISTED_NODES\\\",\\n      \\\"paths\\\":[\\\"/var/mnt/storage\\\"]\\n    }\\n  ]\\n}\"
  }
}"

# 4. Fix PodSecurity for helper pods
kubectl label namespace local-path-storage \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite

# 5. Restart provisioner to apply config
kubectl -n local-path-storage rollout restart deployment local-path-provisioner

# 6. Set as default StorageClass
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# 7. Verify
kubectl get storageclass
kubectl -n local-path-storage get pods
```

**Note**: The disk mount at `/var/mnt/storage` persists via the Talos patch and survives reboots automatically.

## Uninstalling Local Path Provisioner

**⚠️ WARNING: This will delete all volumes and data!**

```bash
# 1. Delete all PVCs first
kubectl get pvc -A
kubectl delete pvc <pvc-name> -n <namespace>

# 2. Uninstall Local Path Provisioner
kubectl delete -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

# 3. Remove data from external drive (optional)
# Note: There's no easy way to run commands in Talos
# Data will remain on /var/mnt/storage until manually cleaned
```

## Storage Specifications

- **Node**: talos-7f2-ouz (192.168.1.11)
- **Device**: /dev/sdb (1TB external SSD)
- **Mount Point**: /var/mnt/storage
- **Filesystem**: XFS (auto-created by Talos)
- **StorageClass**: local-path (default)
- **Provisioner**: rancher.io/local-path v0.0.30
- **Reclaim Policy**: Delete (volumes deleted with PVC)
- **Volume Binding**: WaitForFirstConsumer

## Next Steps

With storage configured, you can now:

1. **Deploy Ingress Controller** - [docs/05-ingress-traefik.md](./05-ingress-traefik.md)
2. **Deploy cert-manager** - For automatic TLS certificates
3. **Deploy monitoring stack** - Prometheus, Grafana, Alertmanager
4. **Deploy stateful applications** - As needed for your use case

---

**Storage is Ready!** ✅

Your cluster now has:
- ✅ 1TB external SSD mounted and formatted
- ✅ Dynamic volume provisioning with Local Path Provisioner
- ✅ Default StorageClass configured
- ✅ Ready for stateful applications

**Last Updated**: 2025-10-06
**Local Path Provisioner Version**: v0.0.30
**Node**: talos-7f2-ouz (192.168.1.11, 1TB external drive)
