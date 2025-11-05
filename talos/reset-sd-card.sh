#!/bin/bash
# SD Card Reset Script for Talos
# This removes the machine config to force the node into maintenance mode

echo "========================================="
echo "Talos SD Card Reset Script"
echo "========================================="
echo ""
echo "This script will reset a Talos SD card to allow recovery."
echo "Make sure the SD card is mounted on your Mac."
echo ""

# List available volumes
echo "Available volumes:"
ls /Volumes/ | grep -v "Macintosh HD"
echo ""

read -p "Enter the SD card mount name (e.g., STATE or BOOT): " MOUNT_NAME

if [ -z "$MOUNT_NAME" ]; then
    echo "ERROR: No mount name provided"
    exit 1
fi

MOUNT_PATH="/Volumes/$MOUNT_NAME"

if [ ! -d "$MOUNT_PATH" ]; then
    echo "ERROR: Mount path not found: $MOUNT_PATH"
    exit 1
fi

echo ""
echo "Searching for Talos configuration files..."

# Common locations for machine config
CONFIG_PATHS=(
    "$MOUNT_PATH/system/state/config.yaml"
    "$MOUNT_PATH/machine-config.yaml"
    "$MOUNT_PATH/config.yaml"
)

FOUND=0
for CONFIG in "${CONFIG_PATHS[@]}"; do
    if [ -f "$CONFIG" ]; then
        echo "Found: $CONFIG"

        # Backup the config
        BACKUP="${CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "Creating backup: $BACKUP"
        cp "$CONFIG" "$BACKUP"

        # Remove the config
        echo "Removing config to force maintenance mode..."
        rm "$CONFIG"

        FOUND=1
        echo "✓ Config removed successfully"
    fi
done

if [ $FOUND -eq 0 ]; then
    echo "No machine config found in standard locations."
    echo "Listing all YAML files on the SD card:"
    find "$MOUNT_PATH" -name "*.yaml" 2>/dev/null
    echo ""
    echo "You may need to manually locate and remove the machine config."
fi

echo ""
echo "========================================="
echo "Next steps:"
echo "========================================="
echo "1. Eject the SD card from your Mac"
echo "2. Insert it back into the Raspberry Pi"
echo "3. Power on the Pi"
echo "4. Wait 60-90 seconds for it to boot into maintenance mode"
echo "5. Run: ./recover-node.sh <node-ip>"
echo ""
echo "Example: ./recover-node.sh 192.168.1.11"
