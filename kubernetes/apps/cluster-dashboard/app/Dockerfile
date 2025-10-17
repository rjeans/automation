# Multi-stage build for minimal final image
# Stage 1: Build the Go application
FROM golang:1.23-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /build

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY cmd/ ./cmd/
COPY internal/ ./internal/

# Build the application
# CGO_ENABLED=0 for static binary
# -ldflags="-w -s" to strip debug info and reduce size
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build \
    -ldflags="-w -s" \
    -o cluster-dashboard \
    ./cmd/main.go

# Stage 2: Create minimal runtime image with talosctl
FROM alpine:3.19

# Install talosctl and required dependencies
RUN apk add --no-cache ca-certificates tzdata curl && \
    TALOS_VERSION="v1.8.3" && \
    curl -sL https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-arm64 -o /usr/local/bin/talosctl && \
    chmod +x /usr/local/bin/talosctl

# Copy the binary
COPY --from=builder /build/cluster-dashboard /cluster-dashboard

# Copy web templates and static files
COPY web/ /app/web/

# Run as non-root user
USER 65534:65534

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/cluster-dashboard", "health"]

# Run the application
ENTRYPOINT ["/cluster-dashboard"]
