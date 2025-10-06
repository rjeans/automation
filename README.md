# Talos Kubernetes Cluster for Automation

Production-grade Kubernetes cluster running on Raspberry Pi 4 hardware with Talos Linux, designed for hosting n8n workflow automation and other self-hosted services.

## 🎯 Project Goals

- **Deterministic**: All infrastructure defined as code in Git
- **Secure**: Encrypted secrets, minimal attack surface, automated security updates
- **Production-Ready**: High availability, monitoring, backups, disaster recovery
- **Automation-First**: n8n workflow platform for building automation agents

## 📋 Quick Start

1. **Read the Roadmap**: [ROADMAP.md](./ROADMAP.md)
2. **Network Planning**: [docs/00-network-plan.md](./docs/00-network-plan.md)
3. **Prerequisites**: [docs/01-prerequisites.md](./docs/01-prerequisites.md)
4. **Install Talos**: [docs/02-talos-installation.md](./docs/02-talos-installation.md)
5. **Core Services**: [docs/03-core-services.md](./docs/03-core-services.md) *(coming soon)*

## 🏗️ Architecture

### Hardware
- 4x Raspberry Pi 4 (8GB RAM)
- 2x Control Plane nodes (etcd + Kubernetes API)
- 2x Worker nodes

### Software Stack
- **OS**: Talos Linux (immutable, API-driven)
- **Orchestration**: Kubernetes
- **GitOps**: FluxCD or ArgoCD
- **Storage**: Longhorn or Rook-Ceph
- **Ingress**: Traefik or NGINX
- **Certificates**: cert-manager
- **Monitoring**: Prometheus, Grafana, Loki
- **Automation**: n8n

## 📁 Repository Structure

```
automation/
├── talos/
│   ├── config/            # Talos machine configurations
│   ├── patches/           # Configuration patches for customization
│   └── secrets/           # Encrypted secrets (SOPS with age)
├── kubernetes/
│   ├── core/              # Core cluster services (CNI, storage, ingress)
│   ├── apps/              # Application deployments
│   └── n8n/               # n8n workflow automation platform
├── terraform/             # Future: cloud resource provisioning
├── docs/                  # Documentation
│   ├── 01-prerequisites.md
│   ├── 02-talos-installation.md
│   ├── network-plan.md
│   └── ...
├── scripts/               # Automation and helper scripts
├── ROADMAP.md            # Project roadmap and phases
└── README.md             # This file
```

## 🔐 Security

### Secrets Management
- All secrets encrypted with [SOPS](https://github.com/mozilla/sops) and [age](https://github.com/FiloSottile/age)
- Encryption key stored outside repository
- Only encrypted files (`.enc.yaml`) committed to Git

### Decrypt Secrets
```bash
# Set age key location
export SOPS_AGE_KEY_FILE=~/path/to/age.key

# Decrypt a file
sops -d talos/secrets/secrets.enc.yaml > talos/secrets/secrets.yaml

# Edit encrypted file directly
sops talos/secrets/secrets.enc.yaml
```

### Encrypt New Secrets
```bash
# Encrypt a file
sops -e secrets.yaml > secrets.enc.yaml
```

## 🚀 Common Operations

### Access Cluster
```bash
# Set talosconfig
export TALOSCONFIG=$(pwd)/talos/config/talosconfig

# Get kubeconfig
talosctl kubeconfig --nodes 192.168.1.101

# Use kubectl
kubectl get nodes
```

### Check Cluster Health
```bash
# Talos health check
talosctl health

# Kubernetes status
kubectl get nodes
kubectl get pods -A
```

### Update Node Configuration
```bash
# Edit and apply configuration
talosctl apply-config --nodes <node-ip> --file talos/config/controlplane.yaml
```

### View Logs
```bash
# Talos system logs
talosctl logs -f -n <node-ip> kubelet

# Kubernetes pod logs
kubectl logs -f -n kube-system <pod-name>
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
- n8n workflows (exported daily)
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
- [02 - Talos Installation](./docs/02-talos-installation.md) - Cluster installation guide
- More docs coming as we progress through iterations

## 🛠️ Tools Required

- `talosctl` - Talos Linux management
- `kubectl` - Kubernetes management
- `sops` - Secrets encryption
- `age` - Encryption key management
- `helm` - Kubernetes package manager *(coming soon)*
- `flux` or `argocd` - GitOps *(coming soon)*

## 🤝 Contributing

This is a personal infrastructure project, but feel free to use it as reference or suggest improvements via issues.

## 📝 License

This project is for personal use. Use at your own risk.

## 🔗 Resources

- [Talos Linux Documentation](https://www.talos.dev/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [n8n Documentation](https://docs.n8n.io/)
- [SOPS Documentation](https://github.com/mozilla/sops)
- [FluxCD Documentation](https://fluxcd.io/)

## 📈 Current Status

**Iteration**: 1 - Foundation
**Last Updated**: 2025-10-06

- ✅ Repository structure created
- ✅ Documentation started
- ⬜ Talos installed on hardware
- ⬜ Cluster bootstrapped
- ⬜ Core services deployed
- ⬜ n8n deployed

See [ROADMAP.md](./ROADMAP.md) for detailed progress.
