#!/usr/bin/env bash
# Fetch a GenLayer network's node config + trusted protocol manifest, and prove
# they belong to the network's CURRENT phase before anything is written to a node.
#
#   resolve-network.sh \
#     --config-file bradbury \
#     --deployment-dir bradbury-phase-3 \
#     --deployment-key genlayerOrbitTestnet.deployment_bradbury_phase_3 \
#     --chain-id 4221 \
#     [--previous-dirs bradbury-phase-2,bradbury] \
#     [--config-url URL --manifest-url URL]   # use files the GenLayer team published elsewhere
#     [--out DIR]                             # default ./network-resolved
#
# All arguments come from networks.yaml. Writes to DIR:
#   network.yaml            the network's rollup + consensus sections (as published)
#   protocol-manifest.json  the trusted manifest -> configs/node/protocol-manifest.json
#   resolved.env            CONSENSUS_ADDRESS, CHAIN_ID, GENESIS, RPC_URL, WSS_URL, ROLLUP_PROVIDER
#
# Exit codes: 0 verified | 2 usage | 3 published files point at another deployment
#             (docs not yet updated for the current phase) | 4 files inconsistent | 5 fetch failed
set -euo pipefail

CONFIG_FILE="" DEPLOYMENT_DIR="" DEPLOYMENT_KEY="" CHAIN_ID="" PREVIOUS_DIRS=""
CONFIG_URL="" MANIFEST_URL="" OUT="./network-resolved"
DOCS="https://raw.githubusercontent.com/genlayerlabs/genlayer-docs/main/content/validators"
BOOKS="https://raw.githubusercontent.com/genlayerlabs/genlayer-networks/main"

while [ $# -gt 0 ]; do
  case "$1" in
    --config-file)    CONFIG_FILE="$2"; shift 2 ;;
    --deployment-dir) DEPLOYMENT_DIR="$2"; shift 2 ;;
    --deployment-key) DEPLOYMENT_KEY="$2"; shift 2 ;;
    --chain-id)       CHAIN_ID="$2"; shift 2 ;;
    --previous-dirs)  PREVIOUS_DIRS="$2"; shift 2 ;;
    --config-url)     CONFIG_URL="$2"; shift 2 ;;
    --manifest-url)   MANIFEST_URL="$2"; shift 2 ;;
    --out)            OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
for v in CONFIG_FILE DEPLOYMENT_DIR DEPLOYMENT_KEY CHAIN_ID; do
  [ -n "${!v}" ] || { echo "missing --$(echo "$v" | tr 'A-Z_' 'a-z-')" >&2; exit 2; }
done
CONFIG_URL=${CONFIG_URL:-"$DOCS/$CONFIG_FILE.yaml"}
MANIFEST_URL=${MANIFEST_URL:-"$DOCS/$CONFIG_FILE.protocol-manifest.json"}

lc() { tr 'A-F' 'a-f'; }
fail() { echo "✗ $2" >&2; exit "$1"; }
ok() { echo "✓ $1"; }

# Read `key: value` from a top-level section of a flat YAML file (no yq needed).
yaml_get() { # section key file
  awk -v s="$1" -v k="$2" '
    /^[^[:space:]#][^:]*:/ { sect = $0; sub(/:.*/, "", sect) }
    sect == s && $0 ~ "^[[:space:]]+" k ":" {
      v = $0; sub("^[[:space:]]+" k ":[[:space:]]*", "", v); sub(/[[:space:]]+#.*$/, "", v)
      gsub(/^"|"$/, "", v); print v; exit
    }' "$3"
}

book_address_manager() { # deployment_dir [deployment_key] -> AddressManager, or empty
  # With a key, read exactly that deployment; without (previous phases), the first one in the book.
  curl -fsS "$BOOKS/$1/testnet_deployments.json" 2>/dev/null \
    | if [ -n "${2:-}" ]; then jq -r ".${2}.AddressManager // empty"
      else jq -r '[.. | objects | select(has("AddressManager")) | .AddressManager][0] // empty'; fi
}

mkdir -p "$OUT"
curl -fsS "$CONFIG_URL"   -o "$OUT/network.yaml"           || fail 5 "cannot fetch network config: $CONFIG_URL"
curl -fsS "$MANIFEST_URL" -o "$OUT/protocol-manifest.json" || fail 5 "cannot fetch protocol manifest: $MANIFEST_URL"
jq -e . "$OUT/protocol-manifest.json" >/dev/null           || fail 4 "protocol manifest is not valid JSON"

CFG_ADDR=$(yaml_get consensus consensusaddress "$OUT/network.yaml")
CFG_CHAIN=$(yaml_get consensus chainid "$OUT/network.yaml")
GENESIS=$(yaml_get consensus genesis "$OUT/network.yaml")
RPC_URL=$(yaml_get rollup genlayerchainrpcurl "$OUT/network.yaml")
WSS_URL=$(yaml_get rollup genlayerchainwebsocketurl "$OUT/network.yaml")
PROVIDER=$(yaml_get rollup provider "$OUT/network.yaml")
MAN_ADDR=$(jq -r '.registry // empty' "$OUT/protocol-manifest.json")
MAN_CHAIN=$(jq -r '.chainId // empty' "$OUT/protocol-manifest.json")

[ -n "$CFG_ADDR" ] || fail 4 "network config has no consensus.consensusaddress (pre-v0.6 format?)"

# 1. The config and the manifest describe the same deployment.
[ "$(echo "$CFG_ADDR" | lc)" = "$(echo "$MAN_ADDR" | lc)" ] \
  || fail 4 "config consensusaddress $CFG_ADDR != manifest registry $MAN_ADDR"
ok "config and manifest name the same AddressManager ($CFG_ADDR)"

# 2. Both are on the network's chain.
[ "$CFG_CHAIN" = "$CHAIN_ID" ] && [ "$MAN_CHAIN" = "$CHAIN_ID" ] \
  || fail 4 "chain id mismatch: expected $CHAIN_ID, config $CFG_CHAIN, manifest $MAN_CHAIN"
ok "chain id $CHAIN_ID"

# 3. That deployment is the CURRENT phase in the deployment book. Phases share
#    a chain, so this is the only check that catches docs still on an old phase.
BOOK_ADDR=$(book_address_manager "$DEPLOYMENT_DIR" "$DEPLOYMENT_KEY")
[ -n "$BOOK_ADDR" ] || fail 5 "cannot read $DEPLOYMENT_KEY.AddressManager from genlayer-networks/$DEPLOYMENT_DIR"
if [ "$(echo "$CFG_ADDR" | lc)" != "$(echo "$BOOK_ADDR" | lc)" ]; then
  stale="an unknown deployment"
  IFS=',' read -ra prev <<< "$PREVIOUS_DIRS"
  for d in "${prev[@]}"; do
    [ -n "$d" ] || continue
    [ "$(book_address_manager "$d" | lc)" = "$(echo "$CFG_ADDR" | lc)" ] && { stale="$d"; break; }
  done
  fail 3 "published files point at $stale ($CFG_ADDR), not $DEPLOYMENT_DIR ($BOOK_ADDR).
  The docs have not been updated for the current phase yet. Do NOT install with these files.
  Get $DEPLOYMENT_DIR's config + manifest from the GenLayer team and re-run with --config-url/--manifest-url."
fi
ok "matches the current deployment in genlayer-networks/$DEPLOYMENT_DIR"

cat > "$OUT/resolved.env" <<EOF
CONSENSUS_ADDRESS=$CFG_ADDR
CHAIN_ID=$CHAIN_ID
GENESIS=$GENESIS
RPC_URL=$RPC_URL
WSS_URL=$WSS_URL
ROLLUP_PROVIDER=$PROVIDER
EOF
echo "Resolved $DEPLOYMENT_DIR -> $OUT/ (network.yaml, protocol-manifest.json, resolved.env)"
