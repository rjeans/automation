#!/bin/bash
set -e

# Backup all cluster secrets
# This script exports Kubernetes secrets and Talos configs to a backup directory

BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${HOME}/cluster-backups/backup-${BACKUP_DATE}"

echo "🔐 Backing up cluster secrets..."
echo "Backup location: ${BACKUP_DIR}"
echo ""

# Create backup directory
mkdir -p "${BACKUP_DIR}/kubernetes-secrets"
mkdir -p "${BACKUP_DIR}/talos-configs"
mkdir -p "${BACKUP_DIR}/github"

# Backup Talos configurations
echo "📦 Backing up Talos configurations..."
if [ -d "${HOME}/.talos-secrets/pi-cluster" ]; then
    cp -r "${HOME}/.talos-secrets/pi-cluster"/* "${BACKUP_DIR}/talos-configs/"
    echo "  ✅ Talos configs backed up"
else
    echo "  ⚠️  Talos secrets directory not found at ~/.talos-secrets/pi-cluster"
fi

# Backup Kubernetes secrets
echo ""
echo "📦 Backing up Kubernetes secrets..."

# cluster-dashboard talos-config secret
if kubectl get secret -n cluster-dashboard talos-config &>/dev/null; then
    kubectl get secret -n cluster-dashboard talos-config -o yaml > "${BACKUP_DIR}/kubernetes-secrets/talos-config-secret.yaml"
    echo "  ✅ cluster-dashboard/talos-config"
else
    echo "  ⚠️  cluster-dashboard/talos-config not found"
fi

# cloudflare-tunnel token secret
if kubectl get secret -n cloudflare-tunnel cloudflare-tunnel-token &>/dev/null; then
    kubectl get secret -n cloudflare-tunnel cloudflare-tunnel-token -o yaml > "${BACKUP_DIR}/kubernetes-secrets/cloudflare-tunnel-token.yaml"
    echo "  ✅ cloudflare-tunnel/cloudflare-tunnel-token"
else
    echo "  ⚠️  cloudflare-tunnel/cloudflare-tunnel-token not found"
fi

# Backup all secrets in monitoring namespace (may contain additional configs)
if kubectl get secrets -n monitoring &>/dev/null; then
    kubectl get secrets -n monitoring -o yaml > "${BACKUP_DIR}/kubernetes-secrets/monitoring-secrets.yaml"
    echo "  ✅ monitoring namespace secrets"
fi

# Prompt for GitHub PAT
echo ""
echo "🔑 GitHub PAT (Personal Access Token)..."
echo "   This is needed to bootstrap Flux during recovery."
echo ""
read -p "   Do you want to save your GitHub PAT? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -s -p "   Enter your GitHub PAT: " GITHUB_PAT
    echo ""
    if [ -n "$GITHUB_PAT" ]; then
        echo "$GITHUB_PAT" > "${BACKUP_DIR}/github/GITHUB_TOKEN.txt"
        chmod 600 "${BACKUP_DIR}/github/GITHUB_TOKEN.txt"
        echo "  ✅ GitHub PAT saved"
    else
        echo "  ⚠️  No PAT entered, skipping"
    fi
else
    cat > "${BACKUP_DIR}/github/README.txt" <<EOF
GitHub PAT not saved during backup.

You will need a GitHub PAT with 'repo' permissions to bootstrap Flux.
Create one at: https://github.com/settings/tokens

When restoring, export it before running flux bootstrap:
export GITHUB_TOKEN=<your-pat>
EOF
    echo "  ⚠️  Skipped - Add PAT manually during recovery"
fi

# Create a README in the backup
cat > "${BACKUP_DIR}/README.md" <<EOF
# Cluster Backup - ${BACKUP_DATE}

## Contents

### Talos Configurations
- talosconfig - CLI credentials for talosctl
- node11.yaml, node12.yaml, node13.yaml, node14.yaml - Node-specific configs
- controlplane.yaml, worker.yaml - Base templates
- secrets.yaml - Cluster secrets and certificates

### Kubernetes Secrets
- talos-config-secret.yaml - Talos API credentials for cluster-dashboard
- cloudflare-tunnel-token.yaml - Cloudflare tunnel authentication
- monitoring-secrets.yaml - Monitoring namespace secrets (if any)

### GitHub
- GITHUB_TOKEN.txt - GitHub PAT for Flux bootstrap (if saved)

## Restore Instructions

### Restore Talos Configs
\`\`\`bash
mkdir -p ~/.talos-secrets/pi-cluster
cp talos-configs/* ~/.talos-secrets/pi-cluster/
chmod 600 ~/.talos-secrets/pi-cluster/*
\`\`\`

### Restore GitHub PAT
\`\`\`bash
# For Flux bootstrap:
export GITHUB_TOKEN=\$(cat github/GITHUB_TOKEN.txt)
# Or manually set: export GITHUB_TOKEN=<your-pat>
\`\`\`

### Restore Kubernetes Secrets
\`\`\`bash
# After cluster is running and Flux has deployed applications:
kubectl apply -f kubernetes-secrets/talos-config-secret.yaml
kubectl apply -f kubernetes-secrets/cloudflare-tunnel-token.yaml
\`\`\`

## Security Notes

⚠️ This backup contains sensitive credentials:
- Talos API certificates
- Kubernetes cluster certificates
- Application secrets
- GitHub Personal Access Token (if saved)

**Store securely:**
- Encrypted external drive
- Password-protected archive
- Secure cloud storage with encryption
- Never commit to git

## Backup Date
Created: ${BACKUP_DATE}
Cluster: pi-cluster
Talos: v1.11.3
Kubernetes: v1.31.2
EOF

# Set restrictive permissions
chmod -R 600 "${BACKUP_DIR}"/*
chmod 700 "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}/kubernetes-secrets"
chmod 700 "${BACKUP_DIR}/talos-configs"
chmod 700 "${BACKUP_DIR}/github"

# Create a summary
echo ""
echo "✅ Backup complete!"
echo ""
echo "📁 Backup location: ${BACKUP_DIR}"
echo "📊 Backup size: $(du -sh "${BACKUP_DIR}" | cut -f1)"
echo ""
echo "🔒 Backup is protected with restricted permissions (700/600)"
echo ""
echo "💡 Next steps:"
echo "   1. Copy to encrypted external drive"
echo "   2. Or create encrypted archive:"
echo "      tar -czf - \"${BACKUP_DIR}\" | gpg -c > cluster-backup-${BACKUP_DATE}.tar.gz.gpg"
echo "   3. Test restore procedure periodically"
echo ""
echo "📝 See ${BACKUP_DIR}/README.md for restore instructions"
