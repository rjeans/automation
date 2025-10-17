# Talos Kubernetes Cluster Roadmap

## Project Overview
Build a production-grade Kubernetes cluster on 4 Raspberry Pis running Talos Linux, with n8n deployed for workflow automation. All infrastructure managed as code in this Git repository.

## Core Principles
- **Deterministic**: All configurations version-controlled and reproducible
- **Secure**: Encryption, secrets management, minimal attack surface
- **Production-Ready**: HA, monitoring, backups, disaster recovery

---

## Phase 0: Planning & Prerequisites

### Hardware Requirements
- **4x Raspberry Pi 4** (8GB RAM recommended)
- **4x microSD cards** (32GB+ Class 10/U3 or better)
- **Network switch** with gigabit Ethernet ports
- **Power supplies** for all Raspberry Pis
- **Ethernet cables**

### Pre-Installation Tasks
- [ ] Update Raspberry Pi EEPROM firmware (using Raspberry Pi Imager)
- [ ] Label Pis (e.g., rpi-cp01, rpi-cp02, rpi-worker01, rpi-worker02)
- [ ] Plan static IP addresses for all nodes
- [ ] Install `talosctl` CLI on management machine

### Repository Structure
```
automation/
├── talos/
│   ├── config/            # Talos machine configurations
│   ├── patches/           # Configuration patches
│   └── secrets/           # Encrypted secrets (SOPS)
├── kubernetes/
│   ├── core/              # Core cluster services (ingress, storage, etc.)
│   ├── apps/              # Application deployments
│   └── n8n/               # n8n specific manifests
├── terraform/             # Future: cloud resource provisioning
├── docs/                  # Documentation
│   ├── installation.md    # Step-by-step installation guide
│   ├── operations.md      # Day-2 operations
│   └── recovery.md        # Disaster recovery procedures
└── scripts/               # Automation scripts
```

---

## Phase 1: Talos Linux Installation

### 1.1 Preparation
- [ ] Download Talos ARM64 disk image
- [ ] Flash all microSD cards with Talos image
- [ ] Document node IP addresses and roles
- [ ] Generate Talos machine configurations

### 1.2 Cluster Architecture
**Control Plane Nodes** (1-2 nodes):
- Run etcd + Kubernetes control plane components
- Can also run workloads if needed

**Worker Nodes** (2-3 nodes):
- Dedicated to running application workloads

**Recommended Split** (4 nodes):
- 2 control plane nodes (HA for control plane)
- 2 worker nodes

### 1.3 Security Configuration
- [ ] Generate cluster secrets with `talosctl gen secrets`
- [ ] Enable etcd encryption at rest
- [ ] Configure pod security standards
- [ ] Plan certificate rotation strategy
- [ ] Create SOPS encryption keys for secrets in Git

### 1.4 Bootstrap Process
- [ ] Apply control plane configurations
- [ ] Bootstrap etcd on first control plane node
- [ ] Apply worker node configurations
- [ ] Verify all nodes join cluster
- [ ] Configure `kubectl` access
- [ ] Test cluster connectivity

---

## Phase 2: Cluster Bootstrap & Core Services

### 2.1 Networking
**CNI Plugin**: Cilium (recommended) or Flannel
- [ ] Deploy CNI plugin
- [ ] Verify pod-to-pod connectivity
- [ ] Configure network policies support

### 2.2 Storage
**Options**: Longhorn (simpler) or Rook-Ceph (more features)
- [ ] Deploy storage solution
- [ ] Create default StorageClass
- [ ] Test PVC provisioning
- [ ] Configure automated backups

### 2.3 Ingress & TLS
- [x] Deploy ingress controller (Traefik)
- [x] Configure Cloudflare Tunnel for external TLS (replaces cert-manager)
- [x] Test TLS termination at Cloudflare edge
- [x] Simplified ingress (removed cert-manager complexity)

### 2.4 GitOps Setup ✅ COMPLETE
**Using FluxCD for declarative cluster management**

See implementation details: [docs/GITOPS-IMPLEMENTATION-SUMMARY.md](./docs/GITOPS-IMPLEMENTATION-SUMMARY.md)
Guides: [ROADMAP](./docs/GITOPS-ROADMAP.md) | [QUICKSTART](./docs/GITOPS-QUICKSTART.md) | [ARCHITECTURE](./docs/GITOPS-ARCHITECTURE.md)

- [x] Install Flux with GitHub bootstrap
- [x] Define Helm repository sources (Traefik, Metrics Server, n8n)
- [x] Migrate Traefik to Flux management (HelmRelease v33.2.1)
- [x] Migrate Metrics Server to Flux management (HelmRelease v3.13.0)
- [x] Migrate Cloudflare Tunnel to Flux management (Kustomization)
- [x] Migrate n8n to Flux management (HelmRelease v1.15.12)
- [x] Migrate cluster-dashboard to Flux management (Kustomization)
- [x] Add dashboard.monitor labels to all components
- [x] Test GitOps workflow (label additions applied automatically)
- [ ] Set up SOPS for secrets encryption
- [ ] Configure Slack notifications
- [ ] Test complete cluster rebuild from Git

---

## Phase 3: Security & Observability

### 3.1 Security Hardening
- [ ] Implement RBAC policies
- [ ] Apply pod security standards
- [ ] Deploy network policies
- [ ] Set up secrets management (Sealed Secrets or External Secrets Operator)
- [ ] Configure SOPS for encrypting secrets in Git
- [ ] Enable audit logging
- [ ] Configure resource quotas and limits

### 3.2 Monitoring Stack
**Components**:
- Prometheus (metrics collection)
- Grafana (visualization)
- Loki (log aggregation)
- Alertmanager (alerting)

**Tasks**:
- [ ] Deploy kube-prometheus-stack
- [ ] Configure Grafana dashboards
- [ ] Set up Loki for log aggregation
- [ ] Create alert rules
- [ ] Configure notification channels (email/Slack/etc.)
- [ ] Add Talos-specific metrics

### 3.3 Backup Strategy
- [ ] Deploy Velero for cluster backups
- [ ] Configure etcd snapshot automation
- [ ] Set up backup storage location
- [ ] Document backup schedule
- [ ] Test restore procedures

---

## Phase 4: n8n Deployment

### 4.1 Database Setup
- [ ] Deploy PostgreSQL with Helm
- [ ] Configure persistent storage
- [ ] Set up automated backups
- [ ] Create database and user for n8n
- [ ] Store credentials in secrets

### 4.2 Redis (Optional but Recommended)
- [ ] Deploy Redis for queue management
- [ ] Configure persistence
- [ ] Test connectivity

### 4.3 n8n Installation
**Using 8gears Helm Chart**:
- [x] Add n8n Helm repository
- [x] Create custom values file
- [x] Configure database connection
- [x] Set up persistent storage for workflows
- [x] Deploy n8n with Helm
- [x] Configure ingress with Cloudflare Tunnel
- [x] Test web UI access at https://n8n.jeansy.org

### 4.4 n8n Production Configuration
- [ ] Generate and store encryption key
- [ ] Configure webhook endpoints
- [ ] Set up scaling (main app, workers, webhooks)
- [ ] Configure resource limits and requests
- [ ] Enable external service integrations
- [ ] Test workflow execution

### 4.5 n8n Backup
- [ ] Configure workflow export automation
- [ ] Set up PostgreSQL backup schedule
- [ ] Document restore procedures
- [ ] Test workflow import

---

## Phase 5: Backup & Disaster Recovery

### 5.1 Backup Automation
- [ ] Talos configuration backups to Git
- [ ] Scheduled etcd snapshots
- [ ] Velero backup schedules for PVCs
- [ ] PostgreSQL automated dumps
- [ ] n8n workflow exports
- [ ] Off-site backup copies

### 5.2 Recovery Documentation
- [ ] Document complete cluster rebuild process
- [ ] Create runbook for common failures
- [ ] Test etcd restore procedure
- [ ] Test application data restore
- [ ] Verify RTO/RPO targets
- [ ] Maintain offline copies of critical configs

### 5.3 Disaster Recovery Testing
- [ ] Simulate node failure
- [ ] Test control plane HA
- [ ] Simulate complete cluster loss
- [ ] Time recovery procedures
- [ ] Update documentation based on tests

---

## Implementation Timeline

### **Iteration 1: Foundation** (1-2 days)
- Set up Git repository structure
- Install Talos on all Raspberry Pis
- Bootstrap basic Kubernetes cluster
- Verify cluster connectivity and health

### **Iteration 2: Core Infrastructure** (2-3 days)
- Deploy CNI and persistent storage
- Set up ingress controller and Cloudflare Tunnel
- Implement GitOps (FluxCD or ArgoCD)
- Migrate infrastructure to GitOps management

### **Iteration 3: Security & Observability** (1-2 days)
- Configure SOPS for secrets encryption
- Deploy monitoring stack (Prometheus, Grafana, Loki)
- Implement network policies
- Set up backup automation

### **Iteration 4: n8n Deployment** (1-2 days)
- Deploy PostgreSQL database
- Install n8n via Helm
- Configure production settings
- Create first automation workflows

### **Iteration 5: Hardening & Documentation** (1 day)
- Perform disaster recovery testing
- Complete all documentation
- Performance tuning and optimization
- Security audit and hardening review

---

## Best Practices Checklist

### Deterministic & Reproducible
- ✅ All configurations stored in Git
- ✅ Talos immutable OS (API-driven, no SSH)
- ✅ GitOps for declarative deployments
- ✅ Version-pinned Helm charts and container images
- ✅ Documented procedures for all operations

### Security
- ✅ Secrets encrypted in Git (SOPS)
- ✅ TLS everywhere (Cloudflare Tunnel)
- ✅ Network segmentation (NetworkPolicies)
- ✅ RBAC and pod security standards
- ✅ Minimal attack surface (Talos Linux)
- ✅ Regular automated security updates
- ✅ Audit logging enabled

### Production-Ready
- ✅ High availability (multi-node control plane)
- ✅ Comprehensive monitoring and alerting
- ✅ Automated backup procedures
- ✅ Tested disaster recovery plan
- ✅ Resource management and limits
- ✅ Documentation for all procedures

---

## Success Criteria

- [ ] Cluster survives node failures without downtime
- [ ] All infrastructure managed via Git
- [ ] Automated deployments working via GitOps
- [ ] Monitoring and alerting functional
- [ ] Backups tested and verified
- [ ] n8n running and accessible via HTTPS
- [ ] Complete documentation for operations and recovery
- [ ] Security hardening measures in place

---

## Future Enhancements

- Multi-cluster federation
- External cloud integration
- Advanced n8n workflows and integrations
- CI/CD pipelines
- Cost monitoring and optimization
- Additional automation tools
