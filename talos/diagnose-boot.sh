#!/bin/bash
# Diagnose Talos Boot Issues
# Use this to check node connectivity and gather information

echo "========================================="
echo "Talos Boot Diagnostics"
echo "========================================="
echo ""

# Check node connectivity
echo "Testing node connectivity..."
echo ""
for node in 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14; do
    echo -n "Node $node: "
    if ping -c 1 -W 2 $node > /dev/null 2>&1; then
        echo "✓ Reachable"

        # Try to get more info if node is reachable
        echo "  Checking Talos API..."
        if talosctl -n $node get members --insecure 2>/dev/null | grep -q "NODE"; then
            echo "  ✓ Talos API responding (maintenance mode)"
        else
            echo "  ✗ Talos API not responding"
        fi
    else
        echo "✗ Not reachable"
    fi
done

echo ""
echo "========================================="
echo "Possible Issues and Solutions"
echo "========================================="
echo ""
echo "If control plane nodes are not reachable:"
echo ""
echo "1. Check physical connections:"
echo "   - Verify PoE HAT LEDs are on"
echo "   - Check Ethernet cables"
echo "   - Verify switch/router is working"
echo ""
echo "2. Boot mode issues:"
echo "   - Nodes may be in a boot loop"
echo "   - Check console output for error messages"
echo "   - Look for repeated DNS or network errors"
echo ""
echo "3. SD card issues:"
echo "   - Verify SD cards were flashed correctly"
echo "   - Try reflashing one card and test again"
echo ""
echo "4. Network configuration:"
echo "   - Check if DHCP is working on your network"
echo "   - Verify IPs .11-.14 are available"
echo "   - Check router/DHCP server logs"
echo ""
echo "5. VIP configuration interference:"
echo "   - VIP config might be preventing boot"
echo "   - Try booting without VIP first"
echo ""
echo "Next steps:"
echo ""
echo "Option A: Try booting without VIP config"
echo "  1. Reflash SD cards"
echo "  2. Generate config WITHOUT VIP integration"
echo "  3. Apply basic config first, add VIP later"
echo ""
echo "Option B: Check console output"
echo "  Connect HDMI/serial to see exact error messages"
echo ""
