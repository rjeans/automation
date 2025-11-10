# Alist Storage Configuration

## Overview

Alist stores its storage backend configurations in a SQLite database (`/opt/alist/data/data.db`). Storage must be configured through the web UI, and the configuration persists across pod restarts via the Longhorn PVC.

## MinIO S3 Credentials

Alist uses the `alist-service` MinIO service account with the following credentials (injected via environment variables):

- **Access Key ID**: `alist-service`
- **Secret Access Key**: Stored in SOPS-encrypted secret `alist-minio-credentials`

The credentials are available to the Alist container as:
- `MINIO_ACCESS_KEY`
- `MINIO_SECRET_KEY`

## Manual Storage Configuration

### Prerequisites

1. Access Alist at `https://files.jeans-host.net`
2. Log in with admin credentials
3. Navigate to: Settings → Storage

### S3 Storage Configuration

Add two S3 storage backends:

#### 1. Documents Storage

- **Mount Path**: `/documents`
- **Driver**: S3
- **Bucket**: `rag-documents`
- **Endpoint**: `http://minio.rag-system.svc.cluster.local:9000`
- **Region**: `us-east-1`
- **Access Key ID**: Use value from `$MINIO_ACCESS_KEY` env var
- **Secret Access Key**: Use value from `$MINIO_SECRET_KEY` env var
- **Root Folder Path**: `/`
- **Custom Host**: `https://s3.jeans-host.net` (IMPORTANT: Do NOT include bucket name)
- **Force Path Style**: ✓ (enabled)
- **List Object Version**: `v1`
- **Sign URL Expire**: `4` hours
- **Placeholder**: (leave empty)
- **Enable Sign URL Expire**: ✓ (enabled) - This generates presigned URLs

#### 2. Photos Storage

- **Mount Path**: `/photos`
- **Driver**: S3
- **Bucket**: `rag-photos`
- **Endpoint**: `http://minio.rag-system.svc.cluster.local:9000`
- **Region**: `us-east-1`
- **Access Key ID**: Use value from `$MINIO_ACCESS_KEY` env var
- **Secret Access Key**: Use value from `$MINIO_SECRET_KEY` env var
- **Root Folder Path**: `/`
- **Custom Host**: `https://s3.jeans-host.net` (IMPORTANT: Do NOT include bucket name)
- **Force Path Style**: ✓ (enabled)
- **List Object Version**: `v1`
- **Sign URL Expire**: `4` hours
- **Placeholder**: (leave empty)
- **Enable Sign URL Expire**: ✓ (enabled) - This generates presigned URLs

## Getting Credentials

To retrieve the credentials for configuration:

```bash
# Get Access Key ID
kubectl exec -n alist deployment/alist -- env | grep MINIO_ACCESS_KEY

# Get Secret Access Key
kubectl exec -n alist deployment/alist -- env | grep MINIO_SECRET_KEY
```

## Persistence

Once configured, storage backends are stored in the SQLite database which persists via the Longhorn PVC. Configuration survives:
- Pod restarts
- Pod rescheduling
- Deployment updates

## Security Notes

- Storage credentials are never stored in git
- Credentials are encrypted with SOPS and managed by Flux
- MinIO service account uses principle of least privilege (readwrite policy only)
- Alist admin password should be changed from default immediately after first login
