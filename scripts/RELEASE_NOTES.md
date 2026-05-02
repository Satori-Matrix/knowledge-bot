# Knowledge Base v1 — Public Framework Documents

This release ships **15 PDFs** for the forensic-grade knowledge bot demo corpus.

The **HR / People Ops** folder combines **one current ACAS employment guide (UK)** with **four NIST Special Publications** commonly paired with workforce, BYOD, and secure-development governance (routing still treats this category as “policies people ask HR / internal platforms about”).

**IT / Internal Tools** and **Security / DFIR Operations** are **NIST SPs** only (stable `nvlpubs.nist.gov` URLs).

## Contents

### HR / People Ops (5 documents)
- ACAS — *Discipline and Grievances at Work: The ACAS Guide* (PDF dated Aug 2024 on acas.org.uk)
- NIST SP 800-181 — Workforce Framework for Cybersecurity
- NIST SP 800-40 Rev. 4 — Guide to Enterprise Patch Management Planning
- NIST SP 800-121 Rev. 2 — Bluetooth security (BYOD / consumer devices)
- NIST SP 800-218 — Secure Software Development Framework (SSDF)

### IT / Internal Tools (4 documents)
- NIST SP 800-46 Rev. 2 — Enterprise Telework, Remote Access, and BYOD
- NIST SP 800-63B — Digital Identity Guidelines (Authentication)
- NIST SP 800-124 Rev. 2 — Mobile Device Security
- NIST SP 800-53 Rev. 5 — Security and Privacy Controls

### Security / DFIR Operations (6 documents)
- NIST SP 800-61 Rev. 2 — Computer Security Incident Handling Guide (legacy)
- NIST SP 800-61 Rev. 3 — Incident Response Recommendations (current)
- NIST SP 800-190 — Application Container Security Guide
- NIST SP 800-184 — Cybersecurity Event Recovery
- NIST SP 800-83 Rev. 1 — Malware Incident Prevention and Handling
- NIST SP 800-150 — Cyber Threat Information Sharing

## Licence Notes

NIST publications are US Government public domain. The ACAS PDF is © ACAS; use per ACAS terms for redistribution beyond demo/education.

## Reproducibility

Regenerate with `scripts/download-knowledge-base.sh`. `MANIFEST.md` inside the zip records sizes and SHA-256 prefixes.

## Usage

Download `knowledge-base.zip`, unzip, ingest into Vertex AI RAG Engine (or your corpus pipeline).
