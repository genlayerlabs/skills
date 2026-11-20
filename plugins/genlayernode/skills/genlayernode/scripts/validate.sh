#!/bin/bash
# Plugin-local validation runner for the genlayernode skill.
#
# Runs the checks listed in ../validations.yaml. It only needs bash, sed and awk,
# so it works from any project once the plugin is installed (no Taskfile, no yq).
#
# Usage: validate.sh [--mode on-stop|all] [--debug]
#   on-stop (default)  run the ids listed under `on_stop`
#   all                run every validation
# Exit code: 0 all passed, 1 a validation failed, 2 bad usage or missing file.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE="$SCRIPT_DIR/../validations.yaml"
MODE="on-stop"
DEBUG=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) MODE="${2:-}"; shift 2 || exit 2 ;;
        --debug) DEBUG=true; shift ;;
        -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
[[ "$MODE" == "on-stop" || "$MODE" == "all" ]] || { echo "Invalid mode: $MODE" >&2; exit 2; }
[[ -f "$FILE" ]] || { echo "validations.yaml not found next to the skill: $FILE" >&2; exit 2; }

# Emit one TSV line per validation: id <TAB> command <TAB> message
# Newlines inside multiline (block scalar `|`) values are encoded as \001 and
# decoded again by lookup().
parse_validations() {
    awk '
    function val(s) {
        sub(/^[^:]*:[ \t]*/, "", s); sub(/[ \t]+$/, "", s)
        if (s ~ /^".*"$/) {
            s = substr(s, 2, length(s) - 2)
            gsub(/\\"/, "\"", s); gsub(/\\\\/, "\\", s)
        }
        return s
    }
    function flush() {
        if (id != "") printf "%s\t%s\t%s\n", id, cmd, msg
        id = cmd = msg = ""
    }
    function store(v) { if (key == "command") cmd = v; else msg = v }
    function endblock() { store(blk); blk = ""; inblk = 0 }
    {
        if (inblk) {
            if ($0 ~ /^[ \t]*$/) { blk = blk (blk == "" ? "" : "\001"); next }
            match($0, /^[ \t]*/)
            if (bind == 0) bind = RLENGTH
            if (RLENGTH >= bind && bind > 0) {
                blk = blk (blk == "" ? "" : "\001") substr($0, bind + 1)
                next
            }
            endblock()
        }
    }
    /^validations:/ { inv = 1; next }
    /^[A-Za-z_]+:/ { flush(); inv = 0 }
    inv && /^[ \t]*- id:/ { flush(); id = val($0); next }
    inv && /^[ \t]+(command|message):/ {
        key = $0; sub(/^[ \t]+/, "", key); sub(/:.*/, "", key)
        v = val($0)
        if (v ~ /^[|>][-+]?$/) { inblk = 1; bind = 0; blk = ""; next }
        store(v); next
    }
    END { if (inblk) endblock(); flush() }
    ' "$FILE"
}

# Emit the ids listed under top-level on_stop:
parse_on_stop() {
    awk '
    /^on_stop:/ { s = 1; next }
    /^[A-Za-z_]+:/ { s = 0 }
    s && /^[ \t]*-[ \t]/ { sub(/^[ \t]*-[ \t]*/, ""); sub(/[ \t]+(#.*)?$/, ""); gsub(/"/, ""); print }
    ' "$FILE"
}

TSV="$(parse_validations)"

lookup() { # $1=id $2=field number (2=command, 3=message)
    printf '%s\n' "$TSV" | awk -F'\t' -v id="$1" -v f="$2" '$1 == id { print $f; exit }' | tr '\001' '\n'
}

if [[ "$MODE" == "all" ]]; then
    TO_RUN="$(printf '%s\n' "$TSV" | cut -f1)"
else
    TO_RUN="$(parse_on_stop)"
fi

if [[ -z "$TO_RUN" ]]; then
    echo "genlayernode: no validations to run (mode=$MODE) in $FILE" >&2
    exit 2
fi

echo "=== Validating genlayernode (mode=$MODE) ==="
FAILED=""
NFAILED=0
while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    cmd="$(lookup "$id" 2)"
    if [[ -z "$cmd" ]]; then
        echo "  [$id] FAILED: no command found in validations.yaml"
        FAILED="$FAILED${FAILED:+, }$id"; NFAILED=$((NFAILED + 1)); continue
    fi
    echo "  [$id]"
    if [[ "$DEBUG" == true ]]; then echo "    Running: $cmd"; fi
    if bash -c "$cmd" >/dev/null 2>&1; then
        echo "    OK"
    else
        msg="$(lookup "$id" 3)"
        echo "    FAILED: ${msg:-Validation $id failed}"
        FAILED="$FAILED${FAILED:+, }$id"; NFAILED=$((NFAILED + 1))
    fi
done <<EOF
$TO_RUN
EOF

echo ""
if [[ $NFAILED -gt 0 ]]; then
    echo "FAILED: $NFAILED validation(s): $FAILED"
    exit 1
fi
echo "=== genlayernode: OK ==="
