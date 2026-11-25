#!/usr/bin/env bash
# Resolve a genlayer-node release version from the public release bucket.
#
#   resolve-version.sh --line v0.6            # latest stable v0.6.x  (prints e.g. v0.6.0)
#   resolve-version.sh --line v0.6 --list     # every v0.6.x release, newest first
#   resolve-version.sh --list                 # every release, newest first
#   resolve-version.sh --check v0.6.1         # exit 0 if that release exists and is complete
#   add --pre to include -rc / -alpha / -beta builds
#
# "Stable" means exactly vMAJOR.MINOR.PATCH. The line comes from the network's
# `node_release_line` in networks.yaml, so a network is never paired with a
# release line it does not support.
set -euo pipefail

INDEX="https://storage.googleapis.com/storage/v1/b/gh-af/o?prefix=genlayer-node/bin/amd64/&delimiter=/"
BASE="https://storage.googleapis.com/gh-af/genlayer-node/bin/amd64"
LINE="" LIST=false PRE=false CHECK=""

while [ $# -gt 0 ]; do
  case "$1" in
    --line)  LINE="$2"; shift 2 ;;
    --list)  LIST=true; shift ;;
    --pre)   PRE=true; shift ;;
    --check) CHECK="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -n "$CHECK" ]; then
  # A usable release has the tarball and, from v0.6.0 on, the signed checksum file.
  code=$(curl -s -o /dev/null -w '%{http_code}' -r 0-0 "$BASE/$CHECK/genlayer-node-linux-amd64-$CHECK.tar.gz")
  [ "$code" = "200" ] || [ "$code" = "206" ] || { echo "release $CHECK not found (HTTP $code)" >&2; exit 1; }
  echo "$CHECK"
  exit 0
fi

versions=$(curl -fsS "$INDEX" | jq -r '.prefixes[]? | capture("amd64/(?<v>v[^/]+)/$").v')
[ -n "$versions" ] || { echo "could not list releases from $INDEX" >&2; exit 1; }

if [ -n "$LINE" ]; then
  versions=$(printf '%s\n' "$versions" | grep -E "^${LINE//./\\.}(\.|-|$)" || true)
fi
if ! $PRE; then
  versions=$(printf '%s\n' "$versions" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true)
fi
[ -n "$versions" ] || { echo "no release found${LINE:+ for line $LINE}" >&2; exit 1; }

sorted=$(printf '%s\n' "$versions" | sort -V -r)
if $LIST; then printf '%s\n' "$sorted"; else printf '%s\n' "$sorted" | head -1; fi
