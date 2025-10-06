# cert-manager Certificate Management

## Overview

cert-manager automates certificate management in Kubernetes, including automatic issuance and renewal of TLS certificates from Let's Encrypt and other certificate authorities.

**Deployed Version**: v1.16.2
**Namespace**: cert-manager
**Components**:
- cert-manager controller
- cert-manager webhook
- cert-manager cainjector

## Installation

### Prerequisites

- Kubernetes cluster with Traefik ingress controller
- Helm installed
- kubectl configured

### Deploy cert-manager

```bash
# Add Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Create namespace
kubectl create namespace cert-manager

# Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --values kubernetes/core/cert-manager/values.yaml \
  --version v1.16.2

# Verify installation
kubectl get pods -n cert-manager
```

**Expected output:**
```
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-58646f44b8-xxxxx              1/1     Running   0          1m
cert-manager-cainjector-57dd8dc994-xxxxx   1/1     Running   0          1m
cert-manager-webhook-65876f4bd9-xxxxx      1/1     Running   0          1m
```

## Configuration

### Resource Limits

Optimized for Raspberry Pi 4:

```yaml
resources:
  requests:
    cpu: 10m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 128Mi
```

Each component (controller, webhook, cainjector) uses these limits.

### Tolerations

Configured to run on control plane nodes:

```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

## ClusterIssuers

ClusterIssuers are cluster-wide resources that define how to obtain certificates.

### Self-Signed Issuer (Testing)

For local testing without external dependencies:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
```

**Deploy:**
```bash
kubectl apply -f kubernetes/core/cert-manager/test-certificate.yaml
```

### Let's Encrypt Staging

For testing certificate issuance (higher rate limits):

**Important**: Update email address before deploying:

```bash
# Edit the file and replace your-email@example.com
nano kubernetes/core/cert-manager/cluster-issuer-staging.yaml

# Deploy
kubectl apply -f kubernetes/core/cert-manager/cluster-issuer-staging.yaml

# Verify
kubectl get clusterissuer letsencrypt-staging
```

**Configuration:**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: your-email@example.com  # Replace this
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
    - http01:
        ingress:
          class: traefik
```

### Let's Encrypt Production

For production certificates (strict rate limits: 5 certs/week per domain):

**Important**:
- Update email address
- Test with staging first
- Only use after successful staging tests

```bash
# Edit the file and replace your-email@example.com
nano kubernetes/core/cert-manager/cluster-issuer-production.yaml

# Deploy (only after testing with staging)
kubectl apply -f kubernetes/core/cert-manager/cluster-issuer-production.yaml

# Verify
kubectl get clusterissuer letsencrypt-production
```

## Certificate Issuance

### Method 1: Automatic with Ingress Annotations

Add annotations to your Ingress resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging  # or letsencrypt-production
spec:
  tls:
  - hosts:
    - example.yourdomain.com
    secretName: example-tls  # cert-manager will create this
  rules:
  - host: example.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: example-service
            port:
              number: 80
```

cert-manager will automatically:
1. Create a Certificate resource
2. Request certificate from Let's Encrypt
3. Complete HTTP-01 challenge via Traefik
4. Store certificate in the specified secret
5. Renew certificate before expiration

### Method 2: Manual Certificate Resource

Create Certificate resource directly:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-certificate
  namespace: default
spec:
  secretName: example-tls
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
  - example.yourdomain.com
  - www.example.yourdomain.com
```

**Deploy:**
```bash
kubectl apply -f certificate.yaml

# Check status
kubectl get certificate example-certificate
kubectl describe certificate example-certificate
```

## Testing

### Test Self-Signed Certificate

```bash
# Deploy test certificate
kubectl apply -f kubernetes/core/cert-manager/test-certificate.yaml

# Check certificate status
kubectl get certificate test-certificate -n default

# Should show READY=True
# NAME               READY   SECRET                 AGE
# test-certificate   True    test-certificate-tls   30s

# Inspect the secret
kubectl get secret test-certificate-tls -n default -o yaml
```

### Test Let's Encrypt Staging

**Requirements**:
- External access to cluster (port 80)
- Valid domain pointing to cluster IP
- Router port forwarding configured

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: staging-test
  namespace: default
spec:
  secretName: staging-test-tls
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
  - test.yourdomain.com
```

**Monitor challenge:**
```bash
# Watch certificate status
kubectl get certificate staging-test -w

# Check certificate events
kubectl describe certificate staging-test

# View challenge (created temporarily)
kubectl get challenges

# View certificate request
kubectl get certificaterequest
```

**Certificate lifecycle:**
1. Certificate created → Status: Issuing
2. CertificateRequest created
3. Order created with ACME server
4. Challenge created (HTTP-01)
5. Traefik serves challenge response
6. ACME validates challenge
7. Certificate issued → Status: Ready

## Verification

### Check ClusterIssuers

```bash
# List all ClusterIssuers
kubectl get clusterissuer

# Expected output:
# NAME                     READY   AGE
# selfsigned-issuer        True    5m
# letsencrypt-staging      True    5m
# letsencrypt-production   True    5m

# Describe issuer
kubectl describe clusterissuer letsencrypt-staging
```

### Check Certificates

```bash
# List all certificates
kubectl get certificate -A

# Check specific certificate
kubectl describe certificate <name> -n <namespace>

# View certificate secret
kubectl get secret <secret-name> -o yaml
```

### Check cert-manager Logs

```bash
# Controller logs
kubectl logs -n cert-manager -l app=cert-manager -f

# Webhook logs
kubectl logs -n cert-manager -l app=webhook -f

# CA Injector logs
kubectl logs -n cert-manager -l app=cainjector -f
```

## Troubleshooting

### Certificate Stuck in Pending

**Check events:**
```bash
kubectl describe certificate <name>
```

**Common issues:**
1. **HTTP-01 challenge fails**: Ensure port 80 is accessible from internet
2. **DNS not resolving**: Verify domain points to cluster IP
3. **Rate limited**: Switch to staging or wait (production has limits)
4. **Ingress class mismatch**: Ensure `class: traefik` in solver config

### Challenge Not Completing

**View challenge details:**
```bash
kubectl get challenges
kubectl describe challenge <challenge-name>
```

**Test HTTP-01 challenge manually:**
```bash
# Let's Encrypt will access:
# http://yourdomain.com/.well-known/acme-challenge/<token>

# Verify Traefik can serve it
curl -v http://yourdomain.com/.well-known/acme-challenge/test
```

### Webhook Connection Issues

**Error**: `x509: certificate signed by unknown authority`

**Fix**: Restart webhook pods:
```bash
kubectl delete pod -n cert-manager -l app=webhook
```

### Rate Limiting

**Production limits**:
- 5 certificates per week per domain
- 50 certificates per week per account

**Solution**: Use staging for testing:
```yaml
cert-manager.io/cluster-issuer: letsencrypt-staging
```

## Upgrading cert-manager

```bash
# Update Helm repo
helm repo update

# Check current version
helm list -n cert-manager

# Upgrade to new version
helm upgrade cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --values kubernetes/core/cert-manager/values.yaml \
  --version v1.17.0  # new version

# Verify
kubectl get pods -n cert-manager
```

## Uninstalling

```bash
# Delete all certificates first
kubectl delete certificate --all -A

# Delete ClusterIssuers
kubectl delete clusterissuer --all

# Uninstall cert-manager
helm uninstall cert-manager -n cert-manager

# Delete CRDs (if needed)
kubectl delete crd certificates.cert-manager.io
kubectl delete crd certificaterequests.cert-manager.io
kubectl delete crd challenges.cert-manager.io
kubectl delete crd clusterissuers.cert-manager.io
kubectl delete crd issuers.cert-manager.io
kubectl delete crd orders.cert-manager.io

# Delete namespace
kubectl delete namespace cert-manager
```

## Example: Secure n8n with TLS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: n8n-ingress
  namespace: n8n
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  tls:
  - hosts:
    - n8n.yourdomain.com
    secretName: n8n-tls
  rules:
  - host: n8n.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: n8n
            port:
              number: 5678
```

**Result**: Automatic HTTPS with Let's Encrypt certificate, auto-renewal every 60 days.

## Next Steps

After cert-manager is deployed:

1. **Configure email in ClusterIssuers** - Update both staging and production
2. **Test with staging** - Create test certificate with your domain
3. **Configure router** - Port forward 80 and 443 to cluster
4. **Deploy production issuer** - Only after staging tests pass
5. **Secure applications** - Add TLS to n8n and other services

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Traefik + cert-manager](https://doc.traefik.io/traefik/https/acme/)
- [HTTP-01 Challenge](https://letsencrypt.org/docs/challenge-types/#http-01-challenge)

---

**Last Updated**: 2025-10-06
**cert-manager Version**: v1.16.2
**Kubernetes Version**: v1.34.0
