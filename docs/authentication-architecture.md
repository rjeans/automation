# Authentication Architecture

## Overview

This cluster uses a layered authentication approach combining Cloudflare OAuth and Authelia SSO.

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
└─────────────────────────────────────────────────────────────┘
                            ↓ HTTP
┌─────────────────────────────────────────────────────────────┐
│                   Traefik Ingress                            │
│                   - Routing (web:80)                         │
│                   - Middleware Chain                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   Authelia SSO                               │
│                   - Internal Service Auth                    │
│                   - Two-Factor (TOTP)                        │
│                   - ForwardAuth for Apps                     │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   Internal Services                          │
│              (MinIO, n8n, PostgreSQL, etc.)                  │
└─────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

### Cloudflare OAuth (External)
- **Purpose**: External access control and user management
- **Manages**: User accounts, email verification, OAuth flows
- **Protects**: Tunnel entry point
- **Benefits**:
  - Enterprise-grade authentication
  - No password management in cluster
  - Built-in DDoS protection
  - Global CDN performance

### Authelia (Internal)
- **Purpose**: Internal SSO and service authentication
- **Manages**: Service access policies, MFA, session management
- **Protects**: Individual services within cluster
- **Benefits**:
  - Works without internet (local auth)
  - Fine-grained access control
  - OAuth/OIDC provider for apps
  - ForwardAuth integration

## Access Patterns

### External User Access
1. User → Cloudflare Tunnel (OAuth check)
2. Tunnel → Traefik (routes to service)
3. Traefik → Authelia middleware (2FA check)
4. Authelia → Backend service

### Internal Service-to-Service
1. Service A → Authelia (validate token)
2. Authelia → Service B (authorized request)

## Protected Services

### MinIO Console
- **URL**: `minio.jeans-host.net`
- **Protection**: Cloudflare OAuth → Authelia 2FA
- **Access**: Admins group only
- **Middlewares**: `secure-headers`, `authelia`

### n8n Workflow Automation
- **Integration**: Will use Authelia OAuth/OIDC
- **Benefits**: Single sign-on for workflow creators

### Future RAG APIs
- **Integration**: Authelia OAuth tokens
- **Use Case**: API authentication for LLM services

## User Management

### Password Changes
Due to the proxy chain complexity, passwords are managed via the `users.yaml` file:

```bash
# Generate new password hash
kubectl exec -n authelia deploy/authelia -- \
  authelia crypto hash generate argon2 --password 'newpassword'

# Update users.yaml with new hash
# Commit and push to trigger Flux reconciliation
```

### User Configuration
Location: `flux/clusters/talos/apps/authelia/users.yaml` (SOPS encrypted)

```yaml
users:
  admin:
    password: "$argon2id$v=19$m=65536,t=3,p=4$..."
    displayname: "Admin User"
    email: admin@jeansy.org
    groups:
      - admins
```

## Access Control Rules

### MinIO Console
```yaml
domain: "minio.jeans-host.net"
policy: two_factor
subject: "group:admins"
```

### Adding New Services

1. **Create IngressRoute with Authelia middleware:**
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
      middlewares:
        - name: secure-headers
          namespace: authelia
        - name: authelia
          namespace: authelia
      services:
        - name: myapp
          port: 80
```

2. **Add Authelia access rule:**
```yaml
# In authelia/configmap.yaml
access_control:
  rules:
    - domain: "myapp.jeans-host.net"
      policy: two_factor  # or one_factor
      subject:
        - "group:admins"  # or specific users
```

3. **Add Cloudflare Tunnel route** (via dashboard)

## Session Configuration

- **Expiration**: 1 hour
- **Inactivity timeout**: 5 minutes
- **Remember me**: 1 month
- **Domain**: `jeans-host.net`

## MFA Setup

### TOTP Configuration
- **Issuer**: jeans-host.net
- **Algorithm**: SHA1
- **Digits**: 6
- **Period**: 30 seconds

### Verification Codes
Authelia uses filesystem notifier (no email setup needed):

```bash
# Retrieve one-time code for MFA setup
kubectl exec -n authelia deploy/authelia -- cat /config/notifications.txt
```

## Security Considerations

1. **Defense in Depth**: Multiple auth layers prevent single point of failure
2. **Cloudflare Protection**: Handles external threats before reaching cluster
3. **Internal Segmentation**: Authelia controls service-to-service access
4. **MFA Required**: All admin access requires two-factor authentication
5. **Session Security**: Short timeouts and inactivity detection

## Troubleshooting

### Authelia Logs
```bash
kubectl logs -n authelia -l app.kubernetes.io/name=authelia
```

### Check Session Issues
```bash
# View SQLite database
kubectl exec -n authelia deploy/authelia -- sqlite3 /config/db.sqlite3 "SELECT * FROM user_sessions;"
```

### Test Access Flow
1. Access service URL: `https://myapp.jeans-host.net`
2. Cloudflare OAuth prompt (if not authenticated)
3. Authelia login (if no session)
4. Authelia 2FA (if policy requires)
5. Service access granted

## Version Information

- **Authelia**: 4.39.14
- **Cloudflare Tunnel**: 2025.10.0
- **Traefik**: Via Talos Kubernetes

## Related Documentation

- [Authelia Configuration](../flux/clusters/talos/apps/authelia/)
- [Cloudflare Tunnel Setup](../flux/clusters/talos/infrastructure/cloudflare-tunnel/)
- [MinIO Access](../flux/clusters/talos/apps/rag-system/minio/)
