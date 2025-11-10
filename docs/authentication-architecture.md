# Authentication Architecture

## Overview

This cluster uses Cloudflare OAuth for all external access authentication. The architecture prioritizes simplicity with authentication handled at the tunnel entry point.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                      External Access                         │
│                   (Internet → Cluster)                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   Cloudflare Tunnel                          │
│                   - TLS Termination                          │
│                   - OAuth Authentication                     │
│                   - User Management                          │
│                   - Access Control                           │
└─────────────────────────────────────────────────────────────┘
                            ↓ HTTP (authenticated)
┌─────────────────────────────────────────────────────────────┐
│                   Traefik Ingress                            │
│                   - Routing (web:80)                         │
│                   - Service Discovery                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   Internal Services                          │
│              (MinIO, n8n, PostgreSQL, etc.)                  │
└─────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

### Cloudflare Tunnel with OAuth
- **Purpose**: Single point of authentication for all external access
- **Manages**:
  - User accounts and authentication
  - Email verification
  - OAuth flows
  - Access policies per service/route
- **Protects**: All external traffic before it enters the cluster
- **Benefits**:
  - Enterprise-grade authentication
  - No password management in cluster
  - Built-in DDoS protection
  - Global CDN performance
  - Simple architecture (no additional auth layers)
  - Centralized user management in Cloudflare dashboard

### Traefik Ingress
- **Purpose**: Internal routing and service discovery
- **Manages**: HTTP routing based on hostnames
- **Benefits**:
  - Simple configuration (no auth middlewares needed)
  - Fast routing (no additional auth checks)
  - Works with authenticated traffic from Cloudflare

## Access Flow

### External User Access
1. User requests service (e.g., `https://minio.jeans-host.net`)
2. Cloudflare Tunnel OAuth check
   - If not authenticated: OAuth login flow
   - If authenticated: Check access policy for this route
3. Tunnel forwards authenticated request to cluster (HTTP)
4. Traefik routes to appropriate service based on hostname
5. Service receives request (already authenticated by Cloudflare)

### Service Configuration
Services only need a simple IngressRoute, no auth middlewares:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`myapp.jeans-host.net`)
      kind: Rule
      services:
        - name: myapp
          port: 80
```

## Protected Services

### MinIO Console
- **URL**: `https://minio.jeans-host.net`
- **Protection**: Cloudflare OAuth
- **Access Control**: Configured in Cloudflare Tunnel dashboard

### n8n Workflow Automation (Future)
- **URL**: `https://n8n.jeans-host.net`
- **Protection**: Cloudflare OAuth
- **Access Control**: Per-route policies in Cloudflare

### Cluster Dashboard
- **URL**: `https://dashboard.jeansy.org`
- **Protection**: Cloudflare OAuth
- **Access Control**: Admin-only via Cloudflare policies

## User Management

All user management is handled in the **Cloudflare Zero Trust Dashboard**:

1. Navigate to: Access → Service Auth → Configure
2. Add/remove users by email
3. Set access policies per application/route
4. Configure session duration and MFA requirements

### Access Policies in Cloudflare

Example policy for MinIO (configured in Cloudflare dashboard):

```
Application: MinIO Console
Domain: minio.jeans-host.net
Policy:
  - Include: Emails matching: admin@example.com
  - Require: One-time PIN (optional MFA)
```

## Adding New Services

1. **Create Kubernetes IngressRoute:**
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
  namespace: myapp-ns
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`myapp.jeans-host.net`)
      kind: Rule
      services:
        - name: myapp
          port: 80
```

2. **Add route in Cloudflare Tunnel:**
   - Go to Cloudflare Zero Trust → Networks → Tunnels
   - Select your tunnel
   - Add public hostname: `myapp.jeans-host.net`
   - Point to: `http://traefik.kube-system:80`

3. **Configure access policy in Cloudflare:**
   - Access → Applications → Add application
   - Set domain: `myapp.jeans-host.net`
   - Define who can access (emails, groups, etc.)

## Security Considerations

1. **Single Auth Point**: Cloudflare OAuth provides centralized authentication
2. **DDoS Protection**: Cloudflare edge network filters attacks before reaching cluster
3. **Zero Trust Model**: Every request authenticated at tunnel entry
4. **Optional MFA**: Configure in Cloudflare for additional security
5. **Session Management**: Controlled via Cloudflare Zero Trust policies
6. **TLS Termination**: All traffic encrypted until Cloudflare edge

## Troubleshooting

### Check Cloudflare Tunnel Status
```bash
kubectl logs -n cloudflare-tunnel -l app=cloudflared
```

### Verify Traefik Routing
```bash
# Check IngressRoutes
kubectl get ingressroute -A

# View Traefik logs
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik
```

### Test Access Flow
1. Access service URL: `https://minio.jeans-host.net`
2. Cloudflare OAuth prompt (if not authenticated)
3. Service access granted
4. Check Cloudflare dashboard for access logs

### Common Issues

**Issue**: Service not accessible
- Verify Cloudflare Tunnel route exists
- Check IngressRoute matches hostname
- Confirm Cloudflare access policy allows your email

**Issue**: 404 errors
- Verify IngressRoute uses `web` entrypoint (not `websecure`)
- Check service name and port in IngressRoute
- Ensure service is running: `kubectl get pods -n <namespace>`

## Version Information

- **Cloudflare Tunnel**: 2025.10.0
- **Traefik**: Via Talos Kubernetes default installation

## Related Documentation

- [Cloudflare Tunnel Setup](../flux/clusters/talos/infrastructure/cloudflare-tunnel/)
- [MinIO Configuration](../flux/clusters/talos/apps/rag-system/minio/)
- [Cluster Dashboard](../flux/clusters/talos/apps/cluster-dashboard/)
