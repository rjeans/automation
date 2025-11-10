# Canonical Store Management

## Overview

MinIO serves as the canonical storage layer in the RAG pipeline. All document ingestion flows through this storage, and it maintains the authoritative source of truth for all files.

## Architecture Principle

**Single Source of Truth**: MinIO is the canonical store. All other systems (PostgreSQL metadata, vector embeddings, etc.) are derived from and reference MinIO objects.

```
User Upload → Alist (UI) → MinIO (canonical) → NATS (event) → Processing Pipeline
                                    ↓
                            PostgreSQL (metadata + vectors)
```

## Bucket Organization

### Current Buckets

1. **rag-documents**: Document files (PDFs, text files, etc.)
2. **rag-photos**: Photo/image files

### Folder Structure Recommendations

#### For rag-documents:
```
/rag-documents/
  ├── inbox/              # New uploads, pending processing
  ├── processed/          # Successfully processed documents
  │   ├── YYYY/MM/DD/    # Date-based organization
  │   └── ...
  ├── failed/            # Processing failures, needs review
  └── archive/           # Long-term storage, not actively indexed
```

#### For rag-photos:
```
/rag-photos/
  ├── inbox/             # New uploads
  ├── processed/         # Successfully processed
  │   ├── YYYY/MM/DD/   # Date-based organization
  │   └── ...
  └── archive/
```

## Management Operations

### 1. File Lifecycle

**Upload → Process → Store → Archive**

- **Upload**: Users upload via Alist to `/inbox/`
- **Process**: Pipeline detects new files, processes, and extracts data
- **Store**: Successfully processed files moved to `/processed/YYYY/MM/DD/`
- **Archive**: Old files moved to `/archive/` (optional, for compliance)

### 2. Versioning

MinIO versioning is **ENABLED** on both buckets. This means:
- Every file modification creates a new version
- Previous versions are retained
- You can retrieve any historical version
- Deletes are soft-deletes (version marker)

**Checking versions**:
```bash
kubectl exec -n rag-system deployment/minio -- \
  mc ls --versions myminio/rag-documents/path/to/file
```

### 3. Metadata Management

Each file in MinIO should have associated metadata in PostgreSQL:

**PostgreSQL Schema** (example):
```sql
CREATE TABLE documents (
  id UUID PRIMARY KEY,
  s3_bucket VARCHAR NOT NULL,
  s3_key VARCHAR NOT NULL,        -- Full S3 path
  s3_version_id VARCHAR,           -- MinIO version ID
  original_filename VARCHAR,
  content_type VARCHAR,
  file_size BIGINT,
  upload_timestamp TIMESTAMPTZ,
  processing_status VARCHAR,       -- pending, processing, completed, failed
  processing_timestamp TIMESTAMPTZ,
  checksum VARCHAR,                -- SHA256 or MD5
  embeddings VECTOR(1536),         -- For RAG
  UNIQUE(s3_bucket, s3_key, s3_version_id)
);
```

### 4. Access Patterns

#### Via Alist (Human Users)
- Browse files through web UI
- Upload new documents
- Download/preview files
- Organize into folders

#### Via MinIO Console (Admin)
- User management
- Bucket policies
- Versioning configuration
- Storage metrics

#### Via Service Accounts (Applications)
- **alist-service**: Read/write for file management
- **processor-service** (future): Read from inbox, write metadata
- **api-service** (future): Read-only for retrieval

### 5. Monitoring & Observability

**Key Metrics to Track**:
- Total objects per bucket
- Storage usage per bucket
- Upload rate
- Processing lag (time from upload to processed)
- Failed processing rate

**Access via MinIO Console**:
- Navigate to: https://s3.jeans-host.net
- View: Monitoring → Metrics

### 6. Backup Strategy

**Options**:

1. **MinIO to MinIO Replication** (if you add another cluster)
2. **Periodic Export** to external storage
3. **Longhorn Volume Snapshots** (backing the MinIO PVC)

Current setup relies on Longhorn PVC persistence. Consider adding:
- Regular Longhorn snapshots
- Off-cluster backup of critical buckets

### 7. Data Governance

#### Retention Policies

Define policies per bucket:
- **rag-documents**: Retain all versions for 90 days, then keep only latest
- **rag-photos**: Retain all versions for 30 days
- **archive**: No version limit (compliance requirement)

#### Access Control

Current users:
- **Admin (rich)**: Full console access via Cloudflare OAuth
- **alist-service**: Read/write to both buckets (via Alist)
- **Future services**: Principle of least privilege

### 8. Event-Driven Processing

MinIO can emit events to NATS for:
- `s3:ObjectCreated:Put` → Trigger processing pipeline
- `s3:ObjectRemoved:Delete` → Clean up metadata
- `s3:ObjectCreated:Copy` → Handle file moves

**Configuration** (future):
```yaml
# In MinIO HelmRelease
buckets:
  - name: rag-documents
    policy: none
    versioning: true
    notification:
      nats:
        - event: "s3:ObjectCreated:*"
          prefix: "inbox/"
          address: "nats://nats.rag-system.svc.cluster.local:4222"
          subject: "documents.created"
```

## Operational Procedures

### Adding New Buckets

1. Update MinIO HelmRelease with new bucket definition
2. Create service account if needed
3. Configure bucket policy
4. Update Alist with new storage mount
5. Document purpose and retention policy

### Moving Files Between Folders

**Via Alist UI**: Drag and drop (updates S3 key)
**Via MinIO Console**: Use copy + delete
**Via CLI**:
```bash
kubectl exec -n rag-system deployment/minio -- \
  mc cp myminio/rag-documents/inbox/file.pdf \
         myminio/rag-documents/processed/2025/11/10/file.pdf
```

### Recovering Deleted Files

Since versioning is enabled:
```bash
kubectl exec -n rag-system deployment/minio -- \
  mc undo myminio/rag-documents/path/to/deleted-file.pdf
```

## Future Enhancements

1. **Lifecycle Policies**: Auto-move old files to archive, delete old versions
2. **Object Lock**: Compliance mode for immutable records
3. **Encryption**: Server-side encryption for sensitive documents
4. **Replication**: Multi-site disaster recovery
5. **Audit Logging**: Track all access and modifications
6. **Quota Management**: Per-bucket size limits

## See Also

- [RAG Implementation Framework](./rag-implementation-framework.md)
- [Alist Storage Configuration](./alist-storage-configuration.md)
- [MinIO Documentation](https://min.io/docs/)
