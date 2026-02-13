#!/bin/bash
set -euo pipefail

# ============================================================================
# UPDATE CLAUDE.MD SKILLS TABLE
# ============================================================================
# Automatically update the skills table in CLAUDE.md from skill.yaml files.
#
# Usage:
#     ./update-claude-md.sh
#     ./update-claude-md.sh --check  # Check if in sync (don't modify)
#
# The script looks for markers in CLAUDE.md:
#   <!-- SKILLS_TABLE_START -->
#   ... generated content ...
#   <!-- SKILLS_TABLE_END -->
#
# ============================================================================

# ============================================================================
# CONSTANTS
# ============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

readonly CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
readonly SKILLS_DIR="$PROJECT_ROOT/.claude/skills"

readonly START_MARKER="<!-- SKILLS_TABLE_START -->"
readonly END_MARKER="<!-- SKILLS_TABLE_END -->"

# Exit codes
readonly SUCCESS=0
readonly ERR_OUT_OF_SYNC=1
readonly ERR_MISSING_FILE=2

# ============================================================================
# SOURCE SHARED FUNCTIONS
# ============================================================================
SCRIPT_SHARED_DIR="$PROJECT_ROOT/taskfiles/scripts"

if [[ -f "$SCRIPT_SHARED_DIR/logger.sh" ]]; then
    source "$SCRIPT_SHARED_DIR/logger.sh"
else
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { [[ "${DEBUG_MODE:-false}" == "true" ]] && echo "[DEBUG] $*"; }
fi

# ============================================================================
# FUNCTIONS
# ============================================================================

die() {
    log_error "$1"
    exit "${2:-1}"
}

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Update the skills table in CLAUDE.md from skill.yaml files.

Options:
    --check     Check if skills table is in sync (don't modify)
    --debug     Enable debug logging
    --help      Show this help message

Examples:
    $SCRIPT_NAME              # Update CLAUDE.md
    $SCRIPT_NAME --check      # Check if in sync

EOF
}

# Extract description from skill.yaml (handles both quoted and unquoted)
get_skill_description() {
    local skill_yaml="$1"
    local desc=""

    # Try to get description, handling various YAML formats
    desc=$(grep -E '^description:' "$skill_yaml" 2>/dev/null | head -1 | sed 's/^description:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//' | cut -c1-60)

    if [[ -z "$desc" ]]; then
        desc="(no description)"
    fi

    echo "$desc"
}

# Get "when to use" hint based on skill kind and name
get_when_to_use() {
    local skill_name="$1"
    local skill_yaml="$2"

    # Check if skill has a custom "when_to_use" field
    local custom_when
    custom_when=$(grep -E '^when_to_use:' "$skill_yaml" 2>/dev/null | head -1 | sed 's/^when_to_use:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//')

    if [[ -n "$custom_when" ]]; then
        echo "$custom_when"
        return
    fi

    # Fallback to description
    get_skill_description "$skill_yaml"
}

# Generate the skills table content
generate_skills_table() {
    echo "| Skill | When to Use |"
    echo "|-------|-------------|"

    # Sort skills alphabetically
    for skill_dir in $(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | sort); do
        local skill_name
        skill_name=$(basename "$skill_dir")
        local skill_yaml="$skill_dir/skill.yaml"

        if [[ -f "$skill_yaml" ]]; then
            local when_to_use
            when_to_use=$(get_when_to_use "$skill_name" "$skill_yaml")
            echo "| \`$skill_name\` | $when_to_use |"
        fi
    done
}

# Update CLAUDE.md with new skills table
update_claude_md() {
    local new_table="$1"
    local temp_file
    temp_file=$(mktemp)
    local table_file
    table_file=$(mktemp)

    # Check if markers exist
    if ! grep -q "$START_MARKER" "$CLAUDE_MD"; then
        die "Missing $START_MARKER in CLAUDE.md. Please add markers around the skills table."
    fi

    if ! grep -q "$END_MARKER" "$CLAUDE_MD"; then
        die "Missing $END_MARKER in CLAUDE.md. Please add markers around the skills table."
    fi

    # Write table to temp file
    echo "$new_table" > "$table_file"

    # Build new file
    # 1. Print everything up to and including START_MARKER
    # 2. Insert the new table
    # 3. Skip until END_MARKER
    # 4. Print END_MARKER and everything after

    local in_skip=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == *"$START_MARKER"* ]]; then
            echo "$line"
            cat "$table_file"
            in_skip=true
        elif [[ "$line" == *"$END_MARKER"* ]]; then
            echo "$line"
            in_skip=false
        elif [[ "$in_skip" == false ]]; then
            echo "$line"
        fi
    done < "$CLAUDE_MD" > "$temp_file"

    mv "$temp_file" "$CLAUDE_MD"
    rm -f "$table_file"
    log_info "Updated CLAUDE.md skills table"
}

# Check if CLAUDE.md is in sync
check_claude_md() {
    local new_table="$1"
    local temp_file
    temp_file=$(mktemp)

    # Check if markers exist
    if ! grep -q "$START_MARKER" "$CLAUDE_MD"; then
        log_error "Missing $START_MARKER in CLAUDE.md"
        return 1
    fi

    # Extract current table
    local current_table
    current_table=$(awk -v start="$START_MARKER" -v end="$END_MARKER" '
        $0 ~ start { found=1; next }
        $0 ~ end { found=0 }
        found { print }
    ' "$CLAUDE_MD")

    # Compare
    if [[ "$current_table" != "$new_table" ]]; then
        log_error "CLAUDE.md skills table is out of sync"
        echo "Run 'task docs:refresh' to update"
        rm -f "$temp_file"
        return 1
    fi

    rm -f "$temp_file"
    log_info "CLAUDE.md skills table is in sync"
    return 0
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local check_mode=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)
                check_mode=true
                shift
                ;;
            --debug)
                DEBUG_MODE=true
                export DEBUG_MODE
                shift
                ;;
            --help|-h)
                show_usage
                exit $SUCCESS
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    # Check CLAUDE.md exists
    if [[ ! -f "$CLAUDE_MD" ]]; then
        die "CLAUDE.md not found at $CLAUDE_MD" $ERR_MISSING_FILE
    fi

    # Generate new table
    local new_table
    new_table=$(generate_skills_table)

    if [[ "$check_mode" == "true" ]]; then
        check_claude_md "$new_table"
    else
        update_claude_md "$new_table"
    fi
}

main "$@"
