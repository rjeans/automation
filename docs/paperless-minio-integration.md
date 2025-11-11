# Paperless-ngx Integration with MinIO
*Configuration and best practices for using MinIO as the S3 storage backend*

**Author:** Richard Jeans  
**Version:** 0.1  
**Date:** November 2025  

---

## 1. Overview

Paperless-ngx can store all documents, thumbnails, and OCR outputs directly in **MinIO**, an S3-compatible object store.  
This provides a unified, versioned, and secure storage layer consistent with the rest of the media archive (photos, emails, etc.).

MinIO is used as the **canonical storage backend** for all applications in the cluster.  
Paperless-ngx integrates natively through the **django-storages** S3 backend without code changes.

---

## 2. Architecture Summary

| Component | Role |
|------------|------|
| **MinIO** | S3-compatible object store for document files |
| **Postgres** | Metadata database (tags, correspondents, OCR text) |
| **Paperless-ngx** | Application layer handling OCR, metadata, tagging, and user interface |

The result is a clean separation of storage (MinIO) and metadata (Postgres).

---

## 3. Bucket Structure Example

```
s3://docs/
 ├── originals/
 │    ├── 2024/
 │    │    ├── invoice_1234.pdf
 │    │    └── letter_bank.pdf
 ├── thumbnails/
 │    ├── 2024/
 │    │    ├── invoice_1234-thumb.png
 │    │    └── letter_bank-thumb.png
 └── media/
      ├── temp/
      ├── consume/
```

Each object is versioned and can optionally be **object-locked** for immutability.

---

## 4. Environment Configuration

Paperless-ngx enables MinIO by setting environment variables that configure the S3 backend.

Example configuration (for use in HelmRelease, Docker Compose, or Kubernetes Secret):

```yaml
env:
  PAPERLESS_STORAGE_BACKEND: s3
  PAPERLESS_S3_ENDPOINT_URL: http://minio.minio.svc:9000
  PAPERLESS_S3_BUCKET_NAME: docs
  PAPERLESS_S3_ACCESS_KEY_ID: ${MINIO_ACCESS_KEY}
  PAPERLESS_S3_SECRET_ACCESS_KEY: ${MINIO_SECRET_KEY}
  PAPERLESS_S3_REGION_NAME: eu-west-1
  PAPERLESS_S3_USE_SSL: "False"
  PAPERLESS_S3_VERIFY: "False"
  PAPERLESS_S3_ADDRESSING_STYLE: virtual
  PAPERLESS_MEDIA_ROOT: media
  PAPERLESS_FILENAME_FORMAT: "{created_year}/{title}"
```

### Notes
- Set `PAPERLESS_S3_USE_SSL=True` if using HTTPS (e.g. through Cloudflare or MinIO Gateway with TLS).
- For in-cluster traffic, `False` is fine.
- Ensure the MinIO bucket (`docs`) exists and the user credentials are scoped appropriately.

---

## 5. HelmRelease Example (Flux)

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: paperless
  namespace: media
spec:
  chart:
    spec:
      chart: paperless-ngx
      version: ">=0.15.0"
      sourceRef:
        kind: HelmRepository
        name: bjw-s
  values:
    env:
      PAPERLESS_STORAGE_BACKEND: s3
      PAPERLESS_S3_ENDPOINT_URL: http://minio.minio.svc:9000
      PAPERLESS_S3_BUCKET_NAME: docs
      PAPERLESS_S3_ACCESS_KEY_ID: ${MINIO_ACCESS}
      PAPERLESS_S3_SECRET_ACCESS_KEY: ${MINIO_SECRET}
      PAPERLESS_S3_REGION_NAME: eu-west-1
      PAPERLESS_S3_USE_SSL: "False"
      PAPERLESS_S3_VERIFY: "False"
    ingress:
      enabled: true
      hosts:
        - paperless.jeans-host.net
```

---

## 6. Integration with Canonical Storage Model

| Requirement | Paperless + MinIO Behaviour |
|--------------|-----------------------------|
| Unified S3 storage | ✅ All document assets live in `s3://docs/` |
| Versioning + immutability | ✅ Controlled via MinIO bucket policy |
| Backup strategy | ✅ Compatible with existing MinIO replication |
| RAG ingestion | ✅ Extractor/Indexer can access text + PDFs directly from MinIO |
| Flux reproducibility | ✅ All configuration declarative via GitOps |

---

## 7. Operational Tips

- **Performance:**  
  MinIO within the same cluster provides near-local latency. Keep MinIO PVCs on SSD or Ceph-backed volumes.

- **Lifecycle management:**  
  Configure MinIO bucket lifecycle rules to automatically tier old documents to cold storage or offsite replication.

- **Consume folder:**  
  For automated ingestion, mount `s3://docs/inbox/` via rclone or s3fs into `/usr/src/paperless/consume`.

- **Security:**  
  Use dedicated MinIO users scoped to the `docs` bucket.  
  Manage access keys via SOPS-encrypted Flux secrets.  
  Rotate credentials periodically.

---

## 8. Verification Checklist

| Step | Command | Expected Result |
|-------|----------|----------------|
| Verify bucket access | `mc ls minio/docs` | Lists files and folders |
| Check Paperless logs | `kubectl logs paperless-ngx` | "Connected to S3 storage backend" |
| Upload test document | Through Paperless UI | Object visible in `docs/originals/` |
| Download verification | `mc cat minio/docs/originals/<file>` | Returns valid PDF bytes |

---

## 9. Strategic Fit

Integrating MinIO with Paperless achieves:
- **Consistent storage architecture** across all applications.  
- **Data sovereignty** — you control all raw documents and metadata.  
- **AI readiness** — the RAG pipeline can read documents and metadata directly.  
- **Simple migration** — future bespoke OCR or indexing layers can reuse the same S3 structure.

---

**End of Document**  
*(To be placed in `docs/components/paperless-minio-integration.md`)*
