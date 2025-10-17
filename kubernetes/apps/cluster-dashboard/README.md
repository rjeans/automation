# Cluster Dashboard

A lightweight, secure, internet-accessible dashboard for monitoring your Raspberry Pi Kubernetes cluster powered by Talos Linux.

## Features

- **Real-time Cluster Monitoring**: Live updates every 30 seconds via htmx
- **Hardware Status**: Node health, CPU, memory, and storage information
- **Talos Linux Metrics**: Service status and cluster health
- **Kubernetes Status**: Control plane, worker nodes, pod statistics
- **Application Monitoring**: Status of key applications (Traefik, n8n, cert-manager, Cloudflare Tunnel)
- **Beautiful UI**: Clean, responsive design optimized for mobile and desktop
- **Secure by Default**: Read-only RBAC, NetworkPolicy, and security headers
- **Minimal Resource Usage**: ~50m CPU, 64Mi RAM per replica
- **Technology Showcase**: Prominently displays your tech stack

## Architecture

```
┌─────────────────────────────────────────────────┐
│         Cluster Dashboard (Go Application)      │
│  • htmx-powered UI (auto-refresh every 30s)    │
│  • Metrics caching (30s TTL)                    │
│  • Read-only access via RBAC                    │
└──────────────┬──────────────────────────────────┘
               │
               ├─ Kubernetes API (cluster metrics)
               ├─ Metrics Server (node/pod metrics)
               └─ Talos API (node health - optional)
```

## Security Design

The dashboard is designed to be **safe for internet access**:

1. **Read-Only Access**: ServiceAccount with minimal RBAC permissions (only `get`, `list`, `watch`)
2. **No Secrets Exposed**: Displays only aggregated status, never IPs, tokens, or credentials
3. **NetworkPolicy**: Restricts traffic to/from only necessary services
4. **Security Headers**: Browser XSS protection, frame denial, HSTS
5. **TLS Required**: HTTPS-only via cert-manager and Traefik
6. **Rate Limiting**: Optional middleware to prevent abuse
7. **No Search Engine Indexing**: `X-Robots-Tag` header prevents crawling

## Quick Start

### Prerequisites

- Talos Kubernetes cluster (v1.8+)
- Traefik ingress controller
- cert-manager for TLS certificates
- kubectl access to the cluster
- Container registry account (GitHub Container Registry recommended, or Docker Hub)

### Step 0: Initial Setup

Run the setup script to configure your container registry and domain:

```bash
cd kubernetes/apps/cluster-dashboard
./setup.sh
```

The script will let you choose:
1. **GitHub Container Registry (GHCR)** - Recommended ✅
   - Free unlimited public images
   - No rate limiting
   - Already integrated with GitHub
2. **Docker Hub**
   - Traditional Docker registry
   - Rate limits on free tier

The script will automatically configure all the necessary files.

**OR** manually edit these files:
- `chart/values.yaml` - Change registry and domain
- `deployment.yaml` - Change image repository
- See [GITHUB-REGISTRY.md](GITHUB-REGISTRY.md) for GHCR setup
- See [DOCKER-HUB.md](DOCKER-HUB.md) for Docker Hub setup

### Option 1: Deploy with Helm (Recommended)

```bash
# Navigate to the chart directory
cd kubernetes/apps/cluster-dashboard

# Login to your container registry
docker login ghcr.io  # For GitHub (recommended)
# OR
docker login          # For Docker Hub

# Build and push Docker image
make docker-push

# Review and customize values (if not using setup.sh)
vim chart/values.yaml

# Install the chart
helm install cluster-dashboard . -n cluster-dashboard --create-namespace

# Check deployment status
kubectl get pods -n cluster-dashboard
```

### Option 2: Deploy with kubectl

```bash
# Navigate to the manifests directory
cd kubernetes/apps/cluster-dashboard

# Apply all manifests
kubectl apply -f namespace.yaml
kubectl apply -f rbac.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f network-policy.yaml
kubectl apply -f ingress.yaml

# Check deployment status
kubectl get pods -n cluster-dashboard
```

## Configuration

### Customizing the Domain

Edit the domain in [ingress.yaml](ingress.yaml) or [chart/values.yaml](chart/values.yaml):

```yaml
# Change from:
dashboard.automation.local

# To your actual domain:
dashboard.yourdomain.com
```

### Adjusting Resources

The default resource limits are optimized for Raspberry Pi:

```yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi
```

### Enabling Rate Limiting

To prevent abuse, enable rate limiting in [ingress.yaml](ingress.yaml):

```yaml
traefik.ingress.kubernetes.io/router.middlewares: cluster-dashboard-ratelimit@kubernetescrd
```

Or in Helm values:

```yaml
middleware:
  rateLimit:
    enabled: true
    average: 100  # requests per period
    period: 1m
    burst: 50
```

### Adding Cloudflare Tunnel Access

To expose via Cloudflare Tunnel, add to your Cloudflare configuration:

```yaml
ingress:
  - hostname: dashboard.yourdomain.com
    service: http://cluster-dashboard.cluster-dashboard.svc.cluster.local:80
```

## Building the Docker Image

```bash
cd kubernetes/apps/cluster-dashboard/app

# Build for ARM64 (Raspberry Pi)
docker build --platform linux/arm64 -t cluster-dashboard:latest .

# Or build for multiple architectures
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/automation/cluster-dashboard:latest \
  --push .
```

## Development

### Local Development

```bash
cd kubernetes/apps/cluster-dashboard/app

# Install dependencies
go mod download

# Run locally (requires kubeconfig)
go run cmd/main.go

# Access at http://localhost:8080
```

### Project Structure

```
app/
├── cmd/
│   └── main.go              # Application entry point
├── internal/
│   ├── handlers/            # HTTP handlers
│   │   └── dashboard.go
│   ├── k8s/                 # Kubernetes client
│   │   └── client.go
│   ├── talos/               # Talos client (mock)
│   │   └── client.go
│   └── metrics/             # Metrics collection
│       └── cluster.go
├── web/
│   └── templates/           # HTML templates
│       ├── index.html
│       └── metrics.html
├── go.mod
└── Dockerfile
```

## Monitoring the Dashboard

### Health Checks

```bash
# Liveness check
kubectl exec -n cluster-dashboard deploy/cluster-dashboard -- \
  wget -qO- http://localhost:8080/healthz

# Readiness check
kubectl exec -n cluster-dashboard deploy/cluster-dashboard -- \
  wget -qO- http://localhost:8080/readiness
```

### Logs

```bash
# View logs
kubectl logs -n cluster-dashboard -l app.kubernetes.io/name=cluster-dashboard -f

# View logs from specific pod
kubectl logs -n cluster-dashboard cluster-dashboard-<pod-id> -f
```

### Metrics

```bash
# Get metrics as JSON
curl https://dashboard.yourdomain.com/metrics/json

# Get metrics as HTML fragment (for htmx)
curl https://dashboard.yourdomain.com/metrics/html
```

## Troubleshooting

### Dashboard shows "N/A" for CPU/Memory metrics

This means metrics-server is not deployed. Deploy it with:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Pods stuck in "Pending" state

Check events:

```bash
kubectl describe pod -n cluster-dashboard cluster-dashboard-<pod-id>
```

Common causes:
- Insufficient resources on nodes
- Image pull errors
- PodDisruptionBudget constraints

### "Forbidden" errors in logs

The ServiceAccount may need additional RBAC permissions. Check:

```bash
kubectl get clusterrolebinding cluster-dashboard-viewer -o yaml
```

### Network Policy blocking traffic

Verify NetworkPolicy allows ingress from Traefik:

```bash
kubectl get networkpolicy -n cluster-dashboard cluster-dashboard -o yaml
```

## Roadmap

- [ ] Add historical metrics with time-series graphs
- [ ] Deploy Prometheus integration
- [ ] Add alerting capabilities
- [ ] Support for multiple clusters
- [ ] Dark mode toggle
- [ ] Export metrics to external systems
- [ ] Full Talos API integration (currently mock)

## License

MIT License - See LICENSE file for details

## Contributing

Contributions welcome! Please open an issue or PR.

## Support

For issues or questions:
- Open a GitHub issue
- Check existing documentation in `/docs`
- Review the [ROADMAP.md](../../../ROADMAP.md) for planned features
