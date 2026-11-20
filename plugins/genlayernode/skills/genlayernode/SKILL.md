---
name: genlayernode
description: Interactive wizard to set up a GenLayer validator node on Linux.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - WebFetch
  - AskUserQuestion
---

# GenLayer Validator Setup

Interactive wizard to set up a GenLayer validator node from scratch on a Linux server.

## MANDATORY: Show Process Overview at Start

**CRITICAL REQUIREMENT**: At the very beginning of ANY setup or upgrade operation, you MUST display a complete overview of ALL steps that will be performed. This is NON-NEGOTIABLE.

### Before Starting ANY Installation or Upgrade:

1. **Display the full process overview** showing all steps that will be executed
2. **Ask user to confirm** they want to proceed with the installation/upgrade
3. **Before EACH step**, briefly explain what that step will do before executing it

### Required Start Message Format:

```
## GenLayer Validator Node Setup

I'll guide you through the complete validator node installation. Here's what we'll do:

**Step 1: Determine Server Location**
- Identify where the validator will run (local/GCP/AWS/SSH)
- Configure access method for commands

**Step 2: Verify Prerequisites**
- Check system architecture (must be x86_64)
- Verify RAM, CPU, and disk space
- Check Docker, Python 3.10+ (pip, venv), cosign installations
- Install what is missing (after you confirm)

**Step 3: Full Node, New or Existing Validator**
- Full node: no staking, no operator key
- New validator: Run staking wizard on your machine (deployed self-stake minimum)
- Existing: Provide validator wallet address

**Step 4: Download & Extract Node Software**
- Download GenLayer node tarball from official storage
- Verify it (cosign signature + SHA256)
- Install to /opt/genlayer-node/${VERSION}/ with the release install.sh
- Set up directory structure and symlinks
- Run GenVM setup (install.sh runs it)

**Step 5: Configure Environment (.env)**
- Create .env with empty secret values
- You set the RPC provider key manually (if your network's provider needs one)
- Set LLM provider (you'll add API key manually)

**Step 6: Configure Node (config.yaml)**
- Set validator wallet address
- Configure operator address
- Set network endpoints and ports
- Set the network's consensus values and download its protocol manifest
- Set node mode (full or validator)

**Step 7: Set Up Operator Key (validator only)**
- Import keystore from staking wizard, OR
- Copy from previous installation, OR
- Generate new operator key

**Step 8: Start WebDriver Container**
- Launch WebDriver via Docker Compose
- Wait for health check to pass

**Step 9: Run Doctor Check**
- Verify GenVM binaries are installed
- Verify WebDriver connectivity

**Step 10: Choose Deployment Method**
- Systemd service (recommended)
- Docker Compose
- Manual (screen/tmux)

**Step 11: Verify Node Running**
- Check health endpoint
- Verify sync status

**Estimated time: 20-45 minutes**

Ready to begin?
```

### Before Each Step:

Always show a brief description of what will happen:

```
## Step 4: Download & Extract Node Software

This step will:
1. Download the GenLayer node v0.4.4 tarball (~XX MB)
2. Create directory /opt/genlayer-node/v0.4.4/
3. Extract binary, configs, and GenVM files
4. Set up symlinks for easy access
5. Run GenVM setup to download dependencies (~2 min)

Proceeding...
```

**NEVER skip showing what a step will do before executing it.**

---

## What This Skill Will Do

This skill guides you through the complete validator node installation process. When you invoke this skill, it will:

1. **Determine your setup environment** - Local machine, remote server (SSH), or cloud VM (GCP/AWS/Azure)
2. **Verify prerequisites** - Check that your server meets minimum requirements (architecture, RAM, software dependencies)
3. **Guide wallet setup** - Help create a new validator wallet or use an existing one
4. **Download node software** - Fetch the specified version (or latest) from official storage
5. **Generate configuration** - Create config.yaml and .env files with your specific settings
6. **Import/generate operator keys** - Set up the validator's operator account
7. **Configure LLM provider** - Set up API keys for intelligent contract execution
8. **Start the node** - Launch as systemd service, Docker Compose, or manual process
9. **Verify installation** - Check health and sync status
10. **Optional: Enable monitoring** - Set up telemetry push to central monitoring

**Total time estimate**: 20-45 minutes depending on your experience level and setup method.

## CRITICAL: Update Procedure Warning

**If you are UPDATING an existing node, read this first:**

### Zero-Downtime Update Procedure
**NEVER stop your old node before preparing the new version!**

Traditional update process (WRONG - causes 3-4 min downtime):
```
Stop node -> Download -> Extract -> GenVM setup (2 min) -> Start
```

**Correct procedure (10-15 sec downtime):**
```
Download -> Extract -> GenVM setup WHILE OLD NODE RUNS
THEN: Stop old -> Switch symlinks -> Start new
```

**Impact of wrong procedure:**
- 3-4 minutes downtime vs 10-15 seconds
- Missed 12-24 validation opportunities
- Lost rewards during downtime
- Validator needs to re-prime
- Potential slashing penalties

**See `update-procedure.md` for detailed zero-downtime update steps.**

**For fresh installations, see `install-procedure.md` for the step-by-step installation guide.**

### Database Storage Structure
For patch versions (v0.6.x), the data directory MUST be shared, not copied
(v0.6 keeps `genvm.db`, `ops.db` and the keystore there):

**Correct structure:**
```
/opt/genlayer-node/v0.6/data/node/      <- Shared: genvm.db, ops.db, keystore/, logs/
/opt/genlayer-node/v0.6.0/data          -> symlink to ../v0.6/data
/opt/genlayer-node/v0.6.1/data          -> symlink to ../v0.6/data
```

### LLM Strategy and Provider Configuration

Two LLM strategies are available:
- **default** — Random provider selection from enabled backends
- **greybox** — Deterministic ordered fallback via OpenRouter (requires `OPENROUTERKEY`)

```bash
# GenVM config dir = <genvm.root_dir in config.yaml>/config (v0.6+: opt/genvm/<ver>/config)
GENVM_CFG=$(readlink -f "$(sed -n 's/^ *root_dir: *//p' configs/node/config.yaml)")/config

# 1. Apply release LLM config (has all backends)
cp ${GENVM_CFG}/genvm-modules-llm-release.yaml \
   ${GENVM_CFG}/genvm-module-llm.yaml

# 2. For greybox strategy, switch lua script:
sed -i 's/genvm-llm-default\.lua/genvm-llm-greybox.lua/' \
  ${GENVM_CFG}/genvm-module-llm.yaml

# 3. Enable your provider (replace <provider> with name from mapping):
# Provider mapping (env var -> config name):
#   HEURISTKEY -> heurist
#   COMPUT3KEY -> comput3
#   IOINTELLIGENCEKEY -> ionet
#   LIBERTAI_API_KEY -> libertai
#   ANTHROPICKEY -> anthropic
#   GEMINIKEY -> google
#   OPENROUTERKEY -> openrouter
#   MORPHEUS_API_KEY -> morpheus
sed -i '/^  <provider>:/,/^  [a-z]/ s/enabled: false/enabled: true/' \
  ${GENVM_CFG}/genvm-module-llm.yaml
```

**Symptom if not enabled:** Node fails to start with "module_failed_to_start" error
(v0.6: the node starts degraded and doctor reports no usable LLM provider).

### Updating Greybox on a Running Node
To update the Lua script or LLM YAML without a full redeploy, see
`common-procedures.md` -> "Update Greybox Config on Running Node".
Key points:
- Update files in all GenVM instance config directories
- Restart LLM module per GenVM manager: `curl -X POST http://127.0.0.1:<port>/module/stop` then `/module/start`
- No atomic restart — each instance restarts independently

### Validator Triage: RPC Outages, Temporary Bans, and Provider Errors

When a validator reports `504 Gateway Timeout`, `get chain ID`, `validator is banned`, or `NO_PROVIDER_FOR_PROMPT`, triage before changing configuration:

1. **Classify the symptom.**
   - WebSocket `401` (doctor: GenLayer Chain WebSocket fails; the node exits at start) means the RPC provider key `GENLAYERNODE_ROLLUP_GENLAYERCHAINRPCKEY` is empty or wrong in `.env` (Testnet Bradbury: Conduit).
   - `dependencies: get chain ID: 504 Gateway Timeout` usually means the configured rollup RPC is unavailable or overloaded. Confirm with `eth_chainId`/`eth_blockNumber` against the configured HTTP RPC and compare with other operators before editing local node files.
   - `/health` with `temporary ban until epoch ...: validator is banned` means the node may be healthy but consensus has temporarily banned the validator. Fix the root cause first, then request unban with the validator wallet address.
   - `NO_PROVIDER_FOR_PROMPT` means GenVM could not find an enabled LLM backend that satisfies the prompt capabilities. Check enabled providers, API keys, JSON/image capability support, and restart the affected GenVM LLM module after config changes.
2. **Do not rotate endpoints blindly.** Shared RPC incidents can affect multiple operators at once; switching URLs without an official replacement can make recovery harder.
3. **Collect safe diagnostics only.** Share sanitized health output, node/genvm versions, network, and validator address when requesting operator help. Never paste API keys, passwords, private keys, or full `.env` contents.
4. **Use `doctor` before restart when possible.** Run `cd /opt/genlayer-node && sudo -u genlayer bash -c 'set -a; . ./.env; set +a; ./bin/genlayernode doctor'` to catch provider/config issues before putting the service back into rotation.

---

## Requirements

Before starting, ensure your setup meets these requirements:

### System Requirements
- **Architecture**: AMD64 (x86_64) Linux server - ARM64 is NOT supported
- **RAM**: Minimum 16GB (32GB recommended for production)
- **CPU**: Minimum 8 cores (16+ recommended for production)
- **Storage**: Minimum 128GB SSD (256GB+ recommended for production)
- **Operating System**: Ubuntu 22.04+, Debian 12+, or compatible Linux distribution (Python 3.10+)

### Software Dependencies
- **Node.js**: v20 or higher — only on the machine that runs the GenLayer CLI (staking wizard), not on the server
- **Docker**: v20.10 or higher with Compose plugin
- **Python**: Python 3.10+ with pip and venv modules
- **cosign**: To verify the release signature
- **Git**: For version control (optional but recommended)

### Blockchain Requirements
- **GEN Tokens**: The deployed self-stake minimum (`genlayer staking epoch-info --network testnet-bradbury`; 42,000 GEN is the protocol default) if creating new validator
- **GEN for gas**: Small amount of GEN for gas fees on operator account (~10 GEN recommended)
- **RPC Access**: HTTP and WebSocket URLs for GenLayer Chain, and the RPC provider's API key if it needs one (from your network's section in the docs ("Network-Specific Consensus Configuration"); for your own network, from its operator)

### API Keys Required
- **RPC Provider**: API key, if your network's RPC provider needs one — full nodes and validators (Testnet Bradbury: Conduit, https://app.conduit.xyz/rpc-keys)
- **LLM Provider**: API key from one of these providers (a full node syncs without one, but doctor fails):
  - Heurist (recommended for validators)
  - Comput3
  - io.net
  - LibertAI
  - Anthropic
  - Google (Gemini)

### Access Requirements
- **SSH Access**: If installing on remote server (username@hostname)
- **Sudo Privileges**: Installation requires root or sudo access
- **Port Access**: Ports 9151 (RPC), 9153 (Ops), 9155 (Admin), 4444 (WebDriver) must be available

## Installation Process Overview

```mermaid
flowchart TD
    A[1. Environment Setup] --> B[2. Wallet & Staking]
    B --> C[3. Software Download]
    C --> D[4. Configuration]
    D --> E[5. Operator Key Setup]
    E --> F[6. LLM Configuration]
    F --> G[7. Start Services]
    G --> H[8. Verification & Cleanup]
```

### Version Handling

When specifying a version:
- **Specific version**: Use exact version like `v0.6.0`
- **Latest version**: Use the version approved for your network in the release announcement — the most recent listed release may not be approved yet
- **No version specified**: Skill will prompt you to choose from the 5 most recent versions

The skill automatically handles:
- Version-specific directory structure (`/opt/genlayer-node/v0.6.0/`)
- Shared data directory across patch versions (v0.6.x shares genvm.db, ops.db, keystore)
- Symlinks for easy access to current version

## Purpose

Guide validators through complete GenLayer node installation including:
- Prerequisites verification and installation (Python 3.10+, pip, venv, Docker, cosign)
- Full node or validator; wallet creation via staking wizard (deployed self-stake minimum)
- Node software download, verification and extraction
- Configuration via config.yaml, protocol manifest and .env file
- Operator key import from wizard export
- LLM provider setup (Heurist, Comput3, io.net, LibertAI, Anthropic, Google)
- Node startup as systemd service (binary) or Docker Compose
- Optional telemetry/monitoring setup

## Quick Reference

### Directory Structure After Installation
```
/opt/genlayer-node/
├── v0.6/data/node/                 # Shared data directory (all v0.6.x)
│   ├── genvm.db
│   ├── ops.db
│   ├── keystore/
│   └── logs/
├── v0.6.0/                         # Version-specific directory
│   ├── bin/genlayernode
│   ├── opt/genvm/<genvm-version>/
│   ├── docker-compose.yaml
│   ├── .env
│   ├── data -> ../v0.6/data
│   └── configs/node/{config.yaml,protocol-manifest.json}
├── bin -> v0.6.0/bin               # Symlinks for easy access
├── opt -> v0.6.0/opt
├── data -> v0.6.0/data
├── configs -> v0.6.0/configs
├── docker-compose.yaml -> v0.6.0/docker-compose.yaml
├── .env -> v0.6.0/.env
├── alloy-config.river -> v0.6.0/alloy-config.river  # Symlink (ships with tarball)
└── genvm-module-web-docker.yaml -> v0.6.0/genvm-module-web-docker.yaml
```

### Requires
- AMD64 Linux server (16GB+ RAM, 8+ cores, 128GB+ SSD)
- Docker, Python 3.10+ with pip and venv, cosign
- RPC provider API key, if your network needs one (Testnet Bradbury: Conduit)
- Deployed self-stake minimum in GEN (if new validator)
- LLM API key from supported provider
- Operator keystore from staking wizard (validator only, or generate new)

### Default Configuration
| Setting | Default Value |
|---------|---------------|
| RPC URL | **No default** - user must provide |
| WebSocket | **No default** - user must provide |
| Consensus Address (AddressManager) | **Per-deployment — no default** (v0.6+: `consensus.consensusaddress` in config.yaml) |
| Chain ID | **Per-deployment — no default** (v0.6+: `consensus.chainid`, decimal) |
| Genesis Block | **Per-deployment** — AddressManager deploy block (v0.6+: `consensus.genesis`; missing ⇒ scans from block 0) |
| Protocol Manifest | **Per-deployment** (v0.6+: the network's manifest, saved at `configs/node/protocol-manifest.json`) |

Take the per-deployment values from your network's section in the docs ("Network-Specific Consensus Configuration"); for your own network, from its operator. The Testnet Bradbury
values are shown as an example in `install-procedure.md` Phase 5.
| Install Path | `/opt/genlayer-node` |
| RPC Port | `9151` |
| Ops Port | `9153` |
| Admin Port | `9155` |
| Metrics Interval | `15s` |

### LLM Provider Environment Variables
| Provider | Environment Variable |
|----------|---------------------|
| Heurist | `HEURISTKEY` |
| Comput3 | `COMPUT3KEY` |
| io.net | `IOINTELLIGENCEKEY` |
| LibertAI | `LIBERTAI_API_KEY` |
| Anthropic | `ANTHROPICKEY` |
| Google | `GEMINIKEY` |
| xAI (Grok) | `XAIKEY` |
| Atoma | `ATOMAKEY` |
| OpenRouter | `OPENROUTERKEY` |
| Morpheus | `MORPHEUS_API_KEY` |
| OpenAI | `OPENAIKEY` |

## Installation Flow

The skill guides through these steps interactively:

### 0. Determine Server Location and Access Method
**CRITICAL FIRST STEP**: Before any installation begins, determine where the validator will run and how to access it.

**Question**: "Where will you run the validator node?"

**Options**:
- **This machine (local setup)**: Running validator on this computer
  - Commands execute directly via Bash tool
  - Files copied using local filesystem
  - Health checks use localhost
- **Remote Linux server (SSH)**: Generic Linux server accessed via SSH
  - Provide commands as text for user to run via SSH
  - File transfers via scp
  - Collect: username@hostname or username@IP
- **Google Cloud Platform VM**: GCP Compute Engine instance
  - Commands use gcloud compute ssh
  - File transfers via gcloud compute scp
  - Collect: project-id/zone/instance-name
- **AWS EC2 Instance**: Amazon Web Services EC2 instance
  - Commands use AWS Systems Manager or SSH
  - File transfers via scp or AWS transfer
  - Collect: instance-id/region
- **Azure VM**: Azure Virtual Machine
  - Commands use Azure CLI or SSH
  - File transfers via scp
  - Collect: resource-group/vm-name
- **Other cloud provider**: DigitalOcean, Linode, Vultr, etc.
  - Commands use standard SSH
  - File transfers via scp

**Impact**: This choice affects ALL subsequent steps:
- How commands are executed (direct vs via SSH)
- How files are transferred (cp vs scp vs cloud-specific tools)
- How to verify installation (local curl vs SSH tunneling)
- Which CLI tools are needed (gcloud, aws cli, azure cli)

### 1. Check Prerequisites
Verify system meets requirements before starting:

```bash
# Check architecture (must be x86_64)
uname -m

# Check Docker and Docker Compose
docker --version
docker compose version

# Check Python 3.10+ with pip and venv
python3 --version
python3 -m pip --version
python3 -c 'import venv, ensurepip'   # 'python3 -m venv --help' passes without python3-venv

# Check cosign (release signature)
cosign version
```

**Minimum requirements:**
- AMD64 (x86_64) architecture
- 16GB+ RAM, 8+ CPU cores, 128GB+ SSD
- Docker with Compose plugin
- Python 3.10+ with pip and venv
- cosign

**Install what is missing** (after the user confirms) — see `install-procedure.md` -> Prerequisites:
`apt-get install -y python3 python3-pip python3-venv docker.io docker-compose-v2 jq`, cosign from
its pinned GitHub release `.deb`. Node.js is not needed on the server.

### 1. Full Node, New Validator or Existing?
**Full node** (`node.mode: "full"`): no staking wizard, no operator key — skip to Download & Setup.

**Note**: The staking wizard runs on your **local machine** (not the server), since it manages wallet keys.

- **New**: Run staking wizard (deployed self-stake minimum: `genlayer staking epoch-info --network testnet-bradbury`)
  ```bash
  npm install -g "genlayer@${CLI_VERSION}"   # exact version from the release announcement for your network
  genlayer staking wizard --network testnet-bradbury
  ```
  The wizard is **fully interactive** (requires TTY) and guides you through:
  1. Account selection or creation (owner account)
  2. Network selection
  3. Funding source (wallet or vesting contract)
  4. Balance verification (deployed minimum + gas)
  5. Operator setup — creates a separate operator account and exports its keystore
  6. Stake amount confirmation
  7. On-chain validator registration — returns your **validator wallet address**
  8. Optional identity setup (moniker, website, socials; `--skip-identity`)
  9. Summary

  **Phase 2**: the operator must be an account the CLI holds, so it can sign the proof of
  possession. An external operator address alone fails.

  **Three addresses are produced:**
  | Address | Purpose |
  |---------|---------|
  | **Owner** | Cold wallet that controls withdrawals (stays on local machine) |
  | **Operator** | Hot wallet that signs blocks (goes on the server via keystore) |
  | **Validator Wallet** | Smart contract deployed on-chain (used in config.yaml) |

  **After the wizard, save:**
  - Validator wallet address → for `config.yaml`
  - Operator address → for `config.yaml`
  - Operator keystore file → upload to server
  - Export passphrase → you set it on the server as `GENLAYERNODE_PASSWORD` (Docker: `NODE_PASSWORD`)

  **After the wizard, fund the operator:**
  The operator account starts with 0 GEN and needs funds for gas fees to sign validation transactions.
  ```bash
  # Check operator balance
  genlayer account show --account "Operator Name"

  # Send GEN from owner to operator (recommended: 10 GEN)
  genlayer account send 0xOPERATOR_ADDRESS 10gen --account "Owner Name" --network testnet-bradbury
  ```

  **See `staking-wizard-procedure.md` for the complete step-by-step wizard walkthrough, alternative CLI commands, and troubleshooting.**

- **Existing**: Skip to download (must have validator wallet address and operator keystore)

### 2. Download & Setup
**Note**: For remote servers, download to the remote server, not your local machine.

**List available versions:**
```bash
curl -s "https://storage.googleapis.com/storage/v1/b/gh-af/o?prefix=genlayer-node/bin/amd64" | \
  grep -o '"name": *"[^"]*"' | sed -n 's/.*\/\(v[^/]*\)\/.*/\1/p' | sed 's/-rc/~rc/' | sort -ruV | sed 's/~rc/-rc/' | head -5
```

**Download, verify and install (replace ${VERSION} with the approved version, e.g., v0.6.0):**
See `install-procedure.md` Phase 2 for the exact commands. In short:
```bash
base=https://storage.googleapis.com/gh-af/genlayer-node/bin/amd64/${VERSION}
# Download to a temp dir the genlayer user can read (home directories are 750 on Ubuntu)
DL=$(mktemp -d /tmp/genlayer-${VERSION}.XXXX) && chmod 755 "$DL" && cd "$DL"
# All four files must exist — stop on any 404 (never fall back to an older version)
curl -fI ${base}/genlayer-node-linux-amd64-${VERSION}.tar.gz      # + _SHA256SUMS, .sigstore.json, install.sh
wget ${base}/genlayer-node-linux-amd64-${VERSION}.tar.gz ${base}/genlayer-node_${VERSION}_SHA256SUMS \
     ${base}/genlayer-node_${VERSION}_SHA256SUMS.sigstore.json ${base}/install.sh

# Verify before extracting (stop on any failure; the tarball must be listed in SHA256SUMS)
cosign verify-blob --bundle genlayer-node_${VERSION}_SHA256SUMS.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/genlayerlabs/genlayer-node/\.github/workflows/release-package\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com genlayer-node_${VERSION}_SHA256SUMS \
&& grep -q "[ *]genlayer-node-linux-amd64-${VERSION}.tar.gz$" genlayer-node_${VERSION}_SHA256SUMS \
&& sha256sum -c genlayer-node_${VERSION}_SHA256SUMS --ignore-missing \
|| { echo "VERIFICATION FAILED - stop, do not install" >&2; rm -f install.sh; false; }   # no install.sh: the install below cannot run

# Extract + GenVM setup in the final directory (as the genlayer service user)
sudo install -d -o genlayer -g genlayer /opt/genlayer-node
chmod +x install.sh
sudo -u genlayer -H ./install.sh --install-dir /opt/genlayer-node/${VERSION} \
  --tarball genlayer-node-linux-amd64-${VERSION}.tar.gz

# Shared data directory + symlinks for easy access (install-procedure.md Phase 2)
MINOR=$(echo ${VERSION} | grep -oE '^v[0-9]+\.[0-9]+')
sudo -u genlayer mkdir -p /opt/genlayer-node/${MINOR}/data/node/keystore /opt/genlayer-node/${MINOR}/data/node/logs
sudo -u genlayer ln -sfn ../${MINOR}/data /opt/genlayer-node/${VERSION}/data
cd /opt/genlayer-node
for p in bin opt configs data docker-compose.yaml alloy-config.river alloy-healthcheck.sh genvm-module-web-docker.yaml .env; do
  sudo -u genlayer ln -sfn ${VERSION}/$p $p
done
# v0.6+: genvm lives under opt/genvm/<ver> — the `opt` link is REQUIRED, else `./opt/genvm/...` won't resolve
```

install.sh runs the GenVM setup (verifies runners, patches the binaries' interpreter path,
precompiles). It writes the install directory's absolute path into the GenVM binaries: never
move the directory afterwards.

### 3. Environment Configuration (.env)

**IMPORTANT**: Always start from the `.env.example` included in the downloaded artifact. This ensures all required variables are present.

First ask if user wants to copy existing .env or create from example:
- **Use example (Recommended)**: Copy from artifact's `.env.example`, then customize
- **Copy from previous**: Copy .env from previous installation

**Create .env from example:**
```bash
sudo -u genlayer cp /opt/genlayer-node/${VERSION}/.env.example /opt/genlayer-node/${VERSION}/.env
sudo chmod 600 /opt/genlayer-node/${VERSION}/.env
```

**Key values to configure:**
1. **RPC key** - The RPC/WebSocket URLs are in config.yaml (step 4). The RPC provider's API key, if it needs one (Testnet Bradbury: Conduit), goes here:
   ```bash
   GENLAYERNODE_ROLLUP_GENLAYERCHAINRPCKEY=<set by the user>
   ```

2. **LLM API Key** - Set ONE of these (leave others empty):
   - `OPENROUTERKEY=`
   - `HEURISTKEY=`
   - `ANTHROPICKEY=`
   - `GEMINIKEY=`
   - Or the env var for your chosen provider (see LLM Provider Environment Variables table)

3. **Node Password** (validator only) - the operator keystore's export passphrase:
   `GENLAYERNODE_PASSWORD=` (binary) or `NODE_PASSWORD=` (Docker)

4. **Docker only** - `NODE_VERSION=${VERSION}` (exact, never `latest`)

**After creating .env, instruct user to:**
1. Connect to the server (SSH / `gcloud compute ssh` / `aws ssm start-session`)
2. Edit the .env file: `sudo nano /opt/genlayer-node/.env`
3. Set the RPC provider key (if needed) and the LLM API key for their chosen provider
4. Set the keystore passphrase (validator only)
5. Save and confirm when done

### 4. Node Configuration (config.yaml)

**IMPORTANT**: Always start from the config included in the downloaded artifact (`configs/node/config.yaml`; install.sh already set its `genvm.root_dir`). This ensures the config format is compatible with the installed version.

First ask if user wants to copy existing config or use example:
- **Use example config (Recommended)**: Edit the artifact's config.yaml in place, then customize via wizard
- **Copy from previous**: Copy config.yaml from previous installation (keep the new `genvm.root_dir`)

**Network values and protocol manifest** — required since v0.6. Take them from
your network's section in the docs ("Network-Specific Consensus Configuration"); for your own network, from its operator. The commands and the Testnet Bradbury
example are in `install-procedure.md` Phase 5:
- Download the network's manifest to `configs/node/protocol-manifest.json`
- `rollup:` RPC/WebSocket URLs and `provider`
- `consensus:` `consensusaddress`, `chainid` (decimal), `manifestpath: "configs/node/protocol-manifest.json"`, `genesis`
- `node.mode`: `"full"` or `"validator"`

#### Configuration Wizard (Group-based)
After copying the base config, go through each configuration GROUP and ask whether to modify or keep defaults:

**Group 1: Node Identity**
- Ask: "Do you want to modify Node Identity settings?" (Keep defaults / Modify)
- If modify: Ask for validator address, operator address

**Group 2: RPC Endpoints**
- Ask: "Do you want to modify RPC Endpoint settings?" (Keep defaults / Modify)
- If modify: Ask for port, enabled groups (genlayer, genlayer_debug, ethereum, zksync)

**Group 3: Ops Endpoints**
- Ask: "Do you want to modify Ops Endpoint settings?" (Keep defaults / Modify)
- If modify: Ask for port (v0.6 serves /metrics, /health, /balance, /snapshot regardless of the endpoint switches)

**Group 4: Admin Endpoints**
- Ask: "Do you want to modify Admin Endpoint settings?" (Keep defaults / Modify)
- If modify: Ask for port

**Group 5: Metrics Configuration**
- Ask: "Do you want to modify Metrics settings?" (Keep defaults / Modify)
- If modify: Ask for collection intervals

**Note**: Rollup URLs (RPC, WebSocket) and contract addresses are configured in config.yaml. Only the RPC key and other secrets are in .env.

### 5. Operator Key (validator only)
First ask how user wants to provide the operator key:

**Source options:**
- **Upload keystore.json** - Upload the keystore.json file exported from staking wizard (installed as-is; its passphrase goes in .env)
- **Upload keystore directory** - Upload the keystore directory directly (no import needed, just copy to data/node/keystore/)
- **Copy from previous** - Copy keystore from existing installation on this VM
- **Generate new** - Create new key
  - Must fund new address with GEN for gas fees
  - Must update validator settings to use new operator address

**Upload flow:**
1. Ask which type of file user has (keystore.json or keystore directory)
2. **Create the keystore directory first** (required before upload):
   ```bash
   sudo install -d -m 700 -o genlayer -g genlayer /opt/genlayer-node/${VERSION}/data/node/keystore
   ```
3. **Provide upload instructions based on server location (from Step 0)**:

   **For local setup:**
   ```bash
   # Copy keystore.json
   cp ./keystore.json /tmp/keystore.json

   # Or copy keystore directory
   cp -r ./keystore/* /opt/genlayer-node/${VERSION}/data/node/keystore/
   ```

   **For remote SSH server:**
   ```bash
   # Upload keystore.json
   scp ./keystore.json username@hostname:/tmp/keystore.json

   # Or upload keystore directory
   scp -r ./keystore/* username@hostname:/opt/genlayer-node/${VERSION}/data/node/keystore/
   ```

   **For GCP VM:**
   ```bash
   # Upload keystore.json
   gcloud compute scp ./keystore.json instance-name:/tmp/keystore.json \
     --project=project-id --zone=zone

   # Or upload keystore directory
   gcloud compute scp --recurse ./keystore/* instance-name:/opt/genlayer-node/${VERSION}/data/node/keystore/ \
     --project=project-id --zone=zone
   ```

   **For AWS EC2:**
   ```bash
   # Upload keystore.json (assuming SSH access)
   scp -i ~/.ssh/your-key.pem ./keystore.json ec2-user@instance-ip:/tmp/keystore.json

   # Or upload keystore directory
   scp -i ~/.ssh/your-key.pem -r ./keystore/* ec2-user@instance-ip:/opt/genlayer-node/${VERSION}/data/node/keystore/
   ```

4. Wait for user confirmation
5. Verify upload:
   ```bash
   ls -la /opt/genlayer-node/${VERSION}/data/node/keystore/
   ```
6. For keystore.json: install the encrypted file as-is (no passphrase on any command line):
   ```bash
   # Stop if operator.json exists: the keystore is shared by all v0.6.x versions (never overwrite it)
   sudo test ! -e /opt/genlayer-node/${VERSION}/data/node/keystore/operator.json && \
   sudo install -m 600 -o genlayer -g genlayer /tmp/keystore.json \
     /opt/genlayer-node/${VERSION}/data/node/keystore/operator.json && \
   sudo shred -u /tmp/keystore.json
   ```
   Note: the user sets `GENLAYERNODE_PASSWORD` (Docker: `NODE_PASSWORD`) in .env to the export passphrase; doctor does not check it; the node unlocks the keystore when it starts
7. For keystore directory: Already in correct location, just verify contents show UTC--* file

**Note**: The keystore lives in the shared data directory (`/opt/genlayer-node/v0.6/data/node/keystore/`, reached through the version's `data` link).

### 6. Start WebDriver
WebDriver is required for web-based contract operations. Start it before running doctor check:

```bash
cd /opt/genlayer-node && sudo docker compose up -d   # sudo: .env is mode 600 (secrets)
# Optional: read-only Docker API proxy for WebDriver metrics (binary node: DOCKER_HOST=tcp://127.0.0.1:2375)
sudo docker compose up -d docker-socket-proxy
```

Wait for WebDriver to be healthy (at most 3 minutes):
```bash
for i in $(seq 1 36); do
  sudo docker inspect --format='{{.State.Health.Status}}' genlayer-node-webdriver | grep -q '^healthy$' && break
  echo "Waiting for WebDriver to be healthy..."
  sleep 5
done
sudo docker inspect --format='{{.State.Health.Status}}' genlayer-node-webdriver
```

Verify WebDriver is running:
```bash
sudo docker ps | grep webdriver
curl -s http://localhost:4444/status | jq '.value.ready'
```

### 7. Run Doctor Check
Run the doctor command to verify all configuration is correct:

```bash
# v0.6+: the subcommand is `doctor` (NOT `doctor check`). Use `set -a` so .env keys are
# EXPORTED to the child process. Doctor checks the consensus deployment against
# consensus.consensusaddress / chainid and the protocol manifest from config.yaml.
cd /opt/genlayer-node
sudo -u genlayer bash -c 'set -a; . ./.env; set +a; ./bin/genlayernode doctor'
```

**Expected output on success:** all checks ✓ — GenLayer Chain RPC + WebSocket, consensus
deployment (registry sealed, chain id and contracts match the manifest), validator/operator
wallet (validator mode), GenVM binaries + module config, at least one LLM provider, and
WebDriver connectivity.

**If checks fail:**
- GenVM Binaries "not found at opt/genvm/<ver>/...": the `opt` symlink is missing —
  `ln -sfn ${VERSION}/opt /opt/genlayer-node/opt` (v0.6+), then re-run.
- GenVM Binaries missing entirely: re-run setup.py (see Download & Setup).
- LLM provider "not set" though `.env` has it: you sourced `.env` without `set -a` (vars not exported).
- WebSocket fails (401): the RPC provider key `GENLAYERNODE_ROLLUP_GENLAYERCHAINRPCKEY` is empty or wrong.
- Consensus deployment check fails: the manifest is missing, or `consensusaddress` / `chainid` do not match it.
- WebDriver not ready: check `docker logs genlayer-node-webdriver`.

### 8. Deployment Method
Ask user which deployment method they prefer:

- **Systemd Service** (Recommended): Auto-restart, journald logs
- **Docker Compose**: All-in-one containers
- **Manual**: screen/tmux session

#### Systemd Service Setup (Recommended)

1. Create the service file at `/etc/systemd/system/genlayer-node.service`:

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

The node runs as the `genlayer` service user (not in the docker group) and reads the keystore
passphrase from `GENLAYERNODE_PASSWORD` in `EnvironmentFile` — no `--password` argument.

2. Enable and start the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable genlayer-node
sudo systemctl start genlayer-node
```

3. Check service status:
```bash
sudo systemctl status genlayer-node
```

4. View logs:
```bash
journalctl -u genlayer-node -f
```

#### Docker Compose Deployment

```bash
cd /opt/genlayer-node/${VERSION}
sudo chown -R 10001:10001 ./data/      # the container runs as uid 10001
sudo docker compose --profile node run --rm --entrypoint /app/bin/genlayernode genlayer-node doctor
sudo docker compose --profile node up -d
# Add central telemetry (Alloy metrics + logs push): append --profile monitoring

# When switching back to binary/systemd: stop Docker and restore shared-data ownership
# sudo docker compose --profile node down && sudo chown -R genlayer:genlayer /opt/genlayer-node/data/
```

**v0.6+ / pre-release Docker notes:**
- Run `docker compose` **from the version directory** (e.g. `/opt/genlayer-node/<version>`)
  so relative bind mounts (`./configs`, `./data`, `./genvm-module-*.yaml`) resolve.
- **Full node**: set `node.mode: "full"` in config.yaml — no wallet/operator/keystore/staking
  needed (logs: "full node mode detected, skipping validator setup").
- **Custom image (e.g. ECR)**: override the node service `image:` (edit the compose or add a
  `docker-compose.override.yml`). If the instance role lacks ECR permissions, authenticate
  Docker with an admin token:
  `aws ecr get-login-password --profile <p> --region <r> | docker login --username AWS --password-stdin <acct>.dkr.ecr.<r>.amazonaws.com`
- **LLM in Docker**: mount a `genvm-module-llm.yaml` (built from the release's
  `genvm-modules-llm-release.yaml`) onto `/app/opt/genvm/current/config/genvm-module-llm.yaml`
  so your provider is enabled. Releases before rc.2 have no `current` link: mount onto
  `/app/opt/genvm/<ver>/config/genvm-module-llm.yaml` and set `GENVM_VERSION` in `.env`.
  Without it the image's default LLM config is used. Compose loads an override file automatically:
  ```bash
  cd /opt/genlayer-node/${VERSION}
  GENVM_REL=$(sed -n 's/^ *root_dir: *\.\///p' configs/node/config.yaml)   # e.g. opt/genvm/current
  sudo -u genlayer tee docker-compose.override.yml >/dev/null <<EOF
  services:
    genlayer-node:
      volumes:
        - ./${GENVM_REL}/config/genvm-module-llm.yaml:/app/opt/genvm/current/config/genvm-module-llm.yaml:ro
  EOF
  ```
- **Possible crash-loop — symptom-driven, not version-gated**: IF the boot GenVM self-test
  fails with `ADDRESS_FORBIDDEN` reaching the webdriver (genvm's SSRF filter blocks the
  `webdriver-container` HOSTNAME's private IP; literal IPs are never filtered), point
  `webdriver_host` at the webdriver's literal IP. Apply only if you actually see the symptom —
  a release may already allow the configured webdriver_host, in which case it won't occur. Do
  NOT hardcode a compose subnet in shipped assets. See sharp-edge
  `docker-webdriver-host-ssrf-address-forbidden`.

#### Manual Deployment (screen/tmux)

```bash
screen -S genlayer
cd /opt/genlayer-node && sudo -u genlayer bash -c 'set -a; . ./.env; set +a; ./bin/genlayernode run -c $(pwd)/configs/node/config.yaml'
# Detach: Ctrl+A, D
# Reattach: screen -r genlayer
```

### 9. Verify Node Running

After starting the node, verify it's running and syncing:

**Health check:**
```bash
curl -s http://localhost:9153/health | jq
```

Expected response (example: Testnet Bradbury):
```json
{
  "status": "healthy",
  "network": "bradbury-phase2",
  "node_version": "v0.6.0",
  "genvm_version": "v0.6.0-rc10"
}
```

**Sync status:**
```bash
curl -s http://localhost:9153/metrics | grep genlayer_node_synced
```

Expected output (1 = synced, 0 = syncing):
```
genlayer_node_synced{node="0x..."} 1
```

**Check blocks behind:**
```bash
curl -s http://localhost:9153/metrics | grep genlayer_node_blocks_behind
```

**View logs (systemd):**
```bash
journalctl -u genlayer-node -f --no-hostname
```

**View logs (Docker):**
```bash
docker logs -f genlayer-node
```

### 10. Monitoring (Optional)
- Enable telemetry push to GenLayer Foundation's Grafana Cloud using Alloy
- Requires monitoring credentials (request from the GenLayer Foundation team)
- Collects Prometheus metrics and node logs
- See `monitoring-procedure.md` for complete setup
- Reference: https://docs.genlayer.com/validators/monitoring

## Deployment Methods

### Binary (Systemd Service) - Recommended for production
- Persistent service with auto-restart
- Logs via journalctl
- Environment from .env file
- Service file at `/etc/systemd/system/genlayer-node.service`

### Docker Compose
- All-in-one container deployment
- Includes monitoring profile
- Override files for LLM config

## Automation

This skill is defined by canonical YAML files:

- **skill.yaml** - Main procedure, patterns, anti-patterns, defaults, config wizard
- **sharp-edges.yaml** - 30+ common gotchas with detection and fixes
- **validations.yaml** - 25+ automated pre/post checks
- **collaboration.yaml** - Dependencies and composition

## Usage

Invoke this skill when:
- Setting up a new validator node
- Someone asks "how do I become a validator"
- Installing GenLayer node software
- Troubleshooting validator installation issues
- Upgrading an existing node

The skill will guide through each step interactively, verifying prerequisites and configuration at each stage.

### How to Invoke

**Basic invocation:**
```
I want to set up a validator node
```

**With specific version:**
```
Install validator node version v0.4.4
```

**With latest version:**
```
Install validator node using the latest version
```
or simply:
```
Install validator node latest
```

When you use the word "latest", the skill will automatically fetch and install the most recent version from the official storage.

## Complete Installation Steps

| Step | Description | Key Actions |
|------|-------------|-------------|
| 0 | **Determine Server Location** | **Local vs Remote, SSH vs GCP vs AWS** |
| 1 | Check Prerequisites | Architecture, Docker, Python 3.10+, cosign; install what is missing |
| 2 | Full Node, New Validator or Existing? | Staking wizard or skip |
| 3 | Download & Setup | Download tarball, verify (cosign + SHA256), install.sh (extract + GenVM setup), shared data dir, symlinks |
| 4 | Environment (.env) | RPC provider key (if needed), LLM key and (validator) password placeholders |
| 5 | Node Config (config.yaml) | Network values + protocol manifest (from the network's docs), node mode, validator address, operator address, ports |
| 6 | Operator Key | Upload keystore (method depends on Step 0) or generate new (validator only) |
| 7 | Start WebDriver | `docker compose up -d`, wait for healthy |
| 8 | Run Doctor Check | Verify all configuration |
| 9 | Deployment Method | Systemd (recommended), Docker, or manual |
| 10 | Verify Node Running | Health check, sync status |
| 11 | Monitoring (Optional) | Enable telemetry push |

## Key Decision Points

1. **Server location?** -> Local / Remote SSH / GCP / AWS / Azure / Other cloud
2. **Node mode?** -> Full node / Validator (new: staking wizard, or existing)
3. **.env source?** -> Copy from previous / Create new
4. **Config source?** -> Use example (recommended) / Copy from previous
5. **Operator key?** -> Upload keystore.json / Upload keystore directory / Copy from previous / Generate new
6. **Deployment?** -> Systemd (recommended) / Docker / Manual
7. **Monitoring?** -> Enable / Skip

## Critical Input Rules

**IMPORTANT**: When collecting user inputs, follow these rules:

### config.yaml Rollup URLs (Step 4) - Ask via Wizard
Use AskUserQuestion with these options (tool requires minimum 2 options):
- **RPC URL** - Options: ["Skip for now", "I'll enter my URL"]
- **WebSocket URL** - Options: ["Skip for now", "I'll enter my URL"]

**IMPORTANT**: The "Other" text field in AskUserQuestion does not work reliably. When user selects "I'll enter my URL", follow up with a **plain text question** asking them to type the URL directly.

Example flow:
```
Step 1: AskUserQuestion
  Question: "Do you have the GenLayer Chain RPC URL?" (from your network's docs)
  Options:
    - "Skip for now" (will need to configure manually later)
    - "I'll enter my URL"

Step 2: If user selected "I'll enter my URL", ask:
  "Please enter the RPC URL:"
  [User types URL directly in chat]
```

### config.yaml Configuration (Step 4) - Node Identity Group
These values are configured in config.yaml during the Node Identity group:
- **Validator Wallet Address** - Ask in Group 1: Node Identity
- **Operator Address** - Ask in Group 1: Node Identity (will be set after importing operator key)

### Sensitive Values - NEVER Ask for These
These values must NEVER be collected by Claude. Generate .env with placeholders, then ask user to update manually on the VM:
- **RPC Provider Key** - Leave empty: `GENLAYERNODE_ROLLUP_GENLAYERCHAINRPCKEY=`
- **LLM API Key** - Leave empty (e.g. `OPENROUTERKEY=`)
- **Node Password** - Leave empty: `GENLAYERNODE_PASSWORD=` (Docker: `NODE_PASSWORD=`)

After generating .env, instruct user to:
1. SSH to the VM
2. Edit the .env file manually to set sensitive values
3. Confirm when done

## Secret Masking Policy

**CRITICAL**: When displaying any output that may contain secret values, they MUST be masked.

### What Qualifies as a Secret
- **LLM API Keys**: `HEURISTKEY`, `COMPUT3KEY`, `IOINTELLIGENCEKEY`, and other provider keys
- **RPC Key**: `GENLAYERNODE_ROLLUP_GENLAYERCHAINRPCKEY` (RPC provider, e.g. Conduit)
- **Passwords**: `GENLAYERNODE_PASSWORD`, `NODE_PASSWORD`, export passphrases
- **Auth Tokens**: Monitoring credentials, API tokens
- **Private Keys**: Never displayed at all

### FORBIDDEN OPERATIONS

**NEVER execute these types of commands that expose secrets:**

```bash
# FORBIDDEN - DO NOT USE
grep '<LLM_KEY>' /opt/genlayer-node/.env
cat /opt/genlayer-node/.env | grep KEY
gcloud compute ssh ... --command="grep '<LLM_KEY>' /opt/genlayer-node/.env"
ssh username@host "cat /opt/genlayer-node/.env"
```

**Why this is forbidden:**
1. **Exposes secrets in command output** - Keys will be visible in plain text
2. **Violates security policy** - Secrets must NEVER be displayed unmasked
3. **Creates audit trail of secrets** - Command history will contain the secret
4. **Risk of screenshot/log exposure** - User may share output containing secrets

**Instead, instruct the user to check values themselves:**
```bash
# CORRECT - Instruct user to run this on their VM
"To verify your API key is set, SSH to your VM and run:
  grep '<YOUR_LLM_KEY>' /opt/genlayer-node/.env
This will show the key value on your secure terminal."
```

### Masking Rules

1. **When displaying .env file contents**:
   - Mask all API keys showing only first 8 and last 4 characters
   - Example: `HEURISTKEY=abc12345********...xyz9` instead of full key

2. **When displaying command output**:
   - If output contains secrets, mask them before showing to user
   - Example: `export HEURISTKEY=abc12345********...xyz9`

3. **When verifying configuration**:
   - Show masked values: `HEURISTKEY: Set (abc12345********...xyz9)`
   - Never show the full secret value

4. **In logs and error messages**:
   - Ensure logs don't expose secrets
   - Replace any secret values with `***MASKED***`

5. **Remote command execution**:
   - NEVER use `--command` flag with SSH/gcloud to read secrets
   - NEVER pipe secret-containing files through remote commands
   - NEVER execute grep/cat on files with secrets via remote tools

### Implementation Examples

**Reading .env file:**
```bash
# Before displaying, mask secrets using sed (passwords fully, keys first 8 + last 4)
sudo sed -E \
  -e 's/^([A-Z_0-9]*(PASSWORD|PASSPHRASE)[A-Z_0-9]*=).+/\1***MASKED***/' \
  -e '/\*\*\*MASKED\*\*\*$/!s/^([A-Z_0-9]*(KEY|TOKEN)[A-Z_0-9]*=)(.{8}).*(.{4})$/\1\3********...\4/' \
  /opt/genlayer-node/.env
```

**Verifying environment variables:**
```bash
# Show only that key is set, not the value
env | grep -E 'KEY|PASSWORD|TOKEN' | sed -E 's/=.*/=***MASKED***/'
```

**Creating systemd service:**
- NEVER include plain-text passwords in service files or on the command line
- Use `EnvironmentFile` directive to load from .env
- Example: `ExecStart=/opt/genlayer-node/bin/genlayernode run -c /opt/genlayer-node/configs/node/config.yaml` (the node reads `GENLAYERNODE_PASSWORD` from the environment)

### When User Needs to See Full Value
If user needs the actual secret value:
1. Instruct them to read the file directly on their VM
2. Example: "To view your API key, run: `cat /opt/genlayer-node/.env | grep <YOUR_LLM_KEY>`"
3. Never display the full secret in the conversation

### Can Offer Options
These can be presented as multiple choice:
- Full node, new validator or existing?
- LLM provider selection (Heurist, Comput3, io.net, etc.) - select provider, NOT the key
- Operator key source (import, copy, generate)
- Deployment method (systemd, docker, manual)
- Enable monitoring? (yes/no)

## Procedure Documents

This skill includes focused step-by-step procedure guides:

| Document | Purpose |
|----------|---------|
| `install-procedure.md` | Complete installation from scratch |
| `update-procedure.md` | Zero-downtime update procedure |
| `staking-wizard-procedure.md` | Running the staking wizard to create validator wallet |
| `monitoring-procedure.md` | Enable centralized monitoring with Grafana/Alloy |
| `common-procedures.md` | Shared commands used by install and update |
| `pre-update-checklist.md` | Checklist before starting any update |

## Official Documentation

For the latest official setup guide, see:
https://docs.genlayer.com/validators/setup-guide
