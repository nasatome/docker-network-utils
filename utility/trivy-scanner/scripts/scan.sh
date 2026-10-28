#!/bin/sh
# scan.sh - Daily Trivy vulnerability scan with Discord notification
#
# Behavior:
#   - Reads /etc/trivy-scanner/images.txt for allowlist (uncommented lines)
#   - If allowlist is empty, auto-discovers images from running containers
#   - Scans each image for CRITICAL and HIGH CVEs
#   - Posts Discord embed when findings exist OR on weekly heartbeat day (Mon)
#   - If REPORT_DIR is set, also writes a machine-readable report there:
#       critical.tsv    one "image<TAB>vulnerability-id<TAB>package" line per
#                       CRITICAL finding (sorted, unique). When Docker reports a
#                       container's image only by ID (its tag moved to a newer
#                       image), the column carries the image's repository name
#                       instead, so the same CVE keeps the same key.
#       last-scan.json  {finished_at, images, failed, critical, high,
#                       db_updated_at, critical_sha256}, written last; a reader
#                       checks critical_sha256 to know both files match.
#     Lets another tool (e.g. a host timer) alert on NEW findings only, and on
#     scans that failed or ran on a stale vulnerability DB.
#
# Exit codes:
#   0 - Success (notification sent or skipped intentionally)
#   1 - Configuration error (no images, discovery failure, no DB)
#   2 - Notification error (webhook missing+findings, webhook HTTP error)

set -u

WEBHOOK_FILE="/etc/discord-webhook"
IMAGES_FILE="/etc/trivy-scanner/images.txt"
DOCKER_SOCK="/var/run/docker.sock"
HEARTBEAT_DOW="1"  # 1=Monday (date +%u format)
DATE=$(date '+%Y-%m-%d %H:%M %Z')

# Resolve host identity. Precedence: SCANNER_HOST env > /etc/hostname mount > container hostname
if [ -z "${SCANNER_HOST:-}" ] && [ -f /etc/host-hostname ]; then
    SCANNER_HOST=$(tr -d '[:space:]' < /etc/host-hostname)
fi
[ -z "${SCANNER_HOST:-}" ] && SCANNER_HOST=$(hostname)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

# One scan at a time: a manual run and the scheduled one share the container,
# the cache and REPORT_DIR. The lock is released when this process exits.
exec 8>/tmp/trivy-scan.lock
if ! flock -n 8; then
    log "ERROR: another scan is already running in this container"
    exit 1
fi

REPORT_DIR="${REPORT_DIR:-}"
CRIT_TMP=""
# stderr of the current trivy run: its last line goes to the log when a scan fails.
ERR_TMP=$(mktemp) || { log "ERROR: cannot create a temp file"; exit 1; }
if [ -n "$REPORT_DIR" ]; then
    CRIT_TMP=$(mktemp) || { rm -f "$ERR_TMP"; log "ERROR: cannot create a temp file"; exit 1; }
fi
trap 'rm -f "$ERR_TMP" ${CRIT_TMP:+"$CRIT_TMP"}' EXIT

# Name for the report: the reference as Docker gives it, unless it is a bare
# image ID; then the first repository tag or digest of that image, if any.
report_name() {
    if echo "$1" | grep -Eq '^(sha256:)?[0-9a-f]{12,64}$'; then
        ref=$(curl -sf --max-time 10 --unix-socket "$DOCKER_SOCK" \
            "http://localhost/images/$1/json" 2>/dev/null \
            | jq -r '([.RepoTags[]? | select(. != "<none>:<none>")] + [.RepoDigests[]?])[0] // empty' 2>/dev/null)
        echo "${ref:-$1}"
    else
        echo "$1"
    fi
}

# ---- Refresh vulnerability DB (best-effort; falls back to cached DB) ----
log "Updating Trivy vulnerability DB..."
trivy image --download-db-only >/dev/null 2>&1 \
    || log "WARN: DB update had issues, will use cached DB if present"

# ---- Resolve image list ----
IMAGES=""
if [ -f "$IMAGES_FILE" ]; then
    IMAGES=$(grep -v '^[[:space:]]*#' "$IMAGES_FILE" | grep -v '^[[:space:]]*$' || true)
fi

if [ -z "$IMAGES" ]; then
    log "Allowlist empty, auto-discovering from running containers..."
    DISCOVERY=$(curl -sf --max-time 10 --unix-socket "$DOCKER_SOCK" \
        http://localhost/containers/json 2>&1) || {
        log "ERROR: docker socket query failed: $DISCOVERY"
        exit 1
    }
    IMAGES=$(printf '%s' "$DISCOVERY" | jq -r '.[].Image' 2>/dev/null | sort -u)
    if [ -z "$IMAGES" ]; then
        log "ERROR: parsed image list is empty"
        exit 1
    fi
fi

IMG_COUNT=$(echo "$IMAGES" | wc -l)
log "Scanning $IMG_COUNT images..."

# ---- Scan loop ----
TOTAL_C=0
TOTAL_H=0
FAIL_COUNT=0
FINDINGS=""
FAILURES=""
for img in $IMAGES; do
    log "Scanning $img"
    out=$(trivy image --quiet --skip-db-update --severity CRITICAL,HIGH \
        --format json "$img" 2>"$ERR_TMP") || {
        log "  scan failed for $img: $(tail -n 1 "$ERR_TMP" | cut -c1-300)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES="${FAILURES}
- \`${img}\` (scan failed)"
        continue
    }
    # Output that is not a JSON object counts as a failed scan, not as zero findings.
    if ! echo "$out" | jq -e 'type == "object"' >/dev/null 2>&1; then
        log "  unreadable scan output for $img"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES="${FAILURES}
- \`${img}\` (unreadable scan output)"
        continue
    fi
    c=$(echo "$out" | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' 2>/dev/null || echo 0)
    h=$(echo "$out" | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' 2>/dev/null || echo 0)
    if [ -n "$CRIT_TMP" ]; then
        name=$(report_name "$img")
        if ! echo "$out" | jq -r --arg img "$name" \
            '.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL") | [$img, .VulnerabilityID, .PkgName] | @tsv' \
            >> "$CRIT_TMP" 2>/dev/null; then
            log "  WARN: could not list CRITICAL findings of $img for the report"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    fi

    if [ "$((c + h))" -gt 0 ]; then
        FINDINGS="${FINDINGS}
- \`${img}\` — **${c}** crit / **${h}** high"
        TOTAL_C=$((TOTAL_C + c))
        TOTAL_H=$((TOTAL_H + h))
    fi
done

log "Done. Total: $TOTAL_C critical, $TOTAL_H high."

# ---- Machine-readable report (optional) ----
# Best-effort: a report problem never blocks the Discord notification. Unique
# temp names so a manual run and the scheduled one cannot share them; the
# reader matches critical_sha256 against critical.tsv.
if [ -n "$REPORT_DIR" ]; then
    DB_UPDATED=$(trivy version --format json 2>/dev/null | jq -r '.VulnerabilityDB.UpdatedAt // empty' 2>/dev/null)
    if mkdir -p "$REPORT_DIR" 2>/dev/null && [ -w "$REPORT_DIR" ] \
        && TSV_TMP=$(mktemp "$REPORT_DIR/.critical.XXXXXX") \
        && JSON_TMP=$(mktemp "$REPORT_DIR/.last-scan.XXXXXX") \
        && sort -u "$CRIT_TMP" > "$TSV_TMP" \
        && TSV_SHA=$(sha256sum "$TSV_TMP" | cut -d' ' -f1) \
        && jq -n --arg finished "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
            --argjson images "$IMG_COUNT" --argjson failed "$FAIL_COUNT" \
            --argjson critical "$TOTAL_C" --argjson high "$TOTAL_H" \
            --arg db "$DB_UPDATED" --arg sha "$TSV_SHA" \
            '{finished_at: $finished, images: $images, failed: $failed, critical: $critical, high: $high, db_updated_at: $db, critical_sha256: $sha}' \
            > "$JSON_TMP" \
        && chmod 644 "$TSV_TMP" "$JSON_TMP" \
        && mv -f "$TSV_TMP" "$REPORT_DIR/critical.tsv" \
        && mv -f "$JSON_TMP" "$REPORT_DIR/last-scan.json"; then
        log "Report written to $REPORT_DIR"
    else
        log "WARN: could not write the report to $REPORT_DIR"
        rm -f "${TSV_TMP:-}" "${JSON_TMP:-}"
    fi
fi

# ---- Decide whether to notify ----
DOW=$(date +%u)
HAS_FINDINGS=0
if [ -n "$FINDINGS" ] || [ -n "$FAILURES" ]; then
    HAS_FINDINGS=1
fi

if [ "$HAS_FINDINGS" = "0" ] && [ "$DOW" != "$HEARTBEAT_DOW" ]; then
    log "No CRITICAL/HIGH findings, not heartbeat day. Skipping notification."
    exit 0
fi

# ---- Build notification ----
if [ "$HAS_FINDINGS" = "0" ]; then
    TITLE="[${SCANNER_HOST}] Trivy weekly heartbeat - $DATE"
    DESCRIPTION="**Weekly heartbeat** — scanned ${IMG_COUNT} images, **0 critical / 0 high** findings."
    COLOR=3066993  # green
else
    TITLE="[${SCANNER_HOST}] Trivy daily scan - $DATE"
    DESCRIPTION="**Total**: ${TOTAL_C} critical / ${TOTAL_H} high across ${IMG_COUNT} images"
    [ -n "$FINDINGS" ] && DESCRIPTION="${DESCRIPTION}

**Findings**:${FINDINGS}"
    [ -n "$FAILURES" ] && DESCRIPTION="${DESCRIPTION}

**Scan failures**:${FAILURES}"

    if [ "$TOTAL_C" -gt 0 ]; then
        COLOR=15158332   # red
    elif [ "$TOTAL_H" -gt 0 ]; then
        COLOR=15105570   # orange
    else
        COLOR=9807270    # gray (only failures, no CVEs)
    fi
fi

# ---- Truncate description (line-aware, Discord limit is 4096 chars) ----
# awk keeps whole lines while cumulative bytes stay under budget; never cuts mid-line.
DESC_LEN=$(printf '%s' "$DESCRIPTION" | wc -c)
if [ "$DESC_LEN" -gt 3900 ]; then
    DESCRIPTION=$(printf '%s' "$DESCRIPTION" | awk -v max=3700 '
        { n += length + 1; if (n > max) exit; print }
    ')
    DESCRIPTION="${DESCRIPTION}

*(truncated; see Ofelia logs for full report)*"
fi

# ---- Send to Discord ----
if [ ! -f "$WEBHOOK_FILE" ] || [ ! -s "$WEBHOOK_FILE" ]; then
    log "ERROR: webhook file missing/empty but notification needed - report below"
    printf '%s\n%s\n' "$TITLE" "$DESCRIPTION"
    exit 2
fi

WEBHOOK=$(tr -d '[:space:]' < "$WEBHOOK_FILE")
if [ -z "$WEBHOOK" ]; then
    log "ERROR: webhook file contains only whitespace"
    exit 2
fi

PAYLOAD=$(jq -n \
    --arg title "$TITLE" \
    --arg desc "$DESCRIPTION" \
    --argjson color "$COLOR" \
    '{embeds: [{title: $title, description: $desc, color: $color}]}')

RESP_FILE=$(mktemp)
trap 'rm -f "$RESP_FILE" "$ERR_TMP" ${CRIT_TMP:+"$CRIT_TMP"}' EXIT

HTTP_CODE=$(curl -s --max-time 15 -o "$RESP_FILE" -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$WEBHOOK")

if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
    log "Discord notification sent (HTTP $HTTP_CODE)"
    exit 0
else
    log "ERROR: Discord webhook failed: HTTP $HTTP_CODE"
    cat "$RESP_FILE" 2>/dev/null
    exit 2
fi
