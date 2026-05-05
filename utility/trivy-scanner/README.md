# Trivy Scanner

Daily vulnerability scan of running Docker images with Discord notifications.

## What it does

- Runs every day at 06:00 (CDMX timezone) via Ofelia cron daemon
- Scans images for CRITICAL and HIGH severity CVEs using Trivy
- Posts a Discord embed with findings when there is something to report
- Sends a weekly heartbeat (Mondays) even when no findings, so you know the scanner is alive
- Auto-discovers images from running containers, or uses an explicit allowlist

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Ofelia daemon + shared trivy-cache volume |
| `ofelia.ini` | Cron job definition (06:00 daily) |
| `scripts/scan.sh` | Scan + notification logic |
| `images.txt` | Optional allowlist (one image per line) |
| `.discord-webhook` | Webhook URL (gitignored) |

## Setup

```bash
# 1. Create Discord webhook URL file (chmod 600 because it grants posting access)
cp .discord-webhook.example .discord-webhook
$EDITOR .discord-webhook
chmod 600 .discord-webhook

# 2. Ensure shared cache volume exists (one-time)
docker volume create trivy-cache

# 3. Start the daemon
docker compose up -d
```

## Manual scan (testing)

```bash
docker compose exec trivy-scanner /scripts/scan.sh
```

The runner container (`trivy-scanner-runner`) stays up sleeping; Ofelia uses `docker exec` to trigger the scan on schedule. Manual exec uses the same container, so behavior matches the scheduled run exactly.

## Customization

- **Schedule**: edit `ofelia.ini`, run `docker compose restart ofelia`.
- **Images**: uncomment lines in `images.txt` to use a fixed allowlist instead of auto-discovery.
- **Severity threshold**: edit `--severity CRITICAL,HIGH` in `scripts/scan.sh`.
- **Heartbeat day**: edit `HEARTBEAT_DOW` in `scripts/scan.sh` (1=Mon, 7=Sun). Set to `0` to disable.
- **Trivy version**: bump `FROM aquasec/trivy:X.Y.Z` in `Dockerfile`, then `docker compose up -d --build trivy-scanner`.
- **Hostname in Discord embed**: by default reads `/etc/hostname` from the host. Override per-host by uncommenting `SCANNER_HOST=...` in `docker-compose.yml`.
