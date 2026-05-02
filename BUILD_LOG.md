# Build Log

This document tracks the build state of the Knowledge Bot project. It is updated as the project progresses and serves as the operational source of truth for "where we are" between work sessions.

For architectural decisions, see `DECISIONS.md`. For compliance, see `docs/COMPLIANCE.md`. This file is the operational counterpart — what's done, what's next, what's blocked.

---

## Current Status

**Phase:** Foundation complete. MCP configuration recovered and verified 2026-05-02. **Phase 3a** (Docker compose for Postgres + Qdrant + NocoDB + Grafana) is next.

**Last update:** 2026-05-02 (state recovery + MCP verification)

**Demo target:** Wednesday 2026-05-06, 15:30 UK

**Time budget remaining:** ~3-4 hours of focused build before rehearsal

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
- Will join existing `app-net` network for internal addressing

---

## Architecture (Locked, See DECISIONS.md for ADRs)

**v1 (this build):**
- n8n (existing) for workflow orchestration
- Postgres (new container `postgres_binalyze`) for audit log with append-only triggers
- Qdrant (new container `qdrant_binalyze`) for vector retrieval
- NocoDB (new container `nocodb_binalyze`) for reviewer interface
- Grafana (new container `grafana_binalyze`) for operations dashboard
- Slack as ingress + egress
- Claude API for generation

**Architectural option chosen:** Option B — adopt existing n8n + Traefik, dedicated Postgres + Qdrant + NocoDB + Grafana for the bot.

**Rejected alternatives** (full reasoning in DECISIONS.md):
- GCP Cloud Run + Vertex AI — exceeds 6h build budget; documented as v2
- Microsoft Copilot Studio — wrong stack
- Adopt-everything (shared Postgres) — insufficient data isolation
- Cloudflare Tunnel for ingress — Traefik already provides; deferred to v2

---

## Key Decisions Made

(Cross-reference DECISIONS.md for the formal record.)

- **Retention:** 90 days for queries, 7 years for refusals, indefinite under litigation hold
- **GDPR lawful basis:** Article 6(1)(f) Legitimate Interest + Art. 17(3)(e) for legal proceedings
- **RBAC v1:** hardcoded block-list in n8n credentials
- **RBAC v2 design:** `employee` / `people_team` / `compliance_team` / `admin` mapped to Slack User Groups
- **Litigation hold:** retroactive (legal_hold column) + forward (legal_hold_subjects table)
- **Reviewer interface:** NocoDB for case work + Grafana for operations
- **Forensic export:** v1 ships CSV via NocoDB; v2 wrapper (hash + manifest + signature) documented
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
- Postgres MCP — to be added after Postgres for the bot deploys (Phase 3+), read-only mode when introduced

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
├── docs/
│   ├── COMPLIANCE.md            (GDPR posture, retention, hold)
│   ├── SECURITY.md              (threat model, OWASP LLM Top 10)
│   ├── SECURITY_INCIDENTS.md    (forensic security log — dated entries)
│   ├── PRODUCTION_CHECKLIST.md  (full enterprise validation path)
│   ├── REVIEW_GUIDE.md          (3 reviewer paths, prepared Q&A)
│   └── AUTOMATED_VALIDATION.md  (realistic SMB validation stack)
├── .gitignore                   (extended with security patterns)
├── BUILD_LOG.md                 (this file)
├── DECISIONS.md                 (14 ADRs, architectural record)
├── LICENSE                      (MIT, untouched)
└── README.md                    (forensic-grade demo positioning)
```

`.devcontainer/` removed via `git rm` in foundation commit.

`.cursor/mcp.json` exists locally but is gitignored (correctly excluded from public repo).

---

## Files NOT Yet Created (Phase 3+)

```
infra/
├── docker-compose.yml           (Postgres + Qdrant + NocoDB + Grafana)
└── postgres/
    ├── init.sql                 (audit_log schema, triggers, retention)
    └── seed-data.sql            (legal_hold_subjects empty, etc.)

n8n-workflows/
└── knowledge-bot.json           (workflow export)

knowledge-base/
├── people-ops/
│   ├── parental-leave.md        ([ILLUSTRATIVE] stub)
│   ├── expenses.md              ([ILLUSTRATIVE] stub)
│   ├── ir35-stance.md           ([ILLUSTRATIVE] stub)
│   ├── pen-test-sop.md          ([ILLUSTRATIVE] stub)
│   └── onboarding.md            ([ILLUSTRATIVE] stub)
└── ingestion/
    └── ingest.py                (chunk + embed + push to Qdrant)

prompts/
└── system.md                    (Claude system prompt with grounding rules)

scripts/
├── retention-deletion.sql       (nightly cleanup)
└── reset-bot-state.sh           (recovery script)
```

---

## Phase Plan

| Phase | Status | Estimated time |
|-------|--------|----------------|
| Audit | ✅ Complete | (was 25 min) |
| Foundation (rules, decisions, docs) | ✅ Complete | (was ~3 hours) |
| MCP sanity test | ✅ Complete (2026-05-02; incl. config drift + PATH fix) | 5 min |
| Phase 3a: Docker compose for Postgres + Qdrant + NocoDB + Grafana | ⏳ Next | 45 min |
| Phase 3b: Postgres init SQL with triggers + retention + hold tables | ⏳ Phase 3 | 45 min |
| Phase 3c: Knowledge base content + ingestion script | ⏳ Phase 3 | 45 min |
| Phase 3d: n8n workflow (Slack → block-list → retrieval → Claude → audit → response) | ⏳ Phase 3 | 75 min |
| Phase 3e: Slack app config + signature verification | ⏳ Phase 3 | 30 min |
| Phase 3f: Grafana dashboard + NocoDB review setup | ⏳ Phase 3 | 30 min |
| Phase 4: End-to-end testing, edge cases, refusal demo | ⏳ Final | 45 min |
| Phase 5: Rehearsal (run demo twice on screen-share) | ⏳ Final | 30 min |

**Total Phase 3+ remaining:** ~5.5 hours of focused work.

---

## Next 3-5 Concrete Steps

1. **Write Phase 3a Docker compose** — Postgres + Qdrant + NocoDB + Grafana joining `app-net`
2. **Stand up containers** — verify all four start cleanly, network reachability between them
3. **Write Postgres init SQL** — 13-field audit_log schema, append-only triggers, retention column, legal_hold tables, hold_audit table
4. **Verify schema** — run check-audit command against empty schema; confirm structure
5. **Re-open MCP panel after host changes** — if global MCP config changes, confirm four servers still green (operational hygiene)

---

## Open Questions (Carry Forward)

| Question | Owner | Resolution path |
|----------|-------|-----------------|
| Does n8n-mcp load in Cursor on remote-SSH? | Resolved 2026-05-02 | Requires `PATH` override in `mcp.json` for `npx`; documented in `00-base.mdc` and state recovery section above |
| Will n8n version on VPS support n8n-mcp's create_workflow tool? | Optional verify | Not blocking; we build workflow in n8n UI directly anyway |
| Anthropic API key — do we have one, where is it stored? | User to confirm | Bitwarden vault entry needed before Phase 3d |
| Claude model choice for the bot — Sonnet 4 or Opus 4? | User decision | Sonnet 4 is the right default; Opus only if benchmarking shows need |

---

## Resume Instructions for New Chat Session

If resuming this project in a new conversation, paste this paragraph at the top:

> "Resuming work on the Forensic-Grade Knowledge Bot for People Operations (interview demo for DFIR vendor, Wed 2026-05-06 15:30 UK). Architecture LOCKED — see DECISIONS.md. Stack: n8n on Hostinger VPS + Postgres (audit log, append-only triggers) + Qdrant (vectors) + NocoDB (reviewer UI) + Grafana (ops dashboard) + Slack + Claude API. Foundation + MCP verification complete as of 2026-05-02 (four MCPs green: filesystem, sequential-thinking, context7 global; n8n-mcp project-scoped, documentation-only). Next: Phase 3a Docker compose. Read BUILD_LOG.md and docs/SECURITY_INCIDENTS.md if touching Cursor MCP or credentials. Apply Bulletproof Prompt rules from prior session."

Then point me at the repo + BUILD_LOG.md and we re-anchor in 2 minutes.

---

## Update Discipline

Update this file at phase boundaries (not every commit). Specifically:
- After Phase 3a, 3b, 3c, 3d, 3e, 3f each lands
- After any architectural decision change
- Before stopping for the day

Each update should: refresh "Current Status," tick off completed phases, add to "Files Committed," update "Next 3-5 Concrete Steps."

This file IS a demo artifact. Megan or a reviewer skimming the repo can read this in 5 minutes and understand the build's progression. Keep it factual and current.
