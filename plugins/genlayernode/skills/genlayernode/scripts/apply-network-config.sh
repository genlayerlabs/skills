#!/usr/bin/env bash
# Write a resolved network into a node release's config.yaml and install its manifest.
#
#   apply-network-config.sh --resolved DIR --node-dir /opt/genlayer-node/v0.6.0 \
#     [--validator 0x...] [--operator 0x...]
#
# DIR is the output of resolve-network.sh (resolved.env + protocol-manifest.json).
# Edits <node-dir>/configs/node/config.yaml in place (backup: config.yaml.bak):
#   rollup.genlayerchainrpcurl / genlayerchainwebsocketurl / provider
#   consensus.consensusaddress / chainid / genesis (uncommented)
#   node.network (only this key: set when the network publishes one, e.g. Clarke;
#     otherwise an active value left from another network is commented out so the
#     node detects the name from the address)
#   node.validatorWalletAddress / operatorAddress (when given)
# and copies the manifest to the path consensus.manifestpath names.
# Never writes secrets: the RPC key stays in the environment (.env).
set -euo pipefail

RESOLVED="" NODE_DIR="" VALIDATOR="" OPERATOR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --resolved)  RESOLVED="$2"; shift 2 ;;
    --node-dir)  NODE_DIR="$2"; shift 2 ;;
    --validator) VALIDATOR="$2"; shift 2 ;;
    --operator)  OPERATOR="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
CFG="$NODE_DIR/configs/node/config.yaml"
[ -f "$RESOLVED/resolved.env" ] && [ -f "$RESOLVED/protocol-manifest.json" ] \
  || { echo "run resolve-network.sh first: $RESOLVED/resolved.env missing" >&2; exit 2; }
[ -f "$CFG" ] || { echo "no config at $CFG" >&2; exit 2; }
for a in "$VALIDATOR" "$OPERATOR"; do
  [ -z "$a" ] || [[ "$a" =~ ^0x[0-9a-fA-F]{40}$ ]] || { echo "not an address: $a" >&2; exit 2; }
done

# shellcheck disable=SC1091
. "$RESOLVED/resolved.env"
cp "$CFG" "$CFG.bak"

# set_key SECTION KEY VALUE QUOTE: replace (or uncomment) `  key: ...` inside a top-level section,
# keeping any trailing comment.
set_key() {
  awk -v s="$1" -v k="$2" -v v="$3" -v q="$4" '
    /^[^[:space:]#][^:]*:/ { sect = $0; sub(/:.*/, "", sect) }
    sect == s && !done && $0 ~ "^[[:space:]]+#?[[:space:]]*" k ":" {
      ind = $0; sub(/[^[:space:]].*$/, "", ind)
      cmt = ""; if (match($0, /[[:space:]]#[[:space:]].*$/) && $0 !~ "^[[:space:]]+#") cmt = substr($0, RSTART)
      val = (q == "1") ? "\"" v "\"" : v
      print ind k ": " val cmt; done = 1; next
    }
    { print }
    END { if (!done) exit 3 }' "$CFG" > "$CFG.tmp" || { rm -f "$CFG.tmp"; echo "key $1.$2 not found in $CFG" >&2; exit 4; }
  mv "$CFG.tmp" "$CFG"
}

set_key rollup    genlayerchainrpcurl       "$RPC_URL"           1
set_key rollup    genlayerchainwebsocketurl "$WSS_URL"           1
set_key rollup    provider                  "$ROLLUP_PROVIDER"   1
set_key consensus consensusaddress          "$CONSENSUS_ADDRESS" 1
set_key consensus chainid                   "$CHAIN_ID"          1
[ -z "$GENESIS" ] || set_key consensus genesis "$GENESIS" 0
# node.network is ONE key of the user's node: section (mode, wallet addresses stay untouched).
if [ -n "${NODE_NETWORK:-}" ]; then
  [[ "$NODE_NETWORK" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad node.network in resolved.env: $NODE_NETWORK" >&2; exit 4; }
  if grep -qE '^[[:space:]]+#?[[:space:]]*network:' <(awk '/^node:/{n=1;next} /^[^[:space:]#]/{n=0} n' "$CFG"); then
    set_key node network "$NODE_NETWORK" 1
  else  # key absent from this release's example: add it right under `node:`
    awk -v v="$NODE_NETWORK" '{ print } /^node:/ && !d { print "  network: \"" v "\""; d = 1 }' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
  fi
else
  # Only a direct child of node: (the indentation of its first key), whatever that width is.
  awk '/^[^[:space:]#][^:]*:/ { sect = $0; sub(/:.*/, "", sect); ind = "" }
       sect == "node" && /^[[:space:]]+[^[:space:]#]/ {
         if (ind == "") { ind = $0; sub(/[^[:space:]].*$/, "", ind) }
         if (index($0, ind "network:") == 1) $0 = ind "# " substr($0, length(ind) + 1)
       }
       { print }' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
fi
[ -z "$VALIDATOR" ] || set_key node validatorWalletAddress "$VALIDATOR" 1
[ -z "$OPERATOR" ]  || set_key node operatorAddress        "$OPERATOR"  1

manifest_rel=$(awk '/^consensus:/{c=1;next} /^[^[:space:]#]/{c=0} c && /^[[:space:]]+manifestpath:/ {
  v=$0; sub(/^[[:space:]]+manifestpath:[[:space:]]*/,"",v); sub(/[[:space:]]+#.*$/,"",v); gsub(/"/,"",v); print v; exit }' "$CFG")
manifest_rel=${manifest_rel:-configs/node/protocol-manifest.json}
case "$manifest_rel" in /*) dest="$manifest_rel" ;; *) dest="$NODE_DIR/$manifest_rel" ;; esac
mkdir -p "$(dirname "$dest")"
cp "$RESOLVED/protocol-manifest.json" "$dest"

echo "✓ $CFG updated (backup $CFG.bak)"
echo "✓ manifest installed at $dest"
grep -nE '^\s+(genlayerchainrpcurl|genlayerchainwebsocketurl|provider|consensusaddress|chainid|genesis|network|mode|validatorWalletAddress|operatorAddress):' "$CFG" \
  | sed -E 's/[[:space:]]+#.*$//'
