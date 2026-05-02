---
description: Run audit log integrity checks before demo
---

# Audit Log Integrity Check

Run this when validating the audit log is healthy before a demo or commit.

**Target database:** **`binalyze_audit` on Cloud SQL** (primary path after Phase 3b-G).  
v0 Hostinger: `postgres_binalyze` container only if you are explicitly validating the fallback stack.

## Steps

1. Connect to the audit DB on **Cloud SQL** (after Phase 3b-G). Example patterns — replace placeholders:

**Option A — Cloud SQL Auth Proxy + psql:**

```bash
# Example: start proxy in another terminal, then:
psql "host=127.0.0.1 port=<PROXY_PORT> dbname=binalyze_audit user=<DB_IAM_USER> sslmode=require"
```

**Option B — `gcloud sql connect`** (interactive password / IAM flow per your org):

```bash
gcloud sql connect <CLOUD_SQL_INSTANCE_NAME> --user=<DB_USER> --database=binalyze_audit
```

2. Verify table exists with correct schema:

```sql
\d+ audit_log
```

Expected: 13 columns, append-only triggers visible.

3. Verify append-only triggers are active:

```sql
SELECT tgname, tgtype FROM pg_trigger WHERE tgrelid = 'audit_log'::regclass;
```

Expected: triggers blocking UPDATE and DELETE.

4. Count recent rows (sanity check):

```sql
SELECT COUNT(*) FROM audit_log WHERE created_at > NOW() - INTERVAL '1 hour';
```

5. Confirm no UPDATE/DELETE has happened (chain of custody):

```sql
SELECT MAX(id) - MIN(id) - COUNT(*) + 1 AS gap FROM audit_log;
```

Expected: 0 (no gaps from deleted rows).

If ANY of these fail: STOP, do not proceed with demo, investigate before continuing.
