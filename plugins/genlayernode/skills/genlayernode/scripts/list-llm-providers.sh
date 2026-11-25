#!/usr/bin/env bash
# List the LLM providers an installed node release supports, read from its own GenVM
# config (the provider set and key variable names change between releases).
#
#   list-llm-providers.sh /opt/genlayer-node/v0.6.0            # table: provider, env var, enabled
#   list-llm-providers.sh /opt/genlayer-node/v0.6.0 --enable heurist
#
# --enable sets `enabled: true` for that provider (adds the line when absent).
set -euo pipefail

NODE_DIR="${1:?usage: list-llm-providers.sh <node-dir> [--enable <provider>]}"
ENABLE=""; [ "${2:-}" = "--enable" ] && ENABLE="${3:?provider name}"

CFG=""
# Prefer the GenVM tree the node config names (genvm.root_dir, relative to the node dir).
ROOT=$(sed -n 's/^ *root_dir: *//p' "$NODE_DIR/configs/node/config.yaml" 2>/dev/null | head -1 | tr -d '"')
case "$ROOT" in /*) ;; ?*) ROOT="$NODE_DIR/$ROOT" ;; esac
for c in ${ROOT:+"$ROOT/config/genvm-module-llm.yaml"} \
         "$NODE_DIR/opt/genvm/current/config/genvm-module-llm.yaml" \
         "$NODE_DIR/third_party/genvm/config/genvm-module-llm.yaml"; do
  [ -f "$c" ] && { CFG="$c"; break; }
done
[ -n "$CFG" ] || { echo "no genvm-module-llm.yaml under $NODE_DIR" >&2; exit 1; }

if [ -n "$ENABLE" ]; then
  awk -v p="$ENABLE" '
    /^backends:/ { inb = 1 }
    inb && /^  [A-Za-z0-9_]+:[[:space:]]*$/ { cur = $1; sub(":", "", cur); if (cur == p) { found = 1; print; getline nxt
        if (nxt ~ /^    enabled:/) print "    enabled: true"; else { print "    enabled: true"; print nxt }
        next } }
    { print }
    END { if (!found) exit 3 }' "$CFG" > "$CFG.tmp" || { rm -f "$CFG.tmp"; echo "provider '$ENABLE' not in $CFG" >&2; exit 3; }
  mv "$CFG.tmp" "$CFG"
  echo "✓ enabled $ENABLE in $CFG"
fi

# A backend is a provider when it has a `key: ${ENV[...]}` line. No `enabled:` line = enabled.
awk '
  /^backends:/ { inb = 1; next }
  inb && /^[^[:space:]]/ { inb = 0 }
  inb && /^  [A-Za-z0-9_]+:[[:space:]]*$/ { flush(); name = $1; sub(":", "", name); en = "true"; key = ""; next }
  inb && /^    enabled:/ { en = $2 }
  inb && /^    key:/ && match($0, /ENV\[[A-Za-z0-9_]+\]/) { key = substr($0, RSTART + 4, RLENGTH - 5) }
  function flush() { if (name != "" && key != "") printf "%-14s %-22s %s\n", name, key, en; name = "" }
  END { flush() }
' "$CFG" | { printf "%-14s %-22s %s\n" PROVIDER ENV_VAR ENABLED; cat; }
echo "(from $CFG)"
