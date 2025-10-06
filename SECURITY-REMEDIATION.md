# Security Remediation Plan

## Issue Found
Unencrypted machine configuration files (`controlplane.yaml` and `worker.yaml`) were committed to git history in commit `3e01a49`. These files contain:
- Private CA keys (ED25519)
- Bootstrap tokens
- Cluster certificates

## Current Status
✅ Files removed from current HEAD
✅ Files added to `.gitignore`
❌ Files still exist in git history (commits still reachable)

## Recommended Remediation

Since you're rebuilding the cluster anyway, the cleanest approach:

### Option 1: Fresh Git History (RECOMMENDED)
```bash
# 1. Delete .git directory
rm -rf .git

# 2. Reinitialize repository
git init

# 3. Make fresh commit with only safe files
git add -A
git commit -m "Initial commit - clean repository after security remediation"

# 4. Force push to remote (if already pushed)
git remote add origin https://github.com/rjeans/automation.git
git push -u origin main --force
```

### Option 2: Keep Existing History (Less secure)
Accept that the secrets were exposed in history and:
1. Rotate all cluster secrets (rebuild cluster)
2. Never reuse these certificates/keys
3. Ensure repository remains private
4. Document the incident

## Why Encrypted Secrets Should NOT Be Committed

**Question: Do encrypted secrets need to be in git?**

**Answer: NO - Here's why:**

### Machine Configs (controlplane.yaml, worker.yaml)
- ❌ **Should NOT be committed** (even encrypted)
- These are **generated artifacts**, not source code
- Should be regenerated for each cluster build
- Kept locally or in secure secret storage (Vault, 1Password, etc.)

### Cluster Secrets (secrets.yaml)
- ❌ **Should NOT be committed** (even encrypted)
- Generated once per cluster
- Should be backed up securely outside git
- Treat like passwords, not configuration

### Talosconfig
- ⚠️ **Maybe** - only if you need team access
- Contains client certificates for accessing cluster
- If committed (encrypted), team members can decrypt and use
- Alternative: Generate per-user certificates

## Best Practice: What SHOULD Be in Git

✅ **Infrastructure as Code:**
- Terraform/Pulumi code
- Kubernetes manifests (non-secret)
- Helm values files (non-secret)
- Documentation
- Scripts
- GitOps configurations

✅ **Configuration Templates:**
- Talos config patches (without secrets)
- Machine config templates
- Network configurations (IPs, CIDRs)

❌ **What Should NOT Be in Git:**
- Generated machine configs
- Secret material (encrypted or not)
- CA keys and certificates
- Bootstrap tokens
- API credentials

## Secure Alternative: Secret Storage

Instead of git, use:
1. **Local only** - Keep secrets in local filesystem only
2. **Password Manager** - 1Password, Bitwarden (for personal)
3. **Secret Manager** - HashiCorp Vault (for teams)
4. **Encrypted Backup** - External encrypted drive

## Updated Workflow

```bash
# Generate secrets (NOT in git)
talosctl gen secrets -o ~/secure-secrets/automation/secrets.yaml

# Generate configs with secrets
talosctl gen config cluster https://192.168.1.11:6443 \
  --with-secrets ~/secure-secrets/automation/secrets.yaml \
  --output ~/secure-secrets/automation/

# Use configs (NOT in git)
export TALOSCONFIG=~/secure-secrets/automation/talosconfig
talosctl apply-config ...

# Git only contains:
# - Documentation
# - Scripts
# - Network plans
# - Non-secret manifests
```

## Action Required

1. **Immediate**: Rebuild cluster with fresh secrets
2. **Before Rebuild**: Decide on Option 1 or 2 above
3. **Update Docs**: Remove encryption instructions (Step 14)
4. **Update .gitignore**: Already done ✓

## Lessons Learned

1. **Never commit secrets** - Even encrypted
2. **Secrets are not source code** - Don't treat them as such
3. **Use secret managers** - Not git
4. **Audit before push** - Check what's actually in git
5. **Infrastructure != Secrets** - Separate concerns
