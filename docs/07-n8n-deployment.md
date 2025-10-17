# n8n Workflow Automation Deployment

> **⚠️ DEPLOYMENT METHOD CHANGED**
>
> **n8n is now managed by Flux GitOps** - This guide is for reference only.
>
> **Current deployment method**: See [GITOPS-QUICKSTART.md](GITOPS-QUICKSTART.md)
>
> **Configuration location**: `flux/clusters/talos/apps/n8n/`
>
> **To modify n8n**:
> 1. Edit `flux/clusters/talos/apps/n8n/values.yaml`
> 2. Commit and push to Git
> 3. Flux automatically applies changes within 1 minute
>
> **Manual deployment is no longer recommended**

## Overview

n8n is a fair-code licensed workflow automation tool that allows you to connect various services and automate tasks. This deployment includes PostgreSQL for persistent storage and is optimized for Raspberry Pi hardware.

**Deployed Version**: n8n v1.113.3
**Chart Version**: community-charts/n8n v1.15.12
**Namespace**: n8n
**Database**: PostgreSQL (embedded via subchart)
**Management**: Flux HelmRelease (GitOps)

## Architecture

```
┌─────────────────────────────────────────┐
│ Traefik Ingress (NodePort 30080/30443) │
│          n8n.local → n8n service        │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│   n8n Pod (n8n-main container)          │
│   - Workflow execution engine           │
│   - Web UI (port 5678)                  │
│   - Webhook receiver                    │
│   - Resources: 100m CPU / 256Mi RAM     │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│   PostgreSQL Pod                        │
│   - Database: n8n                       │
│   - User: n8n                           │
│   - Port: 5432                          │
│   - Storage: 20Gi PVC on node .11       │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│   Persistent Volumes                    │
│   - n8n-main-persistence: 10Gi          │
│   - data-n8n-postgresql-0: 20Gi         │
│   Both using local-path provisioner     │
└─────────────────────────────────────────┘
```

## Prerequisites

- Kubernetes cluster running (Talos Linux v1.11.2)
- kubectl configured
- Flux installed and bootstrapped
- Storage provisioner (Local Path Provisioner) deployed
- Traefik ingress controller deployed (managed by Flux)
- cert-manager deployed (optional, managed by Flux)

## Current Deployment (GitOps)

### Check n8n Status

```bash
# Check Flux HelmRelease
flux get helmrelease n8n -n n8n

# Check pods
kubectl get pods -n n8n

# Check services
kubectl get svc -n n8n

# Check persistent volumes
kubectl get pvc -n n8n

# View current configuration
cat flux/clusters/talos/apps/n8n/values.yaml
```

### Modify n8n Configuration

```bash
# Edit the values file in Git
vim flux/clusters/talos/apps/n8n/values.yaml

# Commit and push
git add flux/clusters/talos/apps/n8n/values.yaml
git commit -m "feat: Update n8n configuration"
git push

# Flux will automatically apply changes
# Watch reconciliation
flux get helmrelease n8n -n n8n --watch
```

### Verify Deployment

```bash
# Check all resources
kubectl get all -n n8n

# Check persistent volumes
kubectl get pvc -n n8n

# Check ingress routes
kubectl get ingressroute -n n8n

# Test database connection
kubectl exec -n n8n n8n-postgresql-0 -- sh -c 'PGPASSWORD=n8n-postgresql-password psql -U n8n -d n8n -c "\dt"'
```

## Legacy Installation (Not Recommended)

### Step 1: Add Helm Repository

```bash
# ⚠️ This method is deprecated - use Flux instead

# Add community-charts repository
helm repo add community-charts https://community-charts.github.io/helm-charts
helm repo update
```

### Step 2: Create Namespace

```bash
kubectl create namespace n8n
```

### Step 3: Deploy n8n Manually (Legacy - Do Not Use)

```bash
# ⚠️ This method is deprecated - use Flux instead

# Install n8n with PostgreSQL
helm install n8n community-charts/n8n \
  --namespace n8n \
  --values kubernetes/apps/n8n/values.yaml \
  --timeout 10m

# Watch deployment
kubectl get pods -n n8n -w
```

**Note**: This manual method bypasses GitOps and is not recommended. Changes made manually will be reverted by Flux.

## Configuration

### Resource Limits (Raspberry Pi Optimized)

**n8n Pod:**
```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```

**PostgreSQL Pod:**
```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### Health Probes

Critical configuration for Raspberry Pi slow startup:

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: http
  initialDelaySeconds: 60  # Wait 60s before first check
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /healthz/readiness
    port: http
  initialDelaySeconds: 30  # Wait 30s before first check
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

**Why this matters**: Without initial delays, probes start immediately and kill the container before n8n can start up on slower Raspberry Pi hardware.

### Storage Configuration

**n8n Data Volume:**
- Size: 10Gi
- StorageClass: local-path
- Contains: Workflow files, user data, credentials (encrypted)

**PostgreSQL Data Volume:**
- Size: 20Gi
- StorageClass: local-path
- Contains: Execution history, workflow definitions, user accounts
- Node selector: talos-7f2-ouz (node .11 with 1TB external drive)

### Database Configuration

**Connection Settings:**
```yaml
db:
  type: postgresdb
  postgresdb:
    poolSize: 2
    connectionTimeout: 20000
    idleConnectionTimeout: 30000
    schema: public
```

**PostgreSQL Authentication:**
- Username: n8n
- Password: n8n-postgresql-password (stored in secret `n8n-postgresql`)
- Database: n8n
- Host: n8n-postgresql (service name)
- Port: 5432

### Environment Variables

Key n8n configuration:

```yaml
extraEnvVars:
  WEBHOOK_URL: "http://n8n.local:30080/"
  GENERIC_TIMEZONE: "America/Los_Angeles"
  EXECUTIONS_DATA_SAVE_ON_SUCCESS: "all"
  EXECUTIONS_DATA_SAVE_ON_ERROR: "all"
  EXECUTIONS_DATA_SAVE_ON_PROGRESS: "true"
  EXECUTIONS_TIMEOUT: "3600"
  N8N_DIAGNOSTICS_ENABLED: "false"
```

## Accessing n8n

### Local Access (NodePort)

Since `n8n.local` is not a real domain, access via Traefik NodePort with Host header:

```bash
# Access from any cluster node
curl -H "Host: n8n.local" http://192.168.1.11:30080/

# Or open in browser (configure /etc/hosts first)
# Add to /etc/hosts:
# 192.168.1.11  n8n.local

# Then visit:
http://n8n.local:30080/
```

### First-Time Setup

1. **Open n8n in browser**: http://n8n.local:30080/
2. **Create owner account**: Set email and password
3. **Complete onboarding**: Skip or configure email settings
4. **Start building workflows**

### Production Access (with Real Domain)

To use n8n with a real domain and HTTPS:

1. **Update DNS**: Point your domain to cluster IP (e.g., `n8n.yourdomain.com` → `192.168.1.11`)

2. **Configure router port forwarding**:
   - Port 80 → 192.168.1.11:30080
   - Port 443 → 192.168.1.11:30443

3. **Update values.yaml**:
```yaml
ingress:
  hosts:
    - host: n8n.yourdomain.com  # Your actual domain
      paths:
        - path: /
          pathType: Prefix

  tls:
    - secretName: n8n-tls
      hosts:
        - n8n.yourdomain.com

  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production  # Switch to production
```

4. **Update environment variables**:
```yaml
main:
  editorBaseUrl: "https://n8n.yourdomain.com/"
  extraEnvVars:
    WEBHOOK_URL: "https://n8n.yourdomain.com/"
```

5. **Upgrade deployment**:
```bash
helm upgrade n8n community-charts/n8n \
  --namespace n8n \
  --values kubernetes/apps/n8n/values.yaml
```

## Webhooks

n8n can receive webhooks for automation triggers.

**Webhook URL format:**
```
http://n8n.local:30080/webhook/your-webhook-path
```

**Production webhook URL:**
```
https://n8n.yourdomain.com/webhook/your-webhook-path
```

**Testing webhooks:**
```bash
curl -X POST http://n8n.local:30080/webhook/test \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

## Troubleshooting

### Pod Not Starting (CrashLoopBackOff)

**Symptom**: Pod restarts repeatedly

**Common causes:**
1. **Health probes too aggressive**: Increase `initialDelaySeconds`
2. **Database connection failed**: Check PostgreSQL pod is running
3. **Resource constraints**: Check if pod is being OOM killed

**Check logs:**
```bash
kubectl logs -n n8n <pod-name>
kubectl logs -n n8n <pod-name> --previous  # Previous crashed container
kubectl describe pod -n n8n <pod-name>
```

### Database Connection Issues

**Check PostgreSQL status:**
```bash
# Pod running?
kubectl get pods -n n8n -l app.kubernetes.io/name=postgresql

# Test connection
kubectl exec -n n8n n8n-postgresql-0 -- sh -c \
  'PGPASSWORD=n8n-postgresql-password psql -U n8n -d n8n -c "SELECT 1"'

# Check environment variables
kubectl exec -n n8n <n8n-pod> -- env | grep DB_
```

### PVC Not Binding

**Symptom**: Pods stuck in Pending state

**Check PVCs:**
```bash
kubectl get pvc -n n8n
kubectl describe pvc <pvc-name> -n n8n
```

**Common issue**: Wrong StorageClass name
- Correct: `local-path`
- Incorrect: `local-path-storage`

```bash
# Check available StorageClasses
kubectl get storageclass
```

### Ingress Not Working

**Test service directly:**
```bash
# Get service IP
kubectl get svc -n n8n n8n

# Test from cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://n8n.n8n.svc.cluster.local:5678/healthz

# Test via Traefik
curl -H "Host: n8n.local" http://192.168.1.11:30080/ -v
```

**Check Traefik logs:**
```bash
kubectl logs -n traefik -l app.kubernetes.io/name=traefik
```

### Slow Performance

**Check resource usage:**
```bash
kubectl top pods -n n8n
kubectl top nodes
```

**Increase resources if needed:**
```yaml
main:
  resources:
    limits:
      cpu: 2000m      # Increase CPU
      memory: 2Gi     # Increase memory
```

### Workflows Not Executing

**Check execution logs in n8n UI:**
1. Open workflow
2. Click "Executions" tab
3. View execution details

**Check database:**
```bash
# Count executions
kubectl exec -n n8n n8n-postgresql-0 -- sh -c \
  'PGPASSWORD=n8n-postgresql-password psql -U n8n -d n8n -c "SELECT COUNT(*) FROM execution_entity"'
```

## Backup and Recovery

### Backup n8n Data

**Method 1: Export workflows via UI**
1. Open n8n UI
2. Go to Workflows
3. Select workflow → Export

**Method 2: Backup PostgreSQL database**

```bash
# Create backup
kubectl exec -n n8n n8n-postgresql-0 -- sh -c \
  'PGPASSWORD=n8n-postgresql-password pg_dump -U n8n -d n8n' > n8n-backup-$(date +%Y%m%d).sql

# Backup to file inside pod
kubectl exec -n n8n n8n-postgresql-0 -- sh -c \
  'PGPASSWORD=n8n-postgresql-password pg_dump -U n8n -d n8n -f /tmp/n8n-backup.sql'

# Copy backup out
kubectl cp n8n/n8n-postgresql-0:/tmp/n8n-backup.sql ./n8n-backup.sql
```

**Method 3: Backup PVCs**

```bash
# Get PV details
kubectl get pvc -n n8n

# Create snapshot/copy of underlying volume on node .11
# (depends on your backup strategy)
```

### Restore from Backup

**Restore database:**

```bash
# Copy backup into pod
kubectl cp ./n8n-backup.sql n8n/n8n-postgresql-0:/tmp/n8n-backup.sql

# Restore database
kubectl exec -n n8n n8n-postgresql-0 -- sh -c \
  'PGPASSWORD=n8n-postgresql-password psql -U n8n -d n8n -f /tmp/n8n-backup.sql'

# Restart n8n pod to pick up changes
kubectl rollout restart deployment/n8n -n n8n
```

## Upgrading

### GitOps Method (Recommended)

```bash
# Edit HelmRelease to change version
vim flux/clusters/talos/apps/n8n/helmrelease.yaml

# Change version:
# spec:
#   chart:
#     spec:
#       version: "1.16.0"  # New version

# Commit and push
git add flux/clusters/talos/apps/n8n/helmrelease.yaml
git commit -m "feat: Upgrade n8n to v1.16.0"
git push

# Flux will automatically upgrade
flux get helmrelease n8n -n n8n --watch

# Watch rollout
kubectl rollout status deployment/n8n -n n8n
```

### Legacy Manual Method (Not Recommended)

```bash
# ⚠️ This method is deprecated - use Flux instead

# Check current version
helm list -n n8n

# Update Helm repo
helm repo update

# Check available versions
helm search repo community-charts/n8n --versions

# Upgrade to new version
helm upgrade n8n community-charts/n8n \
  --namespace n8n \
  --values kubernetes/apps/n8n/values.yaml \
  --version 1.16.0  # specify new chart version

# Watch rollout
kubectl rollout status deployment/n8n -n n8n
```

### Upgrade PostgreSQL

**Warning**: Upgrading PostgreSQL major versions requires careful migration.

```bash
# Backup first!
kubectl exec -n n8n n8n-postgresql-0 -- sh -c \
  'PGPASSWORD=n8n-postgresql-password pg_dump -U n8n -d n8n' > backup.sql

# Edit values in Git
vim flux/clusters/talos/apps/n8n/values.yaml
# Update postgresql.image.tag

# Commit and push - Flux will upgrade automatically
git add flux/clusters/talos/apps/n8n/values.yaml
git commit -m "feat: Upgrade PostgreSQL version"
git push
```

## Uninstalling

```bash
# Uninstall n8n (keeps PVCs due to resource policy)
helm uninstall n8n -n n8n

# Delete PVCs (WARNING: This deletes all data)
kubectl delete pvc --all -n n8n

# Delete namespace
kubectl delete namespace n8n
```

## Security Considerations

### Current Configuration (Development)

- **Database password**: Simple password in values.yaml
- **No TLS**: HTTP only on local network
- **No authentication on webhooks**: Public if exposed
- **Diagnostics disabled**: No telemetry sent to n8n.io

### Production Hardening

1. **Use Kubernetes Secrets for passwords**:
```yaml
postgresql:
  auth:
    existingSecret: "n8n-postgresql-secret"
```

2. **Enable HTTPS with Let's Encrypt**:
```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production
```

3. **Configure webhook authentication** in n8n UI

4. **Enable two-factor authentication** for n8n users

5. **Restrict network access**:
```yaml
networkPolicy:
  enabled: true
  allowExternal: false
```

6. **Regular backups**: Automate PostgreSQL backups

## Performance Tuning

### Execution Concurrency

For better performance on Raspberry Pi:

```yaml
worker:
  mode: regular  # Use main node for execution
  # OR
  mode: queue    # Use separate worker pods (requires Redis)
  count: 2       # Number of worker pods
```

### Database Connection Pooling

```yaml
db:
  postgresdb:
    poolSize: 4  # Increase for more concurrent workflows
```

### PostgreSQL Tuning

```yaml
postgresql:
  primary:
    extraEnvVars:
      - name: POSTGRESQL_MAX_CONNECTIONS
        value: "100"
      - name: POSTGRESQL_SHARED_BUFFERS
        value: "128MB"
```

## Monitoring

### Check Service Health

```bash
# Health endpoint
curl -H "Host: n8n.local" http://192.168.1.11:30080/healthz

# Readiness
curl -H "Host: n8n.local" http://192.168.1.11:30080/healthz/readiness

# Metrics (if enabled)
curl -H "Host: n8n.local" http://192.168.1.11:30080/metrics
```

### View Logs

```bash
# n8n logs
kubectl logs -n n8n -l app.kubernetes.io/component=main -f

# PostgreSQL logs
kubectl logs -n n8n -l app.kubernetes.io/name=postgresql -f

# All logs
kubectl logs -n n8n --all-containers=true -f
```

## References

- [n8n Documentation](https://docs.n8n.io/)
- [n8n Helm Chart](https://github.com/community-charts/helm-charts/tree/main/charts/n8n)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Workflow Examples](https://n8n.io/workflows/)

---

**Last Updated**: 2025-10-06
**n8n Version**: v1.113.3
**Chart Version**: v1.15.12
**Kubernetes Version**: v1.34.0
