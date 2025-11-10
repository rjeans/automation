# Personal Digital Media Archive and RAG Framework
*A framework for implementation, iteration, and refinement*

**Author:** Richard Jeans  
**Version:** 0.1 (Initial Framework)  
**Date:** November 2025  

---

## 1. Purpose and Vision

This document defines the **implementation framework** for a personal digital media archive and retrieval system that enables **AI-assisted natural language search** across personal photos, documents, and emails.

The initial implementation will run on a **Raspberry Pi–based Kubernetes cluster** managed with **Flux**, using **cloud-based AI services** for embedding, reranking, and generation.  
As the solution matures, heavy AI workloads will migrate to **self-hosted models** on more powerful hardware.

The framework is designed for **iterative refinement**, supporting incremental development and future modular replacement of cloud dependencies with local equivalents.

---

## 2. High-Level Objectives

1. **Canonical Archival Store**  
   - Maintain an immutable, versioned, and searchable archive of personal photos, documents, and emails.  
   - Use open-source software and S3-compatible storage for full data sovereignty.

2. **AI-Assisted Discovery (RAG Pipeline)**  
   - Enable natural language queries over archived materials via a retrieval-augmented generation (RAG) pipeline.  
   - Support hybrid retrieval: semantic similarity + structured metadata filtering.

3. **Unified Web Access**  
   - Provide web interfaces for browsing, managing, and searching media:
     - PhotoPrism for photos/videos
     - Paperless-ngx for documents
     - Mailpiler for email
     - OpenWebUI for conversational AI

4. **Iterative Evolution**  
   - Phase 1: Pi-based cluster + cloud AI services  
   - Phase 2: Local AI inference (Ollama or similar)  
   - Phase 3: Advanced indexing, reranking, and cross-media relations  

---

## 3. Reference Architecture

### 3.1 Overview Diagram

```
[Diagram omitted for brevity — see architecture section in repo]
```

---

## 4. Component Summary

| Category | Component | Function |
|-----------|------------|----------|
| **Storage** | **MinIO** | Canonical archive for photos, documents, emails; S3-compatible; versioning and object lock |
| **Database** | **Postgres + pgvector** | Metadata and embedding store for RAG indexing |
| **Event Bus** | **NATS** | Event-driven pipeline for ingest and processing |
| **Orchestration** | **Flux + n8n** | GitOps lifecycle management + automation workflows |
| **Apps (UI)** | PhotoPrism / Paperless-ngx / Mailpiler / OpenWebUI | Browsing, managing, and AI chat interfaces |
| **AI/RAG** | Extractor, Indexer, Retriever, LLM Adapter | Core RAG pipeline; modular to switch from cloud to local |
| **Security** | Authelia + Cloudflare Zero Trust | Unified authentication and remote access |
| **Backups** | MinIO replication + pg_dump | Versioned S3 backups for resilience |

---

## 5. Implementation Phases

### Phase 0 – Foundation
- Deploy Flux, NGINX ingress, cert-manager
- Set up Postgres + pgvector
- Configure MinIO (versioning + object lock)
- Deploy NATS, Authelia, Cloudflare Zero Trust

### Phase 1 – Canonical Applications
- Deploy PhotoPrism, Paperless-ngx, Mailpiler
- Integrate MinIO S3 storage
- Configure SSO and ingress
- Validate manual ingestion and search

### Phase 2 – Cloud-Backed RAG MVP
- Build LLM Adapter (OpenAI/Cohere/Voyage API integration)
- Deploy Extractor + Indexer + Retriever FastAPI services
- Enable vector indexing in pgvector
- Connect OpenWebUI → Retriever
- Add n8n workflows for ingestion/reindexing

### Phase 3 – Image and Cross-Media Integration
- Implement photo captioning (cloud Vision or BLIP)
- Add CLIP embeddings for photos
- Link PhotoPrism metadata to Postgres
- Enable cross-media semantic queries

### Phase 4 – Self-Hosted AI Transition
- Deploy Ollama or local inference backend
- Update Adapter PROVIDER to 'local'
- Re-embed older data locally
- Migrate from cloud embeddings

### Phase 5 – Refinement & Hardening
- Add autoscaling and monitoring (Prometheus/Grafana)
- Enable feedback loop for RAG relevance
- Automate backup and DR testing

---

## 6. Iteration Framework

Each phase follows a **Plan → Build → Evaluate → Integrate** loop:

1. **Plan:** Define sprint scope and measurable output.  
2. **Build:** Implement and document in repo.  
3. **Evaluate:** Measure performance, cost, and accuracy.  
4. **Integrate:** Merge into Flux and update docs.

---

## 7. Cloud Service Abstraction

**LLM Adapter Responsibilities**
- `/embed`: Convert text → embedding vector  
- `/rerank`: Reorder candidate docs for better precision  
- `/chat`: Generate summaries or conversational responses  

**Config Example:**
```yaml
PROVIDER: openai
EMBED_MODEL: text-embedding-3-small
CHAT_MODEL: gpt-4o-mini
RERANK_PROVIDER: cohere
CACHE_BACKEND: postgres
MAX_QPS_EMBED: 5
```

---

## 8. Security and Compliance

- Authelia SSO + Cloudflare Zero Trust  
- TLS for ingress; SOPS-encrypted secrets  
- Only derived text sent to cloud APIs  
- Object-lock for mail/docs buckets  
- Audit trail via NATS logs

---

## 9. Risks and Mitigations

| Risk | Mitigation |
|-------|-------------|
| Pi resource limits | Offload AI workloads to cloud until stronger node available |
| API cost escalation | Cache embeddings; batch requests |
| Model drift / vendor changes | Adapter abstraction layer |
| Data loss / corruption | Nightly pg_dump + MinIO replication |
| Integration complexity | Modular microservice design |

---

## 10. Deliverables

| Category | Output |
|-----------|--------|
| Documentation | Architecture & API specs |
| Configuration | Flux HelmReleases + SOPS secrets |
| Code | FastAPI services for extractor/indexer/retriever/adapter |
| Infrastructure | Deployed namespaces & services on Pi cluster |
| Validation | End-to-end AI query demo |

---

## 11. Next Steps

1. Create `docs/`, `k8s/apps/`, and `rag/` directories in repo.  
2. Implement foundational stack via Flux.  
3. Build LLM Adapter prototype using OpenAI or Cohere.  
4. Deploy MVP pipeline and validate queries.  
5. Refine through iteration and migrate AI workloads locally.

---

**End of Document**
