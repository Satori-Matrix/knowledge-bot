# Security Incidents — Forensic Log

This file records security-relevant findings tied to this repository or its build environment. Each entry is dated, scoped, and closed or open. Format is consistent so future findings append without restructuring the document.

Entries are factual records of discovery, scope, mitigation, and verification — not narrative postmortems.

---

## 2026-05-02 — Plaintext credentials in Cursor global MCP config

**Timestamp:** 2026-05-02  
**Severity:** Low — no evidence of exposure outside the operator-controlled machine; risk was local persistence of secrets in a config file.  
**Status:** Closed  

### Discovery

During Cursor MCP UI inspection at the start of Phase 3 configuration review, global MCP configuration was read to reconcile claimed versus actual server entries.

### Findings

- One GitHub personal access token, identifiable by prefix `ghp_W1LCR` (full value not recorded here; remainder withheld).
- Two PostgreSQL connection strings associated with unrelated services (`postgres-chainlit`, `postgres-rag`); full URIs not reproduced in this log.

### Scope investigation

An agent-assisted git exposure sweep was executed over: `/root`, `/home`, `/opt`, `/srv`, `/var`, `/usr/local`, `/mnt`, `/media`, `/tmp`, `/snap`, `/etc`, `/boot`. **Verdict: CLEAN** — no `.git` directory was found that tracked `~/.cursor/mcp.json` or otherwise indicated those credential strings were committed to a repository under that sweep boundary.

### Mitigation

- GitHub: PAT revoked at source (along with two other PATs retired the same morning per operator rotation; `gpu-rag-demo` remained the active credential where applicable).
- `~/.cursor/mcp.json` rewritten to remove embedded credentials and unrelated MCP server entries; backups retained locally as `mcp.json.pre-fix-20260502-175039` and `mcp.json.pre-env-20260502-175255`.

### Verification

- Manual MCP startup tests (system `npx` with constrained `PATH`) succeeded for the configured documentation-oriented servers.
- Cursor live verification: four MCP servers loaded and responded (`filesystem`, `sequential-thinking`, `context7`, project-scoped `n8n-mcp`).

### Lessons encoded

Operational guardrails for Cursor remote-SSH and n8n-mcp usage are documented in `.cursor/rules/00-base.mdc` (Environment Notes) and in `DECISIONS.md` (ADR-011 addendum, ADR-013, ADR-014).
