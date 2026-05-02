# Forensic-Grade Knowledge Bot for People Operations

A Slack-deployed knowledge bot for People-team policy questions, built for **forensic-grade audit trail** and **compliance-by-design**. Demo project for an AI Automation Engineer interview at a DFIR vendor.

## What it does

A user invokes the bot from Slack. The service:

1. Verifies the request signature (**Slack Bolt SDK** on **Cloud Run** — no hand-rolled HMAC)
2. Retrieves relevant evidence via **Vertex AI RAG Engine** (layout-aware parsing, including diagrams where configured)
3. Generates a grounded answer with **Gemini 3 via Vertex AI** (or an alternate model such as Claude through **Vertex AI Model Garden** where policy allows), citing sources
4. Refuses politely when retrieval confidence is low (no hallucinated answers on policy questions)
5. Writes a **13-field immutable audit row** to **Cloud SQL (Postgres)** with **append-only triggers** — our schema, our chain of custody

## Architecture (GCP-native, this build)

- **Cloud Run** — Orchestration: Slack ingress, retrieval/generation coordination, optional custom reviewer surfaces
- **Vertex AI RAG Engine** — Commodity layers: ingestion, parsing, embedding, retrieval, reranking
- **Cloud SQL (Postgres)** — **Differentiated:** append-only `audit_log`, retention, litigation hold tables — same design intent as `DECISIONS.md` ADR-005 onward
- **Cloud Storage** — Document upload destination for the corpus
- **Slack** — Ingress and egress
- **Looker Studio + BigQuery** — Operations dashboard and audit-oriented views
- **Cloud Audit Logs + IAM** — Platform-level independent witness alongside application audit rows

**v0 (Hostinger):** A Docker stack under `infra/` (n8n-era prototyping) **remains deployed as fallback**; it is **not** the primary demo path after **ADR-016**. See `DECISIONS.md`.

## Why this shape

**Forensic differentiation is ours:** audit schema, refusal semantics, hold management, and pseudonymisation policy. **Commodity ML/RAG is Google's:** parsing, embeddings, retrieval, and reranking at production quality — including stronger handling of technical layouts than a bolted-on self-hosted vector store.

The demo is positioned as **the architecture Binalyze would actually extend at scale**, not a throwaway self-hosted prototype with a separate “v2 migration” fantasy.

See [`DECISIONS.md`](./DECISIONS.md) for **ADR-016** (GCP pivot), prior ADRs (superseded entries retained), and trade-offs.

## Documentation

- [`DECISIONS.md`](./DECISIONS.md) — architectural decisions and forensic record (incl. ADR-016)
- [`docs/COMPLIANCE.md`](./docs/COMPLIANCE.md) — GDPR posture, retention, RBAC design, litigation hold
- [`docs/SECURITY.md`](./docs/SECURITY.md) — threat model, OWASP LLM Top 10 mapping
- [`docs/PRODUCTION_CHECKLIST.md`](./docs/PRODUCTION_CHECKLIST.md) — v1 production deployment checklist on GCP
- [`docs/REVIEW_GUIDE.md`](./docs/REVIEW_GUIDE.md) — independent reviewer paths

## Demo positioning

This repository is shipped as an interview deliverable. Knowledge base content tagged `[ILLUSTRATIVE]` is synthetic — it does not represent any specific organisation's real policies.

## Status

- Foundation + documentation: complete  
- **ADR-016:** GCP is the primary build path  
- **v0 Hostinger stack:** running as optional fallback (`infra/`)  
- Production-ready: no — follow `PRODUCTION_CHECKLIST.md`

## Security note

**Do not commit secrets.** The `.gitignore` blocks common secret patterns (`.env`, `*.key`, `*.pem`, `.cursor/mcp.json`, credential exports). GCP: use **Secret Manager** and **Workload Identity** — never keys in repo.

## License

MIT. See [`LICENSE`](./LICENSE).
