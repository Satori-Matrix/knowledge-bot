# Security Posture & Threat Model

This document specifies the security posture of the Forensic-Grade Knowledge Bot for People Operations. It is paired with `DECISIONS.md` (architecture), `docs/COMPLIANCE.md` (privacy), and `docs/REVIEW_GUIDE.md` (for an independent reviewer).

This is design documentation. Production deployment requires the gates listed in `docs/PRODUCTION_CHECKLIST.md`, including external security review.

---

## 1. Trust Boundaries

| Boundary | Trusted side | Untrusted side |
|----------|--------------|----------------|
| Slack ingress | Cloud Run + downstream | Slack request body, headers, claimed user identity |
| Database | The bot's own queries | Any direct DB connection from outside approved paths (IAM / VPC) |
| LLM API | Internal pre/post-processing | **Vertex AI** model responses (treat as untrusted text) |
| Looker / BigQuery | Internal analysts (IAM) | Anyone with over-broad IAM grants (mitigate with least privilege) |
| Cursor Remote-SSH | The developer machine | Anything else with SSH access to build hosts |

**GCP project boundary** is the trust core for production. External boundaries (Slack, Vertex, browser to Looker / IAP-protected UIs) use **TLS** and **Google-managed** fronts. **v0 Hostinger** `app-net` remains a separate, smaller trust island for prototyping only.

---

## 2. Threat Model — Top Threats

| # | Threat | Likelihood | Impact | Mitigation |
|---|--------|-----------|--------|------------|
| T1 | Slack request forgery (impersonation) | Medium | High | **Slack Bolt SDK** signature verification on **Cloud Run** |
| T2 | Prompt injection in user query | High | Medium | System prompt is fixed; retrieved chunks delimited; refusal-on-low-confidence; OWASP LLM01 awareness |
| T3 | Sensitive info leakage via LLM response | Medium | High | Refusal threshold; output sanitisation; audit log of every response; OWASP LLM06 |
| T4 | System prompt extraction | Medium | Medium | Don't echo system prompt; output filter on common extraction patterns; OWASP LLM07 |
| T5 | Audit log tampering | Low | Critical | Append-only triggers at DB layer; even DB owner cannot UPDATE/DELETE without explicit trigger disable (audited) |
| T6 | Credential exposure (env vars, MCP config) | Medium | High | **GCP Secret Manager** + **Workload Identity**; `.gitignore` blocks common secret patterns; pre-commit verification |
| T7 | RBAC bypass via forged internal calls | Medium | Medium | Slack signature verification; **IAM** on Cloud Run / Cloud SQL; `slack_user_id` validation against block-list/role-map |
| T8 | DoS via high query volume | Low | Medium | Slack rate limits; **Cloud Run** concurrency caps; **Cloud SQL** connection limits; optional **Cloud Armor** |
| T9 | Supply chain — compromised base images / dependencies | Low | High | **Artifact Registry** digests; **Artifact Analysis**; Dependabot / OSV; monitor GCP and language advisories |
| T10 | Lateral movement after cloud project compromise | Low | Critical | Org policies, **Cloud Audit Logs**, break-glass procedures, least-privilege IAM (out of full bot scope but required for production) |

---

## 3. OWASP LLM Top 10 (2025) — Mapping

| OWASP Category | Status | Mitigation |
|----------------|--------|------------|
| LLM01 — Prompt Injection | Addressed (v1) | System prompt is fixed; retrieved chunks delimited with explicit markers; refusal on low retrieval confidence prevents the LLM from "filling in" with attacker-influenced output |
| LLM02 — Insecure Output Handling | Addressed (v1) | Slack responses are plain text only; no raw HTML, no executable code echoed; URL allowlist for citation links |
| LLM03 — Training Data Poisoning | N/A | We use managed models via **Vertex AI**; no fine-tuning, no custom training data |
| LLM04 — Model Denial of Service | Partial until tuned | Rate limits at Slack + **Cloud Run**; Vertex quotas; per-user budget in PRODUCTION_CHECKLIST |
| LLM05 — Supply Chain | Partial (v2) | Specific versions pinned; CVE monitoring documented; SBOM generation flagged as v2 deliverable |
| LLM06 — Sensitive Information Disclosure | Addressed (design) | Refusal-on-low-confidence; system prompt does not contain secrets; model responses filtered for common PII patterns before sending to Slack |
| LLM07 — Insecure Plugin Design | N/A | No third-party plugins to the bot |
| LLM08 — Excessive Agency | Addressed (v1) | The bot reads and replies; it cannot send messages, modify documents, or take actions outside the audit-log write |
| LLM09 — Overreliance | Addressed by design | The bot ALWAYS cites its sources; refuses on low confidence; user knows the answer is generated, not authoritative |
| LLM10 — Model Theft | N/A | We don't host foundation weights; **Google** / model provider hosts |

---

## 4. Secrets Handling

**Where secrets live (GCP path):**
- Slack signing secret: **GCP Secret Manager**, mounted to Cloud Run or resolved at startup
- Slack bot token: Secret Manager
- Vertex / Google API credentials: **Workload Identity Federation** — no JSON keys in repo
- Cloud SQL credentials: IAM DB auth and/or Secret Manager–backed passwords
- Optional third-party keys (e.g. Anthropic via Model Garden): Secret Manager if not fully abstracted by Vertex

**v0 Hostinger (fallback only):** legacy `.env` + Docker compose for prototyping — **not** the primary architecture.

**Where secrets must NEVER appear:**
- Source code files
- Git commits (verified by `.gitignore` patterns; pre-commit hooks recommended for production)
- Cursor `.cursor/mcp.json` (covered by `.gitignore`)
- Slack messages, including bot replies
- Audit log entries
- Error messages or logs (log sinks must scrub credential-shaped strings)

**Production hardening:**
- **GCP Secret Manager** + **IAM** (replace any remaining `.env` patterns outside local dev)
- Rotate secrets on a documented schedule
- Use short-lived OAuth tokens for Slack where possible

---

## 5. Prompt Injection Defense

The bot is exposed to prompt injection via the `query` field from Slack and via retrieved knowledge base chunks.

**Defenses in v1:**
- Fixed system prompt (not constructed from user input)
- Retrieved chunks wrapped in explicit delimiters (`<retrieved_context>...</retrieved_context>`) within the prompt sent to the **Vertex** model
- Output filter: if the model response contains tokens suggesting prompt-injection success (e.g. instructions to ignore prior instructions, requests to reveal system prompt), the response is replaced with a refusal and the event audited
- Refusal-on-low-retrieval-confidence: if the retrieval doesn't strongly match a knowledge base chunk, the bot refuses rather than guessing — this denies the injection vector of crafting queries that retrieve attacker-controlled data

**Known limitations (v1):**
- A determined attacker who has write access to the knowledge base can plant injection content. Mitigation: knowledge base ingestion is curated; not user-modifiable in v1.
- LLM-vs-LLM evaluators (Promptfoo, Garak) are not run in v1. Documented as v2.

---

## 6. Data Flow Diagram

```
[Slack User]
    | (query, signed by Slack)
    v
[Google Front End / Cloud Run (TLS)]
    |
    v
[Cloud Run — Slack Bolt verifies signature]
    |
    v
[Handler: extract slack_user_id]
    |
    +--> [Cloud SQL: legal_hold_subjects lookup] --(boolean)-->
    |
    +--> [Cloud SQL: RBAC block-list / role map] --(allow/deny)-->
    |
    v (if allowed)
[Vertex AI RAG Engine — retrieve contexts]
    |
    v
[Vertex AI — generate (e.g. Gemini / Claude via Model Garden)]
    |
    v
[Cloud Run: output filter (PII scrub, prompt-leak check)]
    |
    +--> [Cloud SQL: audit_log INSERT]
    |
    v
[Slack: response to user (TLS)]
```

All data crossing trust boundaries is logged to `audit_log`. **Cloud Audit Logs** additionally record privileged GCP API actions — a second witness where applicable.

---

## 7. Authentication & Authorisation

**Slack ingress:**
- Slack signing secret verified per request (**Slack Bolt SDK** on Cloud Run)
- Replay attack: Slack timestamp within 5 minutes (Bolt / Slack recommended window)
- Bot token scoped to minimum (read messages where invoked, write responses, list user groups for v2 RBAC)

**RBAC v1:**
- Hardcoded block-list of `slack_user_id` values (Secret Manager / env on Cloud Run)
- Handler checks before retrieval; blocked request audited with `refusal_reason = 'rbac_blocked'`

**RBAC v2 (documented, not built):**
- Slack User Group membership cached and consulted per query
- Roles: `employee`, `people_team`, `compliance_team`, `admin`
- Per-role **BigQuery row access policies** or Looker views (compliance sees full text + retrieval; employee sees only own audit history)

**Analyst authentication (Looker / BigQuery):**
- Demo: Google accounts with least-privilege IAM
- Production: **Cloud Identity / Workspace SSO**, optional **IAP** in front of custom reviewer UIs

**Database access:**
- Cloud Run service account: **INSERT + SELECT** on `audit_log` (append-only triggers enforce writes)
- Analyst role: **SELECT** (and limited controlled updates for `legal_hold` only if not moved to dedicated procedure)
- DBA / break-glass: separate principal; actions visible in **Cloud Audit Logs**

---

## 8. Logging & Monitoring

**Demo logging:**
- **Cloud Logging** for Cloud Run requests and errors
- **Cloud SQL** audit logs / query insights for security-relevant DB events
- Looker / BigQuery access logs (IAM-aware)
- Audit log writes (the bot's primary product)

**Demo monitoring:**
- Looker Studio dashboards
- Manual review of refusal patterns

**Production monitoring (documented):**
- **Error Reporting** + optional Sentry
- **Log sinks to BigQuery** and export to SIEM
- Alerting on: spike in refusals, RBAC blocks above threshold, audit log integrity failure (e.g. trigger disable detected)

---

## 9. Incident Response (v1 Outline)

If a security incident is detected:

1. **Contain:** scale Cloud Run to zero or revoke IAM invoker / disable Slack routing. In-flight requests fail closed; Slack surfaces controlled error.
2. **Preserve:** **Cloud SQL** export / PITR snapshot; export **Cloud Logging**; preserve **Cloud Audit Logs** for the incident window.
3. **Investigate:** query audit_log for the affected timeframe. Identify scope (which queries, which users, what was returned).
4. **Notify:** internal security lead and DPO. If personal data breach with risk to data subjects, notify supervisory authority within 72 hours per GDPR Art. 33.
5. **Remediate:** fix the root cause. Document.
6. **Communicate:** affected data subjects per Art. 34 if required.

This procedure is a sketch. Production deployment requires a fuller IR plan with named responders, escalation paths, and tabletop exercises.

---

## 10. Validation Path

For an independent reviewer, see `docs/REVIEW_GUIDE.md` for 30-min, 2-hour, and full-review paths.

For external security review, recommended scopes:

- **Code review** (NCC Group, Trail of Bits, IOActive): Cloud Run services, Vertex / RAG integration, **Cloud SQL** schema and triggers, prompt construction, audit-log integrity guarantees. Estimated 2-3 days of consultant time.
- **LLM-specific review** (HiddenLayer, Lakera, Robust Intelligence): prompt injection surface, output handling, refusal robustness. Estimated 1-2 days.
- **Pen-test** of the public surface (Cloud Run URLs, Slack endpoint, IAP-protected UIs): standard web pen-test scope. Estimated 1-3 days.

Total external review budget: approximately £10,000-£20,000 for a focused engagement. Acceptable for production deployment of a security-vendor-internal tool.
