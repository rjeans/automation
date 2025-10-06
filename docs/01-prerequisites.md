# Prerequisites and Preparation

## Hardware Requirements

### Raspberry Pi Cluster
- **4x Raspberry Pi 4** (8GB RAM recommended, 4GB minimum)
- **4x microSD cards** (32GB minimum, 64GB recommended, Class 10/U3 or better)
- **Network switch** with gigabit Ethernet ports (5+ ports)
- **4x Power supplies** (official Raspberry Pi USB-C power supplies recommended)
- **4x Ethernet cables** (Cat5e or Cat6)
- **Optional**: Case with cooling fans for each Pi

### Management Machine
- Laptop/desktop for running `talosctl` and `kubectl`
- macOS, Linux, or Windows with WSL2

## Network Planning

### IP Address Allocation
Cluster IP addresses:

| Hostname | Role | IP Address | Notes |
|----------|------|------------|-------|
| rpi-cp01 | Control Plane | 192.168.1.11 | Primary control plane node |
| rpi-cp02 | Control Plane | 192.168.1.12 | Secondary control plane node (HA) |
| rpi-worker01 | Worker | 192.168.1.13 | Worker node |
| rpi-worker02 | Worker | 192.168.1.14 | Worker node |

**Action Items**:
- [ ] Assign static IPs in your DHCP server based on MAC addresses
- [ ] Document MAC addresses for each Pi
- [ ] Reserve IPs for load balancer VIPs if needed
- [ ] Plan DNS records (optional but recommended)

### Network Requirements
- All nodes must be on the same subnet
- Internet access required for pulling container images
- Open ports between nodes (Talos handles this automatically)
- Consider VLAN segmentation for security (optional)

## Software Installation

### Install talosctl CLI

**macOS** (using Homebrew):
```bash
brew install siderolabs/tap/talosctl
```

**macOS/Linux** (manual):
```bash
curl -sL https://talos.dev/install | sh
```

**Verify installation**:
```bash
talosctl version --client
```

### Install kubectl

**macOS** (using Homebrew):
```bash
brew install kubectl
```

**Linux**:
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

**Verify installation**:
```bash
kubectl version --client
```

### Install SOPS (for secrets encryption)

**macOS**:
```bash
brew install sops
```

**Linux**:
```bash
# Download latest release from https://github.com/mozilla/sops/releases
wget https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
chmod +x sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
```

### Install age (for SOPS encryption)

**macOS**:
```bash
brew install age
```

**Linux**:
```bash
# Download from https://github.com/FiloSottile/age/releases
wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
tar xzf age-v1.1.1-linux-amd64.tar.gz
sudo mv age/age /usr/local/bin/
sudo mv age/age-keygen /usr/local/bin/
```

### Install xz (for decompressing Talos images)

**macOS**:
```bash
brew install xz
```

**Linux**:
```bash
# Debian/Ubuntu
sudo apt install xz-utils

# RHEL/CentOS/Fedora
sudo yum install xz
```

**Note**: Most systems have `xz` pre-installed. Verify with `xz --version`.

## Raspberry Pi Preparation

### Update EEPROM Firmware

**Important**: Update the EEPROM before installing Talos for best compatibility.

1. **Download Raspberry Pi Imager**
   - Get it from: https://www.raspberrypi.com/software/

2. **Update Each Pi**:
   - Insert a microSD card
   - Open Raspberry Pi Imager
   - Choose: **Misc utility images** → **Bootloader** → **SD Card Boot**
   - Write to SD card
   - Boot Raspberry Pi with this card
   - Wait for green LED to blink rapidly (update complete)
   - Power off and remove card

3. **Verify EEPROM version** (optional):
   - Boot with Raspberry Pi OS temporarily
   - Run: `sudo rpi-eeprom-update`
   - Should show recent version (2023 or later)

### Label Your Raspberry Pis

Physical labels help identify nodes:
- Use label maker or tape
- Mark each Pi with its hostname (e.g., "rpi-cp01")
- Note MAC addresses on labels for IP allocation

### Verify Hardware

Before proceeding:
- [ ] All Pis power on correctly
- [ ] All Pis have updated EEPROM
- [ ] Network switch has power and ports work
- [ ] SD cards are good quality and formatted

## Security Preparation

### Generate age Encryption Key

Create encryption key for SOPS:

```bash
# Generate key
age-keygen -o age.key

# Output will show public key like:
# Public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

**Important**:
- Store `age.key` securely (password manager, encrypted drive)
- Add `age.key` to `.gitignore` (already done)
- Back up the key - you cannot decrypt secrets without it
- Share public key with team members who need to encrypt secrets

### Create .sops.yaml Configuration

```bash
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: .*.enc.yaml$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
  - path_regex: talos/secrets/.*
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
EOF
```

Replace the public key with your actual age public key.

## Pre-flight Checklist

Before proceeding to Talos installation:

- [ ] All 4 Raspberry Pis have updated EEPROM
- [ ] Network IPs planned and documented
- [ ] SD cards prepared (high quality, sufficient size)
- [ ] `talosctl` installed and working
- [ ] `kubectl` installed and working
- [ ] `sops` and `age` installed
- [ ] `xz` installed (for decompressing Talos images)
- [ ] Age encryption key generated and backed up
- [ ] `.sops.yaml` configured with public key
- [ ] Git repository initialized
- [ ] Physical workspace organized with labels

## Next Steps

Once all prerequisites are complete, proceed to:
- **[00-network-plan.md](./00-network-plan.md)** - Review network planning
- **[02-talos-installation.md](./02-talos-installation.md)** - Install Talos Linux on Raspberry Pis

## Additional Resources

- [Talos Linux Documentation](https://www.talos.dev/latest/)
- [Talos Raspberry Pi Guide](https://www.talos.dev/latest/talos-guides/install/single-board-computers/rpi_generic/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [SOPS Documentation](https://github.com/mozilla/sops)
