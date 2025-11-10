# Inbox Processing Pipeline

## Overview

Automated pipeline to process documents uploaded to MinIO inbox folders, extract content, generate embeddings, and store metadata in PostgreSQL.

## Architecture

```
User Upload → Alist → MinIO (/inbox/) → NATS Event → Processor → PostgreSQL + Vector Store
                          ↓
                    Move to /processed/
```

## Pipeline Stages

### 1. Event Detection

**Option A: MinIO Bucket Notifications (Recommended)**
- MinIO emits events to NATS when objects are created
- Configure bucket notifications for `s3:ObjectCreated:*` events
- Filter events by prefix (`inbox/`)

**Option B: Polling**
- Cron job periodically checks inbox folder
- Less efficient, but simpler to start

### 2. Document Processing Service

A Kubernetes Deployment that:
- Subscribes to NATS subject `documents.created`
- Downloads document from MinIO
- Extracts text content
- Generates embeddings
- Stores metadata in PostgreSQL
- Moves processed file to `/processed/YYYY/MM/DD/`

**Tech Stack Options:**
- **Python**: Fast to develop, rich ecosystem (PyPDF2, langchain, sentence-transformers)
- **Go**: More efficient, better for long-running services
- **Node.js**: Good TypeScript support, streaming capabilities

### 3. Processing Steps

For each document:

1. **Download**: Fetch from MinIO inbox
2. **Extract Text**:
   - PDF → OCR if needed (tesseract/OCRmyPDF)
   - Images → OCR
   - Text files → direct read
3. **Chunk**: Split into semantic chunks (512-1024 tokens)
4. **Embed**: Generate vector embeddings (OpenAI, sentence-transformers)
5. **Store Metadata**:
   ```sql
   INSERT INTO documents (
     id, s3_bucket, s3_key, s3_version_id,
     original_filename, content_type, file_size,
     upload_timestamp, processing_status,
     extracted_text, embeddings
   ) VALUES (...)
   ```
6. **Move File**: `inbox/file.pdf` → `processed/2025/11/10/file.pdf`
7. **Publish Event**: `documents.processed` to NATS

### 4. Error Handling

- Failed processing → Move to `/failed/` with error metadata
- Retry logic with exponential backoff
- Dead letter queue for manual review
- Logging to structured logs (stdout → Loki)

## Implementation Phases

### Phase 1: Manual Polling Processor (MVP)

**Goal**: Prove the concept with simplest implementation

**Components:**
- Python script in CronJob
- Polls `/inbox/` every 5 minutes
- Basic text extraction (no OCR)
- Simple chunking strategy
- Local embeddings (sentence-transformers)
- PostgreSQL insert with pgvector

**Deliverables:**
- `processor/` directory with Python code
- Dockerfile
- Kubernetes CronJob manifest
- PostgreSQL schema migration

**Effort**: 4-6 hours

### Phase 2: Event-Driven Processor

**Goal**: Real-time processing with NATS integration

**Components:**
- Configure MinIO bucket notifications → NATS
- Python/Go service as Deployment (not CronJob)
- Subscribes to `documents.created` subject
- Same processing logic as Phase 1
- Metrics and health checks

**Deliverables:**
- MinIO HelmRelease with bucket notifications
- Deployment manifest for processor service
- Service monitor for Prometheus (future)

**Effort**: 4-6 hours

### Phase 3: Advanced Processing

**Goal**: Production-grade document processing

**Components:**
- OCR for scanned PDFs (OCRmyPDF in sidecar)
- Image processing (PIL, OpenCV)
- Better chunking (langchain RecursiveTextSplitter)
- External embeddings API (OpenAI) with fallback to local
- Parallel processing (worker pool)
- Job queue for large documents

**Deliverables:**
- Enhanced processor with OCR
- Configuration for embedding providers
- Horizontal pod autoscaling

**Effort**: 8-12 hours

### Phase 4: Pipeline Observability

**Goal**: Full visibility into processing

**Components:**
- Structured logging
- Prometheus metrics (documents processed, errors, latency)
- Grafana dashboard
- Tracing with OpenTelemetry
- Alerting on processing failures

**Effort**: 4-6 hours

## PostgreSQL Schema

```sql
-- Documents table
CREATE TABLE documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  s3_bucket VARCHAR(255) NOT NULL,
  s3_key VARCHAR(1024) NOT NULL,
  s3_version_id VARCHAR(255),
  original_filename VARCHAR(512) NOT NULL,
  content_type VARCHAR(128),
  file_size BIGINT,
  checksum VARCHAR(64),  -- SHA256

  -- Timestamps
  upload_timestamp TIMESTAMPTZ NOT NULL,
  processing_started_at TIMESTAMPTZ,
  processing_completed_at TIMESTAMPTZ,

  -- Status
  processing_status VARCHAR(32) NOT NULL DEFAULT 'pending',
    -- values: pending, processing, completed, failed
  error_message TEXT,
  retry_count INTEGER DEFAULT 0,

  -- Content
  extracted_text TEXT,
  page_count INTEGER,
  language VARCHAR(10),  -- en, fr, etc.

  -- Metadata
  metadata JSONB,  -- flexible field for custom attributes

  -- Indexes
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(s3_bucket, s3_key, s3_version_id)
);

-- Document chunks for RAG
CREATE TABLE document_chunks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  chunk_index INTEGER NOT NULL,
  chunk_text TEXT NOT NULL,
  token_count INTEGER,

  -- Vector embedding
  embedding VECTOR(1536),  -- dimension depends on model

  -- Chunk metadata
  start_char INTEGER,
  end_char INTEGER,
  page_number INTEGER,

  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(document_id, chunk_index)
);

-- Indexes for search
CREATE INDEX idx_documents_status ON documents(processing_status);
CREATE INDEX idx_documents_upload_time ON documents(upload_timestamp DESC);
CREATE INDEX idx_chunks_document ON document_chunks(document_id);
CREATE INDEX idx_chunks_embedding ON document_chunks USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);  -- for vector similarity search

-- Function to update updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_documents_updated_at BEFORE UPDATE ON documents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

## MinIO Bucket Notification Configuration

```yaml
# In MinIO HelmRelease
buckets:
  - name: rag-documents
    policy: none
    versioning: true
    objectlocking: false
    # Bucket notifications
    notifications:
      - name: inbox-watcher
        arn: "arn:minio:sqs::nats:rag-system"
        events:
          - "s3:ObjectCreated:Put"
          - "s3:ObjectCreated:Post"
          - "s3:ObjectCreated:Copy"
        prefix: "inbox/"
        suffix: ""
```

## NATS Subject Design

- `documents.created` - New file uploaded to inbox
- `documents.processed` - Processing completed successfully
- `documents.failed` - Processing failed
- `documents.moved` - File moved to processed folder

**Message Format:**
```json
{
  "eventType": "s3:ObjectCreated:Put",
  "eventTime": "2025-11-10T20:30:00Z",
  "bucket": "rag-documents",
  "key": "inbox/document.pdf",
  "size": 95232,
  "etag": "abc123...",
  "versionId": "version-id",
  "metadata": {}
}
```

## Processor Service Configuration

**Environment Variables:**
```yaml
# MinIO
MINIO_ENDPOINT: http://minio.rag-system.svc.cluster.local:9000
MINIO_ACCESS_KEY: processor-service
MINIO_SECRET_KEY: <from-secret>
MINIO_BUCKET: rag-documents

# PostgreSQL
POSTGRES_HOST: postgres-rag-rw.rag-system.svc.cluster.local
POSTGRES_PORT: 5432
POSTGRES_DB: rag
POSTGRES_USER: processor
POSTGRES_PASSWORD: <from-secret>

# NATS
NATS_URL: nats://nats.rag-system.svc.cluster.local:4222
NATS_SUBJECT: documents.created

# Processing
CHUNK_SIZE: 512
CHUNK_OVERLAP: 50
EMBEDDING_MODEL: sentence-transformers/all-MiniLM-L6-v2
EMBEDDING_DIMENSION: 384
MAX_WORKERS: 4
```

## Next Steps

1. **Choose implementation approach**: Start with Phase 1 (polling) or jump to Phase 2 (events)?
2. **Create PostgreSQL schema**: Apply migration to postgres-rag cluster
3. **Create processor service**: Python/Go/Node.js implementation
4. **Configure MinIO notifications**: Connect to NATS (Phase 2+)
5. **Deploy and test**: Upload file, verify processing

## See Also

- [RAG Implementation Framework](./rag-implementation-framework.md)
- [Canonical Store Management](./canonical-store-management.md)
- [Alist Storage Configuration](./alist-storage-configuration.md)
