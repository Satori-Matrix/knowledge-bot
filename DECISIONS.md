# Architectural Decisions Record

This document captures the architectural decisions made for the Forensic-Grade Knowledge Bot for People Operations, the alternatives considered, and the trade-offs accepted.

The format follows the Architectural Decision Record (ADR) convention: each decision is dated, has a status, the context that drove it, the alternatives weighed, the choice made, and the consequences accepted.

This is a demo project deliverable. All decisions are demo-appropriate; production deployment requires the additional gates listed in `docs/PRODUCTION_CHECKLIST.md`.

---

## ADR-001: v1 Architecture — Self-Hosted n8n + Postgres + Qdrant + Claude API

**Date:** 2026-05-01
**Status:** Accepted (v1)

### Context

A Slack-deployed knowledge bot for an internal People-team use case. The build budget is approximately 6 hours. The deployment target is a security-vendor's internal infrastructure. The non-negotiable design properties are: forensic-grade audit trail, GDPR-compliant data handling, refusal-on-low-confidence retrieval, demonstrable reviewer interface for non-technical users.

### Alternatives Considered

| Alternative | Why not chosen |
|-------------|----------------|
| GCP Cloud Run + Vertex AI Search + Cloud SQL | Strong production option (Mercari shape), but build setup exceeds 6h budget. Documented as v2 path. |
| AWS Bedrock Knowledge Bases | Wrong cloud (target uses Google Workspace, not AWS). Adds vendor relationship. |
| Microsoft Copilot Studio | Wrong stack (no M365 presence on target). Acquiring licensing for the demo is backwards. |
| Glean / Tettra / Question Base | Vendor owns the audit log schema. Demo becomes 'configured a vendor product' not 'architected the system.' |
| Gemini for Workspace | Audit log schema is Google's, not ours. For a DFIR vendor, owning the audit log end-to-end matches the product philosophy. |
| Zapier chatbot | No custom audit trail, no refusal semantics, no chunk-level citations. Insufficient for a security-vendor internal tool. |

### Decision

n8n self-hosted on Hostinger VPS, with Postgres for the audit log, Qdrant for vector retrieval, Claude API for generation, Slack as the ingress and egress channel.

### Consequences

**Accepted:**
- Self-hosted ops burden (small for a single-user demo, real for production)
- Single-node bottleneck for the demo (mitigated by KVM8 sizing — 32GB RAM, 8 vCPU, ample headroom)
- TLS handled by existing Traefik + Let's Encrypt on the VPS

**Mitigated by v2 path:** Production migration to GCP Cloud Run + Cloud SQL + Vertex AI Search if scale demands.

---

## ADR-002: Reuse Existing n8n + Traefik (Option B)

**Date:** 2026-05-01
**Status:** Accepted (v1)

### Context

The target VPS already has n8n + Traefik running (from a Hostinger n8n template) and an unused Qdrant compose file. Three options were weighed.

### Alternatives Considered

| Option | Time | Defensibility |
|--------|------|---------------|
| A. Adopt-everything (reuse Postgres too) | ~3.5h | Lower isolation; data shared with another project |
| B. Adopt n8n + Traefik, dedicated Postgres + Qdrant | ~4.5h | Shared platform, isolated data — strongest balance |
| C. Build standalone via Cloudflare Tunnel + fresh n8n | ~6h | Maximum portability; throws away usable infrastructure |

### Decision

Option B. Reuse n8n and Traefik (proven, TLS already configured, on the shared `app-net` Docker network). Stand up new dedicated Postgres (`postgres_binalyze`) and Qdrant (`qdrant_binalyze`) containers for the bot's data.

### Consequences

**Accepted:**
- Bot's containers share VPS resources with another project; Docker resource limits not yet set
- Bot's n8n workflows visible in the same n8n UI as other projects (visual clarity for demo handled by naming + workflow tagging)
- Data layer is fully isolated; only the orchestration layer is shared

**Migration story (production):** "Bot's data is fully portable. Container migration to a dedicated host is a Docker compose move, not a re-architecture."

---

## ADR-003: Single-Instance n8n (Queue Mode Deferred)

**Date:** 2026-05-01
**Status:** Accepted (v1)

### Context

The original architecture brief mentioned n8n Queue Mode (multi-worker, Redis-backed) as a v1 property. Inspection of the existing n8n install showed single-instance deployment.

### Decision

Stay with single-instance n8n for v1. Queue Mode is documented as v2 upgrade path, justified only when measured throughput demands it.

### Consequences

**Accepted:**
- Demo throughput is bounded by single-process n8n
- Acceptable for the demo's user count (single demonstrator)

**Migration:** Queue Mode adds Redis + worker containers. Documented procedure in PRODUCTION_CHECKLIST.md.

---

## ADR-004: Cloudflare Tunnel Deferred to v2

**Date:** 2026-05-01
**Status:** Accepted (v1)

### Context

Original brief included Cloudflare Tunnel for Slack ingress. Inspection showed Traefik already provides public HTTPS ingress with valid Let's Encrypt TLS.

### Decision

Use existing Traefik for v1. Cloudflare Tunnel deferred to v2 (DDoS protection, no exposed ports, additional audit logging at the edge).

### Consequences

**Accepted:**
- Public ingress via Traefik on a Hostinger subdomain
- TLS auto-renewal via Let's Encrypt
- No DDoS protection layer (acceptable for an internal-traffic bot at demo scale)

---

## ADR-005: Audit Log — 13 Fields, Append-Only, Append-Only-Enforced via Triggers

**Date:** 2026-05-01
**Status:** Accepted (v1)

### Context

The non-negotiable design property is forensic-grade audit. Standard SQL permissions are insufficient — a careless or compromised account could still bypass them. Database-level triggers enforce append-only at the lowest level.

### Decision

Audit log is a Postgres table with these properties:
- 13 fields covering query identity, content, retrieval, generation, refusal reason, retention, legal hold metadata
- INSERT permitted; UPDATE and DELETE blocked by PostgreSQL trigger
- Even the table owner cannot UPDATE/DELETE without explicitly disabling the trigger (which is itself logged)
- Each row includes `created_at`, `retention_until`, `legal_hold` boolean, `legal_hold_reason`, `legal_hold_set_by`, `legal_hold_set_at`

### Consequences

**Accepted:**
- Schema migrations require trigger handling (drop, alter, recreate); documented procedure
- "Hot-fixing" a bad audit row in production requires explicit DBA intervention with logged justification — by design
- Append-only triggers cost negligible CPU per insert

### Forensic / eDiscovery alignment

Append-only at the database layer + cryptographic hash chaining (v2) + signed exports (v2) gives chain-of-custody satisfying ISO/IEC 27037 and FRE 901 expectations. The v1 build implements the database layer; v2 adds export-time hashing and signing.

---

## ADR-006: Retention — 90 Days for Queries, 7 Years for Refusals, Litigation Hold Overrides

**Date:** 2026-05-01
**Status:** Accepted (v1)

### Context

Two competing concerns: GDPR Article 5(1)(e) data minimisation (delete when purpose fulfilled) versus forensic preservation needs (retain evidence). The split-and-override pattern resolves both.

### Decision

- **Default queries:** 90-day retention. Routine deletion script removes rows where `created_at < NOW() - 90 days AND legal_hold = FALSE AND refusal_reason IS NULL`.
- **Refusals:** 7-year retention. Refusals are compliance evidence ("we appropriately declined to answer X under conditions Y") and warrant longer retention.
- **Litigation hold:** Overrides both. Held rows are excluded from any retention deletion script regardless of age.

### Consequences

**Accepted:**
- Two-tier retention requires the deletion script to discriminate by `refusal_reason IS NOT NULL`
- 7-year retention for refusals adds storage cost (negligible at this scale)
- Held data may grow indefinitely under prolonged investigations — by design

**Compliance alignment:** GDPR Art. 5(1)(e) data minimisation respected for routine ops; Art. 17(3)(e) "establishment, exercise or defence of legal claims" exemption invoked for held data. LIA (Legitimate Interest Assessment) documented separately by DPO before production deployment.

---

## ADR-007: GDPR Lawful Basis — Legitimate Interest (Article 6(1)(f))

**Date:** 2026-05-01
**Status:** Design assumption — DPO sign-off required for production

### Context

The bot processes personal data of employees (Slack `user_id`, query text, timestamps). A lawful basis under GDPR Article 6 is required.

### Alternatives Considered

| Basis | Why not chosen |
|-------|---------------|
| Consent (Art. 6(1)(a)) | Bad fit for internal tools — consent is fragile, withdrawable, creates inconsistent service |
| Contract performance (Art. 6(1)(b)) | Bot use isn't a contractual obligation; basis is questionable |
| Legal obligation (Art. 6(1)(c)) | No specific legal mandate exists for an internal Q&A bot |

### Decision

**Article 6(1)(f) — Legitimate Interest.** Standard for workplace tools where the data subject is the employee. The legitimate interest: providing People-team self-service is operationally beneficial, reduces repetitive support burden, and is proportionate to the data processed.

### Consequences

**Required for production deployment:**
- LIA (Legitimate Interest Assessment) document drafted by DPO
- Privacy notice updated to inform employees of the bot's data processing
- Records of Processing (Art. 30) entry added to organisational ROPA

**Forensic export exemption:** Article 17(3)(e) — "establishment, exercise or defence of legal claims" — overrides erasure requests for data under litigation hold. Documented in `docs/COMPLIANCE.md`.

---

## ADR-008: Reviewer Interface — NocoDB for Case Work + Grafana for Operations

**Date:** 2026-05-01
**Status:** Accepted (v1)

### Context

Two distinct user audiences need different views into the audit log:
- **Operators** (e.g. People-team lead, VP Operations): metrics, query rate, refusal rate, retrieval confidence trends
- **Reviewers** (e.g. compliance team): case-work — find specific queries by user/date/keyword, mark for legal hold, export

A single tool serving both audiences poorly serves either.

### Decision

Two-tool approach:
- **Grafana** — operational dashboard. Real-time charts, time-series metrics. Auto-refreshes during demo.
- **NocoDB** — reviewer interface. Spreadsheet-style search, multi-column filters, date range, full-text search, CSV export, row-level legal hold toggle.

Both read from the same Postgres `audit_log` table — single source of truth.

### Alternatives Considered

| Option | Why not chosen |
|--------|---------------|
| SQL queries only | Excludes non-technical reviewers; ticket queue burden on engineering |
| Bespoke web UI (Flask/FastAPI + HTMX) | 90-120 minutes build; consumes 2h of demo budget |
| Retool / Appsmith SaaS | External vendor dependency; less defensible for an internal tool at a security vendor |
| Grafana table panels alone | Not designed for case-management workflows; bulk actions limited |

### Consequences

**v1 capabilities:**
- Reviewer searches by user, date range, status, keyword
- One-click CSV export of filtered set (eDiscovery format = v2)
- Row-level legal hold toggle (NocoDB writes to one specific column; rest stay locked by trigger)

**v1 limitations (documented, not built):**
- CSV export is not cryptographically signed or hashed
- No load-file format (Concordance, Relativity .DAT) for direct eDiscovery production
- No automatic incremental export on hold rows

**v2 deliverable: forensic export wrapper.** Python script triggered by NocoDB webhook or schedule, wraps CSV with SHA-256 hash, JSON manifest (filter used, row count, exporter identity, timestamp), optional PGP signature, optional EDRM XML format. Estimated 2-3 days of focused work.

**Production gates:**
- NocoDB version pinning (CVE history)
- SSO integration on NocoDB UI
- RBAC differentiation (People-team view ≠ Compliance-team view ≠ Admin view)

---

## ADR-009: Litigation Hold — Two Mechanisms (Retroactive + Forward)

**Date:** 2026-05-01
**Status:** Accepted (v1)

### Context

Real legal preservation requests come in two shapes: "preserve everything from user X between dates Y and Z" (retroactive only) and "preserve everything from user X going forward, plus historical" (mixed). The bot supports both.

### Decision

**Retroactive hold:** `legal_hold` boolean column on `audit_log` table. Reviewer toggles via NocoDB UI; trigger captures `set_by` and `set_at`. Routine retention script skips `legal_hold = TRUE` rows.

**Forward hold:** Separate `legal_hold_subjects` table keyed on `slack_user_id`. n8n workflow checks this table before writing each new audit row. If subject is in the table with `released_at IS NULL`, the new row is auto-tagged `legal_hold = TRUE`.

**Hold management:** Adding/removing entries from `legal_hold_subjects` is itself audited (separate `hold_audit` table). The audit log of the audit log.

### Consequences

**Accepted:**
- One additional DB lookup per query (~5ms with `slack_user_id` index)
- Two tables to maintain (audit_log + legal_hold_subjects + hold_audit)
- Reviewer UI must show "subject is currently under hold" indicator on rows

**Procedural requirement:**
- Releasing a hold sets `released_at` but does NOT auto-delete held data
- Held data remains tagged for record purposes after release
- Decision to delete post-release requires separate authorisation (legal review)

**Compliance alignment:** Article 17(3)(e) exemption invoked when erasure request received for held subject. Subject is informed that their request is noted but pending. Documented in `docs/COMPLIANCE.md`.

---

## ADR-010: RBAC v1 — Single Block-List; v2 — Slack User Group Mapping

**Date:** 2026-05-01
**Status:** Accepted (v1) for block-list; documented design for v2 role mapping

### Context

True role-based access control via Slack User Group lookup is the right production design but exceeds the 6h budget. A minimal RBAC primitive in v1 demonstrates the principle without consuming the build.

### Decision

**v1:** Hardcoded block-list of Slack User IDs in n8n credentials. Workflow checks `slack_user_id NOT IN block_list` before retrieval. Blocked attempts logged to audit_log with `refusal_reason = 'rbac_blocked'`.

**v2 (documented):** Replace block-list with role-based access:
- `employee` — can ask people_ops questions, see only own audit history
- `people_team` — can ask all questions, see all audit logs
- `compliance_team` — can mark legal hold, view all audit logs and held subjects
- `admin` — full access, including configuration changes

Slack User Group membership maps to role; cached for 5 minutes; audit log captures `role_at_time_of_query` for forensic record.

### Consequences

**v1 demo signal:** Demonstrates the RBAC primitive with audit-trail integration. Reviewer sees blocked attempts in NocoDB.

**v2 build estimate:** 1-2 days. Slack User Group API integration + role caching + per-role NocoDB views.

---

## ADR-011: MCP Tool Use — Selective, Token-Conscious

**Date:** 2026-05-01
**Status:** Accepted (v1)

### Context

MCP servers vary in token cost. Some inject 30,000+ tokens of schemas per Cursor turn (e.g. official GitHub MCP with 43 tools). Others use progressive discovery (~2,000-3,000 tokens). The wrong choice burns tokens without value.

### Decision

**Three MCPs, selected for token economics:**
- **n8n-mcp** (czlonkowski) — ~14 tools, progressive discovery via `get_node_essentials`. Prevents node hallucination during workflow build.
- **Postgres MCP** (crystaldba/postgres-mcp, restricted mode) — ~6 tools, read-only. Validates audit log writes during testing.
- **Context7** (Upstash) — 2 tools. Live documentation lookup for fast-moving libraries.

**Skipped:**
- GitHub MCP (43 tools, ~28k tokens per turn) — `gh` CLI in terminal achieves same result at zero token cost.

**Token-saving conventions encoded in `.cursor/rules/00-base.mdc`:**
- Use `get_node_essentials` not `get_node`
- Project-level config for project-specific MCPs (n8n, Postgres)
- Global config for general-purpose (Context7)

### Consequences

**Accepted:**
- ~5,000 tokens per Cursor turn baseline schema cost
- Progressive discovery means MCPs are slower for first call but cheaper overall

### Update 2026-05-02

The upstream czlonkowski `n8n-mcp` package consolidated its tool surface: the former `get_node_essentials`, `get_node_info`, and `get_node_documentation` capabilities are now **modes and parameters of a single `get_node` tool** (`detail`: `minimal` | `standard` | `full`, plus other `mode` values per package docs).

ADR-011’s instruction to use **`get_node_essentials`** should be read as **use `get_node` with `detail: "standard"`** against the current package. Token-economics reasoning is unchanged; only the tool name and invocation shape changed.

---

## ADR-012: Knowledge Base Content — `[ILLUSTRATIVE]` Tagging

**Date:** 2026-05-01
**Status:** Accepted (v1)

### Context

The demo cannot use real organisational policies. Synthetic stub content fills the knowledge base. Honesty about the synthetic nature must be preserved.

### Decision

All knowledge base documents tagged `[ILLUSTRATIVE]` in their frontmatter. The bot's response template includes the tag visibly in citations. Reviewers and demo audience can immediately see which content is synthetic.

### Consequences

**Accepted:**
- Demo authenticity is high — no fake claim of real policies
- Real deployment substitutes real internal documentation; the tagging mechanism remains useful as a "draft / unverified" status indicator

---

## ADR-013: Cursor Rules Files — Plan-vs-Reality and Incremental Authoring

**Date:** 2026-05-02  
**Status:** Accepted (v1)

### Context

The foundation phase plan described six `.mdc` rule files (`00-base`, `10-security`, `20-architecture`, `30-database`, `40-n8n-workflows`, `50-llm-prompts`). Only `00-base.mdc` and `10-security.mdc` were authored at foundation close; the other four were never created, while `BUILD_LOG.md` implied a fuller tree than existed on disk.

### Decision

Author the remaining `.mdc` files **alongside the phases they govern**, not ahead of the work. Concretely: `30-database.mdc` is created when Phase 3b Postgres schema work is in progress; `40-n8n-workflows.mdc` when Phase 3d workflow build is in progress; and so on. Rules are added when there is concrete behaviour to encode, not as speculative placeholders.

### Consequences

**Accepted:**
- `BUILD_LOG.md` file trees and “rules present” claims must match the repository at all times — no aspirational rule files in the inventory.
- Early sessions reference fewer `.mdc` files; that is honest scope, not a gap to paper over.

**Rejected for v1:**
- Pre-writing empty or generic `.mdc` stubs “for completeness” without governed artefacts.

---

## ADR-014: n8n-mcp Documentation-Only Mode (No N8N_API_KEY in v1)

**Date:** 2026-05-02  
**Status:** Accepted (v1)

### Context

The czlonkowski `n8n-mcp` package supports at least two modes: **documentation mode** (no n8n API credentials; exposes on the order of seven tools for node lookup, validation, and related read-oriented operations) and **management mode** (with `N8N_API_URL` and `N8N_API_KEY`, exposing additional tools such as workflow create/update against a live n8n instance).

### Decision

**v1 uses documentation-only mode.** The production demo workflow is built in the n8n UI. `n8n-mcp` exists in Cursor to supply accurate node schema and validation during design and prompting — not to mutate live workflows from the agent.

### Reasoning

Least privilege: granting management credentials to an MCP reachable from Cursor would allow an agent session to alter real production workflows during a build — an unnecessarily broad attack surface for a forensic-grade demo whose audit story is anchored elsewhere.

### Consequences

**Accepted:**
- The Cursor agent cannot create or modify the live n8n workflow via `n8n-mcp`; operators build and export workflows manually in n8n.

**Deferred:**
- v2 may enable management mode for ops automation only behind explicit opt-in, change control, and separate credential scope.

---

## Decisions Not Yet Made (Open Questions)

These are explicitly deferred to production planning:

- **Anthropic data residency** — EU enterprise tier vs US standard. Affects GDPR transfer-mechanism analysis.
- **Backup and disaster recovery** — Postgres point-in-time recovery, Qdrant snapshot frequency. Document in PRODUCTION_CHECKLIST.md.
- **Monitoring beyond Grafana** — Sentry for application errors, structured log shipping. v2 scope.
- **Scale beyond demo** — single-instance limits, concurrent query handling, retrieval cache. Driven by measured load, not pre-optimised.

---

## Decision Log Maintenance

This file is intended to grow as the project evolves. New decisions append as new ADRs. Superseded decisions remain in the file with status updated to "Superseded by ADR-XXX." Decisions are not deleted — the record is the chain of custody for the architecture itself.
