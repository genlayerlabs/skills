# GenLayer Validator Monitoring Setup Procedure

## Goal
Enable centralized monitoring by pushing metrics and logs to GenLayer Foundation's Grafana Cloud using Alloy.

## Process Overview

```mermaid
flowchart TD
    subgraph Prerequisites
        A[Node Running & Synced<br/>Port 9153 up] --> B[Request Creds<br/>GenLayer Foundation team]
        B --> C[Receive 4 credentials<br/>Prom + Loki user/pass]
    end

    subgraph Configuration
        C --> D[Step 2: Configure .env<br/>Set credentials + NODE_ID]
        D --> E[Step 3: Test Credentials<br/>curl → HTTP 400/204]
    end

    subgraph Deployment
        E --> F[Step 4: Start Alloy<br/>docker compose --profile monitoring up -d]
        F --> G[Step 5: Verify<br/>Check logs + Alloy UI]
    end
```

## Prerequisites

Before enabling monitoring:

1. **Node must be running** and accessible on ops port (default 9153)
2. **Ops port reachable** (`node.ops.port`, default 9153). In v0.6 the ops server always serves
   `/metrics`; the `node.ops.endpoints.metrics` switch is compatibility metadata only.
3. **Verify local metrics available:**
   ```bash
   curl -s http://localhost:9153/metrics | head -20
   # Should return Prometheus-formatted metrics (genlayer_node_*)
   ```

## What Ships With the Node Tarball

The node tarball (v0.6) **already includes** everything needed for monitoring:

- **`alloy-config.river`** — Full Alloy configuration for log collection and metrics forwarding
- **`docker-compose.yaml`** — Includes the Alloy service (and the read-only `docker-socket-proxy`
  Alloy uses for container discovery) under the `monitoring` profile
- **`alloy-healthcheck.sh`** — Alloy container health check
- **`.env.example`** — Includes all monitoring environment variable placeholders

**You do NOT need to create these files manually.** The `alloy-config.river` symlink is created
automatically during installation/upgrade as part of the standard symlink setup (see `common-procedures.md` -> "Setup Symlinks"). You only need to:
1. Set credentials in `.env`
2. Start the monitoring profile

## Step 1: Request Credentials

**Credentials must be requested from the GenLayer Foundation team.**

1. Contact the GenLayer Foundation team (GenLayer Discord, validator channels)
2. Request monitoring endpoints and credentials for your network
3. See also https://docs.genlayer.com/validators/monitoring
4. You will receive **4 credential values** (Prometheus and Loki have separate auth):
   - **Prometheus** instance ID and API key (for metrics)
   - **Loki** instance ID and API key (for logs)

**IMPORTANT**: Prometheus and Loki use **different usernames** (instance IDs) in Grafana Cloud. They are separate services with separate credentials.

## Step 2: Configure Environment

Edit `.env` on the server to set the monitoring variables:

```bash
sudo nano /opt/genlayer-node/.env
```

**Set these values:**

```bash
# Monitoring URLs — empty in .env.example on purpose (no default endpoint); use the values
# the Foundation gives you (the two URLs below are an example). Alloy stops with
# "ERROR: not set: ..." if any of the six is empty.
CENTRAL_MONITORING_URL=https://prometheus-prod-66-prod-us-east-3.grafana.net/api/prom/push
CENTRAL_LOKI_URL=https://logs-prod-042.grafana.net/loki/api/v1/push

# Prometheus credentials (for metrics)
CENTRAL_MONITORING_USERNAME=<Prometheus instance ID>
CENTRAL_MONITORING_PASSWORD=<API key - starts with glc_>

# Loki credentials (for logs)
CENTRAL_LOKI_USERNAME=<Loki instance ID>
CENTRAL_LOKI_PASSWORD=<API key - starts with glc_>

# Node identification (set these yourself)
NODE_ID=0xYourValidatorWalletAddress
VALIDATOR_NAME=your-validator-name
# Network label for recovery logs and alert routing, e.g. bradbury-phase2 (leave empty rather than guess)
NETWORK_NAME=
```

**Important notes:**
- `NODE_ID` — Use your validator wallet address (e.g., `0x1451c990fa6Fa23Bc2773266Fa022cBb369cE165`);
  a full node has none — use a stable unique name (e.g., `fullnode-eu-1`)
- `VALIDATOR_NAME` — A short identifier for your validator (no spaces, e.g., `my-validator-1`)
- URLs should NOT have trailing slashes
- `CENTRAL_MONITORING_USERNAME` and `CENTRAL_LOKI_USERNAME` are typically **different** numeric IDs
- The password (API key) **may** be the same for both, but verify with your Foundation credentials

**Optional settings (defaults are usually fine):**
```bash
NODE_METRICS_ENDPOINT=host.docker.internal:9153
LOG_FILE_PATTERN=/var/log/genlayer/node*.log
METRICS_SCRAPE_INTERVAL=60s
METRICS_SCRAPE_TIMEOUT=10s
ALLOY_SELF_MONITORING_INTERVAL=60s
```

## Step 3: Test Credentials Before Starting

**CRITICAL**: Always test credentials before starting Alloy to avoid spamming error logs.

```bash
# Reads .env as the service user; credentials go to curl on stdin (-K -), never on a
# command line (visible in the process list). Prints only HTTP codes.
sudo -u genlayer bash -c '
set -a; . /opt/genlayer-node/.env; set +a

# Test Prometheus (metrics) — expect HTTP 400 (auth OK, empty body rejected)
echo "=== Prometheus ==="
printf "user = \"%s:%s\"\n" "$CENTRAL_MONITORING_USERNAME" "$CENTRAL_MONITORING_PASSWORD" | \
  curl -s -K - -o /dev/null -w "HTTP %{http_code}\n" -X POST "$CENTRAL_MONITORING_URL"

# Test Loki (logs) — expect HTTP 204 (auth OK, no content)
echo "=== Loki ==="
printf "user = \"%s:%s\"\n" "$CENTRAL_LOKI_USERNAME" "$CENTRAL_LOKI_PASSWORD" | \
  curl -s -K - -o /dev/null -w "HTTP %{http_code}\n" -X POST "$CENTRAL_LOKI_URL" \
    -H "Content-Type: application/json" --data-raw "{}"
'
```

**Expected results:**
| Endpoint | HTTP Code | Meaning |
|----------|-----------|---------|
| Prometheus | **400** | Auth succeeded, empty body rejected (expected) |
| Loki | **204** | Auth succeeded, no content (expected) |
| Either | **401** | Auth failed — wrong username or password |
| Either | **403** | Forbidden — API key lacks required scope |

**Do NOT proceed until both return non-401 codes.**

## Step 4: Start Alloy

> **Note:** The `alloy-config.river` symlink is created automatically during installation/upgrade
> as part of the standard symlink setup (see `common-procedures.md` -> "Setup Symlinks").
> The file ships with every node tarball — you do NOT need to create or copy it manually.
> The docker-compose.yaml mounts `./alloy-config.river` from the working directory (`/opt/genlayer-node/`),
> which resolves through the symlink to the current version's config.

```bash
cd /opt/genlayer-node
docker compose --profile monitoring up -d
```

**First run will pull the Alloy image** (`grafana/alloy:v1.12.0`, ~150MB).

Verify Alloy is running:
```bash
docker ps | grep alloy
```

Expected:
```
genlayer-node-alloy  grafana/alloy:v1.12.0  ... Up ... 0.0.0.0:12345->12345/tcp
```

## Step 5: Verification

### 5.1 Check Alloy Logs (Most Important)

```bash
# Check for any errors (should be empty)
docker logs genlayer-node-alloy 2>&1 | grep -i "error\|401\|403"

# Check Prometheus status — look for "Done replaying WAL"
docker logs genlayer-node-alloy 2>&1 | grep "Done replaying WAL"

# Check Loki status — look for "tail routine: started"
docker logs genlayer-node-alloy 2>&1 | grep "tail routine: started"
```

**Healthy output (no errors):**
```
Done replaying WAL ... duration=12.8s
tail routine: started ... path=/var/log/genlayer/node.log
```

**Unhealthy output (401 spam):**
```
error="server returned HTTP status 401 Unauthorized"
```
If you see 401 errors, stop Alloy, fix credentials, test with curl, then restart.

### 5.2 Check Alloy UI

Via SSH tunnel:
```bash
# For GCP:
gcloud compute ssh INSTANCE --zone=ZONE --project=PROJECT -- -L 12345:localhost:12345

# For SSH:
ssh -L 12345:localhost:12345 user@your-server
```

Then open `http://localhost:12345` in your browser. The targets page should show `genlayer_node` target as **UP**.

### 5.3 Verify Local Metrics

```bash
curl -s http://localhost:9153/metrics | grep genlayer_node | head -10
```

### 5.3b Verify Alloy Is Actually Pushing

A running Alloy with no errors can still push nothing. Read its own counters twice, a minute apart:

```bash
ALLOY_IP=$(sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' genlayer-node-alloy | awk '{print $1}')
curl -s http://${ALLOY_IP}:12345/metrics | \
  grep -E '^(loki_write_(sent_entries|dropped_entries)_total|prometheus_remote_storage_samples_(total|failed_total|dropped_total))'
```

- `loki_write_sent_entries_total` and `prometheus_remote_storage_samples_total` must **increase**
  between the two reads.
- `loki_write_dropped_entries_total`, `prometheus_remote_storage_samples_failed_total` and
  `prometheus_remote_storage_samples_dropped_total` must stay **0**.

If the sent counters are flat, see "Alloy Exited or Not Pushing After an Upgrade" below.

### 5.4 Check Foundation Dashboard

Once metrics are flowing, your validator should appear on the GenLayer Foundation dashboard:

**Dashboard URL:** https://genlayerfoundation.grafana.net/public-dashboards/66a372d856ea44e78cf9ac21a344f792

Search for your validator using:
- `instance="0xYourValidatorWallet"`
- `validator_name="your-validator-name"`

## Troubleshooting

### Authentication Errors (401/403)
**Symptom:** Alloy logs show `server returned HTTP status 401 Unauthorized` spam.
```bash
docker logs genlayer-node-alloy 2>&1 | grep -c "401"
```

**Root causes:**
1. Wrong username or password in `.env`
2. Prometheus and Loki credentials mixed up (they use **different** instance IDs)
3. API key lacks required scope (`metrics:write` for Prometheus, `logs:write` for Loki)

**Fix:**
1. Stop Alloy: `docker compose --profile monitoring down`
2. Fix credentials in `.env`
3. Test with curl (Step 3 above)
4. Restart: `docker compose --profile monitoring up -d`

### Alloy Config File Not Found
**Symptom:** Alloy container fails to start.
```bash
docker logs genlayer-node-alloy 2>&1 | head -10
```

**Fix:** The `alloy-config.river` symlink should already exist from the install/upgrade symlink setup (see `common-procedures.md` -> "Setup Symlinks"). If missing, recreate it:
```bash
ln -sfn /opt/genlayer-node/${VERSION}/alloy-config.river /opt/genlayer-node/alloy-config.river
```

### No Data Being Pushed (No Errors Either)
**Symptom:** No errors in logs but no data on dashboard.
```bash
# Check if Alloy can reach the node metrics endpoint
docker exec genlayer-node-alloy wget -qO- http://host.docker.internal:9153/metrics | head -5
```

**Fix:** Ensure node is running, `extra_hosts` is in docker-compose.yaml, and `NODE_METRICS_ENDPOINT` is `host.docker.internal:9153` (not `localhost`).

### Alloy Exited or Not Pushing After an Upgrade
**Symptoms (any of):**
- After a v0.5 -> v0.6 fresh install, `docker ps -a` shows `genlayer-node-alloy` as `Exited (0)`;
  the systemd `ExecStartPost` `docker restart` does not bring it back on the new layout, and
  telemetry is silently down.
- Alloy logs `error writing positions file ... no such file or directory` or `error tailing WAL`:
  its storage directory (`/var/lib/alloy/data` inside the container) is gone, and it pushes
  nothing.

```bash
sudo docker ps -a --filter name=genlayer-node-alloy --format '{{.Status}}'
sudo docker logs --tail 50 genlayer-node-alloy 2>&1 | grep -E 'positions file|tailing WAL'
```

**Fix:** recreate the container from the current version's compose file, as root, on the **real**
Docker socket. The read-only docker-socket-proxy answers image and create calls with 403, so
unset `DOCKER_HOST` if it points at the proxy:
```bash
cd /opt/genlayer-node && sudo bash -c 'unset DOCKER_HOST; set -a; . ./.env; set +a; docker compose --profile monitoring up -d --force-recreate alloy'
```
Then confirm the push counters increase (Step 5.3b).

### Changed NODE_ID or VALIDATOR_NAME
`NODE_ID` / `VALIDATOR_NAME` feed the Loki and Prometheus `instance` label. Changing either starts
a new series: saved queries and dashboards on the old name go blank while the data lives under the
new one. Keep them stable, or update saved queries.

### Connection Refused to Node Metrics
**Symptom:** Alloy logs show connection refused errors.

**Fix:** Check that:
- Node is running on port 9153: `curl http://localhost:9153/metrics`
- `extra_hosts` is configured in docker-compose.yaml (maps `host.docker.internal` to the host)
- The `NODE_METRICS_ENDPOINT` env var uses `host.docker.internal:9153` (Alloy runs inside Docker, so `localhost` won't reach the host node)

### URL Format
**Fix:** Ensure URLs in `.env` match this format (no trailing slashes):
```bash
# Correct
CENTRAL_MONITORING_URL=https://prometheus-prod-66-prod-us-east-3.grafana.net/api/prom/push
CENTRAL_LOKI_URL=https://logs-prod-042.grafana.net/loki/api/v1/push

# Wrong (trailing slash)
CENTRAL_MONITORING_URL=https://prometheus-prod-66.../api/prom/push/
```

## Environment Variables Reference

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `CENTRAL_MONITORING_URL` | Yes | Prometheus remote write URL | `https://prometheus-prod-66-...grafana.net/api/prom/push` |
| `CENTRAL_LOKI_URL` | Yes | Loki log push URL | `https://logs-prod-042.grafana.net/loki/api/v1/push` |
| `CENTRAL_MONITORING_USERNAME` | Yes | Prometheus instance ID (numeric) | `1234567` |
| `CENTRAL_MONITORING_PASSWORD` | Yes | Prometheus API key | `glc_xxxxx...` |
| `CENTRAL_LOKI_USERNAME` | Yes | Loki instance ID (numeric, **different** from Prometheus) | `9876543` |
| `CENTRAL_LOKI_PASSWORD` | Yes | Loki API key | `glc_xxxxx...` |
| `NODE_ID` | Yes | Validator wallet address (full node: a stable unique name) | `0x1451c990...` |
| `VALIDATOR_NAME` | Yes | Short validator name (no spaces) | `my-validator-1` |
| `NETWORK_NAME` | No | Network label for recovery logs / alert routing | `bradbury-phase2` |
| `NODE_METRICS_ENDPOINT` | No | Node metrics address | `host.docker.internal:9153` |
| `LOG_FILE_PATTERN` | No | Log file glob pattern | `/var/log/genlayer/node*.log` |
| `METRICS_SCRAPE_INTERVAL` | No | How often to scrape metrics | `60s` (v0.6 default) |
| `METRICS_SCRAPE_TIMEOUT` | No | Scrape timeout | `10s` |
| `ALLOY_SELF_MONITORING_INTERVAL` | No | Alloy self-health check interval | `60s` |

## Stopping / Restarting Monitoring

```bash
# Stop Alloy only (node keeps running)
docker compose --profile monitoring down

# Restart Alloy
docker compose --profile monitoring up -d

# View Alloy logs
docker logs -f genlayer-node-alloy

# WARNING: 'docker compose down' without --profile stops ALL containers including WebDriver
# Always use --profile monitoring to only affect Alloy
```

## Important: Alloy Must Restart When Node Restarts

**CRITICAL**: When the genlayer-node service restarts (during upgrades or otherwise), Alloy's
bind mount to the log directory becomes stale. The container continues reading from the old
log path, and **no new logs are sent to Grafana**.

**Symptoms of stale bind mount:**
- Node is running and healthy (`curl localhost:9153/health` returns OK)
- But Grafana shows no logs/metrics for this validator
- Validator appears offline in monitoring dashboards
- May lead to heartbeat failures and validator banning

**Solution:** The systemd service should include `ExecStartPost` to auto-restart Alloy:
```ini
ExecStartPost=-+/bin/sh -c 'sleep 5 && /usr/bin/docker restart genlayer-node-alloy 2>/dev/null || true'
```

If your existing systemd service doesn't have this line, add it:
```bash
# Edit the service file
sudo nano /etc/systemd/system/genlayer-node.service

# Add after ExecStart line:
# ExecStartPost=-+/bin/sh -c 'sleep 5 && /usr/bin/docker restart genlayer-node-alloy 2>/dev/null || true'

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart genlayer-node
```

**Manual fix (if Alloy is already stale):**
```bash
docker restart genlayer-node-alloy
```

`docker restart` reuses the existing container. If that container is `Exited` after a fresh
install, or its storage directory is gone, a restart cannot fix it: recreate it (see "Alloy Exited
or Not Pushing After an Upgrade").

See `sharp-edges.yaml` -> `alloy-stale-bind-mount` for detailed explanation.
