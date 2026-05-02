#!/usr/bin/env bash
# Download public framework documents for the knowledge bot demo corpus.
# Primary sources: public NIST SPs + ACAS (UK employment). URLs are maintained in-repo; re-run if a host moves a file.
# Verifies each download is a valid PDF, generates manifest, zips the result.
#
# Usage: ./scripts/download-knowledge-base.sh
# Output: knowledge-base/ folder + knowledge-base.zip

set -euo pipefail

# --- Config ---
KB_DIR="knowledge-base"
ZIP_NAME="knowledge-base.zip"
# Browser-like UA — some hosts return HTML/error pages for non-browser user agents.
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
CURL_OPTS=(--silent --show-error --location --max-time 180 --retry 3 --user-agent "$USER_AGENT")

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Helpers ---
SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_FILES=()

log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_err() { echo -e "${RED}[FAIL]${NC} $1"; }

# Download a file and verify it's a valid PDF
download_pdf() {
    local category="$1"
    local filename="$2"
    local url="$3"
    local _description="$4"

    local target_dir="$KB_DIR/$category"
    local target_path="$target_dir/$filename"

    mkdir -p "$target_dir"

    log_info "Downloading: $filename"
    log_info "  Source: $url"

    if curl "${CURL_OPTS[@]}" -o "$target_path" "$url"; then
        # Verify it's actually a PDF (magic bytes check)
        if [[ -f "$target_path" ]] && [[ $(head -c 4 "$target_path" 2>/dev/null) == "%PDF" ]]; then
            local size_kb
            size_kb=$(du -k "$target_path" | cut -f1)
            log_ok "$filename (${size_kb} KB)"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            return 0
        else
            log_err "$filename — downloaded but is not a valid PDF (likely 403 HTML error page)"
            rm -f "$target_path"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAILED_FILES+=("$category/$filename | $url")
            return 1
        fi
    else
        log_err "$filename — curl failed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_FILES+=("$category/$filename | $url")
        return 1
    fi
}

# --- Cleanup any previous run ---
log_info "Cleaning up previous knowledge-base directory if exists"
rm -rf "$KB_DIR" "$ZIP_NAME"
mkdir -p "$KB_DIR"

# --- Category 1: HR / People Ops (+ workforce-adjacent NIST) ---
# Note: Several historical ACAS/CIPD direct PDF URLs now 404 or redirect to HTML; this category keeps one
# live ACAS employment guide plus NIST publications commonly used with People/HR tech & workforce programmes.
echo ""
log_info "=== Category: HR / People Ops ==="
download_pdf "hr-people-ops" \
    "01-acas-discipline-grievances-at-work-guide-2024-08.pdf" \
    "https://www.acas.org.uk/sites/default/files/2024-08/discipline-and-grievances-at-work-the-acas-guide.pdf" \
    "ACAS — Discipline and Grievances at Work: The ACAS Guide (UK, Aug 2024 PDF)"

download_pdf "hr-people-ops" \
    "02-nist-sp-800-181-cybersecurity-workforce-framework.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-181.pdf" \
    "NIST SP 800-181 — Workforce Framework for Cybersecurity"

download_pdf "hr-people-ops" \
    "03-nist-sp-800-40r4-guide-to-secure-deployment-maintenance.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-40r4.pdf" \
    "NIST SP 800-40 Rev. 4 — Guide to Enterprise Patch Management Planning"

download_pdf "hr-people-ops" \
    "04-nist-sp-800-121r2-bluetooth-risk.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-121r2.pdf" \
    "NIST SP 800-121 Rev. 2 — Bluetooth Security for Consumer Products (BYOD / employee devices)"

download_pdf "hr-people-ops" \
    "05-nist-sp-800-218-ssdf.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-218.pdf" \
    "NIST SP 800-218 — Secure Software Development Framework (SSDF)"

# --- Category 2: IT / Internal Tools ---
echo ""
log_info "=== Category: IT / Internal Tools ==="
download_pdf "it-internal-tools" \
    "01-nist-800-46r2-byod-telework.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-46r2.pdf" \
    "NIST SP 800-46 Rev 2 — Guide to Enterprise Telework, Remote Access, and BYOD"

download_pdf "it-internal-tools" \
    "02-nist-800-63b-authentication.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-63b.pdf" \
    "NIST SP 800-63B — Digital Identity Guidelines: Authentication and Lifecycle Management"

download_pdf "it-internal-tools" \
    "03-nist-800-124r2-mobile-device-security.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-124r2.pdf" \
    "NIST SP 800-124 Rev 2 — Guidelines for Managing the Security of Mobile Devices"

download_pdf "it-internal-tools" \
    "04-nist-800-53r5-security-controls.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf" \
    "NIST SP 800-53 Rev 5 — Security and Privacy Controls for Information Systems"

# --- Category 3: Security / DFIR Operations ---
echo ""
log_info "=== Category: Security / DFIR Operations ==="
download_pdf "security-dfir-operations" \
    "01-nist-800-61r2-incident-handling.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-61r2.pdf" \
    "NIST SP 800-61 Rev 2 — Computer Security Incident Handling Guide (legacy, with diagrams)"

download_pdf "security-dfir-operations" \
    "02-nist-800-61r3-incident-response-csf.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-61r3.pdf" \
    "NIST SP 800-61 Rev 3 — Incident Response Recommendations (current, supersedes Rev 2)"

download_pdf "security-dfir-operations" \
    "03-nist-800-190-application-container-security.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf" \
    "NIST SP 800-190 — Application Container Security Guide (IR / DFIR-relevant artefacts)"

download_pdf "security-dfir-operations" \
    "04-nist-800-184-recovery.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-184.pdf" \
    "NIST SP 800-184 — Guide for Cybersecurity Event Recovery"

download_pdf "security-dfir-operations" \
    "05-nist-800-83r1-malware-incident-prevention.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-83r1.pdf" \
    "NIST SP 800-83 Rev 1 — Guide to Malware Incident Prevention and Handling"

download_pdf "security-dfir-operations" \
    "06-nist-800-150-threat-info-sharing.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-150.pdf" \
    "NIST SP 800-150 — Guide to Cyber Threat Information Sharing"

# --- Generate Manifest ---
echo ""
log_info "=== Generating Manifest ==="
MANIFEST_PATH="$KB_DIR/MANIFEST.md"

cat > "$MANIFEST_PATH" <<'MANIFEST_HEADER'
# Knowledge Base Manifest

This corpus consists of public framework documents from US/UK government agencies
and professional bodies. All documents are publicly available and intended for
adoption by organisations.

**Generated by:** `scripts/download-knowledge-base.sh`
**Purpose:** Forensic-grade knowledge bot demo corpus (Acme DFIR placeholder)
**Tag:** All AI-drafted gap-filler documents (added separately) carry an
        `[ILLUSTRATIVE]` tag. Documents listed below are real published frameworks.

---

## Licence Summary

| Source | Licence |
|---|---|
| NIST publications | US Government public domain (NIST publications are not subject to copyright in the US) |
| NCSC UK guidance | Open Government Licence v3.0 |
| gov.uk content | Open Government Licence v3.0 |
| ACAS guidance | Free use for HR purposes; ACAS retains copyright |
| CIPD guides | Free use for member/practitioner reference; CIPD retains copyright |

For production deployment, verify licensing terms for each source independently.
For demo/educational use, all sources permit fair use.

---

## Documents

MANIFEST_HEADER

# Generate per-document entries with metadata
for category in hr-people-ops it-internal-tools security-dfir-operations; do
    if [[ -d "$KB_DIR/$category" ]]; then
        echo "" >> "$MANIFEST_PATH"
        echo "### $category" >> "$MANIFEST_PATH"
        echo "" >> "$MANIFEST_PATH"
        echo "| File | Size | SHA-256 |" >> "$MANIFEST_PATH"
        echo "|---|---|---|" >> "$MANIFEST_PATH"

        shopt -s nullglob
        for pdf in "$KB_DIR/$category"/*.pdf; do
            if [[ -f "$pdf" ]]; then
                filename=$(basename "$pdf")
                size_kb=$(du -k "$pdf" | cut -f1)
                sha=$(sha256sum "$pdf" | cut -d' ' -f1 | head -c 16)
                echo "| \`$filename\` | ${size_kb} KB | \`${sha}...\` |" >> "$MANIFEST_PATH"
            fi
        done
        shopt -u nullglob
    fi
done

echo "" >> "$MANIFEST_PATH"
echo "---" >> "$MANIFEST_PATH"
echo "" >> "$MANIFEST_PATH"
echo "**Generated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> "$MANIFEST_PATH"
echo "**Total documents:** $SUCCESS_COUNT successful, $FAIL_COUNT failed" >> "$MANIFEST_PATH"

# --- Create Zip ---
echo ""
log_info "=== Creating zip archive ==="
zip -rq "$ZIP_NAME" "$KB_DIR"
log_ok "Created $ZIP_NAME ($(du -h "$ZIP_NAME" | cut -f1))"

# --- Final Report ---
echo ""
echo "================================================================"
echo "  KNOWLEDGE BASE DOWNLOAD COMPLETE"
echo "================================================================"
echo "  Successful: $SUCCESS_COUNT"
echo "  Failed:     $FAIL_COUNT"
echo "  Output:     $ZIP_NAME"
echo "  Manifest:   $MANIFEST_PATH"
echo "================================================================"

if [[ $FAIL_COUNT -gt 0 ]]; then
    echo ""
    log_err "Failed downloads:"
    for failed in "${FAILED_FILES[@]}"; do
        echo "  - $failed"
    done
    echo ""
    log_info "Re-run script to retry, or download manually from URLs above."
    exit 1
fi

echo ""
log_ok "All documents downloaded successfully."
log_info "Next: Push to GitHub Release with:"
log_info "  gh release create knowledge-base-v1 $ZIP_NAME \\"
log_info "    --title \"Knowledge Base v1 (15 public framework documents)\" \\"
log_info "    --notes-file scripts/RELEASE_NOTES.md"

exit 0
