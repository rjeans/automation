# PostgreSQL + pgvector Verification Guide

## Overview

This deployment creates a CloudNativePG-managed PostgreSQL 16 instance with pgvector extension for the RAG pipeline.

## Prerequisites

Before deploying, you need to:

1. **Set a strong password** in `secret.yaml`:
   ```bash
   # Edit the secret file
   nano flux/clusters/talos/apps/rag-system/postgresql/secret.yaml

   # Change "CHANGEME-generate-strong-password" to a strong password
   # You can generate one with:
   openssl rand -base64 32
   ```

2. **(Optional) Encrypt with SOPS** if you have it configured:
   ```bash
   sops --encrypt --in-place flux/clusters/talos/apps/rag-system/postgresql/secret.yaml
   ```

## Deployment Steps

1. **Commit and push**:
   ```bash
   git add flux/clusters/talos/apps/
   git commit -m "feat: Add PostgreSQL with pgvector for RAG pipeline"
   git push
   ```

2. **Watch Flux reconciliation**:
   ```bash
   # Watch the apps kustomization
   flux get kustomizations apps -w

   # Watch HelmReleases
   watch flux get helmreleases -n rag-system

   # Watch pods
   kubectl get pods -n rag-system -w
   ```

## Verification Steps

### Step 1: Verify Operator is Running

```bash
kubectl get pods -n rag-system -l app.kubernetes.io/name=cloudnative-pg
```

Expected: 1 pod in `Running` state

### Step 2: Verify PostgreSQL Cluster is Running

```bash
kubectl get cluster -n rag-system
```

Expected output:
```
NAME           AGE   INSTANCES   READY   STATUS                     PRIMARY
postgres-rag   2m    1           1       Cluster in healthy state   postgres-rag-1
```

### Step 3: Verify PVC is Bound

```bash
kubectl get pvc -n rag-system
```

Expected: 20Gi PVC bound to Longhorn storage

### Step 4: Connect to PostgreSQL

```bash
# Get the password
kubectl get secret postgres-rag-superuser -n rag-system -o jsonpath='{.data.password}' | base64 -d
echo

# Connect via kubectl exec
kubectl exec -it -n rag-system postgres-rag-1 -- psql -U postgres
```

### Step 5: Verify pgvector Extension

Once connected to PostgreSQL:

```sql
-- List installed extensions
\dx

-- You should see:
--   vector | 0.7.x | public | vector data type and ivfflat and hnsw access methods
```

### Step 6: Test Vector Operations

```sql
-- Create a test table with vector column
CREATE TABLE test_embeddings (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(1536)  -- OpenAI embedding size
);

-- Insert a test vector
INSERT INTO test_embeddings (content, embedding)
VALUES ('test document', ARRAY[0.1, 0.2, 0.3]::vector);

-- Verify it worked
SELECT * FROM test_embeddings;

-- Clean up test table
DROP TABLE test_embeddings;
```

### Step 7: Test Vector Similarity Search

```sql
-- Create a test table
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(3)
);

-- Insert test data
INSERT INTO documents (content, embedding) VALUES
    ('cat', '[1,0,0]'),
    ('dog', '[0.9,0.1,0]'),
    ('fish', '[0,0,1]');

-- Perform cosine similarity search
SELECT
    content,
    1 - (embedding <=> '[1,0,0]'::vector) as similarity
FROM documents
ORDER BY embedding <=> '[1,0,0]'::vector
LIMIT 3;

-- Expected: cat has highest similarity, then dog, then fish

-- Clean up
DROP TABLE documents;
```

## Connection Details for Applications

Applications can connect using:

- **Host**: `postgres-rag-rw.rag-system.svc.cluster.local`
- **Port**: `5432`
- **Database**: `postgres` (or create app-specific databases)
- **Username**: `postgres`
- **Password**: Stored in secret `postgres-rag-superuser`

### Creating Application Databases

```sql
-- Connect as postgres user, then:
CREATE DATABASE photoprism;
CREATE DATABASE paperless;
CREATE DATABASE mailpiler;

-- For RAG services (optional separate DB)
CREATE DATABASE rag_metadata;
```

## Resource Usage

Monitor resource usage:

```bash
# Pod resource usage
kubectl top pods -n rag-system

# PVC usage
kubectl exec -n rag-system postgres-rag-1 -- df -h /var/lib/postgresql/data
```

## Troubleshooting

### Operator not starting

```bash
kubectl describe pod -n rag-system -l app.kubernetes.io/name=cloudnative-pg
kubectl logs -n rag-system -l app.kubernetes.io/name=cloudnative-pg
```

### Cluster not healthy

```bash
kubectl describe cluster -n rag-system postgres-rag
kubectl logs -n rag-system postgres-rag-1
```

### pgvector not available

```bash
# Check PostgreSQL logs
kubectl logs -n rag-system postgres-rag-1 | grep vector

# Verify shared_preload_libraries
kubectl exec -n rag-system postgres-rag-1 -- psql -U postgres -c "SHOW shared_preload_libraries;"
```

## Next Steps

Once PostgreSQL is verified:

1. ✅ **PostgreSQL + pgvector** - Complete!
2. ⏭️  **Deploy MinIO** - Canonical S3 storage for photos/docs/emails
3. ⏭️  **Deploy first application** - PhotoPrism or Paperless-ngx
4. ⏭️  **Build RAG services** - Extractor, Indexer, Retriever

## Cleanup (if needed)

```bash
# Remove from Flux
git revert <commit>
git push

# Or manually delete
kubectl delete cluster -n rag-system postgres-rag
kubectl delete helmrelease -n rag-system cloudnative-pg
kubectl delete namespace rag-system
```
