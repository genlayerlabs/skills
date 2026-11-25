#!/usr/bin/env bash
# Make the genlayer CLI (staking wizard, validator-join, account send...) talk to
# the network's CURRENT phase, even when the CLI release still points at an older one.
#
#   setup-cli-network.sh \
#     --cli-network testnet-bradbury \
#     --deployment-dir bradbury-phase-3 \
#     --deployment-key genlayerOrbitTestnet.deployment_bradbury_phase_3
#
# Creates (or refreshes) a custom CLI profile named after the deployment, e.g.
# `bradbury-phase-3`, from the genlayer-networks deployment book, and prints that
# name: use it as --network in every genlayer command.
#
# Runs on the machine with the genlayer CLI (usually the operator's laptop, not the server).
# Requires: genlayer (>= 0.40.1: first release with Bradbury Phase 3 built in), node, jq, curl.
set -euo pipefail

CLI_NETWORK="" DEPLOYMENT_DIR="" DEPLOYMENT_KEY=""
BOOKS="https://raw.githubusercontent.com/genlayerlabs/genlayer-networks/main"
while [ $# -gt 0 ]; do
  case "$1" in
    --cli-network)    CLI_NETWORK="$2"; shift 2 ;;
    --deployment-dir) DEPLOYMENT_DIR="$2"; shift 2 ;;
    --deployment-key) DEPLOYMENT_KEY="$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$CLI_NETWORK" ] && [ -n "$DEPLOYMENT_DIR" ] && [ -n "$DEPLOYMENT_KEY" ] \
  || { echo "need --cli-network, --deployment-dir and --deployment-key" >&2; exit 2; }
command -v genlayer >/dev/null || { echo "genlayer CLI not installed: npm install -g genlayer" >&2; exit 1; }

book=$(mktemp); trap 'rm -f "$book"' EXIT
curl -fsS "$BOOKS/$DEPLOYMENT_DIR/testnet_deployments.json" -o "$book" \
  || { echo "cannot fetch genlayer-networks/$DEPLOYMENT_DIR deployment book" >&2; exit 1; }
addr() { jq -r ".${DEPLOYMENT_KEY}.$1 // empty" "$book"; }
want_staking=$(addr Staking)
[ -n "$want_staking" ] || { echo "no Staking address under $DEPLOYMENT_KEY" >&2; exit 1; }

# Always pin the CLI to the deployment book. The built-in profile may lag a phase
# launch (the CLI release ships addresses), and phases share a chain id, so a stale
# built-in profile still "works" - it just stakes on the old phase.
echo "Creating CLI network profile '$DEPLOYMENT_DIR' (base $CLI_NETWORK) from the deployment book." >&2
# Explicit overrides only: `--deployment <book>` is refused for books that hold both
# RoundsStorage and Rounds (CLI 0.40.0), so every address is passed by hand.
genlayer network remove "$DEPLOYMENT_DIR" >/dev/null 2>&1 || true
genlayer network add "$DEPLOYMENT_DIR" --base "$CLI_NETWORK" \
  --consensus-main "$(addr ConsensusMain)" \
  --consensus-data "$(addr ConsensusData)" \
  --staking        "$want_staking" \
  --fee-manager    "$(addr FeeManager)" \
  --rounds-storage "$(addr RoundsStorage)" \
  --appeals        "$(addr Appeals)" >&2
echo "✓ Use --network $DEPLOYMENT_DIR in every genlayer command" >&2
echo "$DEPLOYMENT_DIR"
