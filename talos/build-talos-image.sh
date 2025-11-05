#!/bin/bash
# Build Custom Talos Image with PoE HAT Support
# This creates a Talos image configured for Raspberry Pi with PoE HATs

set -e

TALOS_VERSION="${1:-v1.11.3}"
OUTPUT_DIR="${2:-$HOME/Downloads/_out}"
PROJECT_DIR="/Users/rich/Library/CloudStorage/Dropbox/Development/pi-cluster"

echo "========================================="
echo "Build Custom Talos Image"
echo "========================================="
echo "Talos Version: $TALOS_VERSION"
echo "Output Directory: $OUTPUT_DIR"
echo "Overlay: raspberrypi/rpi_poe.yaml"
echo ""

# Check if overlay file exists
if [ ! -f "$PROJECT_DIR/raspberrypi/rpi_poe.yaml" ]; then
    echo "ERROR: Overlay file not found: $PROJECT_DIR/raspberrypi/rpi_poe.yaml"
    exit 1
fi

echo "Overlay configuration:"
cat "$PROJECT_DIR/raspberrypi/rpi_poe.yaml"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "========================================="
echo "Pulling Talos imager..."
echo "========================================="
docker pull ghcr.io/siderolabs/imager:$TALOS_VERSION

echo ""
echo "========================================="
echo "Building custom Talos image..."
echo "========================================="
echo "This will take ~10 minutes..."
echo ""

docker run --rm -t \
    -v "$OUTPUT_DIR:/out" \
    -v "$PROJECT_DIR/raspberrypi:/raspberrypi:ro" \
    ghcr.io/siderolabs/imager:$TALOS_VERSION \
    sbc \
    --arch arm64 \
    --board rpi_generic \
    --overlay @/raspberrypi/rpi_poe.yaml

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================="
    echo "✓ Build Complete!"
    echo "========================================="
    echo ""
    echo "Image location: $OUTPUT_DIR/sbc-rpi_generic-arm64.raw"
    echo ""
    echo "Image size:"
    ls -lh "$OUTPUT_DIR/sbc-rpi_generic-arm64.raw"
    echo ""
    echo "========================================="
    echo "Next Steps"
    echo "========================================="
    echo ""
    echo "Flash SD cards with this command:"
    echo ""
    echo "  diskutil list                    # Find your SD card"
    echo "  diskutil unmountDisk /dev/diskN  # Replace N with disk number"
    echo "  sudo dd if=$OUTPUT_DIR/sbc-rpi_generic-arm64.raw of=/dev/rdiskN bs=4M conv=fsync"
    echo "  diskutil eject /dev/diskN"
    echo ""
    echo "Repeat for all 4 SD cards."
    echo ""
    echo "See: talos/FRESH-INSTALL.md for complete installation guide"
    echo ""
else
    echo ""
    echo "✗ Build failed"
    exit 1
fi
