# Compliance & Privacy Posture

This document specifies the compliance posture of the Forensic-Grade Knowledge Bot for People Operations. It is paired with `DECISIONS.md` (architecture) and `docs/SECURITY.md` (threat model).

This is design documentation. Production deployment requires the gates listed in `docs/PRODUCTION_CHECKLIST.md`, including DPO ratification of the assertions made here.

---

## 1. Lawful Basis (GDPR Article 6)

The bot processes personal data of employees: Slack `user_id`, query text, query timestamp, generated response, retrieval metadata.

**Lawful basis: Article 6(1)(f) — Legitimate Interest.**

The legitimate interest:
- Reduces repetitive support burden on the People team
- Provides employees self-service access to policy information
- Generates audit data supporting compliance obligations

The processing is proportionate to the stated purpose. Less-invasive alternatives (e.g. unstructured Slack threads with humans) are operationally inferior and produce no audit trail.

**Required for production:**
- LIA (Legitimate Interest Assessment) drafted by the DPO, documenting the three-part test (purpose, necessity, balancing test)
- Privacy notice update informing employees of bot processing
- Records of Processing (Art. 30) entry added to organisational ROPA

---

## 2. Data Subject Rights (GDPR Articles 15-22)

The data subject is the employee whose query is being processed.

| Right | Article | Implementation |
|-------|---------|----------------|
| Access | Art. 15 | SQL/NocoDB query by `slack_user_id` returns all rows; deliver within 30 days |
| Rectification | Art. 16 | Audit log is append-only; corrections appended as new rows referencing the original |
| Erasure | Art. 17 | Pseudonymisation in place: `slack_user_id` hashed irreversibly. Audit history preserved, PII unrecoverable |
| Restriction | Art. 18 | `processing_restricted` flag added per-row when applicable; routine processing skips |
| Portability | Art. 20 | CSV export filtered by `slack_user_id` provides structured machine-readable output |
| Objection | Art. 21 | Subject objects in writing; bot processing of their queries ceases on `slack_user_id` add to opt-out list |

### Right to Erasure — Detailed

When a data subject requests erasure under Art. 17:

1. Verify identity of requester
2. Check if subject is under active litigation hold (`legal_hold_subjects` table)
3. **If under hold:** invoke Art. 17(3)(e) exemption. Subject is informed in writing that their request is noted but pending until hold release. Document the response.
4. **If not under hold:** run pseudonymisation script. Replace `slack_user_id` with SHA-256 hash + a per-user salt (irreversible). Replace `query_text` with `[ERASED]` or remove entirely (decision per legal review). Audit row's `created_at`, `retention_until`, retrieval metadata preserved.
5. Log the erasure event in `erasure_audit` table (separate audit chain).

---

## 3. Retention Policy

| Row type | Default retention | After litigation hold |
|----------|-------------------|----------------------|
| Successful query (answered) | 90 days from `created_at` | Indefinite until release; deletion decision separate |
| Refusal (low-confidence, RBAC-blocked, etc.) | 7 years from `created_at` | Indefinite until release |
| Held data (any type) | Indefinite | Held until `released_at` set; post-release retention is a separate decision |

**Routine deletion script (runs nightly):**
```
DELETE FROM audit_log
WHERE created_at < NOW() - retention_for_this_row_type
  AND legal_hold = FALSE
  AND processing_restricted = FALSE;
```

The script logs its activity to `retention_audit` table: rows considered, rows deleted, runtime.

**Schema field `retention_until`** is computed at insert time:
- Refusals: `created_at + INTERVAL '7 years'`
- Successful queries: `created_at + INTERVAL '90 days'`
- Updateable to extended dates by compliance team via NocoDB (audited change)

---

## 4. Litigation Hold Procedure

### Triggering a Hold

Authorised personnel (`compliance_team` or `admin` role) initiates a hold:

1. Identify subject (Slack `user_id`) and the legal basis (e.g. case number, regulator request)
2. Add row to `legal_hold_subjects` table:
   - `slack_user_id`
   - `reason` (textual; references case ID or regulatory matter)
   - `set_by` (who authorised)
   - `set_at` (timestamp)
   - `released_at` (NULL until released)
3. Mark all existing `audit_log` rows for that subject as `legal_hold = TRUE` via NocoDB or SQL
4. The action is logged to `hold_audit` table

### Effects of Active Hold

- Future queries from the held subject auto-tagged `legal_hold = TRUE` on insert (n8n workflow checks `legal_hold_subjects` before each audit write)
- Routine retention deletion skips rows where `legal_hold = TRUE`
- Erasure requests for the subject denied under Art. 17(3)(e); subject is informed of the deferral
- All `legal_hold_subjects` changes are themselves audited

### Releasing a Hold

1. Set `released_at` timestamp on `legal_hold_subjects` row (do not delete the row — record persists)
2. Held audit_log rows remain tagged `legal_hold = TRUE` (post-release deletion is a separate decision per legal review)
3. New queries from the subject return to default retention rules

### Export — v1 (manual, CSV)

Reviewer filters NocoDB to `legal_hold = TRUE` for the subject + date range. One-click CSV export. The CSV is sent through whatever channel the legal team uses for evidence transfer.

**v1 limitations:** export is not cryptographically hashed, signed, or in an eDiscovery load format. Acceptable for internal hold management; insufficient for production-to-opposing-counsel.

### Export — v2 (forensic-grade wrapper)

A separate Python script wraps the CSV with:
- SHA-256 hash of the export file
- JSON manifest: filter used, row count, timestamp, exporter identity, export tool version
- Optional: PGP signature on the manifest using a designated investigation key
- Optional: EDRM XML or Concordance load file format

The wrapper is documented in `PRODUCTION_CHECKLIST.md`. Estimated 2-3 days of focused work.

---

## 5. Pseudonymisation Strategy

`slack_user_id` is the only direct identifier in the audit log.

**For routine processing:** stored as-is (the value is internal to the Slack workspace and not personally identifying outside it without the workspace context).

**For erasure (Art. 17):** the `slack_user_id` value is replaced in-place with a SHA-256 hash combining the original ID with a per-user random salt. The salt is destroyed after replacement, making the operation irreversible. Audit row history preserved.

**No other PII is stored:** no email, no display name, no profile data. The bot does not need them; not storing them is data minimisation by design.

---

## 6. Records of Processing (Article 30)

A summary fit for the organisational ROPA register:

- **Purpose:** Internal People-team self-service Q&A
- **Categories of data subjects:** Employees of the deploying organisation
- **Categories of personal data:** Slack `user_id`, query text, query timestamp, generated response (which may incidentally reference the subject), retrieval metadata
- **Categories of recipients:** Internal People-team operators (via Grafana), compliance team (via NocoDB), Anthropic (LLM API processor), the deploying organisation's DPO and legal team on request
- **Transfers outside EU/UK:** Anthropic's standard tier processes in US (verify current Anthropic data residency commitments). EU residency available on Anthropic enterprise tier — flagged in `PRODUCTION_CHECKLIST.md` as a v2 commercial option.
- **Retention:** 90 days for successful queries; 7 years for refusals; indefinite for litigation-held data
- **Security measures:** TLS in transit; append-only triggers at the database; pseudonymisation on erasure; access controls (Slack signature verification, RBAC, NocoDB authentication)

---

## 7. Cross-Border Data Transfers

**Default tier (v1):** Claude API requests transit to Anthropic's US infrastructure. The legal mechanism is Anthropic's published Standard Contractual Clauses + adequacy considerations.

**v2 production option:** Anthropic enterprise tier with EU data residency, applicable when the deploying organisation requires EU-only processing.

**TLS in transit:** all external API calls and Slack webhook traffic use TLS 1.2+ (Traefik enforces). Internal Docker network traffic does not use TLS (acceptable for trust-boundary-internal traffic; documented).

---

## 8. Privacy Notice (Template)

For inclusion in the deploying organisation's employee privacy notice or Slack workspace policy:

```
This workspace deploys an internal Q&A bot ("Knowledge Bot") to assist with
People-team and operational questions. When you use the bot:

- Your Slack User ID, your question text, the bot's response, and the
  timestamp are recorded in an internal audit log.
- This data is processed under the lawful basis of Legitimate Interest
  (GDPR Article 6(1)(f)) for the purposes of operational support and
  compliance evidence.
- Successful query records are retained for 90 days.
- Refusal records (where the bot declined to answer) are retained for
  7 years as compliance evidence.
- Data may be retained beyond default periods under legal preservation
  orders.
- You may request access to or erasure of your data by contacting the
  Data Protection Officer.
- Erasure requests during active legal preservation are noted but
  deferred until the preservation order is lifted.

The bot does not store your name, email, or other profile data.
```

---

## 9. DPO Sign-Off Checklist (for production deployment)

Items to verify with the DPO before production:

- [ ] LIA documented and approved
- [ ] Privacy notice updated and circulated to employees
- [ ] ROPA entry added to organisational register
- [ ] DPIA conducted (the bot is likely not high-risk per GDPR Art. 35, but DPIA-lite documents the assessment)
- [ ] Cross-border transfer mechanism confirmed (SCCs current, adequacy decisions still valid)
- [ ] Erasure procedure tested end-to-end on a synthetic test subject
- [ ] Subject Access Request procedure tested with realistic 30-day timeline
- [ ] Litigation hold procedure walked through with internal legal counsel
- [ ] Retention deletion script tested in dry-run mode with sample data

---

## 10. Open Compliance Questions

These require organisational answers, not technical ones:

- Specific retention extensions for regulated industries (SEC, FINRA) if applicable
- Cross-border data transfer adequacy for non-EU data subjects in deploying organisation
- Coordination with existing eDiscovery hold procedures if the organisation has them
- Integration with the organisation's existing DPIA register

These are flagged in `PRODUCTION_CHECKLIST.md` as part of the production readiness gate.
