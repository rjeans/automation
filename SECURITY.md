# Security Policy

## Overview

This repository contains Infrastructure as Code (IaC) for a Talos Kubernetes cluster. Security is a top priority, and we follow industry best practices to ensure no sensitive data is exposed in version control.

## What's Stored in Git

✅ **Safe to commit:**
- Infrastructure as Code (Kubernetes manifests, Helm values)
- GitOps configurations (Flux resources)
- Documentation and guides
- Network architecture and planning
- Scripts and automation tools
- Non-sensitive configuration templates

❌ **Never committed:**
- Talos machine configurations (controlplane.yaml, worker.yaml)
- Cluster secrets (secrets.yaml)
- Talos/Kubernetes config files (talosconfig, kubeconfig)
- TLS certificates and private keys
- API tokens and credentials
- Cloudflare tunnel tokens
- Environment files with sensitive data

## Secrets Management

### Current Approach

All secrets are stored **locally only** in `~/.talos-secrets/automation/` with restrictive file permissions (600). This directory is completely separate from the git repository.

### .gitignore Protection

The repository's `.gitignore` file is configured to prevent accidental commits of sensitive files:

```gitignore
# Talos secrets
secrets.yaml
secrets.yml
talosconfig
controlplane.yaml
worker.yaml

# Kubernetes configs
kubeconfig
*.kubeconfig

# Certificates and keys
*.key
*.pem
*.crt
*.cert

# Environment files
.env
.env.local
.env.*.local

# Cloudflare
*tunnel-token*
cloudflare-token*
```

### Future: SOPS Encryption

Phase 5 of the GitOps roadmap includes implementing Mozilla SOPS for encrypted secrets management. When implemented:
- Secrets will be encrypted with age encryption
- Encrypted secrets can be safely committed to git
- Flux will decrypt secrets at deployment time
- Age private key remains local only

## Public Information Disclosure

This repository intentionally includes some non-sensitive information for educational and documentation purposes:

- **Domain names**: Used in ingress configurations (protected by Cloudflare Tunnel)
- **Private IP addresses**: Standard homelab ranges (192.168.1.x) in documentation
- **Architecture details**: Raspberry Pi hardware, software stack
- **Technology choices**: Talos Linux, Kubernetes, Flux, n8n, Traefik

This follows common practice in open-source homelab and infrastructure-as-code repositories.

## Security Architecture

### Defense in Depth

1. **Network Security**:
   - Private IP addressing (192.168.1.0/24)
   - NAT and firewall protection
   - Cloudflare Tunnel for external access (hides origin IP)

2. **Cluster Security**:
   - Talos Linux (immutable OS, minimal attack surface)
   - API-driven configuration (no SSH)
   - Network policies for pod isolation
   - TLS encryption for all services

3. **Application Security**:
   - HTTPS-only access
   - Certificate management via cert-manager
   - Authentication required for all applications
   - Secrets stored in Kubernetes secrets (not in git)

### Git History

The repository was rebuilt from scratch on **October 6, 2025** (commit `e12d490`) to ensure a clean git history with no sensitive data in any commits. All secrets were regenerated at that time.

## Reporting Security Issues

If you discover a security vulnerability in this repository or its deployed infrastructure, please report it responsibly:

**Contact**: rich@jeansy.org

Please include:
- Description of the vulnerability
- Steps to reproduce (if applicable)
- Potential impact
- Any suggested fixes

**Response Time**: I aim to respond within 48 hours and will work with you to address any legitimate security concerns.

## Security Best Practices for Users

If you're using this repository as a template for your own infrastructure:

1. **Never commit secrets** - Use local storage or encrypted secrets management
2. **Rotate all secrets** - Don't reuse any example credentials or certificates
3. **Review .gitignore** - Ensure your sensitive files are excluded
4. **Audit before push** - Check what's actually being committed with `git status`
5. **Use pre-commit hooks** - Consider tools like git-secrets or trufflehog
6. **Secure your secrets** - Use file permissions (600/400) on sensitive files
7. **Backup separately** - Don't rely on git for secret storage

## Compliance

This repository follows security best practices commonly seen in production infrastructure-as-code repositories:

- ✅ Secrets excluded from version control
- ✅ Clean git history (no secret leakage)
- ✅ Comprehensive .gitignore configuration
- ✅ Documentation of security architecture
- ✅ Planned encrypted secrets management (SOPS)

## References

- [Flux Security Best Practices](https://fluxcd.io/flux/security/)
- [Mozilla SOPS](https://github.com/mozilla/sops)
- [Talos Linux Security](https://www.talos.dev/latest/learn-more/security/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)

## Version History

- **2025-10-17**: Initial security policy created
- **2025-10-06**: Repository rebuilt with clean git history (commit e12d490)
