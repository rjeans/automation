# Talos Kubernetes Cluster - Baseline Configuration

**Last Updated**: 2025-10-06
**Cluster Status**: ✅ Production Ready
**Purpose**: n8n workflow automation platform on Raspberry Pi infrastructure

---

## Cluster Overview

### Hardware Configuration

| Node | IP Address | Role | RAM | Storage | Notes |
|------|------------|------|-----|---------|-------|
| talos-7f2-ouz | 192.168.1.11 | Control Plane | 8GB | 1TB External SSD | Primary storage node |
| talos-903-zt4 | 192.168.1.12 | Control Plane | 8GB | Boot SD only | |
| talos-j4v-jlf | 192.168.1.13 | Control Plane | 8GB | Boot SD only | |
| talos-hai-hgl | 192.168.1.14 | Worker | 8GB | Boot SD only | |

**Total Cluster Resources:**
- **Nodes**: 4 (3 control plane + 1 worker)
- **CPU**: 16 cores (4 cores per Pi)
- **RAM**: 32GB total (8GB per node)
- **Storage**: 1TB external SSD on node .11

### Software Versions

| Component | Version | Notes |
|-----------|---------|-------|
| Talos Linux | v1.11.2 | Immutable OS |
| Kubernetes | v1.34.0 | API-driven orchestration |
| containerd | v2.1.4 | Container runtime |
| etcd | Embedded | 3-node quorum |
| Kernel | 6.12.48-talos | Custom for ARM64 |

### Custom Talos Image

**Factory Schematic ID**: `3f2272fedf123e61d98b8732dd415b04c5673a1027859bfa69f90e5a34221a2f`

**PoE HAT Configuration** (fan control):
```yaml
dtoverlay=rpi-poe
dtparam=poe_fan_temp0=65000,poe_fan_temp0_hyst=5000
dtparam=poe_fan_temp1=70000,poe_fan_temp1_hyst=4999
dtparam=poe_fan_temp2=75000,poe_fan_temp2_hyst=4999
dtparam=poe_fan_temp3=80000,poe_fan_temp3_hyst=4999
```

**Image URL**: `factory.talos.dev/installer/3f2272fedf123e61d98b8732dd415b04c5673a1027859bfa69f90e5a34221a2f:v1.11.2`

---

## Network Configuration

### Cluster Network

- **Pod CIDR**: 10.244.0.0/16
- **Service CIDR**: 10.96.0.0/12
- **DNS**: CoreDNS (cluster-internal)
- **CNI**: Flannel (default Talos CNI)

### External Access

- **Control Plane API**: 192.168.1.11:6443 (primary endpoint)
- **Traefik HTTP**: All nodes port 30080 (disabled)
- **Traefik HTTPS**: All nodes port 30443 (enabled)

### Talos API Endpoints

```bash
# Control plane nodes only (workers don't run Talos API)
talosctl config endpoint 192.168.1.11 192.168.1.12 192.168.1.13
```

---

## Core Services

### 1. Storage - Local Path Provisioner

**Version**: v0.0.30
**Namespace**: local-path-storage
**Status**: ✅ Running

**Configuration:**
- **StorageClass**: `local-path` (default)
- **Storage Location**: `/var/mnt/storage` on node .11
- **External Drive**: 1TB SSD on `/dev/sdb`
- **Filesystem**: XFS (auto-created by Talos)
- **Provisioner**: rancher.io/local-path
- **Volume Binding Mode**: WaitForFirstConsumer

**Node Affinity:**
- All persistent volumes are created on node .11 (192.168.1.11)
- Workloads using PVCs must tolerate control plane taints

**Security:**
- Namespace labeled as `privileged` for helper pods
- Helper pods require hostPath and root privileges

**Talos Disk Configuration** (node .11):
```yaml
# talos/patches/node-11-storage.yaml
machine:
  disks:
    - device: /dev/sdb
      partitions:
        - size: 0
          mountpoint: /var/mnt/storage
```

### 2. Ingress - Traefik

**Version**: v3.2.2 (Helm chart v33.2.1)
**Namespace**: traefik
**Status**: ✅ Running (2 replicas)

**Configuration:**
- **Service Type**: NodePort
- **HTTP Port**: 30080 (disabled for n8n)
- **HTTPS Port**: 30443 (enabled)
- **Dashboard**: Disabled
- **Replicas**: 2 (high availability)

**Resources (per pod):**
- Requests: 100m CPU / 128Mi RAM
- Limits: 500m CPU / 512Mi RAM

**Health Checks:**
- Ping endpoint: `/ping` on traefik entrypoint
- Liveness/Readiness probes configured

**Critical Configuration:**
```yaml
additionalArguments:
  - "--ping=true"
  - "--ping.entrypoint=traefik"  # Not "web"!
```

**Pod Distribution:**
- Anti-affinity configured
- Tolerates control plane taints

### 3. Certificate Management - cert-manager

**Version**: v1.16.2
**Namespace**: cert-manager
**Status**: ✅ Running (3 components)

**Components:**
- cert-manager controller
- cert-manager webhook
- cert-manager cainjector

**Resources (per component):**
- Requests: 10m CPU / 32Mi RAM
- Limits: 100m CPU / 128Mi RAM

**ClusterIssuers Configured:**

1. **selfsigned-issuer** (active)
   - Type: Self-signed certificates
   - Use: Local testing, internal services

2. **letsencrypt-staging** (configured, not in use)
   - Server: acme-staging-v02.api.letsencrypt.org
   - Email: TODO (needs configuration)
   - Challenge: HTTP-01 via Traefik

3. **letsencrypt-production** (configured, not in use)
   - Server: acme-v02.api.letsencrypt.org
   - Email: TODO (needs configuration)
   - Challenge: HTTP-01 via Traefik

**Note**: Let's Encrypt issuers require:
- Real domain name (not .local)
- External DNS pointing to cluster
- Port 80 accessible from internet
- Router port forwarding configured

---

## Applications

### n8n Workflow Automation

**Version**: n8n v1.113.3 (Helm chart v1.15.12)
**Namespace**: n8n
**Status**: ✅ Running
**Access**: https://192.168.1.11:30443/

#### Deployment Details

**Main Application:**
- **Replicas**: 1
- **Container**: n8nio/n8n:1.113.3
- **Port**: 5678 (internal)
- **Resources**:
  - Requests: 100m CPU / 256Mi RAM
  - Limits: 1000m CPU / 1Gi RAM

**Database:**
- **Type**: PostgreSQL (embedded via subchart)
- **Version**: Bitnami Legacy PostgreSQL
- **Architecture**: Standalone
- **Port**: 5432 (internal)
- **Database Name**: n8n
- **Username**: n8n
- **Password**: n8n-postgresql-password (⚠️ Change for production)
- **Resources**:
  - Requests: 100m CPU / 256Mi RAM
  - Limits: 500m CPU / 512Mi RAM

#### Storage Configuration

**n8n Data Volume:**
- **PVC**: n8n-main-persistence
- **Size**: 10Gi
- **StorageClass**: local-path
- **Location**: Node .11 `/var/mnt/storage`
- **Contains**: Workflow files, credentials (encrypted), user data

**PostgreSQL Data Volume:**
- **PVC**: data-n8n-postgresql-0
- **Size**: 20Gi
- **StorageClass**: local-path
- **Location**: Node .11 `/var/mnt/storage`
- **Contains**: Execution history, workflow definitions, users
- **Tables**: 41 tables (initialized)

**Total Storage Used**: ~30Gi on external SSD

#### Network Configuration

**Services:**
- `n8n`: ClusterIP 10.109.225.156:5678
- `n8n-postgresql`: ClusterIP 10.109.160.157:5432
- `n8n-postgresql-hl`: ClusterIP None (headless)

**Ingress:**
1. **Primary** (n8n): Host-based routing for `n8n.local`
2. **Catch-all** (n8n-catchall): IP-based access, no hostname required

**TLS Certificate:**
- **Secret**: n8n-tls-selfsigned
- **Type**: Self-signed (RSA 4096-bit, SHA-256)
- **Validity**: 365 days
- **SANs**:
  - IP: 192.168.1.11, 192.168.1.12, 192.168.1.13, 192.168.1.14
  - DNS: n8n.local
- **Issuer**: CN=192.168.1.11, O=n8n

#### Health Probes (Critical for Raspberry Pi)

**Liveness Probe:**
- Path: `/healthz`
- Initial Delay: **60 seconds** (critical for slow ARM startup)
- Period: 10s
- Timeout: 5s
- Failure Threshold: 3

**Readiness Probe:**
- Path: `/healthz/readiness`
- Initial Delay: **30 seconds**
- Period: 10s
- Timeout: 5s
- Failure Threshold: 3

**Why delays matter**: Without initial delays, Kubernetes kills the container before n8n finishes starting on Raspberry Pi hardware.

#### Environment Variables

```yaml
N8N_EDITOR_BASE_URL: "http://n8n.local:30080/"
WEBHOOK_URL: "http://n8n.local:30080/"
GENERIC_TIMEZONE: "America/Los_Angeles"
EXECUTIONS_DATA_SAVE_ON_SUCCESS: "all"
EXECUTIONS_DATA_SAVE_ON_ERROR: "all"
EXECUTIONS_DATA_SAVE_ON_PROGRESS: "true"
EXECUTIONS_TIMEOUT: "3600"
N8N_DIAGNOSTICS_ENABLED: "false"
DB_TYPE: "postgresdb"
DB_POSTGRESDB_HOST: "n8n-postgresql"
DB_POSTGRESDB_PORT: "5432"
DB_POSTGRESDB_DATABASE: "n8n"
DB_POSTGRESDB_USER: "n8n"
```

#### Access Methods

**HTTPS (Recommended):**
- Primary: `https://192.168.1.11:30443/`
- Failover: `https://192.168.1.12:30443/`, `.13`, `.14`
- Certificate Warning: Expected (self-signed cert)

**HTTP:**
- Status: Disabled (returns 404)
- Port 30080: Not accessible for security

**First-Time Setup:**
1. Navigate to `https://192.168.1.11:30443/`
2. Accept certificate warning (click "Proceed")
3. Create owner account (email + password)
4. Skip or configure email settings
5. Start building workflows

**Webhooks:**
- URL Format: `https://192.168.1.11:30443/webhook/your-webhook-path`
- No authentication by default (configure in n8n UI)

---

## Security Configuration

### Current Security Posture (Development)

**⚠️ Not Production-Hardened:**
- Simple PostgreSQL password in values.yaml
- Self-signed certificate (browser warnings)
- No webhook authentication
- No network policies
- Secrets stored in Git (encrypted with SOPS recommended for production)
- No 2FA on n8n accounts

### Implemented Security Measures

**✅ Currently Active:**
- HTTPS-only access (HTTP disabled)
- TLS encryption in transit
- Diagnostics/telemetry disabled
- Pod security contexts (non-root, drop capabilities)
- Read-only root filesystem where possible
- Resource limits on all pods
- No external npm packages allowed in n8n

### Production Hardening Checklist

For production deployment, implement:

1. **Secrets Management:**
   - [ ] Use SOPS for encrypting secrets in Git
   - [ ] Move PostgreSQL password to Kubernetes Secret
   - [ ] Use external secret manager (Vault, AWS Secrets Manager)

2. **TLS Certificates:**
   - [ ] Obtain real domain name
   - [ ] Configure DNS A records
   - [ ] Switch to Let's Encrypt production issuer
   - [ ] Enable HSTS headers

3. **Network Security:**
   - [ ] Implement NetworkPolicies
   - [ ] Restrict egress traffic
   - [ ] Configure webhook authentication
   - [ ] Enable Traefik access logs for auditing

4. **Authentication:**
   - [ ] Enable 2FA for all n8n users
   - [ ] Implement SSO/LDAP if needed
   - [ ] Use strong passwords (password manager)

5. **Backup & DR:**
   - [ ] Automate PostgreSQL backups
   - [ ] Test restore procedures
   - [ ] Backup PVC snapshots
   - [ ] Document recovery procedures

6. **Monitoring:**
   - [ ] Deploy Prometheus + Grafana
   - [ ] Configure alerts for pod crashes
   - [ ] Monitor storage usage
   - [ ] Track execution failures

---

## Cluster Management

### Accessing the Cluster

**Kubernetes (kubectl):**
```bash
# Config location
~/.kube/config

# Verify access
kubectl get nodes
kubectl get pods -A

# Current context
kubectl config current-context
```

**Talos (talosctl):**
```bash
# Config location
~/.talos-secrets/automation/talosconfig

# Set config
export TALOSCONFIG=~/.talos-secrets/automation/talosconfig

# Configure endpoints (control plane only)
talosctl config endpoint 192.168.1.11 192.168.1.12 192.168.1.13

# Check cluster status
talosctl -n 192.168.1.11 health
talosctl get members
```

### Common Operations

**Check Cluster Health:**
```bash
# Node status
kubectl get nodes

# All pods
kubectl get pods -A

# Storage
kubectl get pvc -A
kubectl get storageclass

# Ingress
kubectl get ingress -A
```

**Check n8n Status:**
```bash
# Pods
kubectl get pods -n n8n

# Logs
kubectl logs -n n8n -l app.kubernetes.io/component=main -f
kubectl logs -n n8n -l app.kubernetes.io/name=postgresql -f

# Database health
kubectl exec -n n8n n8n-postgresql-0 -- sh -c \
  'PGPASSWORD=n8n-postgresql-password psql -U n8n -d n8n -c "SELECT 1"'

# PVC status
kubectl get pvc -n n8n
```

**Restart Services:**
```bash
# Restart n8n
kubectl rollout restart deployment/n8n -n n8n

# Restart PostgreSQL
kubectl rollout restart statefulset/n8n-postgresql -n n8n

# Restart Traefik
kubectl rollout restart deployment/traefik -n traefik
```

**Upgrade Components:**
```bash
# Update Helm repos
helm repo update

# Upgrade n8n
helm upgrade n8n community-charts/n8n \
  --namespace n8n \
  --values kubernetes/apps/n8n/values.yaml

# Upgrade Traefik
helm upgrade traefik traefik/traefik \
  --namespace traefik \
  --values kubernetes/core/traefik/values.yaml

# Upgrade cert-manager
helm upgrade cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --values kubernetes/core/cert-manager/values.yaml
```

**Backup PostgreSQL:**
```bash
# Create backup
kubectl exec -n n8n n8n-postgresql-0 -- sh -c \
  'PGPASSWORD=n8n-postgresql-password pg_dump -U n8n -d n8n' \
  > n8n-backup-$(date +%Y%m%d-%H%M%S).sql

# Verify backup
ls -lh n8n-backup-*.sql
```

**Restore PostgreSQL:**
```bash
# Copy backup to pod
kubectl cp ./n8n-backup.sql n8n/n8n-postgresql-0:/tmp/

# Restore
kubectl exec -n n8n n8n-postgresql-0 -- sh -c \
  'PGPASSWORD=n8n-postgresql-password psql -U n8n -d n8n -f /tmp/n8n-backup.sql'

# Restart n8n
kubectl rollout restart deployment/n8n -n n8n
```

---

## Troubleshooting

### Common Issues

**1. Node Not Ready**
```bash
# Check node status
kubectl describe node <node-name>

# Check Talos services
talosctl -n <node-ip> services

# View logs
talosctl -n <node-ip> logs kubelet
```

**2. Pod Stuck in Pending**
```bash
# Check PVC binding
kubectl get pvc -A

# Check events
kubectl describe pod <pod-name> -n <namespace>

# Check storage provisioner
kubectl get pods -n local-path-storage
```

**3. Pod CrashLoopBackOff**
```bash
# Check logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# Check resource limits
kubectl describe pod <pod-name> -n <namespace>

# Check probes (especially initial delays)
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 10 probe
```

**4. Ingress Returns 404**
```bash
# Check ingress configuration
kubectl describe ingress <name> -n <namespace>

# Check Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik -f

# Test with Host header
curl -H "Host: n8n.local" http://192.168.1.11:30080/

# Test service directly
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://<service-name>.<namespace>.svc.cluster.local:<port>/
```

**5. Storage Issues**
```bash
# Check disk on node .11
talosctl -n 192.168.1.11 get disks

# Check mount
talosctl -n 192.168.1.11 list /var/mnt/storage

# Check volume status
kubectl get pv
kubectl get pvc -A

# Check provisioner logs
kubectl logs -n local-path-storage -l app=local-path-provisioner
```

**6. etcd Issues**
```bash
# Check etcd members
talosctl -n 192.168.1.11 etcd members

# Check etcd health
talosctl -n 192.168.1.11 service etcd status

# Remove failed member
talosctl -n <healthy-node> etcd remove-member <member-id>
```

### Emergency Procedures

**Complete Cluster Rebuild:**
See [docs/02-cluster-rebuild.md](./docs/02-cluster-rebuild.md)

**Node Replacement:**
1. Cordon and drain node: `kubectl drain <node> --ignore-daemonsets`
2. Remove from cluster: `kubectl delete node <node>`
3. Wipe and reinstall Talos on hardware
4. Bootstrap/join cluster
5. Uncordon: `kubectl uncordon <node>`

**Data Recovery:**
1. PVCs are retained even after Helm uninstall (due to `helm.sh/resource-policy: keep`)
2. PostgreSQL backups should be automated and stored off-cluster
3. External SSD can be mounted on another system for manual recovery
4. n8n workflows can be exported via UI before major changes

---

## Resource Usage

### Current Allocation

**Per Node (Raspberry Pi 4 - 8GB RAM):**
- Total: 8GB RAM / 4 CPU cores
- System Reserved: ~500Mi RAM / 0.5 CPU
- Available: ~7.5GB RAM / 3.5 CPU per node

**Cluster Total:**
- Total: 32GB RAM / 16 CPU cores
- System: ~2GB RAM / 2 CPU
- Available: ~30GB RAM / 14 CPU

### Application Resource Usage

**Core Services:**
- Local Path Provisioner: 50m CPU / 64Mi RAM
- Traefik (2 pods): 200m CPU / 256Mi RAM
- cert-manager (3 pods): 30m CPU / 96Mi RAM
- **Total Core**: ~280m CPU / 416Mi RAM

**n8n Application:**
- n8n: 100-1000m CPU / 256Mi-1Gi RAM
- PostgreSQL: 100-500m CPU / 256-512Mi RAM
- **Total n8n**: 200-1500m CPU / 512Mi-1.5Gi RAM

**Storage Usage:**
- n8n data: 10Gi allocated (~2Gi used initially)
- PostgreSQL: 20Gi allocated (~5Gi used initially)
- **Total**: ~30Gi on external SSD

### Headroom

**Available for Additional Workloads:**
- CPU: ~12 CPU cores
- RAM: ~28GB
- Storage: ~970GB on external SSD

**Recommended Limits:**
- Don't exceed 80% node capacity (leave buffer for spikes)
- Monitor storage growth (database, executions, logs)

---

## Change Log

### 2025-10-06 - Initial Baseline

**Cluster Established:**
- Talos v1.11.2 installed on 4 Raspberry Pi 4 nodes
- 3 control plane + 1 worker topology
- Custom image with PoE HAT fan control

**Core Services Deployed:**
- Local Path Provisioner v0.0.30 (1TB SSD on node .11)
- Traefik v3.2.2 ingress controller
- cert-manager v1.16.2

**Applications Deployed:**
- n8n v1.113.3 with PostgreSQL
- HTTPS-only access with self-signed certificate
- Accessible at https://192.168.1.11:30443/

**Configuration Decisions:**
- Single external drive (no distributed storage)
- Simple auth for development (not production-hardened)
- Self-signed cert (no Let's Encrypt - using .local domain)
- HTTP disabled for security

---

## Documentation

**Complete Documentation Set:**
- [00 - Network Planning](./docs/00-network-plan.md)
- [01 - Prerequisites](./docs/01-prerequisites.md)
- [02 - Cluster Rebuild](./docs/02-cluster-rebuild.md)
- [03 - Storage (Local Path Provisioner)](./docs/03-storage-local-path.md)
- [04 - PoE HAT Configuration](./docs/04-poe-hat-configuration.md)
- [05 - Ingress (Traefik)](./docs/05-ingress-traefik.md)
- [06 - cert-manager](./docs/06-cert-manager.md)
- [07 - n8n Deployment](./docs/07-n8n-deployment.md)
- [Security Remediation](./SECURITY-REMEDIATION.md)
- [Roadmap](./ROADMAP.md)

---

## Contact & Support

**Repository**: Local Git repository (not yet pushed to remote)
**Infrastructure as Code**: All configurations in `kubernetes/` directory
**Secrets**: Stored in `~/.talos-secrets/automation/` (excluded from Git)

**For Issues:**
1. Check logs: `kubectl logs <pod> -n <namespace>`
2. Review events: `kubectl describe pod <pod> -n <namespace>`
3. Consult documentation in `docs/` directory
4. Review troubleshooting sections above

---

**This baseline represents a fully functional Kubernetes cluster ready for workflow automation and agent development with n8n.**
