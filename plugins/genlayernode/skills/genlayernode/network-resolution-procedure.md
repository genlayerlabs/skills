# Network & Version Resolution Procedure

## Goal
Decide **which network, which phase and which node version** to install, and fetch
that network's config and trusted protocol manifest, **without trusting any value
written into this skill**. Every install and every update starts here.

## Why nothing is hardcoded

GenLayer runs several networks at once and replaces them over time: Bradbury
(phases 1 → 2 → 3 …), then Clarke, then Mainnet. Each phase is a new consensus
deployment, often **on the same chain id**, and each node release can change the
config format. A contract address, genesis block or version written into this skill
is wrong the day after the next launch, and on a shared chain a wrong address does
not fail loudly: the node syncs a dead deployment and the staking CLI stakes on it.

So the skill keeps only **identity and pointers** (`networks.yaml`) and resolves
everything else at run time from published sources, cross-checked against each other.

| What | Source (public) | Can lag a launch? |
|------|-----------------|-------------------|
| Which networks exist, which phase is current | `networks.yaml` (this skill) | Yes: edit `current_phase` on launch |
| Contract addresses of the current phase | `genlayer-networks/<deployment_dir>/testnet_deployments.json` | No: written at deploy time |
| Node config (`rollup` + `consensus`) | `genlayer-docs/content/validators/<config_file>.yaml` | **Yes**: synced on node releases |
| Trusted protocol manifest | `genlayer-docs/content/validators/<config_file>.protocol-manifest.json` | **Yes** |
| Node versions | `gs://gh-af/genlayer-node/bin/amd64/` listing | No |
| CLI staking addresses | the installed `genlayer` CLI release | **Yes**: fixed by `setup-cli-network.sh` |

## Steps

### R1. Choose the network

Read `networks.yaml`. Offer only entries with `status: active`.

- One active network → confirm it with the user ("Bradbury Testnet, Bradbury Phase 3: correct?").
- Several active → ask which one (AskUserQuestion, one option per network).
- User names a `planned` network (e.g. Clarke before launch) → stop: "Clarke has not
  launched yet; this skill will support it once `networks.yaml` lists it as active."
- User names a `retired` network (e.g. Asimov) → stop and explain it is retired;
  offer the active network instead.

Record for the rest of the run (example values for Bradbury Phase 3):

```bash
NETWORK_ID=bradbury
CHAIN_ID=4221
CONFIG_FILE=bradbury
CLI_NETWORK=testnet-bradbury
DEPLOYMENT_DIR=bradbury-phase-3
DEPLOYMENT_KEY=genlayerOrbitTestnet.deployment_bradbury_phase_3
NODE_NETWORK_NAME=bradbury-phase3
RELEASE_LINE=v0.6
PREVIOUS_DIRS=bradbury-phase-2,bradbury     # from previous_phases[].deployment_dir
```

### R2. Choose the node version

The version is **always** resolved, never assumed:

```bash
scripts/resolve-version.sh --line "$RELEASE_LINE"          # latest stable, e.g. v0.6.0
scripts/resolve-version.sh --line "$RELEASE_LINE" --list   # to let the user pick
scripts/resolve-version.sh --check v0.6.1                  # user named one: verify it exists
```

- "latest" or no preference → latest stable on the network's release line.
- User names a version **outside** the network's release line → warn: the config
  format and manifest are tied to the release line; ask for explicit confirmation.
- Pre-releases (`-rc`, `-alpha`) only when the user asks (`--pre`).

### R3. Fetch and verify the network config (on the server)

```bash
scripts/resolve-network.sh \
  --config-file "$CONFIG_FILE" --chain-id "$CHAIN_ID" \
  --deployment-dir "$DEPLOYMENT_DIR" --deployment-key "$DEPLOYMENT_KEY" \
  --previous-dirs "$PREVIOUS_DIRS" \
  --out /tmp/genlayer-network
```

It checks, in order, and stops on the first failure:

1. config `consensus.consensusaddress` == manifest `registry` (same deployment),
2. config `chainid` == manifest `chainId` == the network's chain id,
3. that AddressManager == the current phase's AddressManager in the deployment book.

| Exit | Meaning | What to do |
|------|---------|------------|
| 0 | Verified | Continue. `/tmp/genlayer-network/` holds `network.yaml`, `protocol-manifest.json`, `resolved.env` |
| 3 | Docs still describe an **older phase** (the script names it) | **Stop.** Do not install with these files. Ask the user for the current phase's config + manifest (GenLayer announcement / Discord), then re-run with `--config-url <url> --manifest-url <url>` (`file://` paths work). The same three checks still run. |
| 4 | Files inconsistent or pre-v0.6 format | Stop and report; do not hand-edit around it |
| 5 | Fetch failed | Check the server's outbound HTTPS, retry |

Show the user the resolved values (they are public, not secrets):

```bash
cat /tmp/genlayer-network/resolved.env
```

### R4. Point the staking CLI at the current phase (operator's laptop)

Only needed when the user will run `genlayer` staking or account commands.

```bash
NET=$(scripts/setup-cli-network.sh \
  --cli-network "$CLI_NETWORK" \
  --deployment-dir "$DEPLOYMENT_DIR" --deployment-key "$DEPLOYMENT_KEY")
# NET=bradbury-phase-3  -> use `--network "$NET"` in EVERY genlayer command
genlayer staking epoch-info --network "$NET"    # sanity check: epoch, min stake
```

This creates a CLI profile from the deployment book, because a CLI release can still
point its built-in `testnet-bradbury` at the previous phase (same chain id, so it
"works" and stakes on the wrong deployment). Requires `genlayer` ≥ 0.40.1.

### R5. Confirm after the node starts

The node names the deployment it detected from `consensusaddress` (it also logs it
as `network=` on start). After start:

```bash
curl -s http://localhost:9153/health | jq -r '.network'
```

| Result | Meaning |
|--------|---------|
| `NODE_NETWORK_NAME` (e.g. `bradbury-phase3`) | Correct |
| A previous phase's name (e.g. `bradbury-phase2`) | **Stale config.** Stop the node, go back to R3 |
| `custom` / empty | This release was built before the phase existed and cannot name it. Not an error by itself (R3 already proved the address), but prefer a release that knows the phase: check for a newer patch on the release line |

## When a new phase or network launches (maintainers)

1. Wait for the deployment folder in `genlayer-networks` (e.g. `bradbury-phase-4/`).
2. In `networks.yaml`: move the old `current_phase` into `previous_phases`, write the
   new `current_phase` (deployment dir, deployment key, node network name, release line).
3. A new network (Clarke, Mainnet): set `status: active` and fill its `TBD` fields.
   Retire the network it replaces (`status: retired`).
4. Nothing else in the skill changes: addresses, genesis, RPC hosts, manifests and
   versions are all resolved at run time.
