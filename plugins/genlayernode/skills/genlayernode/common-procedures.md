# Common Procedures

Shared commands and procedures used by both install and update workflows.

## Download & Extract Node Software

```bash
# Fetch latest version automatically
VERSION=$(curl -s "https://storage.googleapis.com/storage/v1/b/gh-af/o?prefix=genlayer-node/bin/amd64" | \
  grep -o '"name": *"[^"]*"' | sed -n 's/.*\/\(v[^/]*\)\/.*/\1/p' | sort -Vr | head -1)

# Or set specific version manually
# VERSION=v0.4.4

# Download tarball to /tmp
wget https://storage.googleapis.com/gh-af/genlayer-node/bin/amd64/${VERSION}/genlayer-node-linux-amd64-${VERSION}.tar.gz \
  -O /tmp/genlayer-node-${VERSION}.tar.gz

# Create version directory
sudo mkdir -p /opt/genlayer-node/${VERSION}

# Extract
sudo tar -xzvf /tmp/genlayer-node-${VERSION}.tar.gz \
  -C /opt/genlayer-node/${VERSION} --strip-components=1

# Set ownership
sudo chown -R $USER:$USER /opt/genlayer-node/${VERSION}
```

## GenVM Setup

Downloads GenVM binaries (genvm and genvm-modules).

```bash
python3 /opt/genlayer-node/${VERSION}/third_party/genvm/bin/setup.py
```

**Wait for completion before proceeding.**

## Enable LLM Provider

The LLM provider must be enabled in GenVM config. By default, all providers are disabled.

**Provider mapping:**
| Environment Variable | Config Name |
|---------------------|-------------|
| `HEURISTKEY` | heurist |
| `ANTHROPICKEY` | anthropic |
| `GEMINIKEY` | google |
| `COMPUT3KEY` | comput3 |
| `IOINTELLIGENCEKEY` | ionet |
| `LIBERTAI_API_KEY` | libertai |

```bash
# Replace <provider> with your provider name from the table above
sed -i '/^  <provider>:/,/^  [a-z]/ s/enabled: false/enabled: true/' \
  /opt/genlayer-node/${VERSION}/third_party/genvm/config/genvm-module-llm.yaml
```

**Verify it's enabled:**
```bash
grep -A2 '<provider>:' /opt/genlayer-node/${VERSION}/third_party/genvm/config/genvm-module-llm.yaml
# Should show: enabled: true
```

## Create Directory Structure

```bash
# Create data and config directories
mkdir -p /opt/genlayer-node/${VERSION}/data/node
mkdir -p /opt/genlayer-node/${VERSION}/configs/node
```

## Setup Symlinks

Symlinks provide a stable path (`/opt/genlayer-node/bin`) that points to the current version.

```bash
cd /opt/genlayer-node
ln -sfn ${VERSION}/bin bin
ln -sfn ${VERSION}/third_party third_party
ln -sfn ${VERSION}/data data
ln -sfn ${VERSION}/configs configs
ln -sfn ${VERSION}/docker-compose.yaml docker-compose.yaml
ln -sfn ${VERSION}/.env .env
ln -sfn ${VERSION}/alloy-config.river alloy-config.river
```

> **Note:** `alloy-config.river` ships with the node tarball. It must be symlinked like all other
> version-specific files so docker-compose can find it at the root level. After switching symlinks
> during an upgrade, restart Alloy to pick up the new config: `docker restart genlayer-node-alloy`

**After symlinks, you can use:**
- `/opt/genlayer-node/bin/genlayernode` instead of `/opt/genlayer-node/v0.4.4/bin/genlayernode`
- `/opt/genlayer-node/.env` instead of `/opt/genlayer-node/v0.4.4/.env`

## Start WebDriver

WebDriver is required for web-based contract operations.

```bash
cd /opt/genlayer-node
docker compose up -d

# Wait for healthy status
until docker inspect --format='{{.State.Health.Status}}' genlayer-node-webdriver 2>/dev/null | grep -q 'healthy'; do
  echo "Waiting for WebDriver..."
  sleep 2
done
echo "WebDriver is healthy!"
```

**If WebDriver fails to start:**
```bash
# Check for existing container conflict
docker ps -a | grep webdriver

# Remove old container if exists
docker rm -f genlayer-node-webdriver

# Retry
docker compose up -d
```

## Doctor Check

Verifies all configuration is correct before starting the node.

```bash
cd /opt/genlayer-node/${VERSION}
set -a && source .env && set +a
./bin/genlayernode doctor
```

**Expected output:**
```
✓ GenLayer Chain RPC: Connected
✓ GenLayer Chain WebSocket: Connected
✓ Validator Wallet Configuration: OK
✓ GenVM Binaries: Found
✓ WebDriver: Successfully rendered test page
All configuration checks passed!
```

**Note:** Use `set -a && source .env && set +a` to properly export environment variables. Plain `source .env` does not export them.

## Verification Commands

**Check service status:**
```bash
sudo systemctl status genlayer-node
```

**Check node version:**
```bash
curl -s http://localhost:9153/health | jq '.node_version'
```

**Check sync status:**
```bash
curl -s http://localhost:9153/health | jq '.checks.validating'
```

**View logs:**
```bash
sudo journalctl -u genlayer-node -f --no-hostname
```

**Check current sync block:**
```bash
sudo journalctl -u genlayer-node -n 5 --no-pager | grep "blockNumber="
```

**Get latest block from chain:**
```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  https://YOUR-RPC-URL/rpc | jq -r '.result' | xargs printf "%d\n"
```

## Systemd Service

**Service file location:** `/etc/systemd/system/genlayer-node.service`

```ini
[Unit]
Description=GenLayer Node
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/genlayer-node
EnvironmentFile=/opt/genlayer-node/.env
ExecStart=/opt/genlayer-node/bin/genlayernode run --password ${NODE_PASSWORD}
ExecStartPost=-/bin/sh -c 'sleep 5 && /usr/bin/docker restart genlayer-node-alloy 2>/dev/null || true'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

> **Note:** The `ExecStartPost` line automatically restarts the Alloy telemetry container
> whenever the node starts. This is required because Alloy's bind mount to the log directory
> becomes stale when symlinks change during upgrades. The `-` prefix means systemd will
> ignore failures (e.g., if Alloy isn't installed). See `sharp-edges.yaml` -> `alloy-stale-bind-mount`.

**Commands:**
```bash
# Reload after creating/modifying service file
sudo systemctl daemon-reload

# Enable auto-start on boot
sudo systemctl enable genlayer-node

# Start/stop/restart
sudo systemctl start genlayer-node
sudo systemctl stop genlayer-node
sudo systemctl restart genlayer-node

# Check status
sudo systemctl status genlayer-node
```

## Alloy Telemetry Management

Alloy is the telemetry agent that sends logs and metrics to Grafana Cloud.

**Restart Alloy (required after node restarts):**
```bash
docker restart genlayer-node-alloy
```

**Check Alloy status:**
```bash
docker ps | grep alloy
docker logs genlayer-node-alloy 2>&1 | tail -10
```

**Verify bind mount is fresh (not stale):**
```bash
# Compare timestamps - they should match
echo "Host:" && ls -la /opt/genlayer-node/data/node/logs/node.log | awk '{print $6,$7,$8}'
echo "Container:" && docker exec genlayer-node-alloy ls -la /var/log/genlayer/node.log | awk '{print $6,$7,$8}'
```

> **IMPORTANT:** Alloy's bind mount becomes stale when the node restarts and symlinks change.
> This is why the systemd service includes `ExecStartPost` to auto-restart Alloy.
> If timestamps don't match, logs are NOT being sent to Grafana.
> See `sharp-edges.yaml` -> `alloy-stale-bind-mount` for details.

## Common Issues

### Environment Variables Not Loaded
**Symptom:** Doctor check fails, commands don't see env vars.
**Fix:** Use `set -a` before sourcing:
```bash
set -a && source .env && set +a
```

### LLM Provider Not Enabled
**Symptom:** Node fails with "module_failed_to_start" error.
**Fix:** Enable your provider in GenVM config (see "Enable LLM Provider" above).

### WebDriver Container Conflict
**Symptom:** `docker compose up -d` fails with name conflict.
**Fix:**
```bash
docker rm -f genlayer-node-webdriver
docker compose up -d
```

### Database Symlink Error (Fresh Install)
**Symptom:** "mkdir genlayer.db: file exists" error.
**Fix:** Remove dangling symlink:
```bash
rm /opt/genlayer-node/${VERSION}/data/node/genlayer.db
```
Fresh installs don't have a shared database to link to.

### Alloy Not Sending Logs After Upgrade
**Symptom:** Node is running and healthy, but Grafana shows no logs/metrics. Validator appears offline in monitoring.
**Cause:** Alloy's bind mount to the log directory became stale when symlinks changed during upgrade.
**Fix:**
```bash
docker restart genlayer-node-alloy
```
**Prevention:** The systemd service should include `ExecStartPost` to auto-restart Alloy. See the Systemd Service section above.
