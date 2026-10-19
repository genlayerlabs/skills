# Pre-Update Validation Checklist

This checklist MUST be executed before starting any validator node update to catch known edge cases proactively.

## Phase 1: Current Node Analysis

### 1.1 Check Current LLM Configuration
**Purpose:** Detect if LLM provider is configured but not enabled (edge: llm-provider-not-enabled)

```bash
# Check which LLM key is set in .env — NAMES ONLY, never the values
sudo awk -F= '/^(HEURISTKEY|COMPUT3KEY|IOINTELLIGENCEKEY|LIBERTAI_API_KEY|ANTHROPICKEY|GEMINIKEY|OPENROUTERKEY|MORPHEUS_API_KEY|OPENAIKEY|XAIKEY)=/ && length($2)>0 {print $1": set"}' /opt/genlayer-node/.env

# Provider mapping:
#   HEURISTKEY -> heurist
#   COMPUT3KEY -> comput3
#   IOINTELLIGENCEKEY -> ionet
#   LIBERTAI_API_KEY -> libertai
#   ANTHROPICKEY -> anthropic
#   GEMINIKEY -> google
#   OPENROUTERKEY -> openrouter
#   MORPHEUS_API_KEY -> morpheus

# For each non-empty key, check if that provider is enabled
# GenVM config dir of the running version (genvm.root_dir in config.yaml):
GENVM_CFG=$(cd /opt/genlayer-node && readlink -f "$(sed -n 's/^ *root_dir: *//p' configs/node/config.yaml)")/config
# Replace <provider> with the provider name from mapping above:
grep -A 2 '<provider>:' ${GENVM_CFG}/genvm-module-llm.yaml | grep 'enabled'
# If shows "enabled: false" -> FLAG FOR FIX
```

**Action if detected:** Note which provider needs to be enabled in new version.

### 1.2 Check Current Data Directory Structure
**Purpose:** Detect if the data directory is not shared between patch versions (edge: database-not-shared-patch-versions)

```bash
# v0.6: each version's data/ should be a link to the shared /opt/genlayer-node/<minor>/data
for d in /opt/genlayer-node/v0.6.*/data; do printf '%s -> %s\n' "$d" "$(readlink "$d" || echo 'REAL DIRECTORY')"; done
ls /opt/genlayer-node/v0.6/data/node/   # genvm.db ops.db keystore logs

# If a version has a real data/ directory (not a link) -> FLAG FOR FIX
```

**Action if detected:** Plan to move that data directory to the shared location (node stopped) during the update.

### 1.3 Record Current Sync State
**Purpose:** Baseline to verify new version syncs correctly

```bash
# Record current version and sync block
curl -s http://localhost:9153/health | jq -r '.status, .network, .node_version'
curl -s http://localhost:9153/metrics | grep 'genlayer_node_synced_block'
```

**Action:** Save this information to compare after update.

### 1.4 Verify Node is Running
**Purpose:** Confirm we're not stopping a non-running node (edge: high-downtime-update)

```bash
sudo systemctl status genlayer-node --no-pager
```

**Action if NOT running:** Different procedure - no downtime concern, but check why it's not running.

## Phase 2: Pre-Download Preparation

### 2.1 Check Systemd Service Has Alloy Restart
**Purpose:** Ensure systemd will auto-restart Alloy after node starts (edge: alloy-stale-bind-mount)

```bash
grep 'genlayer-node-alloy' /etc/systemd/system/genlayer-node.service
# Should show ExecStartPost line containing genlayer-node-alloy
```

**Action if missing:** Add ExecStartPost to the service file:
```bash
sudo nano /etc/systemd/system/genlayer-node.service
# Add after ExecStart line:
# ExecStartPost=-+/bin/sh -c 'sleep 5 && /usr/bin/docker restart genlayer-node-alloy >/dev/null 2>&1 || true'
# ('+' runs it as root: the node's service user is not in the docker group)

sudo systemctl daemon-reload
```

This prevents the Alloy bind mount from becoming stale after the upgrade.

### 2.2 Check Disk Space
**Purpose:** Ensure enough space for new version (edge: not explicitly documented but critical)

```bash
df -h /opt/genlayer-node
# Need at least 5GB free for new version + shared DB growth
```

**Action if low:** Clean up old versions or warn user.

### 2.3 Verify Prerequisites Still Met
**Purpose:** Ensure system hasn't degraded since initial install

```bash
# Python 3.10+ with pip and venv (python3-venv: ensurepip must import)
python3 -c 'import sys; sys.exit(sys.version_info < (3,10))' && python3 -m pip --version && python3 -c 'import venv, ensurepip'

# Docker, cosign (release signature check)
docker --version && docker compose version && cosign version | grep GitVersion
```

**Action if missing:** Reinstall prerequisites before proceeding.

## Phase 3: Post-Download Validation

### 3.1 Verify GenVM Setup Completion
**Purpose:** Ensure slow GenVM setup completed successfully (edge: setup-py-failed)

```bash
NEW_GENVM=$(cd /opt/genlayer-node/${NEW_VERSION} && readlink -f "$(sed -n 's/^ *root_dir: *//p' configs/node/config.yaml)")
ls -la ${NEW_GENVM}/bin/genvm-modules ${NEW_GENVM}/executor/*/bin/genvm
```

**Action if missing:** Re-run setup.py in that directory (`python3 ${NEW_GENVM}/bin/setup.py`, as the service user), don't proceed to switch.

### 3.2 Preserve LLM Strategy in New Version
**Purpose:** Apply release LLM config and preserve current strategy (default or greybox)

```bash
# Apply release LLM config to new version
sudo -u genlayer cp ${NEW_GENVM}/config/genvm-modules-llm-release.yaml ${NEW_GENVM}/config/genvm-module-llm.yaml

# Check current strategy and carry it forward
grep lua_script_path ${GENVM_CFG}/genvm-module-llm.yaml
# If shows genvm-llm-greybox.lua, apply greybox to new version:
grep -q 'genvm-llm-greybox.lua' ${GENVM_CFG}/genvm-module-llm.yaml && \
  sudo -u genlayer sed -i 's/genvm-llm-default\.lua/genvm-llm-greybox.lua/' ${NEW_GENVM}/config/genvm-module-llm.yaml
```

### 3.3 Check LLM Provider Enabled in New Version
**Purpose:** Proactively fix LLM provider disabled issue BEFORE switching (edge: llm-provider-not-enabled)

```bash
# Check if your provider is enabled in the new version
# Replace <provider> with your provider name (heurist, comput3, ionet, libertai, anthropic, google, openrouter):
grep -A 2 '<provider>:' ${NEW_GENVM}/config/genvm-module-llm.yaml | grep 'enabled'

# If disabled, enable it NOW before switching:
sudo -u genlayer sed -i '/^  <provider>:/,/^  [a-z]/ s/enabled: false/enabled: true/' ${NEW_GENVM}/config/genvm-module-llm.yaml
```

**Action:** Fix BEFORE switching versions.

### 3.4 Verify Shared Data Directory
**Purpose:** Ensure new version uses the shared data directory (edge: database-not-shared-patch-versions)

```bash
# Check that the link was created correctly
readlink /opt/genlayer-node/${NEW_VERSION}/data
# Should be ../v0.6/data

# Verify the shared data exists (genvm.db, ops.db, keystore)
ls -la /opt/genlayer-node/v0.6/data/node/
```

**Action if wrong:** Fix structure before switching.

## Phase 4: Pre-Switch Final Checks

### 4.1 Verify WebDriver Ready
**Purpose:** Ensure WebDriver won't cause startup failure (edge: webdriver-not-healthy)

```bash
docker inspect --format='{{.State.Health.Status}}' genlayer-node-webdriver
# Should be 'healthy'
```

**Action if not healthy:** Fix before switching.

### 4.2 Doctor Check on New Version (Dry Run)
**Purpose:** Test new version without committing to it

```bash
# Run from the new version directory (without stopping old node).
# 'set -a' exports the .env values to doctor (plain 'source' does not).
cd /opt/genlayer-node/${NEW_VERSION}
sudo -u genlayer bash -c 'set -a; . ./.env; set +a; ./bin/genlayernode doctor'
```

**Action if fails:** Fix issues before switching.

## Phase 5: Post-Switch Validation

### 5.1 Verify Version Switched
```bash
curl -s http://localhost:9153/health | jq -r '.node_version'
# Should show new version
```

### 5.2 Verify Sync Progressing
```bash
# Wait 30 seconds, then check sync increased
sleep 30
curl -s http://localhost:9153/metrics | grep 'genlayer_node_synced_block'
# Should be higher than pre-update baseline
```

### 5.3 Check LLM Module Started
```bash
# Should NOT see "module_failed_to_start" errors
sudo journalctl -u genlayer-node --since '2 minutes ago' --no-pager | grep -i 'llm\|genvm is ready'
# Should see "genvm is ready"
```

### 5.4 Verify Alloy Telemetry (CRITICAL)
**Purpose:** Ensure Alloy's bind mount was refreshed and logs are flowing to Grafana (edge: alloy-stale-bind-mount)

```bash
# Check Alloy container is running
docker ps | grep alloy
# Should show genlayer-node-alloy as running

# Compare log file timestamps (host vs container view)
echo "Host log timestamp:"
ls -la /opt/genlayer-node/data/node/logs/node.log 2>/dev/null | awk '{print $6, $7, $8}'

echo "Container log timestamp:"
docker exec genlayer-node-alloy ls -la /var/log/genlayer/node.log 2>/dev/null | awk '{print $6, $7, $8}'

# CRITICAL: Both timestamps MUST match!
# If they differ, Alloy has a stale bind mount and is NOT sending current logs.

# Check Alloy is actively processing
docker logs genlayer-node-alloy 2>&1 | tail -5
# Should show recent activity, not old timestamps
```

**Action if timestamps differ:** The Alloy bind mount is stale. Run:
```bash
docker restart genlayer-node-alloy
```

Then re-verify the timestamps match.

## Automation Recommendation

This checklist should be encoded into the skill as mandatory validation steps:

```yaml
# In validations.yaml
pre_update_validations:
  - id: check-llm-provider-enabled
    when: before_version_switch
    check: |
      # Check if LLM provider in use is enabled in new version
    action: Enable if needed

  - id: verify-shared-database
    when: before_version_switch
    check: |
      # Verify new version uses shared DB
    action: Create shared structure if needed

  - id: verify-genvm-setup-complete
    when: before_version_switch
    check: |
      # Ensure GenVM binaries present
    action: Re-run setup.py if missing
```

## Summary

**Current State:**
- Edge cases documented in sharp-edges.yaml
- But not actively checked during execution
- Issues discovered reactively after failure

**Target State:**
- Edge cases checked proactively before each phase
- Issues prevented before they cause failures
- Validation failures stop the process early

**Implementation:**
Each phase of the update should explicitly check relevant edge cases from sharp-edges.yaml before proceeding.
