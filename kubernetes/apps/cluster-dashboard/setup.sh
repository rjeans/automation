#!/bin/bash

# Cluster Dashboard Setup Script
# This script helps configure the Docker Hub username and domain name

set -e

echo "=========================================="
echo "Cluster Dashboard - Setup Script"
echo "=========================================="
echo ""

# Choose registry
echo "Step 1: Choose Container Registry"
echo "----------------------------------"
echo "1) GitHub Container Registry (GHCR) - Recommended"
echo "   - Free unlimited public images"
echo "   - Already integrated with GitHub"
echo "   - No rate limiting"
echo ""
echo "2) Docker Hub"
echo "   - Traditional Docker registry"
echo "   - Rate limits on free tier"
echo ""
read -p "Choose registry (1 or 2): " REGISTRY_CHOICE

if [ "$REGISTRY_CHOICE" = "1" ]; then
    echo ""
    echo "GitHub Container Registry selected"
    echo "----------------------------------"
    read -p "Enter your GitHub username: " GITHUB_USERNAME

    if [ -z "$GITHUB_USERNAME" ]; then
        echo "Error: GitHub username is required"
        exit 1
    fi

    IMAGE_REPO="ghcr.io/${GITHUB_USERNAME}/cluster-dashboard"
    REGISTRY_TYPE="ghcr"
    REGISTRY_USER="$GITHUB_USERNAME"

elif [ "$REGISTRY_CHOICE" = "2" ]; then
    echo ""
    echo "Docker Hub selected"
    echo "-------------------"
    read -p "Enter your Docker Hub username: " DOCKERHUB_USERNAME

    if [ -z "$DOCKERHUB_USERNAME" ]; then
        echo "Error: Docker Hub username is required"
        exit 1
    fi

    IMAGE_REPO="${DOCKERHUB_USERNAME}/cluster-dashboard"
    REGISTRY_TYPE="dockerhub"
    REGISTRY_USER="$DOCKERHUB_USERNAME"

else
    echo "Error: Invalid choice"
    exit 1
fi

# Get domain name
echo ""
echo "Step 2: Domain Configuration"
echo "-----------------------------"
read -p "Enter your dashboard domain (e.g., dashboard.yourdomain.com): " DOMAIN_NAME

if [ -z "$DOMAIN_NAME" ]; then
    echo "Error: Domain name is required"
    exit 1
fi

# Confirm
echo ""
echo "Configuration Summary:"
echo "----------------------"
echo "Container Registry: $REGISTRY_TYPE"
echo "Image Repository: $IMAGE_REPO"
echo "Dashboard Domain: $DOMAIN_NAME"
echo ""
read -p "Is this correct? (y/n): " CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Setup cancelled."
    exit 0
fi

# Update files
echo ""
echo "Updating configuration files..."

# Update Makefile
echo "  - Updating Makefile..."
if [ "$REGISTRY_TYPE" = "ghcr" ]; then
    sed -i.bak "s|IMAGE_REGISTRY ?= ghcr.io/YOUR_GITHUB_USERNAME|IMAGE_REGISTRY ?= ghcr.io/$REGISTRY_USER|" Makefile
else
    sed -i.bak "s|IMAGE_REGISTRY ?= ghcr.io/YOUR_GITHUB_USERNAME|IMAGE_REGISTRY ?= $REGISTRY_USER|" Makefile
fi

# Update chart/values.yaml
echo "  - Updating chart/values.yaml..."
sed -i.bak "s|repository: ghcr.io/YOUR_GITHUB_USERNAME/cluster-dashboard|repository: $IMAGE_REPO|" chart/values.yaml
sed -i.bak "s/dashboard.automation.local/$DOMAIN_NAME/g" chart/values.yaml

# Update deployment.yaml
echo "  - Updating deployment.yaml..."
sed -i.bak "s|image: ghcr.io/YOUR_GITHUB_USERNAME/cluster-dashboard:latest|image: $IMAGE_REPO:latest|" deployment.yaml

# Update ingress.yaml
echo "  - Updating ingress.yaml..."
sed -i.bak "s/dashboard.automation.local/$DOMAIN_NAME/g" ingress.yaml

# Clean up backup files
echo "  - Cleaning up backup files..."
rm -f Makefile.bak chart/values.yaml.bak deployment.yaml.bak ingress.yaml.bak

echo ""
echo "✓ Configuration complete!"
echo ""
echo "Next Steps:"
echo "-----------"

if [ "$REGISTRY_TYPE" = "ghcr" ]; then
    echo "1. Create GitHub Personal Access Token:"
    echo "   https://github.com/settings/tokens"
    echo "   Scopes needed: write:packages, read:packages"
    echo ""
    echo "2. Login to GitHub Container Registry:"
    echo "   docker login ghcr.io -u $REGISTRY_USER"
    echo ""
else
    echo "1. Login to Docker Hub:"
    echo "   docker login"
    echo ""
fi

echo "2. Build and push the image:"
echo "   make docker-push"
echo ""
echo "3. Deploy to your cluster:"
echo "   make helm-install"
echo ""
echo "4. Check deployment status:"
echo "   make status"
echo ""
echo "5. Access your dashboard:"
echo "   https://$DOMAIN_NAME"
echo ""
echo "For more details, see:"
echo "  - QUICKSTART.md for quick deployment"
if [ "$REGISTRY_TYPE" = "ghcr" ]; then
    echo "  - GITHUB-REGISTRY.md for GHCR setup details"
else
    echo "  - DOCKER-HUB.md for Docker Hub setup details"
fi
echo "  - DEPLOYMENT.md for detailed deployment guide"
echo ""
