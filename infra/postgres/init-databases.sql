-- v0 prototyping environment — superseded by GCP architecture
-- See ADR-016 in DECISIONS.md for the architectural pivot rationale.
-- These containers remain running on the Hostinger VPS as a fallback
-- environment but are not the demo path.
--
-- Internal DB name `binalyze_audit` is a legacy v0 Postgres identifier (not public company branding).
-- Do not rename without a coordinated DB migration on the Hostinger VPS.

CREATE DATABASE binalyze_audit OWNER kb_admin;
