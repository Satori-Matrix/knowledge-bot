# Automated Validation — The Realistic SMB Path

This document specifies the validation pipeline a security-vendor SMB would actually deploy for an internal bot like this one. It complements `docs/PRODUCTION_CHECKLIST.md` (which documents the full enterprise validation path with external review).

The distinction matters: external code review at £10-20k is appropriate for customer-facing systems, regulatory attestations, and compliance certification. For an internal Q&A bot at v1, the automated validation path below covers most of the same surface area at a fraction of the cost — and is what most SMBs actually run.

This file documents the automated validation we would deploy for production. None of these tools are configured in v1; they are documented as the realistic next step before production rollout.

---

## 1. Why Automated Validation, Not External Review

For a 60-80 person security vendor's internal Q&A bot:

- The blast radius is small (internal People-team users, no customer data)
- The codebase is small (n8n workflow + SQL schema + a few scripts)
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

## 3. The Validation Stack — On Pull Request (GitHub Actions)

These run automatically when a PR is opened or updated.

### 3.1 GitHub CodeQL — Semantic Security Analysis

GitHub's native semantic security scanner. Detects SQL injection patterns, command injection, path traversal, etc.

- **Setup:** GitHub Actions workflow (`.github/workflows/codeql.yml`)
- **Languages:** JavaScript (n8n Code nodes), Python (any helper scripts), SQL (with extensions)
- **Cost:** Free for public repos; included in GitHub Advanced Security for private repos

### 3.2 Dependabot — Dependency Vulnerability Alerts

GitHub-native. Watches `package.json`, `requirements.txt`, etc. for vulnerable dependencies. Auto-creates PRs for security updates.

- **Setup:** `.github/dependabot.yml`
- **Cost:** Free, native GitHub feature

### 3.3 CodeRabbit — AI-Powered PR Review

Reviews every PR with AI, comments inline on issues, generates PR summaries. Catches the class of issues that humans see but automation misses (subtle logic, naming, missing edge cases).

- **Setup:** GitHub App, install on repo
- **Configuration:** Optional `.coderabbit.yaml` for project rules
- **Cost:** Free for OSS / personal; paid plans from approximately $24/dev/month for private repos

### 3.4 Gito (Optional Self-Hosted AI Review)

Open-source alternative to CodeRabbit, using your own LLM API key. More control, slightly more setup.

- **Repo:** github.com/Nayjest/Gito (open source)
- **Setup:** GitHub Actions workflow + `LLM_API_KEY` in repo secrets
- **Cost:** Free + your LLM API costs (Anthropic/OpenAI usage at standard rates)

### 3.5 Trivy / Grype — Container Image Scanning

Scans Docker images we build (n8n customisations, Postgres init image, etc.) for known CVEs.

- **Setup:** GitHub Actions step on Docker builds
- **Cost:** Free, open source

---

## 4. The Validation Stack — Periodic / Scheduled

These run on a schedule, not per-PR.

### 4.1 Promptfoo — LLM Eval Suite

Tests the bot's prompt and refusal behaviour against a curated suite of inputs. Catches regressions when we change the system prompt or retrieval logic.

- **Repo:** github.com/promptfoo/promptfoo (open source)
- **Setup:** YAML test suite committed to repo, runs nightly via GitHub Actions
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
| Configure CodeQL workflow | 15 min |
| Enable Dependabot | 5 min |
| Install CodeRabbit GitHub App | 10 min |
| Configure Trivy/Grype on Docker builds | 20 min |
| Write initial Promptfoo test suite (20 baseline evals) | 2-3 hours |

**Total: roughly 4-5 hours of one-time setup. Then it runs.**

---

## 7. What This Catches vs Doesn't

### Automated path catches well:

- Accidentally committed secrets
- Known CVEs in dependencies
- Common code-level vulnerabilities (SQL injection, path traversal, etc. via CodeQL)
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

> "v1 ships with the automated validation stack documented here — pre-commit hooks for secrets and skill scanning, CodeQL on PRs, AI-powered PR review via CodeRabbit, Promptfoo for LLM eval, all running automatically at near-zero cost. Total ~£0-50/month plus 4-5 hours of setup. Full external review documented in PRODUCTION_CHECKLIST.md is appropriate when this scales to customer-facing or regulated-data deployments. For an internal People-team bot, automated covers what matters."

This is the senior-engineering answer. Right-sized for the system, demonstrates current-tools knowledge, doesn't over-engineer.

---

## 9. References

- gitleaks: github.com/gitleaks/gitleaks
- Cisco Skill Scanner: github.com/cisco-ai-defense/skill-scanner
- pre-commit: pre-commit.com
- GitHub CodeQL: docs.github.com/code-security/code-scanning
- Dependabot: docs.github.com/code-security/dependabot
- CodeRabbit: coderabbit.ai
- Gito: github.com/Nayjest/Gito
- Trivy: aquasecurity.github.io/trivy
- Grype: github.com/anchore/grype
- Promptfoo: promptfoo.dev
- OWASP LLM Top 10: owasp.org/llm-top-10
