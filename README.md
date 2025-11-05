# Talos Kubernetes Cluster for Automation

Production-grade Kubernetes cluster running on Raspberry Pi 4 hardware with Talos Linux, designed for self-hosted services and automation workloads.

## 🎯 Project Goals

- **Deterministic**: All infrastructure defined as code in Git
- **Secure**: Encrypted secrets, minimal attack surface, automated security updates
- **Production-Ready**: High availability, monitoring, backups, disaster recovery
- **Automation-Ready**: Platform for deploying workflow automation and custom services

## 📋 Quick Start

1. **Read the Roadmap**: [ROADMAP.md](./ROADMAP.md)
2. **Network Planning**: [docs/00-network-plan.md](./docs/00-network-plan.md)
3. **Prerequisites**: [docs/01-prerequisites.md](./docs/01-prerequisites.md)
4. **Build/Rebuild Cluster**: [docs/02-cluster-rebuild.md](./docs/02-cluster-rebuild.md)
5. **Core Services**:
   - [Storage (Local Path Provisioner)](./docs/03-storage-local-path.md)
   - [Ingress (Traefik)](./docs/05-ingress-traefik.md)
   - [TLS Certificates (cert-manager)](./docs/06-cert-manager.md)
6. **Applications**: Deploy as needed via GitOps

## 🏗️ Architecture

### Hardware
- 4x Raspberry Pi 4 (8GB RAM)
- 3x Control Plane nodes (192.168.1.11, .12, .13) - etcd + Kubernetes API
- 1x Worker node (192.168.1.14)

### Software Stack
- **OS**: Talos Linux v1.11.3 (immutable, API-driven)
- **Orchestration**: Kubernetes v1.31.2
- **GitOps**: Flux CD ✅
- **Storage**: Local Path Provisioner ✅
- **Ingress**: Traefik ✅
- **External Access**: Cloudflare Tunnel ✅
- **Monitoring**: Prometheus + Grafana ✅, Cluster Dashboard ✅

## 📁 Repository Structure

```
automation/
├── flux/                  # ⚡ GitOps - Source of Truth for cluster state
│   └── clusters/talos/
│       ├── flux-system/   # Flux controllers
│       ├── sources/       # Helm repositories, Git sources
│       ├── infrastructure/# Core services (Traefik, Metrics Server, Cloudflare)
│       └── apps/          # Applications (cluster-dashboard, etc.)
│
├── kubernetes/            # 📁 Reference and development (see kubernetes/README.md)
│   ├── core/              # Original manifests (archived, not used by Flux)
│   └── apps/
│       └── cluster-dashboard/  # cluster-dashboard configs
│           ├── app/       # 🔧 Go application source code
│           └── chart/     # Helm chart (reference)
│
├── talos/                 # Talos machine configurations
│   ├── config/            # Machine configs (stored locally for security)
│   └── patches/           # Configuration patches
│
├── docs/                  # 📚 Documentation
│   ├── GITOPS-*.md        # GitOps implementation guides
│   ├── 00-07-*.md         # Setup guides
│   └── ...
│
├── ROADMAP.md             # Project roadmap and status
└── README.md              # This file
```

**⚠️ Important**: All cluster resources are managed by Flux from `flux/clusters/talos/`.
The `kubernetes/` directory is kept for reference only. See [kubernetes/README.md](./kubernetes/README.md).

## 🔐 Security

### Secrets Management (Personal Use)
- **All secrets stored locally** in `~/.talos-secrets/automation/`
- **NOT in git repository** - maximum security
- Protected by filesystem permissions (600)
- Full disk encryption (FileVault/BitLocker) for additional security
- Regular backups to encrypted external drive

### Secret Files Location
```
~/.talos-secrets/automation/
├── secrets.yaml          # Cluster secrets
├── controlplane.yaml     # Control plane config
├── worker.yaml           # Worker config
└── talosconfig           # Client certificates
```

**Why local-only?**
- No team access needed
- Simpler than encryption
- Filesystem permissions sufficient
- Backed up separately from git

## 🚀 Common Operations

### GitOps Workflow (Primary Method)
```bash
# Make changes to manifests
vim flux/clusters/talos/apps/cluster-dashboard/helmrelease.yaml

# Commit and push
git add flux/
git commit -m "Update cluster configuration"
git push

# Flux automatically applies within 1 minute!
# Or force immediate reconciliation:
flux reconcile kustomization flux-system --with-source
```

### Check Cluster Health
```bash
# Flux status (all resources managed by GitOps)
flux get all -A

# Kubernetes status
kubectl get nodes
kubectl get pods -A

# Talos health check
export TALOSCONFIG=~/.talos-secrets/automation/talosconfig
talosctl health
```

### View Logs
```bash
# Flux logs (see GitOps activity)
flux logs --all-namespaces --follow

# Application logs
kubectl logs -f -n monitoring deployment/kube-prometheus-stack-grafana

# Talos system logs
talosctl logs -f -n <node-ip> kubelet
```

## 📊 Monitoring

Once monitoring is deployed (Phase 3):

- **Grafana**: https://grafana.yourdomain.com
- **Prometheus**: https://prometheus.yourdomain.com
- **AlertManager**: Configured for critical alerts

## 🔄 Backup & Recovery

### Automated Backups
- etcd snapshots (hourly)
- Persistent volumes (Velero, daily)
- Application data (exported as needed)
- PostgreSQL dumps (daily)

### Manual Backup
```bash
# etcd snapshot
talosctl -n <control-plane-node> etcd snapshot /tmp/etcd-snapshot.db

# Retrieve snapshot
talosctl -n <control-plane-node> copy /tmp/etcd-snapshot.db ./
```

### Recovery
See [docs/recovery.md](./docs/recovery.md) *(coming soon)*

## 🧪 Development Workflow

### Making Changes
1. Create feature branch
2. Update infrastructure code
3. Test in staging (if available)
4. Commit encrypted configs
5. Push and create PR
6. GitOps auto-deploys on merge

### Testing Configuration
```bash
# Validate Talos config
talosctl validate --config talos/config/controlplane.yaml

# Validate Kubernetes manifests
kubectl apply --dry-run=client -f kubernetes/apps/

# Validate Helm values
helm template my-release chart/ -f values.yaml
```

## 📚 Documentation

- [Roadmap](./ROADMAP.md) - Project phases and timeline
- [00 - Network Planning](./docs/00-network-plan.md) - IP addressing and network setup
- [01 - Prerequisites](./docs/01-prerequisites.md) - Hardware and software requirements
- [02 - Cluster Rebuild](./docs/02-cluster-rebuild.md) - Build or rebuild cluster (30 min)
- [03 - Storage (Local Path Provisioner)](./docs/03-storage-local-path.md) - Single-node persistent storage
- [04 - PoE HAT Configuration](./docs/04-poe-hat-configuration.md) - Custom Talos image with fan control
- [05 - Ingress (Traefik)](./docs/05-ingress-traefik.md) - HTTP/HTTPS routing and load balancing
- [06 - cert-manager](./docs/06-cert-manager.md) - Automatic TLS certificate management
- [Security Remediation](./SECURITY-REMEDIATION.md) - Security best practices and lessons learned

## 🛠️ Tools Required

- `talosctl` - Talos Linux management
- `kubectl` - Kubernetes management
- `flux` - GitOps CLI (installed and active)
- `helm` - Kubernetes package manager (optional - Flux manages Helm releases)

## 🤝 Contributing

This is a personal infrastructure project, but feel free to use it as reference or suggest improvements via issues.

## 📝 License

This project is for personal use. Use at your own risk.

## 🔗 Resources

- [Talos Linux Documentation](https://www.talos.dev/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [SOPS Documentation](https://github.com/mozilla/sops)
- [FluxCD Documentation](https://fluxcd.io/)

## 📈 Current Status

**Iteration**: 4 - Applications
**Last Updated**: 2025-10-06

- ✅ Repository structure created
- ✅ Documentation completed
- ✅ Talos installed on hardware
- ✅ Cluster bootstrapped (3 control plane + 1 worker)
- ✅ Core services deployed:
  - ✅ Storage (Local Path Provisioner with 1TB SSD)
  - ✅ Ingress (Traefik v3.2.2)
  - ✅ cert-manager (v1.16.2)
- ✅ Monitoring (Prometheus, Grafana, Alertmanager)

See [ROADMAP.md](./ROADMAP.md) for detailed progress.
