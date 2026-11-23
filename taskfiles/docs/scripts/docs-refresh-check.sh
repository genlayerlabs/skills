#!/bin/bash
set -euo pipefail

# ============================================================================
# DOCS REFRESH CHECK
# ============================================================================
# Check if generated documentation is in sync with source files.
# Generates fresh docs to a temp directory and compares with existing.
#
# Usage:
#     ./docs-refresh-check.sh
#     ./docs-refresh-check.sh --debug
#
# INPUTS:
# Optional:
#   --debug          Enable debug logging
#   --help           Show usage information
#
# OUTPUTS:
#   Exit code 0 if docs are in sync
#   Exit code 1 if docs are out of sync
#
# ============================================================================

# ============================================================================
# CONSTANTS
# ============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

# Exit codes
readonly SUCCESS=0
readonly ERR_OUT_OF_SYNC=1
readonly ERR_INVALID_ARGS=2

# Paths
readonly SKILLS_REFERENCE_GENERATOR="$PROJECT_ROOT/taskfiles/claude/scripts/generate-skill-reference.sh"
readonly CLAUDE_MD_UPDATER="$PROJECT_ROOT/taskfiles/docs/scripts/update-claude-md.sh"
readonly DOCS_SKILLS_DIR="$PROJECT_ROOT/docs/skills"
readonly REFERENCE_FILE="$DOCS_SKILLS_DIR/REFERENCE.md"

# ============================================================================
# SOURCE SHARED FUNCTIONS
# ============================================================================
SCRIPT_SHARED_DIR="$PROJECT_ROOT/taskfiles/scripts"

if [[ -f "$SCRIPT_SHARED_DIR/logger.sh" ]]; then
    source "$SCRIPT_SHARED_DIR/logger.sh"
else
    # Fallback logging functions
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { if [[ "${DEBUG_MODE:-false}" == "true" ]]; then echo "[DEBUG] $*"; fi; }
fi

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

die() {
    log_error "$1"
    exit "${2:-$ERR_OUT_OF_SYNC}"
}

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Check if generated documentation is in sync with source files.

Options:
    --debug     Enable debug logging
    --help      Show this help message

Exit codes:
    0 - All documentation is in sync
    1 - Documentation is out of sync (run 'task docs:refresh' to fix)

Examples:
    $SCRIPT_NAME
    $SCRIPT_NAME --debug

EOF
}

# ============================================================================
# MAIN FUNCTIONS
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
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
                die "Unknown option: $1" $ERR_INVALID_ARGS
                ;;
        esac
    done
}

# Replace the generated header timestamp (line 4, "> Last updated: YYYY-MM-DD HH:MM")
# with a placeholder; it is an error if line 4 is not in that format.
normalize_timestamp() {
    local ts_re='^> Last updated: [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}$'
    # Fail unless the header carries a real timestamp (a literal placeholder is rejected).
    sed -n 4p "$1" | grep -q "$ts_re" || return 1
    sed "4s/$ts_re/> Last updated: <timestamp>/" "$1"
}

check_skills_reference() {
    local temp_dir="$1"
    local temp_reference="$temp_dir/docs/skills/REFERENCE.md"

    log_debug "Generating fresh REFERENCE.md to $temp_reference"

    # Generate fresh docs to temp location
    mkdir -p "$temp_dir/docs/skills"

    if [[ -x "$SKILLS_REFERENCE_GENERATOR" ]]; then
        if ! "$SKILLS_REFERENCE_GENERATOR" --canonical --output "$temp_reference" >/dev/null 2>&1; then
            log_error "Skills reference generator failed"
            return 1
        fi
    else
        log_debug "Skills reference generator not found or not executable"
        return 0
    fi

    # Compare with existing
    if [[ -f "$REFERENCE_FILE" ]]; then
        if [[ -f "$temp_reference" ]]; then
            # Normalize only the generated header timestamp; it changes every minute.
            local norm_existing="$temp_dir/existing.normalized"
            local norm_fresh="$temp_dir/fresh.normalized"
            if ! normalize_timestamp "$REFERENCE_FILE" > "$norm_existing" \
                || ! normalize_timestamp "$temp_reference" > "$norm_fresh"; then
                log_error "Failed to normalize docs/skills/REFERENCE.md for comparison"
                return 1
            fi
            if ! diff -q "$norm_existing" "$norm_fresh" >/dev/null 2>&1; then
                log_error "docs/skills/REFERENCE.md is out of sync"
                echo "Run 'task docs:refresh' to update"
                return 1
            fi
            log_info "docs/skills/REFERENCE.md is in sync"
        else
            log_info "docs/skills/REFERENCE.md exists (no skills to compare)"
        fi
    else
        if [[ -f "$temp_reference" ]]; then
            log_error "docs/skills/REFERENCE.md does not exist but should"
            echo "Run 'task docs:refresh' to generate"
            return 1
        fi
        log_info "No skills documentation to check"
    fi

    return 0
}

main() {
    parse_arguments "$@"

    # Create temp directory for comparison
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT

    log_debug "Using temp directory: $temp_dir"

    local has_errors=false

    # Check skills reference
    if ! check_skills_reference "$temp_dir"; then
        has_errors=true
    fi

    # Check CLAUDE.md skills table
    if [[ -x "$CLAUDE_MD_UPDATER" ]]; then
        if ! "$CLAUDE_MD_UPDATER" --check; then
            has_errors=true
        fi
    fi

    if [[ "$has_errors" == "true" ]]; then
        exit $ERR_OUT_OF_SYNC
    fi

    echo "OK: All documentation is in sync"
    exit $SUCCESS
}

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================
main "$@"
