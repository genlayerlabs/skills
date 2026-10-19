# Common Procedures

Shared commands and procedures used by both install and update workflows.

## Download & Extract Node Software

```bash
# Set the exact version approved for your network (release announcement).
# Do not take the newest listed version automatically: it may not be approved yet.
VERSION=v0.6.0

# Download tarball, checksums, signature and install.sh to a temp dir
# (stop on any 404 — never fall back to an older version)
base=https://storage.googleapis.com/gh-af/genlayer-node/bin/amd64/${VERSION}
DL=$(mktemp -d /tmp/genlayer-${VERSION}.XXXX) && chmod 755 "$DL" && cd "$DL"
wget -q ${base}/genlayer-node-linux-amd64-${VERSION}.tar.gz ${base}/genlayer-node_${VERSION}_SHA256SUMS \
        ${base}/genlayer-node_${VERSION}_SHA256SUMS.sigstore.json ${base}/install.sh

# Verify before extracting (stop on any failure; the tarball must be listed in SHA256SUMS)
cosign verify-blob --bundle genlayer-node_${VERSION}_SHA256SUMS.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/genlayerlabs/genlayer-node/\.github/workflows/release-package\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com genlayer-node_${VERSION}_SHA256SUMS \
&& grep -q "[ *]genlayer-node-linux-amd64-${VERSION}.tar.gz$" genlayer-node_${VERSION}_SHA256SUMS \
&& sha256sum -c genlayer-node_${VERSION}_SHA256SUMS --ignore-missing \
|| { echo "VERIFICATION FAILED - stop, do not install" >&2; rm -f install.sh; false; }   # no install.sh: the install below cannot run

# Create version directory, extract and run the GenVM setup (install.sh), as the service user
sudo install -d -o genlayer -g genlayer /opt/genlayer-node
chmod +x install.sh
sudo -u genlayer -H ./install.sh --install-dir /opt/genlayer-node/${VERSION} \
  --tarball genlayer-node-linux-amd64-${VERSION}.tar.gz
```

Details and expected output: `install-procedure.md` Phase 2.

## GenVM Setup

`install.sh` runs it. To run it by hand (for example after a failed setup), use the GenVM tree
that `genvm.root_dir` names, **in the final directory** (it writes absolute paths into the binaries):

```bash
cd /opt/genlayer-node/${VERSION}
GENVM_ROOT=$(readlink -f "$(sed -n 's/^ *root_dir: *//p' configs/node/config.yaml)")
sudo -u genlayer python3 ${GENVM_ROOT}/bin/setup.py
```

It verifies the runners, patches the binaries' interpreter path and precompiles the runners.
**Wait for completion before proceeding.**

## LLM Strategy Selection

The release tarball includes two LLM strategies:
- **default** — Random provider selection from all enabled backends (upstream behavior)
- **greybox** — Deterministic ordered fallback via OpenRouter as primary aggregator

**Ask the user which strategy they want.** This determines the LLM config and required API keys.

### Apply LLM Strategy

```bash
# GenVM config dir of the version being configured (genvm.root_dir in its config.yaml)
GENVM_CFG=$(cd /opt/genlayer-node/${VERSION} && readlink -f "$(sed -n 's/^ *root_dir: *//p' configs/node/config.yaml)")/config

# Step 1: Overlay the release LLM config (includes all backends: openrouter, morpheus, etc.)
cp ${GENVM_CFG}/genvm-modules-llm-release.yaml \
   ${GENVM_CFG}/genvm-module-llm.yaml

# Step 2: If greybox strategy, switch the Lua script path
# (skip this step for default strategy)
sed -i 's/genvm-llm-default\.lua/genvm-llm-greybox.lua/' \
  ${GENVM_CFG}/genvm-module-llm.yaml
```

**Verify:**
```bash
grep lua_script_path ${GENVM_CFG}/genvm-module-llm.yaml
# default:  genvm-llm-default.lua
# greybox:  genvm-llm-greybox.lua
```

**Required keys by strategy:**
| Strategy | Required Key | Optional Keys |
|----------|-------------|---------------|
| default | At least one provider key (HEURISTKEY, COMPUT3KEY, etc.) | Any additional providers |
| greybox | `OPENROUTERKEY` (primary aggregator) | HEURISTKEY, IOINTELLIGENCEKEY (fallback providers) |

## Enable LLM Provider

After applying the LLM strategy, enable providers that have API keys configured.

The release config ships with all providers present but auto-detection depends on the key being set.
For **greybox** strategy, OpenRouter is the primary — ensure `OPENROUTERKEY` is set in `.env`.
For **default** strategy, enable at least one provider.

**Provider mapping:**
| Environment Variable | Config Name |
|---------------------|-------------|
| `HEURISTKEY` | heurist |
| `ANTHROPICKEY` | anthropic |
| `GEMINIKEY` | google |
| `COMPUT3KEY` | comput3 |
| `IOINTELLIGENCEKEY` | ionet |
| `LIBERTAI_API_KEY` | libertai |
| `XAIKEY` | xai |
| `ATOMAKEY` | atoma |
| `OPENROUTERKEY` | openrouter |
| `MORPHEUS_API_KEY` | morpheus |

```bash
# Replace <provider> with your provider name from the table above
sed -i '/^  <provider>:/,/^  [a-z]/ s/enabled: false/enabled: true/' \
  ${GENVM_CFG}/genvm-module-llm.yaml
```

**Verify it's enabled:**
```bash
grep -A2 '<provider>:' ${GENVM_CFG}/genvm-module-llm.yaml
# Should show: enabled: true
```

## Update Greybox Config on Running Node

Update the greybox Lua script and/or LLM YAML config without a full redeploy.
The LLM module must be restarted per GenVM instance — there is no atomic restart.

**Prerequisites:** Node is running, you know which GenVM manager ports are active.

### Step 1: Find GenVM manager ports

```bash
# Each validator runs its own GenVM manager on a different port
# Check the deployed configs for bind addresses:
grep -r bind_address ${GENVM_CFG}/genvm-module-llm.yaml
# Or check active processes:
ss -tlnp | grep genvm
```

### Step 2: Update the files

```bash
GENVM_CONFIG="${GENVM_CFG}"

# Update the Lua script (source of truth: release/genvm-llm-greybox.lua)
# Copy the new version to ALL genvm instance config directories
cp /path/to/new/genvm-llm-greybox.lua ${GENVM_CONFIG}/genvm-llm-greybox.lua

# If also updating the YAML config (new backends, model changes):
cp /path/to/new/genvm-module-llm.yaml ${GENVM_CONFIG}/genvm-module-llm.yaml
```

**Note:** For multi-validator setups (infra deployments), each validator has its own
genvm instance directory. Update the files in ALL instance config dirs, not just the
shared config.

### Step 3: Restart LLM module on each GenVM manager

The Lua script is loaded at LLM module startup, NOT hot-reloaded per call.
You must stop and start the LLM module for changes to take effect.

```bash
# For each GenVM manager port (e.g., 3999, or whatever port is active):
PORT=3999

# Stop the LLM module
curl -X POST "http://127.0.0.1:${PORT}/module/stop" \
  -H 'Content-Type: application/json' \
  -d '{"module_type": "Llm"}'

# Start the LLM module (reloads Lua script and YAML config)
curl -X POST "http://127.0.0.1:${PORT}/module/start" \
  -H 'Content-Type: application/json' \
  -d '{"module_type": "Llm", "config": null}'
```

Repeat for each GenVM manager port. There is no atomic restart — each instance
restarts independently.

### Step 4: Verify

```bash
# Run a transaction that triggers an LLM call, then check logs for:
#   "greybox: success" with the expected provider/model
# The GenVMLog entries appear in the node's structured log per-transaction.
grep "greybox" /opt/genlayer-node/data/node/logs/node.log | tail -5
```

## Create Directory Structure

The tarball ships `configs/node/`. The data directory is shared per minor line and linked from
each version (see `install-procedure.md` Phase 2):

```bash
MINOR=$(echo ${VERSION} | grep -oE '^v[0-9]+\.[0-9]+')
sudo -u genlayer mkdir -p /opt/genlayer-node/${MINOR}/data/node/keystore /opt/genlayer-node/${MINOR}/data/node/logs
sudo -u genlayer ln -sfn ../${MINOR}/data /opt/genlayer-node/${VERSION}/data
```

## Setup Symlinks

Symlinks provide a stable path (`/opt/genlayer-node/bin`) that points to the current version.

```bash
cd /opt/genlayer-node
for p in bin opt configs data docker-compose.yaml alloy-config.river alloy-healthcheck.sh genvm-module-web-docker.yaml .env; do
  sudo -u genlayer ln -sfn ${VERSION}/$p $p
done
# 'opt' makes the config's relative genvm.root_dir (./opt/genvm/...) resolve from /opt/genlayer-node
```

> **Note:** `alloy-config.river` ships with the node tarball. It must be symlinked like all other
> version-specific files so docker-compose can find it at the root level. After switching symlinks
> during an upgrade, restart Alloy to pick up the new config: `docker restart genlayer-node-alloy`

**After symlinks, you can use:**
- `/opt/genlayer-node/bin/genlayernode` instead of `/opt/genlayer-node/v0.6.0/bin/genlayernode`
- `/opt/genlayer-node/.env` instead of `/opt/genlayer-node/v0.6.0/.env`

## Start WebDriver

WebDriver is required for web-based contract operations.

```bash
cd /opt/genlayer-node
sudo docker compose up -d                          # sudo: .env is mode 600 (secrets)
sudo docker compose up -d docker-socket-proxy     # optional: WebDriver metrics for a binary node

# Wait for healthy status (at most 3 minutes)
for i in $(seq 1 36); do
  s=$(sudo docker inspect -f '{{.State.Health.Status}}' genlayer-node-webdriver 2>/dev/null)
  [ "$s" = healthy ] && break
  echo "Waiting for WebDriver (${s:-not created})..."; sleep 5
done
[ "$s" = healthy ] && echo "WebDriver is healthy!" || sudo docker logs --tail 30 genlayer-node-webdriver
```

**If WebDriver fails to start:**
```bash
# Check for existing container conflict
docker ps -a | grep webdriver

# Remove old container if exists
docker rm -f genlayer-node-webdriver

# Retry
sudo docker compose up -d
```

## Doctor Check

Verifies all configuration is correct before starting the node.

```bash
cd /opt/genlayer-node
sudo -u genlayer bash -c 'set -a; . ./.env; set +a; ./bin/genlayernode doctor'
```

**Expected output** (example: Testnet Bradbury):
```
  ✓ GenLayer Chain RPC: Connected to https://rpc-genlayer-chain-testnet-cfn8m3xc6l.t.conduit.xyz
  ✓ GenLayer Chain WebSocket: Connected to wss://rpc-genlayer-chain-testnet-cfn8m3xc6l.t.conduit.xyz
  ✓ All required config fields are present
  ✓ Consensus Deployment (admission):
    ✓ registry 0x3F71AE080BD6270A91dBcc7960d88797828538E0 is sealed
    ✓ chain 4221, 97 contracts match the trusted manifest
  ✓ GenVM Binaries: Found at ./opt/genvm/v0.6.0-rc10
  ✓ LLM Providers: 1 of 6 enabled backends usable
  ✓ WebDriver: Successfully rendered test page at http://127.0.0.1:4444
All configuration checks passed!
```

(Validator mode also checks the validator wallet / operator key. `ℹ interpreter outside the genvm
tree` lines are informational. "you have no fallback" warns that only one LLM provider works.)

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
curl -s http://localhost:9153/metrics | grep -E '^genlayer_node_(synced|blocks_behind|synced_block)'
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
User=genlayer
Group=genlayer
WorkingDirectory=/opt/genlayer-node
EnvironmentFile=/opt/genlayer-node/.env
Environment=DOCKER_HOST=tcp://127.0.0.1:2375
ExecStart=/opt/genlayer-node/bin/genlayernode run -c /opt/genlayer-node/configs/node/config.yaml
ExecStartPost=-+/bin/sh -c 'sleep 5 && /usr/bin/docker restart genlayer-node-alloy >/dev/null 2>&1 || true'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

> **Note:** The `ExecStartPost` line automatically restarts the Alloy telemetry container
> whenever the node starts. This is required because Alloy's bind mount to the log directory
> becomes stale when symlinks change during upgrades. The `-` prefix means systemd will
> ignore failures (e.g., if Alloy isn't installed); the `+` runs it as root, because the
> `genlayer` service user is not in the docker group. See `sharp-edges.yaml` -> `alloy-stale-bind-mount`.
>
> No password is on the command line: in validator mode the node reads `GENLAYERNODE_PASSWORD`
> from `EnvironmentFile`. `DOCKER_HOST` points at the read-only docker-socket-proxy (WebDriver
> metrics); remove the line if that proxy is not started.

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

### Database Error: "mkdir data/node/genvm.db: file exists"
**Symptom:** The node stops at start with `error opening database at "data/node/genvm.db": mkdir ... file exists`.
**Cause:** `data/node/genvm.db` is a link whose target does not exist from where the node runs —
typically a pre-v0.6 `genlayer.db` link (the v0.6 node renames `genlayer.db` to `genvm.db` on
start, link included), seen inside a Docker container where the target is not mounted.
**Fix:** Use the v0.6 layout: the whole `data/` is the shared link and `data/node/genvm.db` is a
real directory inside it (`common-procedures.md` -> "Create Directory Structure"). With the node stopped, move the real
database directory into place instead of linking it.

### Alloy Not Sending Logs After Upgrade
**Symptom:** Node is running and healthy, but Grafana shows no logs/metrics. Validator appears offline in monitoring.
**Cause:** Alloy's bind mount to the log directory became stale when symlinks changed during upgrade.
**Fix:**
```bash
docker restart genlayer-node-alloy
```
**Prevention:** The systemd service should include `ExecStartPost` to auto-restart Alloy. See the Systemd Service section above.
