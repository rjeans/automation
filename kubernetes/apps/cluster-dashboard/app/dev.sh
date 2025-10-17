#!/bin/bash
# Development server with hot reload

# Set environment variables for local development
export PORT=3000

# Get GOPATH
GOPATH=$(go env GOPATH)
AIR_BIN="${GOPATH}/bin/air"

# Check if air is installed
if [ ! -f "$AIR_BIN" ]; then
    echo "air not found. Installing..."
    go install github.com/air-verse/air@latest
fi

# Run air for hot reload
echo "Starting dashboard with hot reload on port 3000..."
echo "Press Ctrl+C to stop"
echo ""

"$AIR_BIN"
