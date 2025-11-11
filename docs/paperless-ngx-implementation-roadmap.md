# Paperless-ngx Implementation Roadmap

## Overview

Incremental deployment of Paperless-ngx on Kubernetes with MinIO S3 backend integration, following GitOps principles with Flux.

**Goal**: Production-ready document management system with:
- MinIO as canonical storage backend
- PostgreSQL for metadata (reuse existing postgres-rag cluster)
- Redis for task queue and caching
- Traefik ingress with Cloudflare tunnel
- Full GitOps deployment via Flux

---

## Architecture Review

Based on [paperless-minio-integration.md](./paperless-minio-integration.md):

### ✅ Strengths
- Clear S3 integration strategy using django-storages
- Proper separation: MinIO (storage) + PostgreSQL (metadata)
- Consistent with canonical storage model
- GitOps-ready configuration approach

### ⚠️ Adjustments Needed

1. **Namespace**: Document uses `media` namespace, but we should use `rag-system` for consistency
2. **MinIO Endpoint**: Should be `http://minio.rag-system.svc.cluster.local:9000` (not `minio.minio.svc`)
3. **Bucket Name**: Suggest `rag-documents` instead of `docs` (already exists in MinIO)
4. **PostgreSQL**: Reuse existing `postgres-rag` cluster instead of separate database
5. **Region**: Can use `us-east-1` instead of `eu-west-1` (MinIO default)
6. **Service Account**: Need dedicated MinIO user for Paperless (not reuse admin)

---

## Helm Chart Selection

**Recommended**: gabe565/paperless-ngx chart
- **Repo**: `https://charts.gabe565.com` or `oci://ghcr.io/gabe565/charts/paperless-ngx`
- **Latest Version**: 0.24.1 (app version 2.14.7)
- **Features**: PostgreSQL subchart, Redis subchart, well-maintained
- **Drawback**: We'll disable subcharts and use existing PostgreSQL + add Redis separately

---

## Implementation Phases

### Phase 1: Infrastructure Preparation (30 minutes)

**Goal**: Set up prerequisites for Paperless deployment

**Tasks**:
1. Add `rag-documents` bucket to MinIO (already exists ✅)
2. Create MinIO service account for Paperless
   - Username: `paperless-service`
   - Policy: `readwrite` (scoped to `rag-documents` bucket)
   - Store credentials in SOPS-encrypted secret
3. Create PostgreSQL database and user in postgres-rag cluster
   - Database: `paperless`
   - User: `paperless`
   - Grant full access to `paperless` database
4. Add Redis to rag-system namespace
   - Deploy via Helm chart (bitnami/redis)
   - Minimal resources for Pi cluster
   - Password stored in SOPS secret

**Deliverables**:
- `flux/clusters/talos/apps/rag-system/minio/user-paperless-secret.yaml` (SOPS)
- `flux/clusters/talos/apps/rag-system/minio/helmrelease.yaml` (updated users section)
- `flux/clusters/talos/apps/rag-system/postgres-rag/paperless-database.yaml` (SQL init job)
- `flux/clusters/talos/apps/rag-system/redis/` (new directory with HelmRelease)

**Validation**:
```bash
# MinIO user exists
kubectl get secret -n rag-system minio-user-paperless

# Database exists
kubectl exec -n rag-system postgres-rag-1 -- psql -U postgres -c "\l" | grep paperless

# Redis running
kubectl get pods -n rag-system | grep redis
```

---

### Phase 2: Paperless-ngx Deployment with S3 Backend (45 minutes)

**Goal**: Deploy Paperless with MinIO S3 storage from the start

**Tasks**:
1. Add gabe565 Helm repository to Flux
   - Create HelmRepository manifest
2. Create Paperless namespace resources
   - Use `rag-system` namespace (not separate namespace)
3. Create Paperless configuration secret (SOPS encrypted)
   - PostgreSQL credentials
   - Redis credentials
   - MinIO credentials
   - Admin user credentials
4. Create HelmRelease for Paperless
   - **Disable** PostgreSQL subchart (use external)
   - **Disable** Redis subchart (use external)
   - **Enable** S3 storage with MinIO backend
   - Configure external PostgreSQL connection
   - Configure external Redis connection
   - Configure S3 environment variables
   - Resource limits: CPU 200m-1000m, Memory 512Mi-2Gi
   - Small PVC only for consume/temp directories (5Gi Longhorn)
5. Create Service and basic IngressRoute
   - Service: ClusterIP on port 8000
   - IngressRoute: `paperless.jeans-host.net`

**Environment Variables (S3 Configuration)**:
```yaml
env:
  # Database
  PAPERLESS_DBHOST: postgres-rag-rw.rag-system.svc.cluster.local
  PAPERLESS_DBPORT: "5432"
  PAPERLESS_DBNAME: paperless
  PAPERLESS_DBUSER: paperless
  PAPERLESS_DBPASS: ${POSTGRES_PASSWORD}

  # Redis
  PAPERLESS_REDIS: redis://redis.rag-system.svc.cluster.local:6379

  # S3 Storage Backend
  PAPERLESS_STORAGE_TYPE: s3
  PAPERLESS_S3_ENDPOINT: http://minio.rag-system.svc.cluster.local:9000
  PAPERLESS_S3_BUCKET_NAME: rag-documents
  PAPERLESS_S3_ACCESS_KEY_ID: ${MINIO_ACCESS_KEY}
  PAPERLESS_S3_SECRET_ACCESS_KEY: ${MINIO_SECRET_KEY}
  PAPERLESS_S3_REGION: us-east-1
  PAPERLESS_S3_USE_SSL: "false"
  PAPERLESS_S3_SIGNATURE_VERSION: s3v4

  # Folder structure
  PAPERLESS_FILENAME_FORMAT: "{created_year}/{correspondent}/{title}"
  PAPERLESS_FILENAME_FORMAT_REMOVE_NONE: "true"
```

**Deliverables**:
- `flux/clusters/talos/apps/rag-system/paperless/helmrepository.yaml`
- `flux/clusters/talos/apps/rag-system/paperless/secret.yaml` (SOPS)
- `flux/clusters/talos/apps/rag-system/paperless/helmrelease.yaml`
- `flux/clusters/talos/apps/rag-system/paperless/ingressroute.yaml`
- `flux/clusters/talos/apps/rag-system/paperless/kustomization.yaml`
- Update `flux/clusters/talos/apps/rag-system/kustomization.yaml`

**Validation**:
```bash
# Pod running
kubectl get pods -n rag-system | grep paperless

# Access web UI
curl -I http://paperless.jeans-host.net

# Check logs for S3 connection
kubectl logs -n rag-system deployment/paperless-ngx | grep -i s3

# Upload test document
# Verify object in MinIO console
```

**Expected Result**: Paperless UI accessible, documents stored directly in S3

---

### Phase 3: Cloudflare Tunnel Integration (15 minutes)

**Goal**: Expose Paperless securely via Cloudflare Tunnel with OAuth

**Tasks (formerly Phase 4)**:

**Deliverables**:
1. Add Cloudflare tunnel route for `paperless.jeans-host.net`
2. Update IngressRoute to handle external traffic
3. Configure Paperless to trust Cloudflare proxy headers
   ```yaml
   env:
     PAPERLESS_ALLOWED_HOSTS: "paperless.jeans-host.net,localhost"
     PAPERLESS_CORS_ALLOWED_HOSTS: "https://paperless.jeans-host.net"
     PAPERLESS_USE_X_FORWARD_HOST: "true"
     PAPERLESS_USE_X_FORWARD_PORT: "true"
   ```
4. Optional: Configure Cloudflare Access for authentication layer

**Deliverables**:
- Updated Cloudflare tunnel configuration
- Updated `flux/clusters/talos/apps/rag-system/paperless/helmrelease.yaml`

**Validation**:
```bash
# Access from internet
curl -I https://paperless.jeans-host.net

# Verify HTTPS redirect and OAuth (if configured)
```

---

### Phase 4: Consume Folder & Automation (30 minutes)

**Goal**: Set up automated document ingestion

**Options**:

**Option A: S3 Inbox Folder** (Recommended for cloud-first approach)
- Upload documents to `s3://rag-documents/inbox/`
- CronJob watches inbox and moves to Paperless consume endpoint
- Paperless processes and files to appropriate S3 paths

**Option B: Persistent Volume Consume**
- Mount PVC at `/usr/src/paperless/consume`
- Upload via SFTP/rsync to PVC
- Paperless auto-consumes from filesystem

**Tasks** (Option A):
1. Create consume-watcher CronJob
   - Runs every 5 minutes
   - Lists objects in `inbox/` prefix
   - POSTs to Paperless API to consume each file
   - Moves processed files to `inbox/processed/`
2. Update MinIO bucket to allow API access to inbox
3. Document upload workflow in README

**Deliverables**:
- `flux/clusters/talos/apps/rag-system/paperless/consume-watcher-cronjob.yaml`
- `docs/paperless-usage.md` (user guide)

**Validation**:
```bash
# Upload file to inbox
mc cp test.pdf minio/rag-documents/inbox/

# Wait for cron
kubectl get jobs -n rag-system

# Verify document in Paperless UI
```

---

### Phase 5: OCR & Text Extraction Configuration (30 minutes)

**Goal**: Optimize OCR for RAG pipeline integration

**Tasks**:
1. Configure Paperless OCR settings:
   ```yaml
   env:
     PAPERLESS_OCR_LANGUAGE: eng
     PAPERLESS_OCR_MODE: skip_noarchive  # Skip if PDF already has text
     PAPERLESS_OCR_CLEAN: clean
     PAPERLESS_OCR_DESKEW: "true"
     PAPERLESS_OCR_ROTATE_PAGES: "true"
     PAPERLESS_OCR_OUTPUT_TYPE: pdfa
   ```
2. Test OCR with scanned document
3. Verify extracted text stored in PostgreSQL
4. Optional: Configure Tika for additional format support

**Deliverables**:
- Updated `flux/clusters/talos/apps/rag-system/paperless/helmrelease.yaml`

**Validation**:
```bash
# Upload scanned PDF
# Verify OCR text in document view
# Query PostgreSQL for extracted text
kubectl exec -n rag-system postgres-rag-1 -- psql -U paperless -d paperless \
  -c "SELECT title, content FROM documents_document LIMIT 1"
```

---

### Phase 6: RAG Pipeline Integration (1 hour)

**Goal**: Enable RAG pipeline to ingest Paperless documents

**Tasks**:
1. Create read-only MinIO service account for RAG pipeline
   - Username: `rag-reader`
   - Policy: `readonly` on `rag-documents` bucket
2. Design integration approach:
   - **Option A**: Direct PostgreSQL query for document metadata + MinIO fetch for PDF
   - **Option B**: Paperless API integration for document export
   - **Option C**: MinIO event notifications when Paperless saves to S3
3. Create document sync job/service
   - Query Paperless PostgreSQL for new documents
   - Fetch PDF from MinIO
   - Extract embeddings
   - Store in vector database
4. Optional: Bi-directional sync (RAG enrichments back to Paperless tags)

**Deliverables**:
- `flux/clusters/talos/apps/rag-system/minio/user-rag-reader-secret.yaml`
- `docs/rag-paperless-integration.md` (architecture doc)
- Future: Document sync service implementation

**Validation**:
- Manual test of PostgreSQL query + MinIO fetch
- Verify read-only access from rag-reader account

---

### Phase 7: Backup & Disaster Recovery (30 minutes)

**Goal**: Ensure Paperless data is backed up

**Tasks**:
1. MinIO backup strategy:
   - Already covered by existing MinIO replication/backup (if configured)
   - Verify `rag-documents` bucket included in backup policy
2. PostgreSQL backup:
   - Already covered by CloudNativePG automated backups
   - Verify `paperless` database included
3. Document restore procedure:
   - Restore MinIO bucket
   - Restore PostgreSQL database
   - Redeploy Paperless HelmRelease
4. Test restore in development environment (optional)

**Deliverables**:
- `docs/paperless-backup-restore.md`

**Validation**:
```bash
# Verify MinIO versioning enabled
mc version info minio/rag-documents

# Verify PostgreSQL backups
kubectl get backup -n rag-system
```

---

### Phase 8: Monitoring & Observability (Optional - 45 minutes)

**Goal**: Add metrics and alerting for Paperless

**Tasks**:
1. Enable Prometheus ServiceMonitor (if Prometheus deployed)
2. Create Grafana dashboard for Paperless metrics:
   - Document count
   - Processing queue length
   - Storage usage
   - OCR performance
3. Configure alerts:
   - Pod restarts
   - High memory usage
   - Failed document processing
4. Add structured logging to external log aggregator (if available)

**Deliverables**:
- `flux/clusters/talos/apps/rag-system/paperless/servicemonitor.yaml`
- `docs/paperless-monitoring.md`

---

## Summary Timeline

| Phase | Description | Est. Time | Cumulative |
|-------|-------------|-----------|------------|
| 1 | Infrastructure prep (MinIO user, PostgreSQL DB, Redis) | 30min | 30min |
| 2 | Paperless deployment with S3 backend | 45min | 1h 15min |
| 3 | Cloudflare tunnel | 15min | 1h 30min |
| 4 | Consume folder automation | 30min | 2h |
| 5 | OCR optimization | 30min | 2h 30min |
| 6 | RAG pipeline integration | 1h | 3h 30min |
| 7 | Backup strategy | 30min | 4h |
| 8 | Monitoring (optional) | 45min | 4h 45min |

**Total Core Implementation**: ~4 hours
**Total with Monitoring**: ~4 hours 45 minutes

---

## Risk Mitigation

### Risk 1: Resource Constraints on Raspberry Pi
- **Mitigation**: Start with minimal replicas (1), conservative resource limits
- **Monitoring**: Watch CPU/memory usage, adjust limits iteratively

### Risk 2: S3 Storage Configuration Issues
- **Mitigation**: S3 is well-tested infrastructure, MinIO already stable
- **Validation**: Test document upload immediately after deployment
- **Rollback**: MinIO versioning allows recovery of any corrupted objects

### Risk 3: PostgreSQL Database Conflicts
- **Mitigation**: Use dedicated `paperless` database, not shared schema
- **Isolation**: Separate user with scoped permissions

### Risk 4: OCR Performance on ARM
- **Mitigation**: Use `skip_noarchive` mode to skip PDFs with existing text
- **Alternative**: Offload heavy OCR to external service if needed

---

## Success Criteria

- ✅ Paperless UI accessible via Cloudflare tunnel
- ✅ Documents stored in MinIO `rag-documents` bucket with versioning
- ✅ OCR extraction working for scanned PDFs
- ✅ Metadata stored in PostgreSQL `postgres-rag` cluster
- ✅ Automated document ingestion via inbox folder
- ✅ RAG pipeline can read documents from MinIO
- ✅ All configuration managed via Flux GitOps
- ✅ Backups verified for both MinIO and PostgreSQL

---

## Next Steps

1. **Review this roadmap** for any adjustments based on specific requirements
2. **Begin Phase 1**: Infrastructure preparation
3. **Iterate incrementally**: Validate each phase before proceeding
4. **Document learnings**: Update this roadmap with actual timings and issues

---

## See Also

- [Paperless-MinIO Integration](./paperless-minio-integration.md) - Original integration design
- [Canonical Store Management](./canonical-store-management.md) - Storage strategy
- [RAG Implementation Framework](./rag-implementation-framework.md) - Overall RAG architecture
