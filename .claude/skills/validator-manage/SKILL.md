---
name: validator-manage
description: Manage GenLayer validators across testnets using the genlayer CLI. Join, fund, set identity, list, and organize validators per network and owner.
user-invocable: true
allowed-tools: [Bash, Read, Grep, Glob, AskUserQuestion]
---

# Validator Manage

## Purpose
Manage GenLayer validators across testnet networks (asimov, bradbury, etc.) using the local `genlayer` CLI. Covers listing, joining, funding operators, setting identities, renaming accounts, and producing per-network reports.

## Quick Reference
- Tool: `genlayer` CLI (npm global package)
- Config: `~/.genlayer/genlayer-config.json`
- Keystores: `~/.genlayer/keystores/<name>.json`
- Memory: project memory `validators.md`

## Prerequisites

```bash
# Verify CLI is installed and check version
genlayer --version

# Check current network
genlayer network list

# List available accounts
genlayer account list
```

## Key Concepts

### Address Roles
- **Owner**: Controls the validator on-chain. Can set identity, exit, deposit. One owner can own many validators.
- **Operator**: Runs the node software. Each validator has exactly one operator. Different per network.
- **Validator**: The on-chain wallet created when joining. Assigned automatically by the staking contract.

### Network Isolation
Each testnet has its own staking contract. Validators must be joined separately per network. Operator keys should be unique per network (same owner, different operators).

## Operations

### Switch Network

```bash
genlayer network set testnet-bradbury
genlayer network info
```

### List Validators (Per Network)

```bash
# Table view with stake, status, weight
genlayer staking validators

# Detailed info for a specific validator
genlayer staking validator-info <validator-address>
```

### Join Validator

```bash
genlayer staking validator-join \
  --amount "100000gen" \
  --operator <operator-address> \
  --account "<owner-cli-name>"
```

Returns the on-chain `validatorWallet` address.

### Fund Operator

```bash
genlayer account send --account "<owner-cli-name>" <operator-address> <amount>
```

### Set Moniker (Identity)

**Requires the owner account**, not the operator.

```bash
genlayer staking set-identity <validator-address> \
  --moniker "GenLayerLabs Validator N" \
  --account "<owner-cli-name>"
```

### Create New Operator Accounts

```bash
genlayer account create \
  --name "GenLayerLabs Bradbury Validator N" \
  --password "<password>" \
  --no-set-active
```

### Rename Local Account

Account names are just filenames in the keystore directory:

```bash
mv ~/.genlayer/keystores/"Old Name.json" ~/.genlayer/keystores/"New Name.json"
```

After renaming, unlock the account under the new name:

```bash
genlayer account unlock --account "New Name"
```

### Check Balances

```bash
genlayer account show --account "<name>"
```

### Epoch & Staking Info

```bash
genlayer staking epoch-info
genlayer staking active-validators
genlayer staking quarantined-validators
genlayer staking banned-validators
```

## Reporting Format

Always use box-drawing tables for terminal output, grouped by network and owner:

```
═══════════════════════════════════════════════════════════════════════════════════
 TESTNET-BRADBURY
═══════════════════════════════════════════════════════════════════════════════════

Owner: 0xAAAA...AAAA (Owner Name) — 100K GEN remaining
┌──────────────────────────┬──────────────────────┬──────────────────────┬────────┐
│         Moniker          │      Validator       │       Operator       │ Status │
├──────────────────────────┼──────────────────────┼──────────────────────┼────────┤
│ Example Validator 1      │ 0xBBBB...BBBB        │ 0xCCCC...CCCC        │ pending│
└──────────────────────────┴──────────────────────┴──────────────────────┴────────┘
```

## Batch Operations

When joining multiple validators:
1. Create all operator accounts first (`account create`)
2. Join all validators with the owner account (`staking validator-join`)
3. Fund all operators (`account send`)
4. Set monikers for all (`staking set-identity`)
5. Verify with `staking validators`
6. Update memory file with new mappings

## Current Accounts

See the project memory file `validators.md` for the full mapping of owners, validators, and operators across networks.

## Automation
See `skill.yaml` for procedure definition.
See `sharp-edges.yaml` for common pitfalls.
