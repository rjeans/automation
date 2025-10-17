.PHONY: build push deploy test clean help

# Variables
# For GitHub Container Registry (recommended): ghcr.io/your-github-username
# For Docker Hub: your-dockerhub-username
IMAGE_REGISTRY ?= ghcr.io/rjeans
IMAGE_NAME ?= cluster-dashboard
IMAGE_TAG ?= latest
NAMESPACE ?= cluster-dashboard
HELM_RELEASE ?= cluster-dashboard

# Build the Go application locally
build:
	@echo "Building Go application..."
	cd app && go build -o ../bin/cluster-dashboard ./cmd/main.go

# Build Docker image for ARM64 (Raspberry Pi)
docker-build:
	@echo "Building Docker image for ARM64..."
	cd app && docker buildx build \
		--platform linux/arm64 \
		-t $(IMAGE_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG) \
		.

# Build and push Docker image
docker-push:
	@echo "Building and pushing Docker image..."
	cd app && docker buildx build \
		--platform linux/arm64 \
		-t $(IMAGE_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG) \
		--push \
		.

# Deploy using Helm
helm-install:
	@echo "Installing with Helm..."
	helm install $(HELM_RELEASE) ./chart \
		-n $(NAMESPACE) \
		--create-namespace

# Upgrade Helm deployment
helm-upgrade:
	@echo "Upgrading with Helm..."
	helm upgrade $(HELM_RELEASE) ./chart \
		-n $(NAMESPACE) \
		--reuse-values

# Uninstall Helm deployment
helm-uninstall:
	@echo "Uninstalling Helm release..."
	helm uninstall $(HELM_RELEASE) -n $(NAMESPACE)

# Deploy using kubectl
kubectl-deploy:
	@echo "Deploying with kubectl..."
	kubectl apply -f namespace.yaml
	kubectl apply -f rbac.yaml
	kubectl apply -f deployment.yaml
	kubectl apply -f service.yaml
	kubectl apply -f network-policy.yaml
	kubectl apply -f ingress.yaml

# Delete deployment with kubectl
kubectl-delete:
	@echo "Deleting deployment..."
	kubectl delete -f ingress.yaml
	kubectl delete -f network-policy.yaml
	kubectl delete -f service.yaml
	kubectl delete -f deployment.yaml
	kubectl delete -f rbac.yaml
	kubectl delete -f namespace.yaml

# View logs
logs:
	@echo "Viewing logs..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(IMAGE_NAME) -f

# Check deployment status
status:
	@echo "Checking deployment status..."
	@echo "\n=== Pods ==="
	kubectl get pods -n $(NAMESPACE)
	@echo "\n=== Services ==="
	kubectl get svc -n $(NAMESPACE)
	@echo "\n=== Ingress ==="
	kubectl get ingress -n $(NAMESPACE)
	@echo "\n=== Certificates ==="
	kubectl get certificate -n $(NAMESPACE)

# Port forward for local testing
port-forward:
	@echo "Port forwarding to localhost:8080..."
	kubectl port-forward -n $(NAMESPACE) svc/$(IMAGE_NAME) 8080:80

# Run tests locally
test:
	@echo "Running tests..."
	cd app && go test -v ./...

# Lint Go code
lint:
	@echo "Linting Go code..."
	cd app && golangci-lint run ./...

# Format Go code
fmt:
	@echo "Formatting Go code..."
	cd app && go fmt ./...

# Tidy Go modules
tidy:
	@echo "Tidying Go modules..."
	cd app && go mod tidy

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf bin/
	cd app && rm -f cluster-dashboard

# Full rebuild and deploy
deploy-all: docker-push helm-upgrade
	@echo "Deployment complete!"
	$(MAKE) status

# Development workflow
dev: fmt tidy build
	@echo "Development build complete!"

# Show help
help:
	@echo "Cluster Dashboard - Makefile Commands"
	@echo ""
	@echo "Building:"
	@echo "  make build          - Build Go binary locally"
	@echo "  make docker-build   - Build Docker image for ARM64"
	@echo "  make docker-push    - Build and push Docker image"
	@echo ""
	@echo "Deployment:"
	@echo "  make helm-install   - Install with Helm"
	@echo "  make helm-upgrade   - Upgrade Helm deployment"
	@echo "  make helm-uninstall - Uninstall Helm release"
	@echo "  make kubectl-deploy - Deploy with kubectl"
	@echo "  make kubectl-delete - Delete kubectl deployment"
	@echo ""
	@echo "Development:"
	@echo "  make dev            - Format, tidy, and build"
	@echo "  make test           - Run tests"
	@echo "  make lint           - Lint code"
	@echo "  make fmt            - Format code"
	@echo "  make tidy           - Tidy Go modules"
	@echo ""
	@echo "Operations:"
	@echo "  make logs           - View pod logs"
	@echo "  make status         - Check deployment status"
	@echo "  make port-forward   - Forward port to localhost:8080"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make deploy-all     - Full rebuild and deploy"
	@echo ""
	@echo "Variables:"
	@echo "  IMAGE_REGISTRY      - Container registry (default: ghcr.io/automation)"
	@echo "  IMAGE_NAME          - Image name (default: cluster-dashboard)"
	@echo "  IMAGE_TAG           - Image tag (default: latest)"
	@echo "  NAMESPACE           - Kubernetes namespace (default: cluster-dashboard)"
