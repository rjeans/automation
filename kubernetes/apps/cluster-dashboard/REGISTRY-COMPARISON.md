# Container Registry Comparison

Quick comparison to help you choose between GitHub Container Registry and Docker Hub.

## TL;DR

**For macOS with GitHub repos → Use GitHub Container Registry (GHCR)** ✅

## Detailed Comparison

| Feature | GitHub Container Registry | Docker Hub |
|---------|--------------------------|------------|
| **Price (Free Tier)** | Unlimited public images | Unlimited public images |
| **Private Storage** | 500MB free | 1 private repo only |
| **Pull Rate Limits** | ❌ None | ⚠️ 100-200 pulls per 6 hours |
| **Authentication** | GitHub token | Separate password/token |
| **Integration** | Native with GitHub repos | Separate service |
| **CI/CD** | Built-in with GitHub Actions | Requires setup |
| **Image URL** | `ghcr.io/username/image` | `username/image` |
| **Setup Time** | 5 minutes | 5 minutes |
| **Multi-arch Support** | ✅ Yes | ✅ Yes |
| **OCI Compliance** | ✅ Full | ✅ Full |
| **CDN Performance** | Fast | Good |
| **Ideal For** | Projects on GitHub | Docker-first workflows |

## Why GHCR is Better for Your Setup

### 1. You're Already Using GitHub
Your automation repo is likely on GitHub, so GHCR is native:
- No separate account needed
- Images linked to your repo automatically
- One less service to manage

### 2. No Rate Limiting
Docker Hub free tier limits:
- 100 pulls per 6 hours (anonymous)
- 200 pulls per 6 hours (authenticated)

This can be problematic when:
- Testing deployments repeatedly
- Multiple nodes pulling the same image
- CI/CD pipelines running frequently

GHCR has **no rate limits**.

### 3. Better Free Private Images
- **GHCR**: 500MB of private storage
- **Docker Hub**: Only 1 private repository

### 4. Easier Authentication
**GHCR:**
```bash
# Use your GitHub Personal Access Token
docker login ghcr.io -u YOUR_GITHUB_USERNAME
# Password: [paste token]
```

**Docker Hub:**
```bash
# Need separate Docker Hub account
docker login
# Username: your-dockerhub-username
# Password: [separate password]
```

### 5. Built-in CI/CD
GitHub Actions automatically provides `GITHUB_TOKEN` for pushing to GHCR - no secrets needed!

**GHCR (no extra setup):**
```yaml
- name: Login to GitHub Container Registry
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}  # ← Already available!
```

**Docker Hub (requires setup):**
```yaml
- name: Login to Docker Hub
  uses: docker/login-action@v3
  with:
    username: ${{ secrets.DOCKERHUB_USERNAME }}  # ← Must add secret
    password: ${{ secrets.DOCKERHUB_TOKEN }}     # ← Must add secret
```

## When to Use Docker Hub

Docker Hub might be better if:

1. **You're already heavily invested in Docker Hub**
   - Existing images there
   - Team familiar with it
   - Don't want to migrate

2. **You need Docker Hub specific features**
   - Official Docker Images (base images)
   - Docker Hub webhooks
   - Docker Hub API integrations

3. **Not using GitHub**
   - Code hosted elsewhere (GitLab, Bitbucket)
   - No GitHub account

4. **Want traditional Docker workflow**
   - More familiar to Docker users
   - Shorter image names (no `ghcr.io/` prefix)

## Cost Comparison (Beyond Free Tier)

| Feature | GHCR | Docker Hub |
|---------|------|------------|
| **Public images** | Always free | Always free |
| **Private storage** | $0.25/GB/month | $5/month (Pro tier) |
| **Bandwidth** | Free | Free |
| **Image builds** | Via GitHub Actions | Via Docker Hub (limited) |

For a 10GB private registry:
- **GHCR**: ~$2.50/month
- **Docker Hub**: $5/month (minimum)

## Real-World Example: Your Cluster Dashboard

### Scenario: Testing deployments

You're tweaking your dashboard and deploying multiple times to test:

**With Docker Hub (free tier):**
```
Pull 1: ✅ Success
Pull 2: ✅ Success
...
Pull 100: ✅ Success
Pull 101: ❌ Rate limited! Wait 6 hours.
```

**With GHCR:**
```
Pull 1: ✅ Success
Pull 2: ✅ Success
...
Pull 500: ✅ Success  (no limits!)
```

### Scenario: Multi-node cluster

You have 4 Raspberry Pis, each pulling the image:

**Docker Hub:** 4 pulls counted toward your limit

**GHCR:** No limit to worry about

## Migration is Easy

Already using Docker Hub? Switching is simple:

```bash
# Pull from Docker Hub
docker pull your-username/cluster-dashboard:latest

# Tag for GHCR
docker tag your-username/cluster-dashboard:latest \
  ghcr.io/your-github-username/cluster-dashboard:latest

# Push to GHCR
docker push ghcr.io/your-github-username/cluster-dashboard:latest

# Update deployment
kubectl set image deployment/cluster-dashboard \
  dashboard=ghcr.io/your-github-username/cluster-dashboard:latest \
  -n cluster-dashboard
```

## Setup Time Comparison

### GHCR Setup
```bash
# 1. Create GitHub token (one-time)
# Visit: https://github.com/settings/tokens
# Scopes: write:packages, read:packages

# 2. Login
docker login ghcr.io -u YOUR_GITHUB_USERNAME

# 3. Push
docker push ghcr.io/your-github-username/cluster-dashboard:latest
```
**Time: 5 minutes**

### Docker Hub Setup
```bash
# 1. Create Docker Hub account (one-time)
# Visit: https://hub.docker.com

# 2. Login
docker login

# 3. Push
docker push your-dockerhub-username/cluster-dashboard:latest
```
**Time: 5 minutes**

Both are equally fast to set up!

## Recommendation for Your Situation

### You mentioned: "I am using Docker on Mac OS X"

Since you're on macOS and likely using GitHub for your automation repo:

**Use GitHub Container Registry (GHCR)** ✅

**Reasons:**
1. No rate limiting issues
2. Already integrated with your workflow
3. Better free tier for private images
4. Easier CI/CD with GitHub Actions
5. One less service to manage
6. Native integration with your repo

### Quick Start with GHCR

```bash
# Run the setup script
cd kubernetes/apps/cluster-dashboard
./setup.sh
# Choose option 1 (GHCR)

# Create GitHub token
open https://github.com/settings/tokens

# Login to GHCR
docker login ghcr.io -u YOUR_GITHUB_USERNAME

# Build and push
make docker-push

# Deploy
make helm-install
```

## Still Want Docker Hub?

That's totally fine! Both work great. The setup script supports both:

```bash
./setup.sh
# Choose option 2 (Docker Hub)
```

Or see [DOCKER-HUB.md](DOCKER-HUB.md) for detailed Docker Hub instructions.

## Questions?

- **"Can I use both?"** Yes! You can push to both registries.
- **"Can I switch later?"** Yes! Migration takes ~2 minutes.
- **"Which is faster?"** Both are fast, GHCR has better CDN coverage.
- **"Which is more reliable?"** Both are highly reliable.

## Summary

For your Raspberry Pi Kubernetes cluster on macOS with GitHub:

**🏆 Winner: GitHub Container Registry (GHCR)**

- No rate limits
- Better free tier
- Native GitHub integration
- Easier automation
- One less password to manage

**But Docker Hub works too!** Choose what feels right for you.
