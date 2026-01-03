# Traefik Reverse Proxy

## Security: Cloudflare Trusted IPs

This setup only trusts X-Forwarded-* headers from Cloudflare IPs, preventing IP spoofing attacks.

### How it works

1. `traefik.yml` contains the trusted IP ranges (static config)
2. Ofelia cron updates IPs weekly from [Cloudflare's official list](https://www.cloudflare.com/ips/)
3. Traefik is restarted automatically to apply changes

> **Note**: `forwardedHeaders.trustedIPs` is static configuration in Traefik. Changes require a restart (~5 seconds downtime).

### Manual update

```bash
# Download and apply new IPs manually
curl -sf https://www.cloudflare.com/ips-v4 && curl -sf https://www.cloudflare.com/ips-v6
docker compose restart traefik
```

---

## Ofelia: Docker Job Scheduler

[Ofelia](https://github.com/mcuadros/ofelia) runs scheduled jobs in Docker containers. Configuration is in `ofelia.ini`.

### Schedule Format

```
seconds minutes hours day-of-month month day-of-week
```

| Field | Values |
|-------|--------|
| seconds | 0-59 |
| minutes | 0-59 |
| hours | 0-23 |
| day-of-month | 1-31 |
| month | 1-12 |
| day-of-week | 0-6 (Sunday=0) |

### Examples

| Schedule | Meaning |
|----------|---------|
| `0 0 18 * * 0` | Every Sunday at 6:00 PM |
| `0 0 0 * * *` | Every day at midnight |
| `0 30 * * * *` | Every hour at :30 |
| `0 0 6 1 * *` | First day of month at 6:00 AM |

### Job Types

**job-run**: Creates a NEW container for each execution (recommended for most tasks)
```ini
[job-run "my-job"]
schedule = 0 0 0 * * *
image = alpine:latest
command = echo "Hello from new container"
```

**job-exec**: Runs command in an EXISTING container
```ini
[job-exec "my-job"]
schedule = 0 0 0 * * *
container = my-container-name
command = echo "Hello from existing container"
```

### Adding a New Cron Job

1. Edit `ofelia.ini`:
```ini
[job-run "my-new-job"]
schedule = 0 0 6 * * 1
image = alpine:latest
command = echo "Runs every Monday at 6 AM"
```

2. Apply changes:
```bash
docker compose restart ofelia
```

3. Check logs:
```bash
docker compose logs -f ofelia
```

### Advanced Options

```ini
[job-run "advanced-example"]
schedule = 0 0 0 * * *
image = alpine:latest
network = reverse_traefik              # Connect to Docker network
volume = /host/path:/container/path    # Mount volumes (can repeat)
volume = /another:/path
environment = MY_VAR=value             # Environment variables
command = sh -c 'echo $MY_VAR'
```

### Finding Container by Service Label

Instead of hardcoding container names, use Docker labels:
```bash
docker ps -q -f label=com.docker.compose.service=traefik
```

This finds the container regardless of the compose project name.

### Discord Notifications

To receive alerts when jobs fail, use the included `scripts/notify-discord.sh` helper.

#### Setup

1. Create Discord webhook (Server Settings → Integrations → Webhooks)

2. Save webhook URL:
```bash
echo "https://discord.com/api/webhooks/ID/TOKEN" > .discord-webhook
chmod 600 .discord-webhook
```

#### Usage in Jobs

Mount the scripts directory and call `notify-discord.sh` on failure:

```ini
[job-run "my-job"]
schedule = 0 0 0 * * *
image = alpine:latest
volume = /path/to/.discord-webhook:/etc/discord-webhook:ro
volume = /path/to/scripts:/scripts:ro
command = sh -c 'do_something || /scripts/notify-discord.sh Job failed - error message here'
```

> **Note**: Ofelia's INI parser mangles quoted strings. Use the script to avoid quoting issues with curl/JSON.

#### Script Details

`scripts/notify-discord.sh` accepts the message as arguments:
```bash
/scripts/notify-discord.sh Your message here without quotes
```

The script reads the webhook URL from `/etc/discord-webhook` (mounted from `.discord-webhook`).

---

### Steps for Linux:

1. Exec Commands

*Change the PROJECT_DIR variable to your address, where you normally store projects.*

`export PROJECT_DIR="/opt/prj";`

`mkdir -p $PROJECT_DIR`

`cd $PROJECT_DIR`

`git clone git@github.com:nasatome/docker-network-utils.git`

```
cd docker-network-utils && \
cd reverse-proxy && \
cd traefik
```

```
cp .env.example .env && \
cp .cloudflare-api.key.example .cloudflare-api.key
```
2. Set variables in .env file

3. Change Password var TRAEFIK_BASIC_AUTH_USERS in .env file; You can use this command:

`docker run --rm httpd:2.4-alpine htpasswd -nbB CHANGE_USER CHANGE_PASSWORD; history -d $(history | tail -1 | awk '{print $1}') ; printf "\n\n"`

4. Check DNS KEY (cloudflare-api.key For Cloudflare Example)

Notes: 

For Traefik Help: 
`docker run --rm traefik:2.4 --help | less` 

Providers for Traefik 2.4
`https://doc.traefik.io/traefik/https/acme/#providers`

#### Other providers example: 
In the .env file change the TRAEFIK_DNS_PROVIDER variable: 
For digital ocean

``` 
TRAEFIK_DNS_PROVIDER=digitalocean
```

Create a file with the same name of TRAEFIK_DNS_PROVIDER, example:
`vi .TRAEFIK_DNS_PROVIDER-api.key`

now the file name looks like this `.digitalocean-api.key`

contains: 

```
DO_AUTH_TOKEN=<token_value>
```

5. Finally: Up the docker compose

`docker-compose pull && docker-compose down -v && docker-compose up -d`
