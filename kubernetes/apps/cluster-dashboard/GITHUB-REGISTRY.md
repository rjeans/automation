# GitHub Container Registry Setup Guide

This guide shows you how to build and push the Cluster Dashboard image to GitHub Container Registry (GHCR).

## Why GitHub Container Registry?

✅ **Recommended for your setup** because:
- Already integrated with your Git workflow
- Free unlimited public image storage
- 500MB free private storage
- No rate limiting issues
- Faster pulls than Docker Hub
- One less service to manage
- Better privacy controls

## Prerequisites

- GitHub account
- Docker installed with buildx support
- Git repository (you already have this!)

## Quick Setup

### 1. Create a GitHub Personal Access Token

1. Go to https://github.com/settings/tokens
2. Click "Generate new token" → "Generate new token (classic)"
3. Name: `cluster-dashboard-packages`
4. Expiration: Choose your preference (90 days or no expiration)
5. Select scopes:
   - ✅ `write:packages` (Upload packages to GitHub Package Registry)
   - ✅ `read:packages` (Download packages from GitHub Package Registry)
   - ✅ `delete:packages` (Delete packages from GitHub Package Registry)
6. Click "Generate token"
7. **Copy the token** (you won't see it again!)

### 2. Login to GitHub Container Registry

```bash
# Login using your token
echo "YOUR_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# Or enter interactively
docker login ghcr.io -u YOUR_GITHUB_USERNAME
# Password: paste your token
```

### 3. Configure Your Username

**Option A: Use the setup script**
```bash
cd kubernetes/apps/cluster-dashboard
./setup.sh

# When prompted for Docker Hub username, enter:
# ghcr.io/YOUR_GITHUB_USERNAME
```

**Option B: Manual configuration**

Edit [chart/values.yaml](chart/values.yaml):
```yaml
image:
  repository: ghcr.io/your-github-username/cluster-dashboard
```

Edit [deployment.yaml](deployment.yaml):
```yaml
image: ghcr.io/your-github-username/cluster-dashboard:latest
```

Edit [Makefile](Makefile):
```makefile
IMAGE_REGISTRY ?= ghcr.io/your-github-username
```

### 4. Build and Push

**Using Makefile:**
```bash
# If you set IMAGE_REGISTRY in Makefile
make docker-push

# Or override at command line
make docker-push IMAGE_REGISTRY=ghcr.io/your-github-username
```

**Using Docker directly:**
```bash
cd app

# Build for Raspberry Pi (ARM64)
docker buildx build --platform linux/arm64 \
  -t ghcr.io/your-github-username/cluster-dashboard:latest \
  --push .
```

### 5. Make Image Public (Optional)

By default, images are private. To make it public:

1. Go to https://github.com/your-username?tab=packages
2. Find `cluster-dashboard`
3. Click on the package
4. Go to "Package settings" (bottom right)
5. Scroll to "Danger Zone"
6. Click "Change visibility" → "Public"

**OR** set it during push by adding a label to your Dockerfile:
```dockerfile
LABEL org.opencontainers.image.source=https://github.com/your-username/your-repo
```

## Using with Kubernetes

### Public Image (No Authentication Needed)

If your image is public, no additional setup is needed. Just deploy:

```bash
make helm-install
```

### Private Image (Requires Secret)

Create a Kubernetes secret with your GitHub token:

```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USERNAME \
  --docker-password=YOUR_TOKEN \
  -n cluster-dashboard
```

Update [chart/values.yaml](chart/values.yaml):
```yaml
imagePullSecrets:
  - name: ghcr-secret
```

Or for kubectl deployment, edit [deployment.yaml](deployment.yaml):
```yaml
spec:
  imagePullSecrets:
    - name: ghcr-secret
```

## Automated Builds with GitHub Actions

Create `.github/workflows/ghcr.yml`:

```yaml
name: Build and Push to GHCR

on:
  push:
    branches: [main]
    paths:
      - 'kubernetes/apps/cluster-dashboard/app/**'
  workflow_dispatch:

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository_owner }}/cluster-dashboard

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
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
          platforms: linux/arm64,linux/amd64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

**No secrets needed!** GitHub Actions automatically provides `GITHUB_TOKEN` with package permissions.

Just commit and push:
```bash
git add .github/workflows/ghcr.yml
git commit -m "Add automated GHCR builds"
git push
```

## Verification

### Check on GitHub

Visit: `https://github.com/YOUR_USERNAME?tab=packages`

You should see `cluster-dashboard` listed.

### Pull and Test

```bash
# Pull the image
docker pull ghcr.io/your-username/cluster-dashboard:latest

# Inspect it
docker inspect ghcr.io/your-username/cluster-dashboard:latest

# Check size
docker images ghcr.io/your-username/cluster-dashboard:latest
```

### Test on Kubernetes

```bash
# Port forward to test
kubectl port-forward -n cluster-dashboard svc/cluster-dashboard 8080:80

# Visit http://localhost:8080
```

## Comparison: GHCR vs Docker Hub

| Feature | GitHub Container Registry | Docker Hub |
|---------|---------------------------|------------|
| **Free public images** | Unlimited | Unlimited |
| **Free private storage** | 500MB | 1 private repo |
| **Rate limiting** | None | 100-200 pulls/6h |
| **Build minutes** | GitHub Actions included | Limited |
| **Authentication** | GitHub token | Separate password |
| **Integration** | Native Git integration | Separate service |
| **Pull performance** | Fast (CDN) | Good |
| **OCI compliance** | Full | Full |
| **Multi-arch support** | Yes | Yes |
| **Setup complexity** | Low (if using GitHub) | Low |
| **Best for** | Projects already on GitHub | Docker-first workflows |

## Token Management

### Storing Tokens Securely

**On your Mac (recommended):**
```bash
# Store in Keychain
security add-generic-password \
  -a YOUR_GITHUB_USERNAME \
  -s ghcr.io \
  -w YOUR_TOKEN

# Retrieve it
security find-generic-password \
  -a YOUR_GITHUB_USERNAME \
  -s ghcr.io \
  -w
```

**Or use pass (password manager):**
```bash
brew install pass
pass insert ghcr-token
# Enter your token

# Use it
docker login ghcr.io -u YOUR_USERNAME -p $(pass show ghcr-token)
```

### Rotating Tokens

When your token expires:

1. Generate new token on GitHub
2. Update Docker login: `docker login ghcr.io`
3. Update Kubernetes secret:
   ```bash
   kubectl delete secret ghcr-secret -n cluster-dashboard
   kubectl create secret docker-registry ghcr-secret \
     --docker-server=ghcr.io \
     --docker-username=YOUR_USERNAME \
     --docker-password=NEW_TOKEN \
     -n cluster-dashboard
   ```

## Linking Image to Repository

Add this to your Dockerfile to link the image to your repo:

```dockerfile
# At the top of your Dockerfile
LABEL org.opencontainers.image.source=https://github.com/YOUR_USERNAME/automation
LABEL org.opencontainers.image.description="Cluster Dashboard for Raspberry Pi Kubernetes"
LABEL org.opencontainers.image.licenses=MIT
```

This makes the image appear in your repository's sidebar.

## Troubleshooting

### "denied: permission_denied"

```bash
# Make sure you're logged in
docker login ghcr.io

# Verify token has write:packages scope
# Regenerate token if needed
```

### "unauthorized: unauthenticated"

```bash
# Token expired or invalid
docker logout ghcr.io
docker login ghcr.io -u YOUR_USERNAME
# Enter token again
```

### Image not showing in GitHub

1. Check image exists: `docker pull ghcr.io/your-username/cluster-dashboard:latest`
2. Add labels to Dockerfile (see "Linking Image to Repository")
3. Rebuild and push

### Can't pull image in Kubernetes

```bash
# For private images, create the secret
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_TOKEN \
  -n cluster-dashboard

# Verify secret exists
kubectl get secret ghcr-secret -n cluster-dashboard -o yaml
```

## Migration from Docker Hub

Already using Docker Hub? Easy to migrate:

```bash
# Pull from Docker Hub
docker pull your-username/cluster-dashboard:latest

# Tag for GHCR
docker tag your-username/cluster-dashboard:latest \
  ghcr.io/your-github-username/cluster-dashboard:latest

# Push to GHCR
docker push ghcr.io/your-github-username/cluster-dashboard:latest

# Update Kubernetes
kubectl set image deployment/cluster-dashboard \
  dashboard=ghcr.io/your-github-username/cluster-dashboard:latest \
  -n cluster-dashboard
```

## Best Practices

1. **Use GitHub Actions** for automated builds
2. **Tag releases** with semantic versioning
3. **Make public images public** (no rate limits)
4. **Use fine-grained tokens** (not classic tokens)
5. **Set token expiration** for security
6. **Store tokens in Keychain** on macOS
7. **Link images to repo** with labels

## Next Steps

1. Generate GitHub Personal Access Token
2. Login to GHCR: `docker login ghcr.io`
3. Build and push: `make docker-push`
4. Deploy: `make helm-install`
5. (Optional) Set up GitHub Actions for automation

## Resources

- GHCR Docs: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
- GitHub Actions: https://docs.github.com/en/actions
- OCI Image Spec: https://github.com/opencontainers/image-spec
