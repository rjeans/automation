# Ingress Setup with Traefik

> **⚠️ DEPLOYMENT METHOD CHANGED**
>
> **Traefik is now managed by Flux GitOps** - This guide is for reference only.
>
> **Current deployment method**: See [GITOPS-QUICKSTART.md](GITOPS-QUICKSTART.md)
>
> **Configuration location**: `flux/clusters/talos/infrastructure/traefik/`
>
> **To modify Traefik**:
> 1. Edit `flux/clusters/talos/infrastructure/traefik/values-configmap.yaml`
> 2. Commit and push to Git
> 3. Flux automatically applies changes within 1 minute
>
> **Manual deployment is no longer recommended**

## Overview

Traefik is a modern HTTP reverse proxy and load balancer. This setup uses NodePort for external access, suitable for home lab environments.

## Architecture

- **Deployment**: 2 replicas for high availability
- **Service Type**: NodePort (ports 30080/30443)
- **Access**: `http://<any-node-ip>:30080` or `https://<any-node-ip>:30443`
- **Dashboard**: Available via IngressRoute at `traefik.local`
- **Management**: Flux HelmRelease (GitOps)

## Current Deployment (GitOps)

### Check Traefik Status

```bash
# Check Flux HelmRelease
flux get helmrelease traefik -n traefik

# Check pods
kubectl get pods -n traefik

# Check service
kubectl get svc -n traefik

# View configuration
kubectl get configmap -n traefik traefik-values -o yaml
```

### Modify Traefik Configuration

```bash
# Edit the values ConfigMap in Git
vim flux/clusters/talos/infrastructure/traefik/values-configmap.yaml

# Commit and push
git add flux/clusters/talos/infrastructure/traefik/values-configmap.yaml
git commit -m "feat: Update Traefik configuration"
git push

# Flux will automatically apply changes
# Watch reconciliation
flux logs --follow --level=info
```

## Legacy Installation (Not Recommended)

### Prerequisites

- Helm installed
- Kubernetes cluster running
- kubectl configured

### Deploy Traefik Manually (Legacy - Do Not Use)

```bash
# ⚠️ This method is deprecated - use Flux instead

# Add Traefik Helm repository
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Create namespace
kubectl create namespace traefik

# Install Traefik
helm install traefik traefik/traefik \
  --namespace traefik \
  --values kubernetes/core/traefik/values.yaml \
  --version 33.2.1
```

**Note**: This manual method bypasses GitOps and is not recommended. Changes made manually will be reverted by Flux.

### Verify Installation

```bash
# Check pods
kubectl -n traefik get pods

# Check service
kubectl -n traefik get svc

# Expected output: 2 pods Running, NodePort service on 30080/30443
```

## Configuration

The configuration is stored in `kubernetes/core/traefik/values.yaml`.

### Key Settings

- **Replicas**: 2 (HA across control plane nodes)
- **Node Ports**:
  - HTTP: 30080
  - HTTPS: 30443
- **Resources**: Optimized for Raspberry Pi (100m CPU, 128Mi RAM)
- **Tolerations**: Can run on control plane nodes
- **Security**: PodSecurityContext configured for restricted mode

## Usage

### Creating an Ingress

**Option 1: IngressRoute (Traefik CRD - Recommended)**

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
  namespace: my-namespace
spec:
  entryPoints:
    - web  # HTTP
  routes:
  - match: Host(`myapp.local`)
    kind: Rule
    services:
    - name: my-app-service
      port: 80
```

**Option 2: Standard Kubernetes Ingress**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: my-namespace
spec:
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app-service
            port:
              number: 80
```

### Accessing Services

1. **Via Node IP**: `http://192.168.1.11:30080` (or any node IP)
2. **With Host Header**: `curl -H "Host: myapp.local" http://192.168.1.11:30080`
3. **DNS Setup** (optional): Add entries to your router/DNS for cleaner URLs

### Example Application

```bash
# Deploy test app
kubectl create deployment whoami --image=traefik/whoami
kubectl expose deployment whoami --port=80

# Create IngressRoute
kubectl apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: whoami
spec:
  entryPoints:
    - web
  routes:
  - match: Host(\`whoami.local\`)
    kind: Rule
    services:
    - name: whoami
      port: 80
EOF

# Test
curl -H "Host: whoami.local" http://192.168.1.11:30080
```

## Accessing Traefik Dashboard

The dashboard is enabled and accessible via IngressRoute:

```bash
# Access via curl
curl -H "Host: traefik.local" http://192.168.1.11:30080/dashboard/

# Or add to /etc/hosts
echo "192.168.1.11 traefik.local" | sudo tee -a /etc/hosts

# Then visit http://traefik.local:30080/dashboard/
```

## Upgrading Traefik

### GitOps Method (Recommended)

```bash
# Edit HelmRelease to change version
vim flux/clusters/talos/infrastructure/traefik/helmrelease.yaml

# Change version:
# spec:
#   chart:
#     spec:
#       version: "33.3.0"  # New version

# Commit and push
git add flux/clusters/talos/infrastructure/traefik/helmrelease.yaml
git commit -m "feat: Upgrade Traefik to v33.3.0"
git push

# Flux will automatically upgrade
flux get helmrelease traefik -n traefik --watch
```

### Legacy Manual Method (Not Recommended)

```bash
# ⚠️ This method is deprecated - use Flux instead

# Update values if needed
vim kubernetes/core/traefik/values.yaml

# Upgrade
helm upgrade traefik traefik/traefik \
  --namespace traefik \
  --values kubernetes/core/traefik/values.yaml \
  --version 33.2.1
```

## Adding TLS/HTTPS

TLS will be configured later with cert-manager. For now, you can:

1. **Self-Signed Certificates**: Create manually and add to Traefik
2. **cert-manager**: Deploy in next phase for automatic Let's Encrypt certificates

## Troubleshooting

### Pods Not Ready

```bash
# Check logs
kubectl -n traefik logs -l app.kubernetes.io/name=traefik

# Common issues:
# - Health check failures: Verify ping endpoint configuration
# - Resource constraints: Check node resources
```

### Cannot Access Services

```bash
# Verify IngressRoute
kubectl get ingressroute -A

# Check Traefik service
kubectl -n traefik get svc

# Test with curl
curl -v -H "Host: myapp.local" http://192.168.1.11:30080
```

### 404 Errors

- Verify Host header matches IngressRoute
- Check service name and port in IngressRoute
- Ensure backend pods are running

## Uninstalling

```bash
# Delete Traefik
helm uninstall traefik -n traefik

# Delete namespace
kubectl delete namespace traefik

# Delete CRDs (if needed)
kubectl delete crd $(kubectl get crd | grep traefik | awk '{print $1}')
```

## Next Steps

With Traefik deployed:

1. **Deploy cert-manager** - Automatic TLS certificates
2. **Deploy n8n** - With ingress for web access
3. **Optional**: Deploy MetalLB for LoadBalancer support (instead of NodePort)

---

**Traefik is Ready!** ✅

Access your cluster via:
- HTTP: `http://<node-ip>:30080`
- HTTPS: `https://<node-ip>:30443`
- Dashboard: `http://traefik.local:30080/dashboard/`

**Last Updated**: 2025-10-06
**Traefik Version**: v3.2.2
**Helm Chart**: 33.2.1
