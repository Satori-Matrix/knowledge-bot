# Production Deployment Checklist

This document specifies what changes between the v1 demo and a production deployment of the Forensic-Grade Knowledge Bot for People Operations.

The demo (v1) is appropriate for interview purposes and limited internal use with documented limitations. Production deployment requires the items below.

Cost estimates assume UK/EU 2026 consulting rates (£600-£1,500/day depending on specialism). Actuals depend on team and engagement scope.

---

## 1. Infrastructure Hardening

| Item | Current (v1) | Required (production) | Effort |
|------|--------------|----------------------|--------|
| Hosting | Hostinger VPS, single instance | Cloud Run / Cloud SQL OR dedicated VPS with HA pair | 2-3 days |
| TLS | Let's Encrypt via Traefik | Same; add monitoring on cert expiry | 0.5 day |
| DDoS protection | None | Cloudflare Tunnel OR cloud WAF | 1 day |
| Backups | Manual snapshot of Docker volumes | Automated nightly Postgres + Qdrant snapshots, off-site retention | 1-2 days |
| OS hardening | Default Ubuntu 24.04 | Apply CIS Benchmark Level 1; fail2ban; auditd | 1 day |
| Patch management | Manual (47 updates pending at v1) | Automated unattended-upgrades; reboot windows scheduled | 0.5 day |
| Monitoring | Grafana + manual review | Add Sentry for app errors; structured logs to SIEM | 2-3 days |
| Alerting | None | Pager rotation for: audit log integrity failure, RBAC block spike, refusal rate anomaly | 1 day |

**Total infra hardening:** ~9-12 days of focused work.

---

## 2. Secret Management

| Item | Current (v1) | Required (production) |
|------|--------------|----------------------|
| Storage | `.env` files + n8n credential store | HashiCorp Vault, AWS Secrets Manager, or GCP Secret Manager |
| Rotation | Manual | Documented schedule (Slack tokens 90 days, API keys 180 days, DB passwords 90 days) |
| Access audit | None | All secret reads logged to SIEM |
| Pre-commit checks | `.gitignore` only | Add `gitleaks` or `trufflehog` pre-commit hook |

**Effort:** 2-3 days for full Secret Manager migration; 0.5 day for pre-commit hook.

---

## 3. Authentication & Authorisation

### Slack ingress
- v1: n8n native signature verification (sufficient)
- v2: same; add per-user rate limiting at the workflow level (~0.5 day)

### NocoDB
- v1: local NocoDB user accounts
- v2: SSO via Slack OAuth or organisation IdP (SAML/OIDC). NocoDB enterprise tier supports this. Effort: ~2 days.

### Database access
- v1: dedicated Postgres users per role (n8n_writer, nocodb_user, dba)
- v2: same; add credential rotation; consider Postgres row-level security for finer audit_log access control. Effort: ~3 days.

### RBAC
- v1: hardcoded block-list in n8n credentials
- v2: Slack User Group lookup with role mapping (`employee`, `people_team`, `compliance_team`, `admin`); 5-minute role cache; per-role NocoDB views. Effort: ~5-8 days.

---

## 4. Compliance Gates

Items that block production deployment until completed:

| Item | Owner | Estimated effort |
|------|-------|------------------|
| LIA (Legitimate Interest Assessment) drafted | DPO | 1-2 days |
| Privacy notice updated and circulated | DPO + Comms | 1 day |
| Records of Processing (Art. 30) entry added | DPO | 0.5 day |
| DPIA (or DPIA-lite documenting low-risk assessment) | DPO + Engineering | 1-2 days |
| Cross-border transfer mechanism confirmed | DPO + Legal | 1 day |
| Erasure procedure tested end-to-end | Engineering + DPO | 0.5 day |
| SAR procedure tested with 30-day timeline | Engineering + DPO | 0.5 day |
| Litigation hold procedure walked through | Engineering + Legal | 0.5 day |
| Retention deletion script tested in dry-run | Engineering | 0.5 day |

**Total compliance gates:** ~7-10 days, requires DPO availability.

---

## 5. Forensic Export — v2 Wrapper

The v1 demo exports CSV from NocoDB without cryptographic guarantees. Production-grade forensic export requires a wrapper.

### Functional requirements

- Triggered by NocoDB webhook (export button) or scheduled (nightly for active holds)
- Wraps the CSV with:
  - SHA-256 hash of the CSV file
  - JSON manifest including: filter used, row count, exporter Slack ID, exporter role, export tool version, timestamp, parent hash (chained to previous export)
  - Optional: PGP signature on manifest using investigation-team key
  - Optional: EDRM XML format alongside CSV for direct eDiscovery production
  - Optional: Concordance .DAT load file for compatibility with Relativity et al
- Stores export package in write-once storage (S3 with object lock, GCS retention bucket, or equivalent)
- Logs the export event to a separate `export_audit` table (chain of custody on the chain of custody)

### Implementation

Python 3.12 + small Flask listener for webhook + standard libraries (hashlib, json, gnupg). Deployed as a separate Docker container on `app-net`.

**Effort: 2-3 days for v2 minimum (CSV + hash + manifest + signature). Add 1-2 days for EDRM XML. Add 1 day for Concordance load files.**

**Cost equivalent: £1,200-£4,500 in consulting time.**

---

## 6. External Security Review

Recommended before production rollout. Three review tracks:

### Code + architecture review
- Vendors: NCC Group, Trail of Bits, IOActive, Nettitude
- Scope: n8n workflow logic, Postgres schema and triggers, prompt construction, audit-log integrity, RBAC logic
- Effort: 2-3 consultant-days
- Cost: **£3,000-£6,000**

### LLM-specific review
- Vendors: HiddenLayer, Lakera, Robust Intelligence
- Scope: prompt injection robustness, output handling, refusal logic, system-prompt leakage
- Effort: 1-2 consultant-days
- Cost: **£2,000-£4,000**

### Web pen-test
- Scope: Traefik public surface, NocoDB UI, Slack endpoint, exposed ports
- Effort: 1-3 consultant-days
- Cost: **£1,500-£4,500**

**Total external review: £6,500-£14,500 for a focused engagement.**

For SMB-scale internal tools, see `docs/AUTOMATED_VALIDATION.md` for a realistic alternative path using free AI-powered code review and static analysis tooling. External review at this cost level is appropriate for customer-facing systems, regulatory attestations, or compliance certification — not typically required for internal Q&A bots.

Bug bounty (HackerOne, Bugcrowd, Intigriti) as ongoing supplement: £500-£5,000 per valid finding once enabled. Customer-facing systems only.

---

## 7. Performance & Scale

The v1 single-instance deployment is bounded by:
- n8n single-process throughput (~10-20 queries/second peak)
- Postgres connections (20 by default, configurable)
- Qdrant memory footprint (depends on collection size)

### Scale gates

| Trigger | Action | Effort |
|---------|--------|--------|
| Sustained >5 queries/sec from Slack | Move n8n to Queue Mode (Redis + workers) | 1-2 days |
| Postgres CPU >70% | Add read replica for NocoDB queries | 1 day |
| Qdrant memory >80% | Move to dedicated host or managed service | 2-3 days |
| Knowledge base >100k chunks | Evaluate hybrid retrieval (BM25 + vector) | 3-5 days |

**Pre-optimise nothing. Measure first.**

---

## 8. Observability

### v1
- Grafana dashboard (queries, refusals, retrieval confidence)
- n8n execution logs (7-day retention by default)

### v2
| Item | Tool | Effort | Cost |
|------|------|--------|------|
| Application errors | Sentry | 0.5 day setup | £20-50/month |
| Structured log shipping | Vector / Fluent Bit → SIEM (Splunk, Datadog, Elastic) | 1-2 days setup | £100-£500/month for low-volume |
| LLM monitoring | Lakera Guard / Promptfoo CI | 1 day setup | £500-£2000/month for managed |
| Custom alerts | Grafana alerting OR PagerDuty | 1 day setup | £15-30/user/month |

**v2 monthly running cost: £600-£2,500 depending on volume and depth.**

---

## 9. Documentation Gaps to Close Before Production

These docs exist (v1) but need expansion for production:

| Doc | Current state | Production state |
|-----|---------------|------------------|
| `DECISIONS.md` | 12 ADRs covering v1 | Add ADRs for production decisions made during deployment |
| `docs/COMPLIANCE.md` | Design assumptions | Operational procedures with named responsible parties |
| `docs/SECURITY.md` | Threat model + OWASP mapping | Add: incident response runbook, on-call rotation, communication tree |
| New: `docs/RUNBOOK.md` | Does not exist | Operational procedures: deploys, rollbacks, common incidents, contact info |
| New: `docs/SLA.md` | Does not exist | Internal SLA: uptime target, response time, refusal rate threshold |

**Effort for production documentation:** ~3-5 days.

---

## 10. Total Production Readiness Estimate

Adding the items above:

| Category | Days | Cost equivalent (consulting) |
|----------|------|------------------------------|
| Infrastructure hardening | 9-12 | £5,400-£18,000 |
| Secret management migration | 2-3 | £1,200-£4,500 |
| Authentication / RBAC v2 | 8-13 | £4,800-£19,500 |
| Compliance gates | 7-10 | requires DPO time |
| Forensic export wrapper (v2) | 2-3 | £1,200-£4,500 |
| External security review | 5-8 consultant-days | £6,500-£14,500 (only if compliance attestation or customer-facing) |
| Observability v2 setup | 3.5-4.5 | £2,100-£6,750 |
| Documentation expansion | 3-5 | £1,800-£7,500 |

**Total production readiness:** approximately 40-60 person-days of focused engineering plus £10-25k in external services for high-stakes deployments. SMB-scale internal deployment costs significantly less when using the automated validation path documented in `docs/AUTOMATED_VALIDATION.md`.

This is a realistic upper-bound budget. Larger organisations or higher-stakes systems would multiply these. Internal-only SMB deployment lower-bound is significantly less.

---

## 11. What This Checklist Is For

This checklist exists to:

1. Make explicit what v1 does NOT include
2. Give the deploying organisation a budget for production readiness
3. Demonstrate that v1's limitations are known, documented, and addressable
4. Anchor conversations with security, compliance, and operations teams

It is not:
- A timeline (depends on team, priorities, and parallel work)
- A binding cost estimate (real engagements vary widely)
- A substitute for actual operational discipline (running the system reveals what no checklist anticipates)

---

## 12. Items Deliberately Out of Scope

The following are NOT in this checklist because they belong elsewhere:

- Anything requiring product decisions by the deploying organisation (e.g. "should this also support voice queries?")
- Anything outside the bot's blast radius (general VPS hardening beyond bot needs, organisation-wide IdP setup)
- Vendor selection criteria (DPO, security review firms, etc.) — that's procurement, not engineering
- Long-term roadmap features (v3 GraphRAG via LightRAG; multi-corpus support; etc.) — see `DECISIONS.md` "Decisions Not Yet Made"
