# Security Posture & Threat Model

This document specifies the security posture of the Forensic-Grade Knowledge Bot for People Operations. It is paired with `DECISIONS.md` (architecture), `docs/COMPLIANCE.md` (privacy), and `docs/REVIEW_GUIDE.md` (for an independent reviewer).

This is design documentation. Production deployment requires the gates listed in `docs/PRODUCTION_CHECKLIST.md`, including external security review.

---

## 1. Trust Boundaries

| Boundary | Trusted side | Untrusted side |
|----------|--------------|----------------|
| Slack ingress | n8n + downstream | Slack request body, headers, claimed user identity |
| Database | The bot's own queries | Any direct DB connection from outside the Docker network |
| LLM API | Internal pre/post-processing | Claude API responses (treat as untrusted text) |
| NocoDB UI | Internal operators | Anyone with valid auth (RBAC enforces row-level access) |
| Cursor Remote-SSH | The developer machine | Anything else with SSH access to the VPS |

Internal Docker network (`app-net`) is the trust core. External boundaries (Slack, Claude API, browser to NocoDB, browser to Grafana) are TLS-terminated by Traefik.

---

## 2. Threat Model — Top Threats

| # | Threat | Likelihood | Impact | Mitigation |
|---|--------|-----------|--------|------------|
| T1 | Slack request forgery (impersonation) | Medium | High | n8n native Slack signature verification (n8n >= 1.106.0) |
| T2 | Prompt injection in user query | High | Medium | System prompt is fixed; retrieved chunks delimited; refusal-on-low-confidence; OWASP LLM01 awareness |
| T3 | Sensitive info leakage via LLM response | Medium | High | Refusal threshold; output sanitisation; audit log of every response; OWASP LLM06 |
| T4 | System prompt extraction | Medium | Medium | Don't echo system prompt; output filter on common extraction patterns; OWASP LLM07 |
| T5 | Audit log tampering | Low | Critical | Append-only triggers at DB layer; even DB owner cannot UPDATE/DELETE without explicit trigger disable (audited) |
| T6 | Credential exposure (env vars, MCP config) | Medium | High | Secrets in env vars or n8n credentials only; `.gitignore` blocks common secret patterns; pre-commit verification |
| T7 | RBAC bypass via direct workflow trigger | Medium | Medium | Webhook signature verification; rate limiting; `slack_user_id` validation against block-list/role-map |
| T8 | DoS via high query volume | Low | Medium | Slack API has its own rate limits; n8n has request queueing; Postgres connection pool bounded |
| T9 | Supply chain — compromised n8n/Qdrant/Claude SDK | Low | High | Pin specific versions; monitor advisories; `crystaldba/postgres-mcp` in restricted mode |
| T10 | Lateral movement after VPS compromise | Low | Critical | Standard host hardening (out of bot scope); SSH key-only; fail2ban; audited sshd config |

---

## 3. OWASP LLM Top 10 (2025) — Mapping

| OWASP Category | Status | Mitigation |
|----------------|--------|------------|
| LLM01 — Prompt Injection | Addressed (v1) | System prompt is fixed; retrieved chunks delimited with explicit markers; refusal on low retrieval confidence prevents the LLM from "filling in" with attacker-influenced output |
| LLM02 — Insecure Output Handling | Addressed (v1) | Slack responses are plain text only; no raw HTML, no executable code echoed; URL allowlist for citation links |
| LLM03 — Training Data Poisoning | N/A | We use Claude API; no fine-tuning, no custom training data |
| LLM04 — Model Denial of Service | Partial (v2) | Rate limits enforced at Slack and at n8n; per-user query budget documented in PRODUCTION_CHECKLIST |
| LLM05 — Supply Chain | Partial (v2) | Specific versions pinned; CVE monitoring documented; SBOM generation flagged as v2 deliverable |
| LLM06 — Sensitive Information Disclosure | Addressed (v1) | Refusal-on-low-confidence; system prompt does not contain secrets; Claude responses filtered for common PII patterns before sending to Slack |
| LLM07 — Insecure Plugin Design | N/A | No third-party plugins to the bot |
| LLM08 — Excessive Agency | Addressed (v1) | The bot reads and replies; it cannot send messages, modify documents, or take actions outside the audit-log write |
| LLM09 — Overreliance | Addressed by design | The bot ALWAYS cites its sources; refuses on low confidence; user knows the answer is generated, not authoritative |
| LLM10 — Model Theft | N/A | We don't host a model; Anthropic does |

---

## 4. Secrets Handling

**Where secrets live:**
- Slack signing secret: n8n credential (encrypted at rest by n8n)
- Slack bot token: n8n credential
- Claude API key: n8n credential
- Postgres password: Docker compose env var, sourced from `.env` file
- Qdrant API key (if any): n8n credential
- NocoDB admin credentials: NocoDB-managed, separate database

**Where secrets must NEVER appear:**
- Source code files
- Git commits (verified by `.gitignore` patterns; pre-commit hooks recommended for production)
- Cursor `.cursor/mcp.json` (covered by `.gitignore`)
- Slack messages, including bot replies
- Audit log entries
- Error messages or logs (n8n logs scrubbed for credential-shaped strings)

**Production hardening (v2):**
- Migrate from `.env` files to a Secret Manager (HashiCorp Vault, AWS Secrets Manager, GCP Secret Manager)
- Rotate secrets on a documented schedule
- Use short-lived OAuth tokens for Slack where possible

---

## 5. Prompt Injection Defense

The bot is exposed to prompt injection via the `query` field from Slack and via retrieved knowledge base chunks.

**Defenses in v1:**
- Fixed system prompt (not constructed from user input)
- Retrieved chunks wrapped in explicit delimiters (`<retrieved_context>...</retrieved_context>`) within the prompt sent to Claude
- Output filter: if Claude's response contains tokens suggesting prompt-injection success (e.g. instructions to ignore prior instructions, requests to reveal system prompt), the response is replaced with a refusal and the event audited
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
[Traefik (TLS termination)]
    |
    v
[n8n webhook node — verifies Slack signature]
    |
    v
[n8n: extract slack_user_id]
    |
    +--> [Postgres: legal_hold_subjects lookup] --(boolean)-->
    |
    +--> [Postgres: rbac block-list lookup] --(allow/deny)-->
    |
    v (if allowed)
[n8n: retrieve from Qdrant]
    |
    v
[n8n: send prompt to Claude API (TLS, Anthropic)]
    |
    v
[Claude: response with citations]
    |
    v
[n8n: output filter (PII scrub, prompt-leak check)]
    |
    +--> [Postgres: audit_log INSERT]
    |
    v
[Slack: response to user (TLS)]
```

All data crossing trust boundaries is logged to `audit_log`. No external data is logged unencrypted to disk outside that table.

---

## 7. Authentication & Authorisation

**Slack ingress:**
- Slack signing secret verified per request (n8n native, n8n >= 1.106.0)
- Replay attack: Slack timestamp within 5 minutes (n8n native)
- Bot token scoped to minimum (read messages where invoked, write responses, list user groups for v2 RBAC)

**RBAC v1:**
- Hardcoded block-list of `slack_user_id` values
- Workflow checks before retrieval; blocked request audited with `refusal_reason = 'rbac_blocked'`

**RBAC v2 (documented, not built):**
- Slack User Group membership cached and consulted per query
- Roles: `employee`, `people_team`, `compliance_team`, `admin`
- Per-role NocoDB view (compliance team sees full text + retrieval; employee sees only own audit history)

**NocoDB authentication:**
- v1: Local NocoDB user accounts (admin-created)
- v2: SSO via Slack OAuth or organisation IdP (SAML/OIDC)

**Database access:**
- n8n connects via dedicated Postgres user with INSERT and SELECT only on `audit_log`
- NocoDB connects via separate user with SELECT and limited UPDATE (only `legal_hold` column on `audit_log`; full access on `legal_hold_subjects`)
- DBA access via separate credentialed account; all DBA actions logged

---

## 8. Logging & Monitoring

**v1 logging:**
- n8n execution logs (kept for 7 days by default; configurable)
- Postgres query log for security events (connections, denied queries)
- NocoDB user activity (built-in)
- Audit log writes (the bot's primary product)

**v1 monitoring:**
- Grafana dashboard for operational metrics
- Manual review of refusal patterns

**v2 monitoring (documented):**
- Sentry for application errors
- Structured log shipping to a SIEM
- Alerting on: spike in refusals, RBAC blocks above threshold, audit log integrity failure (e.g. trigger disable detected)

---

## 9. Incident Response (v1 Outline)

If a security incident is detected:

1. **Contain:** stop the n8n workflow (n8n UI: deactivate workflow). All in-flight requests fail; Slack returns the workflow's error response.
2. **Preserve:** snapshot Postgres (`pg_dump`), snapshot Qdrant volume, archive n8n execution logs.
3. **Investigate:** query audit_log for the affected timeframe. Identify scope (which queries, which users, what was returned).
4. **Notify:** internal security lead and DPO. If personal data breach with risk to data subjects, notify supervisory authority within 72 hours per GDPR Art. 33.
5. **Remediate:** fix the root cause. Document.
6. **Communicate:** affected data subjects per Art. 34 if required.

This procedure is a sketch. Production deployment requires a fuller IR plan with named responders, escalation paths, and tabletop exercises.

---

## 10. Validation Path

For an independent reviewer, see `docs/REVIEW_GUIDE.md` for 30-min, 2-hour, and full-review paths.

For external security review, recommended scopes:

- **Code review** (NCC Group, Trail of Bits, IOActive): the n8n workflow, the Postgres schema and triggers, the bot's prompt construction, the audit-log integrity guarantees. Estimated 2-3 days of consultant time.
- **LLM-specific review** (HiddenLayer, Lakera, Robust Intelligence): prompt injection surface, output handling, refusal robustness. Estimated 1-2 days.
- **Pen-test** of the public surface (Traefik, NocoDB, Slack endpoint): standard web pen-test scope. Estimated 1-3 days.

Total external review budget: approximately £10,000-£20,000 for a focused engagement. Acceptable for production deployment of a security-vendor-internal tool.
