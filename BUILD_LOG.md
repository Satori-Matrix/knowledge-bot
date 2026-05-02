# Build Log

This document tracks the build state of the Knowledge Bot project. It is updated as the project progresses and serves as the operational source of truth for "where we are" between work sessions.

For architectural decisions, see `DECISIONS.md`. For compliance, see `docs/COMPLIANCE.md`. This file is the operational counterpart — what's done, what's next, what's blocked.

---

## Current Status

**Phase:** Foundation + MCP verification complete 2026-05-02. **Architecture pivot (ADR-016, 2026-05-02):** primary build path is **GCP** (Cloud Run + Vertex AI RAG Engine + Cloud SQL + Cloud Storage + Looker/BigQuery). **Phase 3a** (Hostinger `infra/` stack) is **complete and retained as v0 fallback** on the VPS — superseded as the demo/production target by ADR-016. **Next:** **Phase 3a-G** (GCP project setup).

**Last update:** 2026-05-02 (architectural pivot to GCP; ADR-016)

**Demo target:** Wednesday 2026-05-06, 15:30 UK

**Time budget remaining:** ~6–7 hours of focused build on the GCP path before rehearsal (see Phase Plan)

---

## Architecture Re-platform (2026-05-02)

The project **pivoted mid-build** from a **self-hosted Hostinger** stack (n8n + Postgres + Qdrant + NocoDB + Grafana) to a **production-grade GCP** architecture. Full reasoning, alternatives, and Rule 13 are in **`DECISIONS.md` ADR-016**. ADR-001 through ADR-004 and ADR-008 are **superseded** (text retained as forensic record); ADR-005–007, ADR-009–014 remain valid.

**Operational meaning:** **Phase 3a** (`infra/docker-compose.yml` on Hostinger) stays **up** as **v0 prototyping / fallback**. **Phase 3b onward** on the primary roadmap executes against **GCP** (phases **3a-G … 3f-G** in the table below).

**Preserved:** Audit log schema intent (append-only, 13 fields, retention, hold tables), GDPR posture, litigation-hold logic, documentation discipline, MCP/tooling work — all carry forward to **Cloud SQL** and Cloud Run.

---

## State Recovery (2026-05-02)

`BUILD_LOG.md` previously claimed `n8n-mcp` and Context7 were present in MCP config; inspection showed neither was in the effective `mcp.json` files at that time (config drift versus narrative).

Global `~/.cursor/mcp.json` on the build host had accumulated unrelated MCP entries and **plaintext credentials** (see `docs/SECURITY_INCIDENTS.md` — forensic log only; credentials are not duplicated here).

Cursor remote-SSH workspaces prepend Cursor’s bundled Node on `PATH`, which breaks MCP servers invoked with bare `npx` unless `PATH` is constrained for those processes. Verified fix: `"env": { "PATH": "/usr/bin:/bin" }` on the `npx`-based entries, with `/usr/bin/npx` as command (see `.cursor/rules/00-base.mdc`).

The czlonkowski `n8n-mcp` package consolidated tools: older `get_node_essentials` is now `get_node` with `detail: "standard"` (see ADR-011 addendum and ADR-013/014 in `DECISIONS.md`).

**Verified MCP set (2026-05-02):** `filesystem`, `sequential-thinking`, and `context7` (global); `n8n-mcp` (project scope). All four green in Cursor after the above corrections.

---

## Stack Verified

Audited 2026-05-01 on Hostinger VPS `srv1178070.hstgr.cloud` (72.61.207.148).

### VPS profile
- Plan: KVM 8 — 8 vCPU, 32 GB RAM, 400 GB disk
- OS: Ubuntu 24.04
- Idle resource use: ~2 GB RAM, <5% CPU
- Public ingress: Traefik on ports 80/443 with Let's Encrypt TLS
- n8n public URL: `https://n8n.srv1178070.hstgr.cloud`

### Existing infrastructure on VPS (will reuse)
- `root-n8n-1` — n8n service
- `root-traefik-1` — reverse proxy with TLS
- Docker network `app-net` — shared bridge network
- `/root/docker-compose.yml` — n8n + Traefik orchestration

### Existing infrastructure on VPS (will NOT touch)
- `chainlit_revive`, `raganything`, `ollama`, `reranker` — revive-battery-rag stack
- `postgres_chainlit`, `postgres_rag` — revive's databases (unrelated to bot)
- `/root/qdrant/docker-compose.yml` — orphaned compose file (never deployed)

### Resources for bot's containers
- ~29 GB RAM headroom available
- ~330 GB disk headroom available
- Free ports: 5432, 5433, 6333, 6334, plus any unprivileged
- v0 bot containers join existing `app-net` (see `infra/`); primary path is GCP per ADR-016

---

## Architecture (Locked, See DECISIONS.md for ADRs)

**Primary path (post ADR-016, this build):**
- **Cloud Run** — Slack webhook, orchestration, optional reviewer UI surfaces
- **Vertex AI RAG Engine** — Ingestion, layout-aware parsing (incl. diagrams), embedding, retrieval, reranking (commodity layers)
- **Cloud SQL (Postgres)** — `audit_log` and related tables with append-only triggers (same design intent as ADR-005)
- **Cloud Storage** — Document uploads feeding the corpus
- **Slack** — Ingress/egress; **Slack Bolt SDK** signature verification on Cloud Run
- **Looker Studio + BigQuery** — Ops dashboard (replaces Grafana)
- **Looker / BigQuery and/or Cloud Run UI** — Reviewer / case-work (replaces NocoDB as primary)
- **Gemini 3 via Vertex AI** for generation; **Claude** optional via Vertex **Model Garden**

**v0 (Hostinger, fallback only — superseded as target by ADR-016):** n8n + Traefik + `postgres_binalyze` + `qdrant_binalyze` + `nocodb_binalyze` + `grafana_binalyze` on `app-net` (see `infra/docker-compose.yml`). Containers **remain running** for prototyping and insurance; not the demo/production architecture.

**ADR anchor:** **ADR-016** (pivot). Superseded Hostinger-target ADRs: 001, 002, 003, 004, 008 — bodies preserved in `DECISIONS.md`.

---

## Key Decisions Made

(Cross-reference DECISIONS.md for the formal record.)

- **Retention:** 90 days for queries, 7 years for refusals, indefinite under litigation hold
- **GDPR lawful basis:** Article 6(1)(f) Legitimate Interest + Art. 17(3)(e) for legal proceedings
- **RBAC v1:** hardcoded block-list in Cloud Run config / Secret Manager (v0: n8n credentials on Hostinger)
- **RBAC v2 design:** `employee` / `people_team` / `compliance_team` / `admin` mapped to Slack User Groups
- **Litigation hold:** retroactive (legal_hold column) + forward (legal_hold_subjects table)
- **Reviewer / ops surfaces:** Looker Studio + BigQuery views; optional Cloud Run reviewer UI (replaces NocoDB + Grafana as primary)
- **Forensic export:** CSV / BQ export + v2 wrapper (hash + manifest + signature) documented in `PRODUCTION_CHECKLIST.md`
- **Single category v1:** People Operations only (multi-category metadata schema designed in)
- **Knowledge base content:** all stub docs tagged `[ILLUSTRATIVE]`
- **External validation path:** automated SMB stack (~£0-50/month) is the realistic answer; £10-20k external review documented for high-stakes deployments only

---

## MCP Servers Configured (verified 2026-05-02)

| Server | Scope | Tools (approx.) | Notes |
|--------|--------|-----------------|--------|
| **filesystem** | Global (`~/.cursor/mcp.json`) | 14 | Working |
| **sequential-thinking** | Global | 1 | Working |
| **context7** | Global | 2 | Working — `/usr/bin/npx` + `env.PATH` `/usr/bin:/bin` |
| **n8n-mcp** (czlonkowski) | Project (`.cursor/mcp.json`) | 7 tools + 2 resources | Documentation-only mode; working — `/usr/bin/npx` + same `PATH` override |

**Removed from global config during recovery:** `github`, `postgres-chainlit`, `postgres-rag`, `memory` (and associated plaintext material — see `docs/SECURITY_INCIDENTS.md`).

**Still skipped by design (token economics / phase):**
- GitHub MCP — replaced by `gh` CLI in terminal
- Postgres MCP — to be added after **Cloud SQL** for the bot is reachable (Phase 3b-G+), read-only mode when introduced

**MCP sanity test:** ✅ Complete (2026-05-02), including config drift recovery and live Cursor checks for all four servers above.

---

## Files Committed (in repo)

```
KNOWLEDGE-BOT/
├── .cursor/
│   ├── rules/
│   │   ├── 00-base.mdc          (project guardrails — alwaysApply)
│   │   └── 10-security.mdc      (sensitive paths — globs)
│   └── commands/
│       └── check-audit.md       (audit log integrity check)
├── infra/
│   ├── docker-compose.yml       (postgres_binalyze, qdrant_binalyze, nocodb_binalyze, grafana_binalyze + app-net + Traefik labels)
│   ├── .env.example             (variable template; real `.env` is gitignored)
│   └── postgres/
│       └── init-databases.sql   (creates binalyze_audit on first Postgres init; NocoDB DB from POSTGRES_DB)
├── docs/
│   ├── COMPLIANCE.md            (GDPR posture, retention, hold)
│   ├── SECURITY.md              (threat model, OWASP LLM Top 10)
│   ├── SECURITY_INCIDENTS.md    (forensic security log — dated entries)
│   ├── PRODUCTION_CHECKLIST.md  (full enterprise validation path)
│   ├── REVIEW_GUIDE.md          (3 reviewer paths, prepared Q&A)
│   └── AUTOMATED_VALIDATION.md  (realistic SMB validation stack)
├── .gitignore                   (extended with security patterns)
├── BUILD_LOG.md                 (this file)
├── DECISIONS.md                 (16 ADRs, architectural record — incl. ADR-016 GCP pivot)
├── LICENSE                      (MIT, untouched)
└── README.md                    (forensic-grade demo positioning)
```

`.devcontainer/` removed via `git rm` in foundation commit.

`.cursor/mcp.json` exists locally but is gitignored (correctly excluded from public repo).

---

## Files NOT Yet Created (Phase 3+)

```
infra/postgres/
├── init.sql                     (audit_log schema, triggers, retention — Phase 3b-G on Cloud SQL; v0 Hostinger optional)
└── seed-data.sql                (legal_hold_subjects empty, etc.)

cloud-run/ (or equivalent service layout)
└── (Slack webhook + retrieval orchestration — Phase 3d-G)

n8n-workflows/
└── knowledge-bot.json           (optional v0 only; primary path is Cloud Run per ADR-016)

knowledge-base/
├── people-ops/
│   ├── parental-leave.md        ([ILLUSTRATIVE] stub)
│   ├── expenses.md              ([ILLUSTRATIVE] stub)
│   ├── ir35-stance.md           ([ILLUSTRATIVE] stub)
│   ├── pen-test-sop.md          ([ILLUSTRATIVE] stub)
│   └── onboarding.md            ([ILLUSTRATIVE] stub)
└── ingestion/
    └── ingest.py                (GCS upload + RAG Engine corpus wiring — Phase 3c-G)

prompts/
└── system.md                    (system prompt with grounding rules; model via Vertex)

scripts/
├── retention-deletion.sql       (nightly cleanup — Cloud SQL / scheduler)
└── reset-bot-state.sh           (recovery script)
```

---

## Phase Plan

| Phase | Status | Estimated time |
|-------|--------|----------------|
| Audit | ✅ Complete | (was 25 min) |
| Foundation (rules, decisions, docs) | ✅ Complete | (was ~3 hours) |
| MCP sanity test | ✅ Complete (2026-05-02; incl. config drift + PATH fix) | 5 min |
| Phase 3a: Hostinger Docker compose (Postgres + Qdrant + NocoDB + Grafana) | ✅ Complete (v0 prototyping; superseded by GCP path — ADR-016) | 45 min |
| Phase 3a-G: GCP project setup (billing, APIs, org policy sanity) | ⏳ Next | ~60 min |
| Phase 3b-G: Cloud SQL audit log schema with triggers | ⏳ Phase 3-G | ~45 min |
| Phase 3c-G: Cloud Storage + Vertex AI RAG Engine corpus | ⏳ Phase 3-G | ~60 min |
| Phase 3d-G: Cloud Run service — Slack webhook + RAG retrieval + generation | ⏳ Phase 3-G | ~90 min |
| Phase 3e-G: Slack app config with Bolt SDK signature verification | ⏳ Phase 3-G | ~30 min |
| Phase 3f-G: Looker Studio dashboard + reviewer interface | ⏳ Phase 3-G | ~60 min |
| Phase 4: End-to-end testing + refusal demo | ⏳ Final | ~45 min |
| Phase 5: Rehearsal (run demo twice on screen-share) | ⏳ Final | ~30 min |

**Total Phase 3+ remaining (GCP path):** ~**6.5 hours** of focused work.

---

## Next 3-5 Concrete Steps

1. **Phase 3a-G — GCP project setup** — enable APIs (Run, Vertex AI, Cloud SQL, Storage, IAM, Logging), billing account, least-privilege starter IAM roles
2. **Phase 3b-G — Cloud SQL** — create Postgres instance; apply `audit_log` init SQL (append-only triggers, hold tables); verify with `check-audit` flow
3. **Phase 3c-G — RAG corpus** — GCS bucket for docs; Vertex AI RAG Engine corpus + ingestion pipeline
4. **Phase 3d-G — Cloud Run** — Slack Bolt webhook, retrieval callout, generation, **every path writes `audit_log`**
5. **Re-open MCP panel after host changes** — if global MCP config changes, confirm four servers still green (operational hygiene)

---

## Open Questions (Carry Forward)

| Question | Owner | Resolution path |
|----------|-------|-----------------|
| Does n8n-mcp load in Cursor on remote-SSH? | Resolved 2026-05-02 | Requires `PATH` override in `mcp.json` for `npx`; documented in `00-base.mdc` and state recovery section above |
| Will n8n version on VPS support n8n-mcp's create_workflow tool? | Optional verify | Not blocking; we build workflow in n8n UI directly anyway |
| Vertex / Gemini vs Claude (Model Garden) — default model for demo? | User to confirm | ADR-016: Gemini 3 default; Claude optional via Vertex |
| API keys / WIF — where stored for Cloud Run? | User to confirm | GCP Secret Manager + workload identity recommended before Phase 3d-G |

---

## Resume Instructions for New Chat Session

If resuming this project in a new conversation, paste this paragraph at the top:

> "Resuming work on the Forensic-Grade Knowledge Bot for People Operations (interview demo for DFIR vendor, Wed 2026-05-06 15:30 UK). Architecture LOCKED — see DECISIONS.md **ADR-016** (GCP pivot from 2026-05-02). Primary stack: **Cloud Run + Vertex AI RAG Engine + Cloud SQL (Postgres, append-only audit) + Cloud Storage + Slack (Bolt SDK) + Looker/BigQuery**; **Gemini 3 via Vertex** default, Claude via Model Garden optional. Hostinger **Phase 3a** containers remain as **v0 fallback** (`infra/`). Foundation + MCP verification complete. **Next: Phase 3a-G** (GCP project setup). Read BUILD_LOG.md and docs/SECURITY_INCIDENTS.md if touching MCP or credentials. Apply Bulletproof Prompt rules from prior session."

Then point me at the repo + BUILD_LOG.md and we re-anchor in 2 minutes.

---

## Update Discipline

Update this file at phase boundaries (not every commit). Specifically:
- After Phase 3a, 3b, 3c, 3d, 3e, 3f each lands
- After any architectural decision change
- Before stopping for the day

Each update should: refresh "Current Status," tick off completed phases, add to "Files Committed," update "Next 3-5 Concrete Steps" (GCP **3a-G … 3f-G** as applicable).

This file IS a demo artifact. The interview's hiring manager or an independent reviewer skimming the repo can read this in 5 minutes and understand the build's progression. Keep it factual and current.
