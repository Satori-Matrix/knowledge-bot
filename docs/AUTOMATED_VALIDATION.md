# Automated Validation — The Realistic SMB Path

This document specifies the validation pipeline a security-vendor SMB would actually deploy for an internal bot like this one. It complements `docs/PRODUCTION_CHECKLIST.md` (which documents the full enterprise validation path with external review).

The distinction matters: external code review at £10-20k is appropriate for customer-facing systems, regulatory attestations, and compliance certification. For an internal Q&A bot at v1, the automated validation path below covers most of the same surface area at a fraction of the cost — and is what most SMBs actually run.

This file documents the automated validation we would deploy for **GCP production**. None of these tools are fully configured in the demo repo; they are documented as the realistic next step before production rollout.

---

## 1. Why Automated Validation, Not External Review

For a 60-80 person security vendor's internal Q&A bot:

- The blast radius is small (internal People-team users, no customer data)
- The codebase is small (Cloud Run services + SQL schema + a few scripts)
- The threat model is bounded (see `docs/SECURITY.md` section 2)
- The review cycle should be every PR, not annual

External review every 12 months catches issues 12 months late. Automated AI-powered review on every commit catches the same class of issues immediately, and at near-zero cost. For systems below the customer-facing or regulated-data threshold, automated is the right answer.

For systems above that threshold (customer data, regulatory attestation, public-facing security product), `docs/PRODUCTION_CHECKLIST.md` section 6 documents the external review path and budget.

---

## 2. The Validation Stack — Pre-Commit (Local)

These run on the developer's machine before code reaches GitHub.

### 2.1 gitleaks — Secret Detection

Detects accidentally-committed secrets (API keys, tokens, passwords, private keys) before they reach the remote repo.

- **Install:** `brew install gitleaks` (macOS), `apt install gitleaks` (Debian/Ubuntu), or download from GitHub releases
- **Configuration:** `.gitleaks.toml` in repo root (default rules cover most cases)
- **Pre-commit hook:** added via `pre-commit` framework
- **Cost:** Free, open source

### 2.2 Cisco Skill Scanner — Cursor Skills Validation

Specifically scans Cursor Agent Skills (the `.cursor/rules/*.mdc` files we ship) for prompt injection patterns, data exfiltration indicators, and malicious code patterns.

- **Repo:** github.com/cisco-ai-defense/skill-scanner (Apache 2.0)
- **Install:** `pip install cisco-ai-skill-scanner`
- **Pre-commit hook:** scans only changed skill files for fast commits
- **Cost:** Free
- **Particularly relevant:** because we ship Cursor rules (`.cursor/rules/`) ourselves, this validates our own skills don't contain risky patterns

### 2.3 pre-commit Framework — Hook Orchestration

Runs all the above hooks consistently across team machines.

- **Install:** `pip install pre-commit`
- **Configuration:** `.pre-commit-config.yaml` in repo root
- **Cost:** Free

---

## 3. The Validation Stack — On Pull Request (CI)

These run automatically when a PR is opened or updated. On GCP the **native** equivalents are **Cloud Build** triggers; GitHub Actions remains valid if the repo lives on GitHub — pick one CI spine, not duplicate pipelines without reason.

### 3.1 Cloud Build — CI / CD

Google-managed builds for container images and tests. Runs unit tests, builds images, pushes to **Artifact Registry**.

- **Setup:** `cloudbuild.yaml` in repo; trigger on push to `main` / PR (via GitHub App or Cloud Source Repositories)
- **Cost:** Free tier then usage-based; fits SMB budgets at low volume

### 3.2 Artifact Analysis — Container Image Scanning

**Artifact Analysis** (and related **Container Analysis** APIs) scans images in **Artifact Registry** for known CVEs and policy violations.

- **Setup:** enable on the registry; optionally block deploy on Critical findings
- **Cost:** Included in typical GCP billing models for scanning; verify current pricing

### 3.3 Dependabot / Renovate — Dependency Vulnerability Alerts

If the repo is on **GitHub**: Dependabot watches manifests. On **GCP** only: consider **Renovate** or Cloud Build steps invoking `osv-scanner` / `npm audit` / `pip-audit`.

- **Cost:** Free tiers available

### 3.4 CodeRabbit / Gito — AI-Powered PR Review (optional)

Same as before: GitHub App (CodeRabbit) or self-hosted Gito with your own LLM key — useful for any Git-hosted project.

- **Cost:** Free tier or usage-based

### 3.5 Security Command Center (SCC) — Posture & Threats

For GCP organisations: **Security Command Center** (Premium or Standard tiers per org needs) surfaces misconfigurations, suspicious activity, and compliance violations across projects.

- **Setup:** enable at org/folder level; wire bot project as asset
- **Cost:** Tier-dependent; often acceptable for security-vendor internal standards

### 3.6 Cloud Logging + Log Router — Centralisation

**Cloud Logging** with a **log sink to BigQuery** gives queryable, long-retention operational and security logs — including correlating **Cloud Audit Logs** with application logs.

- **Setup:** sink filter + BigQuery dataset + IAM for analysts
- **Cost:** Ingest + storage; demo-scale typically small

---

## 4. The Validation Stack — Periodic / Scheduled

These run on a schedule, not per-PR.

### 4.1 Promptfoo — LLM Eval Suite

Tests the bot's prompt and refusal behaviour against a curated suite of inputs. Catches regressions when we change the system prompt or retrieval logic.

- **Repo:** github.com/promptfoo/promptfoo (open source)
- **Setup:** YAML test suite committed to repo, runs nightly via **Cloud Build** or GitHub Actions
- **Tests we'd write:**
  - Prompt injection attempts (from OWASP LLM Top 10 examples)
  - Refusal robustness (queries with no relevant retrieval should return clear refusal)
  - Hallucination detection (queries about topics outside the knowledge base)
  - System prompt extraction attempts
  - PII leakage attempts
- **Cost:** Free + LLM API costs for test runs

### 4.2 OWASP LLM Top 10 Self-Assessment

Quarterly walk-through of `docs/SECURITY.md` section 3 against current OWASP guidance. Document any gaps that have emerged.

- **Cost:** ~2 hours of internal time per quarter

### 4.3 Manual Senior Engineer Review

Annual: a senior engineer outside the immediate team reads the bot's full code + architecture for fresh-eyes assessment.

- **Cost:** ~4-8 hours of internal time per year, or ~£500-£1,500 if external

---

## 5. Total Cost Comparison

For a v1 internal Q&A bot deployment:

| Validation path | Cost | Coverage |
|----------------|------|----------|
| **Automated (this doc)** | £0-50/month | Per-PR security review, secret detection, dependency alerts, container scanning, LLM eval |
| **External review (PRODUCTION_CHECKLIST sec. 6)** | £6,500-£14,500 once + ongoing | Code review, LLM-specific testing, web pen-test |
| **Both combined (high-stakes deployment)** | £6,500-£14,500 once + £0-50/month | Defense in depth |

For internal bots: automated path is sufficient.
For customer-facing systems or regulatory attestation: combine both.

---

## 6. Setup Effort

If we deployed this stack tomorrow:

| Task | Effort |
|------|--------|
| Install pre-commit framework + gitleaks + skill-scanner hooks | 30 min |
| Configure Cloud Build trigger + `cloudbuild.yaml` | 30 min |
| Enable Dependabot (or Renovate) | 5-15 min |
| Install CodeRabbit GitHub App (optional) | 10 min |
| Enable Artifact Analysis on Artifact Registry | 20 min |
| Create log sink to BigQuery + IAM | 30 min |
| Write initial Promptfoo test suite (20 baseline evals) | 2-3 hours |

**Total: roughly 4-5 hours of one-time setup. Then it runs.**

---

## 7. What This Catches vs Doesn't

### Automated path catches well:

- Accidentally committed secrets
- Known CVEs in dependencies
- Common code-level vulnerabilities (SQL injection, path traversal, etc. via **Cloud Build** static analysis or optional GitHub CodeQL)
- Prompt injection regressions in LLM behaviour
- Cursor skill issues (via Cisco Skill Scanner)
- Subtle code review issues (via AI PR reviewers)

### Automated path does NOT catch:

- Architectural-level issues requiring senior judgment
- Novel attack patterns not in tool databases
- Business-logic vulnerabilities specific to your workflow
- Threats requiring deep social engineering analysis
- Compliance gaps requiring DPO interpretation

For these: human review (internal or external) remains essential. Automation is a force multiplier, not a replacement.

---

## 8. The Honest Demo Narrative

When asked about validation:

> "We ship with the automated validation path documented here — pre-commit hooks for secrets and skill scanning, **Cloud Build** (or GitHub Actions) for CI, **Artifact Analysis** on container images, **SCC** for posture, **Cloud Logging → BigQuery** sinks for correlation with **Cloud Audit Logs**, plus Promptfoo for LLM eval. Total roughly **£0-50/month** at SMB demo scale plus a few hours of setup. Full external review in PRODUCTION_CHECKLIST.md is for customer-facing or regulated-data deployments. For an internal People-team bot on GCP, automated covers what matters."

This is the senior-engineering answer. Right-sized for the system, demonstrates current-tools knowledge, doesn't over-engineer.

---

## 9. References

- gitleaks: github.com/gitleaks/gitleaks
- Cisco Skill Scanner: github.com/cisco-ai-defense/skill-scanner
- pre-commit: pre-commit.com
- Cloud Build: cloud.google.com/build/docs
- Artifact Analysis / Container Analysis: cloud.google.com/artifact-analysis/docs
- Security Command Center: cloud.google.com/security-command-center/docs
- Cloud Logging / Log Router sinks: cloud.google.com/logging/docs/export
- GitHub CodeQL (optional if using GitHub): docs.github.com/code-security/code-scanning
- Dependabot: docs.github.com/code-security/dependabot
- CodeRabbit: coderabbit.ai
- Gito: github.com/Nayjest/Gito
- Promptfoo: promptfoo.dev
- OWASP LLM Top 10: owasp.org/llm-top-10
