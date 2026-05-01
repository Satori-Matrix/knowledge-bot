# Forensic-Grade Knowledge Bot for People Operations

A Slack-deployed knowledge bot for People-team policy questions, built with a focus on **forensic-grade audit trail** and **compliance-by-design**. Demo project for an AI Automation Engineer interview at a DFIR vendor.

## What it does

A user runs `/ask <question>` in Slack. The bot:

1. Verifies the request signature (Slack signing secret, native n8n verification)
2. Retrieves relevant chunks from a controlled knowledge base
3. Generates a grounded answer with Claude Sonnet, citing sources
4. Refuses politely when retrieval confidence is low (no hallucinated answers on policy questions)
5. Writes a 13-field immutable audit row covering chain of custody for every interaction

## Architecture (v1, this demo)

- **n8n** (self-hosted, Hostinger VPS) — workflow orchestration
- **Postgres** — append-only audit log with PostgreSQL trigger enforcement
- **Qdrant** — vector store for hybrid retrieval
- **Claude API** (Anthropic) — generation with structured grounded prompts
- **Slack** — ingress (slash command) and egress (response with citations)
- **Grafana** — operational dashboard for queries, refusals, retrieval metrics
- **Traefik** — reverse proxy with automatic Let's Encrypt TLS

## Why this shape

The audit log isn't a feature — it's the point. Internal AI tools that answer compliance questions without an audit trail are a reputational liability for any security-focused company. This bot can answer the forensic question: "who asked what, when, what was returned, what sources were cited, was the answer refused, why?"

See [`DECISIONS.md`](./DECISIONS.md) for architectural reasoning, build-vs-buy analysis, and rejected alternatives.

## Documentation

- [`DECISIONS.md`](./DECISIONS.md) — architectural decisions and trade-offs
- [`docs/COMPLIANCE.md`](./docs/COMPLIANCE.md) — GDPR posture, retention, RBAC design, litigation hold
- [`docs/SECURITY.md`](./docs/SECURITY.md) — threat model, OWASP LLM Top 10 mapping
- [`docs/PRODUCTION_CHECKLIST.md`](./docs/PRODUCTION_CHECKLIST.md) — what changes from demo to production deployment
- [`docs/REVIEW_GUIDE.md`](./docs/REVIEW_GUIDE.md) — for an independent reviewer: 30-min, 2-hour, and full review paths

## Demo positioning

This repository is shipped as an interview deliverable. The knowledge base content tagged `[ILLUSTRATIVE]` is illustrative only — it does not represent any specific organisation's actual policies. Real deployment would substitute real internal documentation.

## Status

- Foundation: complete
- Workflow build: in progress
- Production-ready: no. Production deployment requires the items in `PRODUCTION_CHECKLIST.md`.

## Security note

**Do not commit secrets.** The `.gitignore` blocks common secret patterns (`.env`, `*.key`, `*.pem`, `.cursor/mcp.json`, n8n credential exports). If you fork this repo, audit `.gitignore` before your first commit.

## License

MIT. See [`LICENSE`](./LICENSE).
