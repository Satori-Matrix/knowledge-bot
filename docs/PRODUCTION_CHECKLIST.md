# Production Deployment Checklist

This document specifies the **v1 production deployment gates** for the Forensic-Grade Knowledge Bot for People Operations on **GCP** (primary architecture per **ADR-016**). It is **not** framed as a future “migration from Hostinger”; GCP is the build path. A **v0 Hostinger** stack under `infra/` may remain as prototyping fallback but is **out of scope** for this checklist.

The interview demo is appropriate for limited internal use with documented limitations. **Production on GCP** requires the items below.

Cost estimates assume UK/EU 2026 consulting rates (£600-£1,500/day depending on specialism). Actuals depend on team and engagement scope.

---

## 1. Infrastructure Hardening

| Item | Current (demo / early GCP) | Required (production GCP) | Effort |
|------|----------------------------|----------------------------|--------|
| Hosting | Single-region Cloud Run + Cloud SQL (dev sizing) | HA where offered: multi-zone Cloud SQL, min instances / regional Run, pooling | 2-3 days |
| TLS | Managed Google front ends + automatic certs | Certificate monitoring; HTTPS-only org policies | 0.5 day |
| DDoS / edge | Default Google edge | **Cloud Armor** in front of public ingress as traffic grows | 1 day |
| Backups | Default Cloud SQL backups / PITR | **Restore drills**; GCS versioning for corpus; documented RPO/RTO | 1-2 days |
| OS / runtime | Managed (Run) + managed SQL | Org policy bundles; **VPC-SC** if residency demands | 1-2 days |
| Patch management | Pin image digests in dev | **Artifact Analysis** in CI; routine base-image refresh | 0.5-1 day |
| Monitoring | Looker + Cloud Logging | Error Reporting, **BQ log sinks**, operational dashboards | 2-3 days |
| Alerting | Minimal | Policies: trigger tampering, RBAC spikes, refusal anomalies, replication lag | 1 day |

**Total infra hardening:** ~9-12 days of focused work.

---

## 2. Secret Management

| Item | Current (demo) | Required (production) |
|------|----------------|----------------------|
| Storage | Local `.env` / ad-hoc env vars | **GCP Secret Manager** + **Workload Identity Federation** (no long-lived JSON keys in repos) |
| Rotation | Manual | Documented schedule (Slack tokens 90 days, API keys 180 days, DB passwords 90 days) |
| Access audit | None | All secret reads logged to SIEM |
| Pre-commit checks | `.gitignore` only | Add `gitleaks` or `trufflehog` pre-commit hook |

**Effort:** 2-3 days for full Secret Manager migration; 0.5 day for pre-commit hook.

---

## 3. Authentication & Authorisation

### Slack ingress
- Demo: Slack Bolt SDK signature verification on Cloud Run (sufficient baseline)
- Production: add per-user rate limiting and **Cloud Armor** / WAF rules as traffic grows (~0.5 day)

### Reviewer / ops UI (Looker, BigQuery, optional Cloud Run UI)
- Demo: Looker Studio on BigQuery views; IAM-controlled datasets
- Production: **SSO** (Google Workspace / Cloud Identity) for analysts; row-level views per role; optional custom Cloud Run reviewer app behind IAP. Effort: ~2-5 days depending on path.

### Database access (Cloud SQL)
- Demo: single service account + app user with least privilege
- Production: **IAM database auth** or rotated passwords in Secret Manager; separate DB roles for writer vs analyst; optional **RLS** on `audit_log` for finer separation. Effort: ~3 days.

### RBAC
- Demo: hardcoded block-list in **Secret Manager** / Run env
- Production: Slack User Group lookup with role mapping (`employee`, `people_team`, `compliance_team`, `admin`); short-lived cache; per-role BigQuery row access policies or Looker views. Effort: ~5-8 days.

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

The demo may export CSV from **BigQuery** or Looker without cryptographic guarantees. Production-grade forensic export requires a wrapper.

### Functional requirements

- Triggered by **Cloud Scheduler** + Cloud Run job, **Pub/Sub**, or analyst-initiated workflow (not committed secrets)
- Wraps the CSV with:
  - SHA-256 hash of the CSV file
  - JSON manifest including: filter used, row count, exporter Slack ID, exporter role, export tool version, timestamp, parent hash (chained to previous export)
  - Optional: PGP signature on manifest using investigation-team key
  - Optional: EDRM XML format alongside CSV for direct eDiscovery production
  - Optional: Concordance .DAT load file for compatibility with Relativity et al
- Stores export package in write-once storage (S3 with object lock, GCS retention bucket, or equivalent)
- Logs the export event to a separate `export_audit` table (chain of custody on the chain of custody)

### Implementation

Python 3.12 + Cloud Run (HTTP or scheduled) + standard libraries (hashlib, json, gnupg). Artifact in **GCS** with retention / Object Versioning.

**Effort: 2-3 days for v2 minimum (CSV + hash + manifest + signature). Add 1-2 days for EDRM XML. Add 1 day for Concordance load files.**

**Cost equivalent: £1,200-£4,500 in consulting time.**

---

## 6. External Security Review

Recommended before production rollout. Three review tracks:

### Code + architecture review
- Vendors: NCC Group, Trail of Bits, IOActive, Nettitude
- Scope: Cloud Run handlers, Vertex / RAG call paths, **Cloud SQL** schema and triggers, prompt construction, audit-log integrity, RBAC logic
- Effort: 2-3 consultant-days
- Cost: **£3,000-£6,000**

### LLM-specific review
- Vendors: HiddenLayer, Lakera, Robust Intelligence
- Scope: prompt injection robustness, output handling, refusal logic, system-prompt leakage
- Effort: 1-2 consultant-days
- Cost: **£2,000-£4,000**

### Web pen-test
- Scope: **Cloud Run** public URL(s), **Slack** endpoint, **IAP**-protected UIs (if any), IAM-exposed surfaces — not internal-only GCP APIs
- Effort: 1-3 consultant-days
- Cost: **£1,500-£4,500**

**Total external review: £6,500-£14,500 for a focused engagement.**

For SMB-scale internal tools, see `docs/AUTOMATED_VALIDATION.md` for a realistic alternative path using free AI-powered code review and static analysis tooling. External review at this cost level is appropriate for customer-facing systems, regulatory attestations, or compliance certification — not typically required for internal Q&A bots.

Bug bounty (HackerOne, Bugcrowd, Intigriti) as ongoing supplement: £500-£5,000 per valid finding once enabled. Customer-facing systems only.

---

## 7. Performance & Scale

The demo deployment is bounded by:
- **Cloud Run** concurrency and CPU allocation
- **Cloud SQL** connections and vCPU / memory tier
- **Vertex AI RAG Engine** quotas and corpus size

### Scale gates

| Trigger | Action | Effort |
|---------|--------|--------|
| Sustained >5 queries/sec from Slack | Raise Run concurrency; add min instances; cache hot retrieval | 1-2 days |
| Cloud SQL CPU >70% | Scale tier; add **read replica** for analyst queries | 1 day |
| Corpus / query cost growth | Tune RAG chunking; evaluate caching; review **Model Garden** routing | 2-3 days |
| Knowledge base >100k chunks | RAG Engine tuning; optional hybrid strategies per Google guidance | 3-5 days |

**Pre-optimise nothing. Measure first.**

---

## 8. Observability

### Demo
- Looker Studio on BigQuery views (queries, refusals, metadata)
- Cloud Logging for Run request logs

### Production additions
| Item | Tool | Effort | Cost |
|------|------|--------|------|
| Application errors | **Error Reporting** + optional Sentry | 0.5 day setup | Varies |
| Structured log shipping | **Log Router → BigQuery** sink + SIEM export | 1-2 days setup | £100-£500/month typical low-volume |
| LLM monitoring | Vertex evaluation + Promptfoo CI | 1 day setup | Usage-based |
| Custom alerts | Cloud Monitoring alerting policies + PagerDuty/Opsgenie | 1 day setup | £15-30/user/month typical |

**Monthly running cost:** highly variable; demo scale often **£0-50/month** plus cloud spend.

---

## 9. Documentation Gaps to Close Before Production

These docs exist but need expansion for production:

| Doc | Current state | Production state |
|-----|---------------|------------------|
| `DECISIONS.md` | ADRs through ADR-016 + historical superseded entries | Add ADRs for org-specific production choices |
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
| Observability (production rollout) | 3.5-4.5 | £2,100-£6,750 |
| Documentation expansion | 3-5 | £1,800-£7,500 |

**Total production readiness:** approximately 40-60 person-days of focused engineering plus £10-25k in external services for high-stakes deployments. SMB-scale internal deployment costs significantly less when using the automated validation path documented in `docs/AUTOMATED_VALIDATION.md`.

This is a realistic upper-bound budget. Larger organisations or higher-stakes systems would multiply these. Internal-only SMB deployment lower-bound is significantly less.

---

## 11. What This Checklist Is For

This checklist exists to:

1. Make explicit what the **demo / early GCP** build does NOT yet include
2. Give the deploying organisation a budget for **production readiness on GCP**
3. Demonstrate that limitations are known, documented, and addressable without a separate “v2 migration” from a toy stack
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
