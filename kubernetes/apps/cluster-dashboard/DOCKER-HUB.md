# Docker Hub Setup Guide

This guide shows you how to build and push the Cluster Dashboard image to Docker Hub.

## Prerequisites

- Docker installed with buildx support
- Docker Hub account (free tier works fine)
- Your Docker Hub username

## Quick Setup

### 1. Login to Docker Hub

```bash
docker login

# Enter your Docker Hub username and password/token
```

### 2. Set Your Username

Replace `YOUR_DOCKERHUB_USERNAME` in these files with your actual Docker Hub username:

**Option A: Set environment variable (temporary)**
```bash
export DOCKERHUB_USERNAME="your-username"
```

**Option B: Edit files directly**

Edit [chart/values.yaml](chart/values.yaml):
```yaml
image:
  repository: your-username/cluster-dashboard  # ← Change this
```

Edit [deployment.yaml](deployment.yaml):
```yaml
image: your-username/cluster-dashboard:latest  # ← Change this
```

### 3. Build and Push

**Using Makefile:**
```bash
# Build and push (replace with your username)
make docker-push IMAGE_REGISTRY=your-username

# Or set it in the Makefile once
vim Makefile  # Change IMAGE_REGISTRY to your username
make docker-push
```

**Using Docker directly:**
```bash
cd app

# Build for Raspberry Pi (ARM64)
docker buildx build --platform linux/arm64 \
  -t your-username/cluster-dashboard:latest \
  --push .

# Or build for multiple architectures
docker buildx build --platform linux/amd64,linux/arm64 \
  -t your-username/cluster-dashboard:latest \
  --push .
```

## Deployment

Once pushed to Docker Hub, deploy with Helm:

```bash
# If using environment variable
helm install cluster-dashboard ./chart \
  -n cluster-dashboard \
  --create-namespace \
  --set image.repository=${DOCKERHUB_USERNAME}/cluster-dashboard

# Or if you edited values.yaml
helm install cluster-dashboard ./chart \
  -n cluster-dashboard \
  --create-namespace
```

## Docker Hub vs GitHub Container Registry

| Feature | Docker Hub | GitHub Container Registry |
|---------|-----------|---------------------------|
| Free tier | Yes (unlimited public images) | Yes (500MB free storage) |
| Build minutes | Limited | Generous GitHub Actions minutes |
| Image pulls | Unlimited for public images | Unlimited |
| Setup | Login with username/password | Login with GitHub token |
| URL format | `username/image:tag` | `ghcr.io/username/image:tag` |

## Creating a Docker Hub Repository

### Via Web UI

1. Go to https://hub.docker.com
2. Click "Create Repository"
3. Name: `cluster-dashboard`
4. Visibility: Public (or Private)
5. Click "Create"

### Via CLI (automatic on first push)

Docker Hub will automatically create the repository when you first push:

```bash
docker buildx build --platform linux/arm64 \
  -t your-username/cluster-dashboard:latest \
  --push .
```

## Using a Private Repository

If you want to keep your image private:

### 1. Create a Docker Hub token

1. Go to https://hub.docker.com/settings/security
2. Click "New Access Token"
3. Name: `kubernetes-cluster`
4. Permissions: Read & Write
5. Copy the token (save it securely!)

### 2. Create a Kubernetes secret

```bash
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=your-username \
  --docker-password=YOUR_TOKEN \
  -n cluster-dashboard
```

### 3. Update deployment to use the secret

Edit [chart/values.yaml](chart/values.yaml):
```yaml
imagePullSecrets:
  - name: dockerhub-secret
```

Or for kubectl deployment, edit [deployment.yaml](deployment.yaml):
```yaml
spec:
  imagePullSecrets:
    - name: dockerhub-secret
```

## Tagging Strategy

### Latest tag (default)
```bash
docker buildx build --platform linux/arm64 \
  -t your-username/cluster-dashboard:latest \
  --push .
```

### Version tags
```bash
# Semantic versioning
docker buildx build --platform linux/arm64 \
  -t your-username/cluster-dashboard:v0.1.0 \
  -t your-username/cluster-dashboard:latest \
  --push .
```

### Git commit tags
```bash
# Use git commit SHA
GIT_SHA=$(git rev-parse --short HEAD)
docker buildx build --platform linux/arm64 \
  -t your-username/cluster-dashboard:${GIT_SHA} \
  -t your-username/cluster-dashboard:latest \
  --push .
```

## Automating with GitHub Actions

Create `.github/workflows/docker-hub.yml`:

```yaml
name: Build and Push to Docker Hub

on:
  push:
    branches: [main]
    paths:
      - 'kubernetes/apps/cluster-dashboard/app/**'
  workflow_dispatch:

env:
  IMAGE_NAME: cluster-dashboard

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ secrets.DOCKERHUB_USERNAME }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: ./kubernetes/apps/cluster-dashboard/app
          platforms: linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

Then add secrets to GitHub:
1. Go to your repo → Settings → Secrets → Actions
2. Add `DOCKERHUB_USERNAME` (your Docker Hub username)
3. Add `DOCKERHUB_TOKEN` (your Docker Hub access token)

## Verifying the Image

After pushing, verify it's available:

```bash
# Check on Docker Hub
open https://hub.docker.com/r/your-username/cluster-dashboard

# Pull and inspect
docker pull your-username/cluster-dashboard:latest
docker inspect your-username/cluster-dashboard:latest

# Check size
docker images your-username/cluster-dashboard:latest
```

## Image Size Optimization

The current multi-stage build produces a ~100MB image. To verify:

```bash
docker images your-username/cluster-dashboard:latest

# Expected output:
# REPOSITORY                           TAG       SIZE
# your-username/cluster-dashboard      latest    ~100MB
```

This is already optimized! The image uses:
- Multi-stage build (builder + scratch)
- Static binary (CGO_ENABLED=0)
- Stripped symbols (-ldflags="-w -s")
- Minimal base (scratch)

## Troubleshooting

### "permission denied" when pushing

```bash
# Make sure you're logged in
docker login

# Check your credentials
docker logout
docker login
```

### "denied: requested access to the resource is denied"

The repository name must match your username:
```bash
# Correct
your-username/cluster-dashboard

# Wrong
someone-else/cluster-dashboard
```

### buildx not available

```bash
# Enable buildx
docker buildx create --use

# Or install manually
docker buildx install
```

### Image doesn't run on Raspberry Pi

Make sure you're building for ARM64:
```bash
docker buildx build --platform linux/arm64 ...
```

## Next Steps

1. Push your image to Docker Hub
2. Update the deployment manifests with your image name
3. Deploy to your cluster
4. (Optional) Set up GitHub Actions for automated builds

## Questions?

- Docker Hub docs: https://docs.docker.com/docker-hub/
- Buildx docs: https://docs.docker.com/buildx/
- Multi-platform builds: https://docs.docker.com/build/building/multi-platform/
