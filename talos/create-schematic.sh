#!/bin/bash
# Create Talos Image Factory Schematic from Overlay
# This creates a schematic using the Talos Image Factory API

set -e

TALOS_VERSION="${1:-v1.11.3}"
PROJECT_DIR="/Users/rich/Library/CloudStorage/Dropbox/Development/pi-cluster"
OVERLAY_FILE="$PROJECT_DIR/raspberrypi/rpi_poe.yaml"

echo "========================================="
echo "Create Talos Image Factory Schematic"
echo "========================================="
echo "Talos Version: $TALOS_VERSION"
echo "Overlay File: $OVERLAY_FILE"
echo ""

# Check if overlay file exists
if [ ! -f "$OVERLAY_FILE" ]; then
    echo "ERROR: Overlay file not found: $OVERLAY_FILE"
    exit 1
fi

echo "Overlay configuration:"
cat "$OVERLAY_FILE"
echo ""

echo "========================================="
echo "Creating Schematic..."
echo "========================================="
echo ""

# Create schematic using API
RESPONSE=$(curl -s -X POST --data-binary @"$OVERLAY_FILE" https://factory.talos.dev/schematics)
SCHEMATIC_ID=$(echo "$RESPONSE" | grep -oE '[a-f0-9]{64}')

if [ -z "$SCHEMATIC_ID" ]; then
    echo "✗ Failed to create schematic"
    echo ""
    echo "Response:"
    echo "$RESPONSE"
    exit 1
fi

echo "✓ Schematic Created!"
echo ""
echo "========================================="
echo "Schematic Details"
echo "========================================="
echo ""
echo "Schematic ID: $SCHEMATIC_ID"
echo ""
echo "========================================="
echo "Download Images"
echo "========================================="
echo ""
echo "1. Raw disk image (for SD card flashing):"
echo "   wget https://factory.talos.dev/image/$SCHEMATIC_ID/$TALOS_VERSION/metal-arm64.raw.xz"
echo "   xz -d metal-arm64.raw.xz"
echo ""
echo "2. Installer image (for machine config):"
echo "   factory.talos.dev/installer/$SCHEMATIC_ID:$TALOS_VERSION"
echo ""
echo "========================================="
echo "Quick Download Command"
echo "========================================="
echo ""
echo "cd ~/Downloads"
echo "wget https://factory.talos.dev/image/$SCHEMATIC_ID/$TALOS_VERSION/metal-arm64.raw.xz"
echo "xz -d metal-arm64.raw.xz"
echo ""
echo "Then flash to SD cards:"
echo "  diskutil list"
echo "  diskutil unmountDisk /dev/diskN"
echo "  sudo dd if=metal-arm64.raw of=/dev/rdiskN bs=4M conv=fsync"
echo "  diskutil eject /dev/diskN"
echo ""
echo "========================================="
echo "Machine Config Reference"
echo "========================================="
echo ""
echo "Add this to your machine config if needed:"
echo ""
echo "machine:"
echo "  install:"
echo "    image: factory.talos.dev/installer/$SCHEMATIC_ID:$TALOS_VERSION"
echo ""

# Save schematic ID to file for reference
echo "$SCHEMATIC_ID" > "$PROJECT_DIR/talos/.schematic-id"
echo "✓ Schematic ID saved to: talos/.schematic-id"
echo ""
