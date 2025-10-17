# Quick Start Guide

Get your Cluster Dashboard up and running in 5 minutes!

## TL;DR

```bash
# 1. Build and push the image
cd kubernetes/apps/cluster-dashboard
make docker-push IMAGE_REGISTRY=ghcr.io/YOUR_USERNAME

# 2. Update values
vim chart/values.yaml  # Change image repo and domain

# 3. Deploy
make helm-install

# 4. Check status
make status

# 5. Access dashboard
# Open: https://dashboard.yourdomain.com
```

## Prerequisites

- Kubernetes cluster with Traefik and cert-manager
- Docker with buildx support
- kubectl configured
- Helm 3.x installed

## Step-by-Step

### 1. Clone and Navigate

```bash
cd kubernetes/apps/cluster-dashboard
```

### 2. Build Docker Image

```bash
# Option A: Using Makefile
make docker-push IMAGE_REGISTRY=ghcr.io/YOUR_USERNAME

# Option B: Manual
cd app
docker buildx build --platform linux/arm64 \
  -t ghcr.io/YOUR_USERNAME/cluster-dashboard:latest \
  --push .
```

### 3. Configure

Edit `chart/values.yaml`:

```yaml
image:
  repository: ghcr.io/YOUR_USERNAME/cluster-dashboard  # ← Change this

ingress:
  hosts:
    - host: dashboard.yourdomain.com  # ← Change this
```

### 4. Deploy

```bash
# Using Helm (recommended)
helm install cluster-dashboard ./chart \
  -n cluster-dashboard \
  --create-namespace

# Or using kubectl
kubectl apply -f .
```

### 5. Verify

```bash
# Check pods
kubectl get pods -n cluster-dashboard

# Check certificate
kubectl get certificate -n cluster-dashboard

# View logs
kubectl logs -n cluster-dashboard -l app.kubernetes.io/name=cluster-dashboard
```

### 6. Access

Open your browser to `https://dashboard.yourdomain.com`

## Common Commands

```bash
# View logs
make logs

# Check status
make status

# Port forward for testing
make port-forward  # Then visit http://localhost:8080

# Upgrade after changes
make helm-upgrade

# Uninstall
make helm-uninstall
```

## Testing Locally

```bash
# Port forward to test without ingress
kubectl port-forward -n cluster-dashboard svc/cluster-dashboard 8080:80

# Access at http://localhost:8080
```

## Troubleshooting

### Pods not starting?

```bash
kubectl describe pod -n cluster-dashboard cluster-dashboard-xxxxx
```

### Certificate issues?

```bash
kubectl describe certificate -n cluster-dashboard
kubectl logs -n cert-manager deploy/cert-manager
```

### Can't access dashboard?

```bash
# Check ingress
kubectl get ingress -n cluster-dashboard -o yaml

# Check Traefik
kubectl logs -n traefik -l app.kubernetes.io/name=traefik
```

## What You Get

Once deployed, the dashboard shows:

- 🔧 **Hardware Status**: All nodes, CPU, memory
- 🐧 **Talos Linux**: Version and service health
- ☸️ **Kubernetes**: Control plane and worker status
- 🚀 **Applications**: Traefik, n8n, cert-manager, Cloudflare

Updates automatically every 30 seconds!

## Next Steps

1. Configure Cloudflare Tunnel for external access
2. Deploy metrics-server for detailed metrics
3. Customize branding and styling
4. Set up monitoring and alerts

## Need Help?

- Read [README.md](README.md) for full documentation
- Check [DEPLOYMENT.md](DEPLOYMENT.md) for detailed deployment guide
- Review Makefile commands with `make help`
