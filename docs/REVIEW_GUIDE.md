# Reviewer's Guide

This document is for an independent reviewer assessing the Forensic-Grade Knowledge Bot for People Operations. Three review paths are provided depending on time available.

The bot is a v1 interview demo. Limitations are documented (see `docs/PRODUCTION_CHECKLIST.md`); production gates are explicit.

---

## Review Path 1: 30-Minute Quick Look

For a reviewer with limited time. Five questions, five files.

### Q1: What does this bot actually do?
**Read:** `README.md` (top of file, 30 seconds)

### Q2: What architectural decisions were made and why?
**Read:** `DECISIONS.md`, sections ADR-001 (architecture), ADR-005 (audit log), ADR-008 (reviewer interface), ADR-009 (litigation hold). Skim others. (~10 minutes)

### Q3: What are the security controls?
**Read:** `docs/SECURITY.md`, sections 2 (threat model), 3 (OWASP mapping), 5 (prompt injection defense). (~5 minutes)

### Q4: What's the GDPR posture?
**Read:** `docs/COMPLIANCE.md`, sections 1 (lawful basis), 2 (data subject rights), 4 (litigation hold). (~5 minutes)

### Q5: What's not production-ready and what would it take?
**Read:** `docs/PRODUCTION_CHECKLIST.md`, sections 4 (compliance gates), 6 (external security review), 10 (total estimate). (~5 minutes)

**At the end of 30 minutes, the reviewer can answer:**
- Is the architecture defensible?
- Are limitations honestly documented?
- Is the path to production realistic?

---

## Review Path 2: Two-Hour Deep Look

Adds technical inspection on top of Path 1.

### After completing Path 1, additionally:

#### A. Inspect the audit log schema
- Look at the Postgres init SQL (in `infra/postgres/init.sql` or equivalent path)
- Verify: 13 fields present, append-only triggers exist, retention column present, legal_hold columns present
- Verify: triggers are `BEFORE UPDATE` and `BEFORE DELETE` raising exception
- Confirm: even table owner cannot bypass without explicit trigger disable

#### B. Trace one request end-to-end
- Read the n8n workflow JSON (in `n8n-workflows/knowledge-bot.json`)
- Confirm: Slack signature verification node is the first node
- Confirm: legal_hold_subjects lookup happens before audit log write
- Confirm: RBAC block-list check happens before retrieval
- Confirm: every path (success, refusal, RBAC block) writes an audit row

#### C. Inspect the system prompt
- Read the prompt construction (in workflow JSON or `prompts/system.md`)
- Confirm: system prompt is fixed, not constructed from user input
- Confirm: retrieved chunks delimited (look for `<retrieved_context>` markers or equivalent)
- Confirm: refusal instruction explicit ("if confidence < threshold, refuse with stated reason")

#### D. Run a query end-to-end (in a test environment)
- Run `/check-audit` command (see `.cursor/commands/check-audit.md`)
- Issue a Slack `/ask` query for a test case
- Watch the audit_log row appear
- Issue a query designed to fail (e.g. nonsense input) — confirm refusal + audit row

#### E. Verify exposure
- Run `nmap` against the public IP — should show only 80, 443, 22 (SSH key-only)
- Hit the n8n public subdomain — should be authentication-gated
- Hit NocoDB — should require login

**At the end of two hours, the reviewer can answer:**
- Does the implementation match the design?
- Are there any obvious gaps between the threat model and the running system?
- Would they sign off on internal-use deployment?

---

## Review Path 3: Full Review

Full review takes 1-2 days and is appropriate before production deployment, not for interview demo purposes.

### A. All of Path 2, plus:

### B. Code review
- Read every n8n Code node (JavaScript executed inline in the workflow)
- Read all SQL: schema, triggers, retention script, hold-management procedures
- Read the `.cursor/rules/` files to understand the development discipline
- Read the knowledge base ingestion script(s)

### C. Threat model deep dive
- Walk through each threat (T1-T10 in `docs/SECURITY.md`) with a "if I were the attacker" mindset
- For each, confirm the mitigation is implemented (not just claimed)
- Identify any threats not in the model

### D. LLM-specific testing
- Run a Promptfoo or Garak evaluation suite against the bot
- Test prompt injection patterns from OWASP LLM Top 10 + recent literature
- Test refusal robustness on edge cases
- Document failure modes

### E. Compliance review
- Walk through `COMPLIANCE.md` with the deploying organisation's DPO
- Verify the LIA (Legitimate Interest Assessment) is drafted and signed
- Verify ROPA entry exists
- Test SAR and erasure procedures end-to-end
- Confirm litigation hold integrates with existing legal process

### F. Operational review
- Review the runbook (in production: `docs/RUNBOOK.md`)
- Walk through incident response procedures
- Test the deployment and rollback paths
- Verify backups are taken and restorable

**At the end of a full review, the reviewer produces a written report covering:**
- Architecture assessment with severity-rated findings
- OWASP LLM Top 10 conformance with evidence
- Compliance posture with DPO concurrence
- Operational readiness assessment
- Recommendation: deploy / deploy with conditions / do not deploy

This is what an external review firm (NCC Group, Trail of Bits, etc.) produces. Cost: **£8,000-£20,000** for a focused engagement (see `docs/PRODUCTION_CHECKLIST.md` section 6). For SMB-scale internal tools, see `docs/AUTOMATED_VALIDATION.md` for the lower-cost automated alternative.

---

## Common Reviewer Questions With Pre-Prepared Answers

These are questions a reviewer is likely to ask, with pointers to the answer. Use this as a self-test: if a reviewer asks one of these and the answer isn't in the docs, that's a documentation gap.

### "How does the bot handle a malicious user trying to extract the system prompt?"
See `docs/SECURITY.md` section 5 (prompt injection defense). Output filter detects common extraction patterns; refusal-on-low-retrieval-confidence denies the vector of crafting queries that retrieve attacker-controlled data.

### "What if the audit log gets too big?"
See `docs/COMPLIANCE.md` section 3 (retention policy). Default 90 days for queries, 7 years for refusals, indefinite for held data. Routine deletion script runs nightly. Held data may grow indefinitely under prolonged investigations — by design.

### "How do you handle a GDPR right-to-erasure request from someone under legal hold?"
See `docs/COMPLIANCE.md` section 2 (data subject rights — erasure detailed). Article 17(3)(e) exemption invoked; subject is informed in writing that their request is noted but pending until hold release.

### "What if the LLM hallucinates an incorrect policy answer?"
See `DECISIONS.md` ADR-005 (audit log). Every response is logged with retrieval metadata; users can flag responses; refusals on low confidence prevent the most common hallucination class (no retrieval matched).

### "What stops a developer from secretly modifying an audit row?"
See `DECISIONS.md` ADR-005 (audit log triggers) and `docs/SECURITY.md` section 2 (T5). Append-only PostgreSQL triggers block UPDATE and DELETE at the database level. Disabling the triggers requires DBA-level access, which is itself logged. The audit log of the audit log.

### "How does this scale to 10x the demo's traffic?"
See `docs/PRODUCTION_CHECKLIST.md` section 7 (performance and scale). Specific gates and corresponding actions documented. n8n Queue Mode, Postgres read replica, Qdrant horizontal scaling — pre-optimise nothing, measure first.

### "What's your incident response plan?"
See `docs/SECURITY.md` section 9 (incident response). v1 sketch covers contain → preserve → investigate → notify → remediate → communicate. Production deployment requires a fuller plan with named responders.

### "Has this been independently security-reviewed?"
**v1: No external review. Self-reviewed against OWASP LLM Top 10 (see `docs/SECURITY.md` section 3) plus automated AI-powered code review (see `docs/AUTOMATED_VALIDATION.md`).** External review path with named vendors and budget is in `docs/PRODUCTION_CHECKLIST.md` section 6, appropriate for compliance attestations or customer-facing rollout.

### "What happens if Anthropic has an outage?"
v1: bot returns an error to Slack; the error itself is audited. v2 (production): consider a fallback path (cached frequent answers, secondary LLM provider) — documented in `DECISIONS.md` "Decisions Not Yet Made."

### "What's the worst-case scenario you've thought about?"
Top three (from `docs/SECURITY.md`):
1. Audit log integrity compromise (T5) — mitigated by DB-level triggers; production adds hash chaining
2. Sensitive info leakage via LLM (T3) — mitigated by output filter and refusal threshold
3. Slack request forgery (T1) — mitigated by signature verification; standard.

### "Show me how to run an investigation if Compliance asks for all queries from User X between dates Y and Z."
See `docs/COMPLIANCE.md` section 4 (litigation hold procedure). Reviewer filters NocoDB by `slack_user_id` and date range, exports CSV, optionally toggles `legal_hold` on selected rows. v2 wrapper adds cryptographic hash and manifest.

---

## How to Submit Review Feedback

For interview review purposes: feedback to the bot's author directly.

For production deployment review: feedback should be a written report with:
- Severity-rated findings (Critical / High / Medium / Low / Informational)
- Each finding: description, impact, recommendation, suggested timeline
- Overall recommendation (deploy / deploy with conditions / do not deploy)
- Conformance assessment against OWASP LLM Top 10

Templates exist for this format from external review firms; we recommend using their standard format rather than inventing a new one.

---

## What This Guide Is Not

- Not a substitute for the reviewer's own judgment
- Not a guarantee that following these paths catches all issues
- Not appropriate for compliance certification (SOC 2, ISO 27001) — those require formal auditor engagement, not this guide
