# Cluster Dashboard Ingress Configuration

## Overview

The cluster dashboard uses a single ingress configuration optimized for external access via Cloudflare Tunnel. Local access is handled via kubectl port-forwarding.

## External Access - `ingress-external.yaml`

**URL**: `https://dashboard.jeansy.org`

### Configuration

```yaml
host: dashboard.jeansy.org
service: cluster-dashboard:80
entrypoints: web, websecure
priority: 10
```

### Traffic Flow

```
Internet → Cloudflare Edge (TLS termination)
        → Cloudflare Tunnel (cloudflared pods)
        → Traefik Ingress Controller
        → cluster-dashboard Service
        → cluster-dashboard Pods
```

### Features

- ✅ TLS/HTTPS handled by Cloudflare
- ✅ DDoS protection
- ✅ Hidden origin IP
- ✅ No port forwarding needed
- ✅ Works from anywhere

### Cloudflare Tunnel Configuration

Configured in Cloudflare Zero Trust Dashboard:

```
Hostname: dashboard.jeansy.org
Service: http://traefik.traefik:80
```

## Local Access - Port Forwarding

**URL**: `http://localhost:8080` (via kubectl port-forward)

### Port Forward Command

```bash
kubectl port-forward -n cluster-dashboard svc/cluster-dashboard 8080:80
```

Then access at: `http://localhost:8080`

### Features

- ✅ Secure (requires kubectl access)
- ✅ No exposed ports needed
- ✅ Works from anywhere with cluster access
- ✅ Simple and clean

## Why No TLS for Cloudflare Tunnel?

Since Cloudflare Tunnel provides:
- TLS termination at Cloudflare's edge
- Encrypted tunnel (cloudflared) to the cluster
- Origin certificate (if needed)

We don't need cert-manager or Let's Encrypt certificates for external access. TLS is handled entirely by Cloudflare.

## Deployment

Apply the external ingress configuration:

```bash
kubectl apply -f ingress-external.yaml
```

Verify:

```bash
kubectl get ingress -n cluster-dashboard
```

Expected output:
```
NAME                         CLASS     HOSTS                  PORTS
cluster-dashboard-external   traefik   dashboard.jeansy.org   80
```

## Testing

### External Access
```bash
curl https://dashboard.jeansy.org
```

### Local Access
```bash
kubectl port-forward -n cluster-dashboard svc/cluster-dashboard 8080:80
# In another terminal:
curl http://localhost:8080
```

Both should return the dashboard HTML with CPU temperature data.
