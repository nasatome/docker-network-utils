#!/bin/sh
# scan.sh - Daily Trivy vulnerability scan with Discord notification
#
# Behavior:
#   - Reads /etc/trivy-scanner/images.txt for allowlist (uncommented lines)
#   - If allowlist is empty, auto-discovers images from running containers
#   - Scans each image for CRITICAL and HIGH CVEs
#   - Posts Discord embed when findings exist OR on weekly heartbeat day (Mon)
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
FINDINGS=""
FAILURES=""
for img in $IMAGES; do
    log "Scanning $img"
    out=$(trivy image --quiet --skip-db-update --severity CRITICAL,HIGH \
        --format json "$img" 2>/dev/null) || {
        log "  scan failed for $img"
        FAILURES="${FAILURES}
- \`${img}\` (scan failed)"
        continue
    }
    c=$(echo "$out" | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' 2>/dev/null || echo 0)
    h=$(echo "$out" | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' 2>/dev/null || echo 0)

    if [ "$((c + h))" -gt 0 ]; then
        FINDINGS="${FINDINGS}
- \`${img}\` — **${c}** crit / **${h}** high"
        TOTAL_C=$((TOTAL_C + c))
        TOTAL_H=$((TOTAL_H + h))
    fi
done

log "Done. Total: $TOTAL_C critical, $TOTAL_H high."

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
trap 'rm -f "$RESP_FILE"' EXIT

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
