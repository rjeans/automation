# Document Processor Implementation Plan

## Overview

Build a Go-based document processor service that subscribes to MinIO events via NATS, creates document metadata in PostgreSQL, and organizes files by date.

## Incremental Implementation Steps

### Step 1: Project Structure & Scaffolding
**Goal**: Set up Go project with basic structure

**Tasks**:
1. Create `processor/` directory with Go module
2. Set up basic directory structure:
   ```
   processor/
   ├── cmd/
   │   └── processor/
   │       └── main.go          # Entry point
   ├── internal/
   │   ├── config/
   │   │   └── config.go        # Configuration from env
   │   ├── storage/
   │   │   └── minio.go         # MinIO client
   │   ├── database/
   │   │   └── postgres.go      # PostgreSQL client
   │   ├── messaging/
   │   │   └── nats.go          # NATS subscriber
   │   └── processor/
   │       └── processor.go     # Core processing logic
   ├── go.mod
   ├── go.sum
   ├── Dockerfile
   └── README.md
   ```
3. Initialize with basic dependencies:
   - `github.com/nats-io/nats.go` - NATS client
   - `github.com/minio/minio-go/v7` - MinIO SDK
   - `github.com/jackc/pgx/v5` - PostgreSQL driver
   - `github.com/kelseyhightower/envconfig` - Config from env

**Validation**: `go build` succeeds

**Time Estimate**: 30 minutes

### Step 2: PostgreSQL Schema
**Goal**: Create database schema for document metadata

**Tasks**:
1. Create SQL migration file
2. Define `documents` table with basic fields:
   - id, s3_bucket, s3_key, s3_version_id
   - original_filename, content_type, file_size, checksum
   - upload_timestamp, processing_status
   - created_at, updated_at
3. Add processing_status enum/check constraint
4. Create indexes on status and timestamps
5. Apply migration to postgres-rag cluster

**SQL File**: `flux/clusters/talos/apps/rag-system/postgres-rag/migrations/001_documents_table.sql`

**Validation**: Query table from postgres pod

**Time Estimate**: 20 minutes

### Step 3: Configuration Management
**Goal**: Load configuration from environment variables

**Tasks**:
1. Define config struct in `internal/config/config.go`:
   ```go
   type Config struct {
       // MinIO
       MinioEndpoint   string `envconfig:"MINIO_ENDPOINT" required:"true"`
       MinioAccessKey  string `envconfig:"MINIO_ACCESS_KEY" required:"true"`
       MinioSecretKey  string `envconfig:"MINIO_SECRET_KEY" required:"true"`
       MinioBucket     string `envconfig:"MINIO_BUCKET" default:"rag-documents"`

       // PostgreSQL
       PostgresHost     string `envconfig:"POSTGRES_HOST" required:"true"`
       PostgresPort     int    `envconfig:"POSTGRES_PORT" default:"5432"`
       PostgresDB       string `envconfig:"POSTGRES_DB" default:"rag"`
       PostgresUser     string `envconfig:"POSTGRES_USER" required:"true"`
       PostgresPassword string `envconfig:"POSTGRES_PASSWORD" required:"true"`

       // NATS
       NatsURL     string `envconfig:"NATS_URL" required:"true"`
       NatsSubject string `envconfig:"NATS_SUBJECT" default:"minio.events"`

       // Processing
       WorkerCount int `envconfig:"WORKER_COUNT" default:"4"`
   }
   ```
2. Implement `Load()` function using envconfig

**Validation**: Print loaded config in main()

**Time Estimate**: 15 minutes

### Step 4: Database Client
**Goal**: Connect to PostgreSQL and implement repository pattern

**Tasks**:
1. Create database connection in `internal/database/postgres.go`
2. Implement `DocumentRepository` interface:
   ```go
   type DocumentRepository interface {
       Create(ctx context.Context, doc *Document) error
       GetByS3Key(ctx context.Context, bucket, key string) (*Document, error)
       UpdateStatus(ctx context.Context, id uuid.UUID, status string, errorMsg *string) error
   }
   ```
3. Define `Document` struct matching schema
4. Implement with pgx connection pool
5. Add connection health check

**Validation**: Insert test document, query it back

**Time Estimate**: 45 minutes

### Step 5: MinIO Client
**Goal**: Connect to MinIO and implement file operations

**Tasks**:
1. Create MinIO client in `internal/storage/minio.go`
2. Implement `StorageClient` interface:
   ```go
   type StorageClient interface {
       GetObjectInfo(ctx context.Context, bucket, key string) (ObjectInfo, error)
       MoveObject(ctx context.Context, bucket, srcKey, destKey string) error
       GetObject(ctx context.Context, bucket, key string) (io.ReadCloser, error)
   }
   ```
3. Implement move using Copy + Delete
4. Add connection health check

**Validation**: Move a test file in bucket

**Time Estimate**: 30 minutes

### Step 6: NATS Subscriber
**Goal**: Subscribe to MinIO events from NATS

**Tasks**:
1. Create NATS client in `internal/messaging/nats.go`
2. Define MinIO event structure:
   ```go
   type MinIOEvent struct {
       EventName string                 `json:"EventName"`
       Key       string                 `json:"Key"`
       Records   []MinIOEventRecord     `json:"Records"`
   }

   type MinIOEventRecord struct {
       EventVersion string              `json:"eventVersion"`
       EventName    string              `json:"eventName"`
       EventTime    time.Time           `json:"eventTime"`
       S3           MinIOEventS3        `json:"s3"`
   }

   type MinIOEventS3 struct {
       Bucket MinIOBucket `json:"bucket"`
       Object MinIOObject `json:"object"`
   }
   ```
3. Implement subscription with handler callback
4. Add graceful shutdown handling

**Validation**: Subscribe and print received events (manual test upload)

**Time Estimate**: 30 minutes

### Step 7: Core Processing Logic
**Goal**: Process events and create document metadata

**Tasks**:
1. Create processor in `internal/processor/processor.go`
2. Implement processing workflow:
   ```go
   func (p *Processor) ProcessDocument(ctx context.Context, event MinIOEvent) error {
       // 1. Extract event details
       // 2. Get object metadata from MinIO
       // 3. Compute destination path (processed/YYYY/MM/DD/)
       // 4. Create document record in PostgreSQL
       // 5. Move file from inbox to processed
       // 6. Update status to 'completed'
   }
   ```
3. Generate destination path: `processed/{YYYY}/{MM}/{DD}/{filename}`
4. Handle errors and update status to 'failed'
5. Add structured logging (slog)

**Validation**: Upload file to inbox, verify it moves and DB record created

**Time Estimate**: 1 hour

### Step 8: Worker Pool
**Goal**: Process events concurrently

**Tasks**:
1. Create worker pool in main():
   ```go
   jobs := make(chan MinIOEvent, 100)

   for i := 0; i < config.WorkerCount; i++ {
       go worker(ctx, jobs, processor)
   }
   ```
2. NATS handler pushes events to jobs channel
3. Workers pull from channel and process
4. Add metrics: processed count, error count

**Validation**: Upload multiple files, verify parallel processing

**Time Estimate**: 30 minutes

### Step 9: Reprocessing Support
**Goal**: Allow reprocessing of documents

**Tasks**:
1. Add `reprocess` flag to document record (boolean)
2. Add `reprocess_count` counter
3. Create NATS subject for reprocess requests: `documents.reprocess`
4. Reprocess event format:
   ```json
   {
     "document_id": "uuid",
     "reason": "string"
   }
   ```
5. Subscriber handles both new and reprocess events
6. For reprocess: fetch document from DB, rebuild event, process

**Validation**: Trigger reprocess via NATS publish, verify it works

**Time Estimate**: 45 minutes

### Step 10: Health Checks & Observability
**Goal**: Make service production-ready

**Tasks**:
1. Add HTTP server for health checks:
   - `/health` - overall health
   - `/ready` - readiness (DB, MinIO, NATS connected)
   - `/metrics` - Prometheus metrics (future)
2. Add structured logging with fields:
   - document_id, s3_key, status, duration, error
3. Add graceful shutdown:
   - Drain NATS subscription
   - Wait for in-flight jobs
   - Close connections
4. Add panic recovery in workers

**Validation**: curl health endpoints, verify graceful shutdown

**Time Estimate**: 45 minutes

### Step 11: Containerization
**Goal**: Package as Docker image

**Tasks**:
1. Create multi-stage Dockerfile:
   ```dockerfile
   # Build stage
   FROM golang:1.21-alpine AS builder
   WORKDIR /app
   COPY go.* ./
   RUN go mod download
   COPY . .
   RUN CGO_ENABLED=0 go build -o processor ./cmd/processor

   # Runtime stage
   FROM alpine:3.19
   RUN apk --no-cache add ca-certificates
   COPY --from=builder /app/processor /processor
   USER nobody
   ENTRYPOINT ["/processor"]
   ```
2. Build and test locally
3. Push to container registry (GitHub Container Registry)

**Validation**: Run container with env vars, verify it works

**Time Estimate**: 30 minutes

### Step 12: Kubernetes Deployment
**Goal**: Deploy to cluster with Flux

**Tasks**:
1. Create MinIO service account for processor
2. Create PostgreSQL user with appropriate permissions
3. Create secrets for credentials (SOPS encrypted)
4. Create Deployment manifest:
   - Resource limits (CPU: 100m-500m, Mem: 128Mi-512Mi)
   - Environment variables from secrets/configmaps
   - Health/readiness probes
   - Replicas: 2 (for HA)
5. Add to Flux kustomization

**Files**:
- `flux/clusters/talos/apps/rag-system/document-processor/`

**Validation**: Deploy, verify logs show successful processing

**Time Estimate**: 1 hour

### Step 13: MinIO Bucket Notifications
**Goal**: Configure MinIO to send events to NATS

**Tasks**:
1. Update MinIO HelmRelease to add bucket notification:
   ```yaml
   buckets:
     - name: rag-documents
       notifications:
         - name: inbox-watcher
           events:
             - "s3:ObjectCreated:Put"
           prefix: "inbox/"
   ```
2. Configure NATS connection in MinIO
3. Test event flow end-to-end

**Note**: This might require MinIO restart

**Validation**: Upload file, see event in processor logs

**Time Estimate**: 30 minutes

## Implementation Order Summary

1. ✅ **Step 1**: Project scaffolding (30min)
2. ✅ **Step 2**: PostgreSQL schema (20min)
3. ✅ **Step 3**: Configuration (15min)
4. ✅ **Step 4**: Database client (45min)
5. ✅ **Step 5**: MinIO client (30min)
6. ✅ **Step 6**: NATS subscriber (30min)
7. ✅ **Step 7**: Core processing (1hr)
8. ✅ **Step 8**: Worker pool (30min)
9. ✅ **Step 9**: Reprocessing (45min)
10. ✅ **Step 10**: Health checks (45min)
11. ✅ **Step 11**: Docker image (30min)
12. ✅ **Step 12**: Kubernetes deployment (1hr)
13. ✅ **Step 13**: MinIO notifications (30min)

**Total Estimated Time**: ~8 hours

## Testing Strategy

**Unit Tests**: Each package should have tests
- Database operations (use testcontainers)
- Processing logic (mock dependencies)
- Configuration loading

**Integration Tests**: Test full flow
- Upload file to MinIO
- Verify NATS event received
- Verify DB record created
- Verify file moved

**Manual Testing**: Use Alist UI
- Upload document via Alist
- Check PostgreSQL for record
- Verify file in processed folder

## Future Enhancements (Post-MVP)

1. **Text Extraction**: Add OCR for PDFs
2. **Chunking**: Split documents into semantic chunks
3. **Embeddings**: Generate vector embeddings
4. **Retry Logic**: Exponential backoff for failures
5. **Dead Letter Queue**: Move failed items for manual review
6. **Metrics**: Prometheus metrics for monitoring
7. **Tracing**: OpenTelemetry for distributed tracing
8. **Webhook Support**: Notify external systems on completion

## See Also

- [Inbox Processing Pipeline](./inbox-processing-pipeline.md)
- [RAG Implementation Framework](./rag-implementation-framework.md)
