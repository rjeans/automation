# Deployment Guide

Step-by-step guide to deploy the Cluster Dashboard to your Raspberry Pi Kubernetes cluster.

## Prerequisites Checklist

Before deploying, ensure you have:

- [ ] Talos Kubernetes cluster running (v1.8+)
- [ ] Traefik ingress controller installed
- [ ] cert-manager installed and configured
- [ ] kubectl configured with cluster access
- [ ] (Optional) Cloudflare Tunnel for external access
- [ ] (Optional) metrics-server for detailed CPU/Memory metrics

## Step 1: Build and Push the Docker Image

### Option A: Build Locally

```bash
cd kubernetes/apps/cluster-dashboard/app

# Build for Raspberry Pi (ARM64)
docker buildx build --platform linux/arm64 \
  -t ghcr.io/YOUR_USERNAME/cluster-dashboard:latest \
  --push .
```

### Option B: Build with GitHub Actions

Create `.github/workflows/build-dashboard.yaml`:

```yaml
name: Build Dashboard

on:
  push:
    branches: [main]
    paths:
      - 'kubernetes/apps/cluster-dashboard/app/**'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: ./kubernetes/apps/cluster-dashboard/app
          platforms: linux/arm64
          push: true
          tags: ghcr.io/${{ github.repository_owner }}/cluster-dashboard:latest
```

## Step 2: Configure Your Domain

Edit the domain name in your deployment files:

### For Helm deployment:

Edit `chart/values.yaml`:

```yaml
ingress:
  hosts:
    - host: dashboard.yourdomain.com  # Change this
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: cluster-dashboard-tls
      hosts:
        - dashboard.yourdomain.com  # Change this

certificate:
  dnsNames:
    - dashboard.yourdomain.com  # Change this
```

### For kubectl deployment:

Edit `ingress.yaml`:

```yaml
# Find and replace all instances of:
dashboard.automation.local

# With your actual domain:
dashboard.yourdomain.com
```

## Step 3: Update Image Repository

Update the image reference to match your registry:

### For Helm:

Edit `chart/values.yaml`:

```yaml
image:
  repository: ghcr.io/YOUR_USERNAME/cluster-dashboard
  tag: "latest"
```

### For kubectl:

Edit `deployment.yaml`:

```yaml
containers:
  - name: dashboard
    image: ghcr.io/YOUR_USERNAME/cluster-dashboard:latest
```

## Step 4: Deploy with Helm (Recommended)

```bash
# Navigate to chart directory
cd kubernetes/apps/cluster-dashboard/chart

# Review your values
cat values.yaml

# Dry run to check for errors
helm install cluster-dashboard . \
  -n cluster-dashboard \
  --create-namespace \
  --dry-run --debug

# Deploy
helm install cluster-dashboard . \
  -n cluster-dashboard \
  --create-namespace

# Check deployment
kubectl get pods -n cluster-dashboard -w
```

## Step 5: Verify Deployment

### Check Pod Status

```bash
kubectl get pods -n cluster-dashboard

# Expected output:
# NAME                                 READY   STATUS    RESTARTS   AGE
# cluster-dashboard-xxxxx-xxxxx        1/1     Running   0          30s
# cluster-dashboard-xxxxx-xxxxx        1/1     Running   0          30s
```

### Check Logs

```bash
kubectl logs -n cluster-dashboard -l app.kubernetes.io/name=cluster-dashboard -f

# Expected output:
# Starting Cluster Dashboard...
# Kubernetes client initialized
# Talos client initialized
# Metrics collector initialized
# Dashboard handler initialized
# Server listening on port 8080
```

### Check Service

```bash
kubectl get svc -n cluster-dashboard

# Expected output:
# NAME                TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
# cluster-dashboard   ClusterIP   10.96.xxx.xxx   <none>        80/TCP    1m
```

### Check Ingress

```bash
kubectl get ingress -n cluster-dashboard

# Expected output:
# NAME                CLASS     HOSTS                      ADDRESS   PORTS     AGE
# cluster-dashboard   traefik   dashboard.yourdomain.com             80, 443   1m
```

### Check Certificate

```bash
kubectl get certificate -n cluster-dashboard

# Expected output:
# NAME                      READY   SECRET                    AGE
# cluster-dashboard-tls     True    cluster-dashboard-tls     2m
```

## Step 6: Configure DNS

### Option A: Local DNS (for testing)

Add to `/etc/hosts` on your local machine:

```
192.168.1.11  dashboard.automation.local
```

### Option B: External DNS

Create an A record pointing to your public IP or Cloudflare Tunnel.

### Option C: Cloudflare Tunnel

Edit your Cloudflare Tunnel config:

```yaml
ingress:
  - hostname: dashboard.yourdomain.com
    service: https://cluster-dashboard.cluster-dashboard.svc.cluster.local:80
    originRequest:
      noTLSVerify: false
  - service: http_status:404
```

Apply the config:

```bash
kubectl apply -f kubernetes/apps/cloudflare-tunnel/config.yaml
```

## Step 7: Access the Dashboard

Open your browser and navigate to:

```
https://dashboard.yourdomain.com
```

You should see:
- Hardware status with all nodes
- Talos Linux information
- Kubernetes cluster metrics
- Application status cards

## Step 8: (Optional) Deploy metrics-server

To get detailed CPU/Memory metrics:

```bash
# Download and modify metrics-server for Raspberry Pi
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    k8s-app: metrics-server
  name: system:aggregated-metrics-reader
rules:
- apiGroups:
  - metrics.k8s.io
  resources:
  - pods
  - nodes
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    k8s-app: metrics-server
  name: system:metrics-server
rules:
- apiGroups:
  - ""
  resources:
  - nodes/metrics
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - pods
  - nodes
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server-auth-reader
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: extension-apiserver-authentication-reader
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server:system:auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    k8s-app: metrics-server
  name: system:metrics-server
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:metrics-server
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
---
apiVersion: v1
kind: Service
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server
  namespace: kube-system
spec:
  ports:
  - name: https
    port: 443
    protocol: TCP
    targetPort: https
  selector:
    k8s-app: metrics-server
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: metrics-server
  template:
    metadata:
      labels:
        k8s-app: metrics-server
    spec:
      containers:
      - args:
        - --cert-dir=/tmp
        - --secure-port=4443
        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
        - --kubelet-use-node-status-port
        - --metric-resolution=15s
        - --kubelet-insecure-tls
        image: registry.k8s.io/metrics-server/metrics-server:v0.7.0
        imagePullPolicy: IfNotPresent
        livenessProbe:
          failureThreshold: 3
          httpGet:
            path: /livez
            port: https
            scheme: HTTPS
          periodSeconds: 10
        name: metrics-server
        ports:
        - containerPort: 4443
          name: https
          protocol: TCP
        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /readyz
            port: https
            scheme: HTTPS
          initialDelaySeconds: 20
          periodSeconds: 10
        resources:
          requests:
            cpu: 100m
            memory: 200Mi
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
        volumeMounts:
        - mountPath: /tmp
          name: tmp-dir
      nodeSelector:
        kubernetes.io/os: linux
      priorityClassName: system-cluster-critical
      serviceAccountName: metrics-server
      volumes:
      - emptyDir: {}
        name: tmp-dir
EOF

# Verify metrics-server is running
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Test metrics
kubectl top nodes
```

## Troubleshooting

### Issue: Pods not starting

```bash
# Check events
kubectl describe pod -n cluster-dashboard cluster-dashboard-xxxxx

# Common fixes:
# 1. Image pull errors - verify image exists
# 2. Resource constraints - check node resources
# 3. RBAC issues - verify ServiceAccount
```

### Issue: Certificate not ready

```bash
# Check certificate status
kubectl describe certificate -n cluster-dashboard cluster-dashboard-tls

# Check cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager -f

# Verify ClusterIssuer exists
kubectl get clusterissuer
```

### Issue: Dashboard shows errors

```bash
# Check dashboard logs
kubectl logs -n cluster-dashboard -l app.kubernetes.io/name=cluster-dashboard

# Common issues:
# 1. RBAC permissions - verify ClusterRole
# 2. API server access - check NetworkPolicy
# 3. Metrics server not available - deploy metrics-server
```

### Issue: Can't access dashboard

```bash
# Test service internally
kubectl run -it --rm debug --image=alpine --restart=Never -- sh
wget -qO- http://cluster-dashboard.cluster-dashboard.svc.cluster.local

# Test ingress
kubectl get ingress -n cluster-dashboard -o yaml

# Check Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik
```

## Upgrading

### Helm upgrade:

```bash
helm upgrade cluster-dashboard ./chart \
  -n cluster-dashboard \
  --reuse-values
```

### kubectl upgrade:

```bash
kubectl apply -f kubernetes/apps/cluster-dashboard/
```

### Rolling back:

```bash
# Helm rollback
helm rollback cluster-dashboard -n cluster-dashboard

# kubectl rollback
kubectl rollout undo deployment/cluster-dashboard -n cluster-dashboard
```

## Uninstalling

### Helm:

```bash
helm uninstall cluster-dashboard -n cluster-dashboard
kubectl delete namespace cluster-dashboard
```

### kubectl:

```bash
kubectl delete -f kubernetes/apps/cluster-dashboard/
```

## Next Steps

- Configure Cloudflare Tunnel for external access
- Set up monitoring alerts
- Customize the UI branding
- Deploy Prometheus for historical metrics
- Add custom metrics endpoints
