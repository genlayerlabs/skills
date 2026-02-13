#!/bin/bash
set -euo pipefail

# ============================================================================
# GENERATE SKILL REFERENCE
# ============================================================================
# Generate docs/skills/REFERENCE.md from skill.yaml files.
#
# Creates a comprehensive reference document with:
# - Overview table of all skills
# - Detailed sections by skill kind (gate, scaffolder, helper, discipline, meta, frontend)
# - Patterns and anti-patterns from each skill
#
# Usage:
#     ./generate-skill-reference.sh
#     ./generate-skill-reference.sh --output /path/to/output.md
#     ./generate-skill-reference.sh --debug
#
# INPUTS:
# Optional:
#   --output FILE    Output file path (default: docs/skills/REFERENCE.md)
#   --debug          Enable debug logging
#   --help           Show usage information
#
# OUTPUTS:
#   Creates docs/skills/REFERENCE.md with skill reference documentation
#   Exit code 0 on success, 1 on failure
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
readonly ERR_GENERAL=1
readonly ERR_INVALID_ARGS=2

# Skill prefix (change this to adapt to different projects)
readonly SKILL_PREFIX="claude-skill-"

# Default output file
DEFAULT_OUTPUT_FILE="docs/skills/REFERENCE.md"
OUTPUT_FILE=""

# Collected skills data
SKILL_NAMES=()
SKILL_KINDS=()
SKILL_VERSIONS=()
SKILL_DESCRIPTIONS=()
SKILL_PURPOSES=()
SKILL_FOLDERS=()

# ============================================================================
# SOURCE SHARED FUNCTIONS
# ============================================================================
SCRIPT_SHARED_DIR="$PROJECT_ROOT/taskfiles/scripts"

# Source the shared logger functions
source "$SCRIPT_SHARED_DIR/logger.sh"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

die() {
    log_error "$1"
    exit "${2:-$ERR_GENERAL}"
}

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Generate docs/skills/REFERENCE.md from skill.yaml files.

Options:
    --output FILE   Output file path (default: $DEFAULT_OUTPUT_FILE)
    --debug         Enable debug logging
    --help          Show this help message

Examples:
    $SCRIPT_NAME
    $SCRIPT_NAME --output /path/to/output.md

EOF
}

# Check if yq is available
has_yq() {
    command -v yq >/dev/null 2>&1
}

# Truncate string to max length with ellipsis
truncate_string() {
    local str="$1"
    local max_len="$2"

    if [[ ${#str} -gt $max_len ]]; then
        echo "${str:0:$((max_len-3))}..."
    else
        echo "$str"
    fi
}

# Escape pipe characters for markdown tables
escape_pipes() {
    echo "$1" | sed 's/|/\\|/g'
}

# ============================================================================
# YAML PARSING FUNCTIONS
# ============================================================================

# Load skill data from skill.yaml and SKILL.md
# Sets global arrays with skill data
load_skill() {
    local skill_dir="$1"
    local skill_yaml="$skill_dir/skill.yaml"
    local skill_md="$skill_dir/SKILL.md"
    local folder
    folder=$(basename "$skill_dir")

    if [[ ! -f "$skill_yaml" ]]; then
        return 1
    fi

    local name="" kind="" version="" description="" purpose=""

    if has_yq; then
        name=$(yq '.name // ""' "$skill_yaml" 2>/dev/null || echo "")
        kind=$(yq '.kind // ""' "$skill_yaml" 2>/dev/null || echo "")
        version=$(yq '.version // ""' "$skill_yaml" 2>/dev/null || echo "")
        description=$(yq '.description // ""' "$skill_yaml" 2>/dev/null || echo "")
        purpose=$(yq '.purpose // ""' "$skill_yaml" 2>/dev/null || echo "")

        # If no description in skill.yaml, try SKILL.md frontmatter
        if [[ -z "$description" ]] && [[ -f "$skill_md" ]]; then
            local frontmatter
            frontmatter=$(sed -n '/^---$/,/^---$/p' "$skill_md" | sed '1d;$d')
            if [[ -n "$frontmatter" ]]; then
                description=$(echo "$frontmatter" | yq '.description // ""' 2>/dev/null || echo "")
            fi
        fi
    else
        # Basic parsing
        name=$(grep -E '^name:' "$skill_yaml" | head -1 | sed 's/^name:[[:space:]]*//' | sed 's/^"//;s/"$//')
        kind=$(grep -E '^kind:' "$skill_yaml" | head -1 | sed 's/^kind:[[:space:]]*//' | sed 's/^"//;s/"$//')
        version=$(grep -E '^version:' "$skill_yaml" | head -1 | sed 's/^version:[[:space:]]*//' | sed 's/^"//;s/"$//')
        description=$(grep -E '^description:' "$skill_yaml" | head -1 | sed 's/^description:[[:space:]]*//' | sed 's/^"//;s/"$//')
        # purpose is multi-line, harder to parse without yq
        purpose=""
    fi

    # Use folder name if no name
    [[ -z "$name" ]] && name="$folder"

    # Store in arrays
    SKILL_NAMES+=("$name")
    SKILL_KINDS+=("${kind:-unknown}")
    SKILL_VERSIONS+=("${version:-—}")
    SKILL_DESCRIPTIONS+=("${description:-—}")
    SKILL_PURPOSES+=("${purpose:-}")
    SKILL_FOLDERS+=("$folder")

    return 0
}

# Get patterns from skill.yaml
# Outputs: id|description lines
get_skill_patterns() {
    local skill_dir="$1"
    local skill_yaml="$skill_dir/skill.yaml"

    if [[ ! -f "$skill_yaml" ]]; then
        return 0
    fi

    if has_yq; then
        local count
        count=$(yq '.patterns | length' "$skill_yaml" 2>/dev/null || echo "0")

        if [[ "$count" != "0" ]] && [[ "$count" != "null" ]]; then
            for ((i=0; i<count; i++)); do
                local pid pdesc
                pid=$(yq ".patterns[$i].id // \"—\"" "$skill_yaml" 2>/dev/null)
                pdesc=$(yq ".patterns[$i].description // \"—\"" "$skill_yaml" 2>/dev/null)
                # Clean up multiline descriptions
                pdesc=$(echo "$pdesc" | tr '\n' ' ' | sed 's/  */ /g')
                echo "$pid|$pdesc"
            done
        fi
    fi
}

# Get anti-patterns from skill.yaml
# Outputs: id|description|why_bad lines
get_skill_anti_patterns() {
    local skill_dir="$1"
    local skill_yaml="$skill_dir/skill.yaml"

    if [[ ! -f "$skill_yaml" ]]; then
        return 0
    fi

    if has_yq; then
        local count
        count=$(yq '.anti_patterns | length' "$skill_yaml" 2>/dev/null || echo "0")

        if [[ "$count" != "0" ]] && [[ "$count" != "null" ]]; then
            for ((i=0; i<count; i++)); do
                local aid adesc awhy
                aid=$(yq ".anti_patterns[$i].id // \"—\"" "$skill_yaml" 2>/dev/null)
                adesc=$(yq ".anti_patterns[$i].description // \"—\"" "$skill_yaml" 2>/dev/null)
                awhy=$(yq ".anti_patterns[$i].why_bad // \"—\"" "$skill_yaml" 2>/dev/null)
                # Clean up multiline
                adesc=$(echo "$adesc" | tr '\n' ' ' | sed 's/  */ /g')
                awhy=$(echo "$awhy" | tr '\n' ' ' | sed 's/  */ /g')
                echo "$aid|$adesc|$awhy"
            done
        fi
    fi
}

# Get owns list from skill.yaml
get_skill_owns() {
    local skill_dir="$1"
    local skill_yaml="$skill_dir/skill.yaml"

    if [[ ! -f "$skill_yaml" ]]; then
        return 0
    fi

    if has_yq; then
        yq '.owns[]' "$skill_yaml" 2>/dev/null || true
    fi
}

# Get non-negotiables from skill.yaml (for discipline skills)
get_skill_non_negotiables() {
    local skill_dir="$1"
    local skill_yaml="$skill_dir/skill.yaml"

    if [[ ! -f "$skill_yaml" ]]; then
        return 0
    fi

    if has_yq; then
        local count
        count=$(yq '.non_negotiables | length' "$skill_yaml" 2>/dev/null || echo "0")

        if [[ "$count" != "0" ]] && [[ "$count" != "null" ]]; then
            for ((i=0; i<count; i++)); do
                local nid ndesc
                nid=$(yq ".non_negotiables[$i].id // \"—\"" "$skill_yaml" 2>/dev/null)
                ndesc=$(yq ".non_negotiables[$i].description // \"—\"" "$skill_yaml" 2>/dev/null)
                ndesc=$(echo "$ndesc" | tr '\n' ' ' | sed 's/  */ /g')
                echo "$nid|$ndesc"
            done
        fi
    fi
}

# ============================================================================
# MARKDOWN GENERATION
# ============================================================================

generate_reference() {
    local skills_dir="$PROJECT_ROOT/.claude/skills"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M')

    # Collect all skills
    for skill_dir in "$skills_dir"/*/; do
        [[ ! -d "$skill_dir" ]] && continue

        local folder
        folder=$(basename "$skill_dir")

        # Only include skills with correct prefix
        if [[ "$folder" != ${SKILL_PREFIX}* ]]; then
            continue
        fi

        load_skill "$skill_dir" || continue
    done

    local skill_count=${#SKILL_NAMES[@]}

    # Count unique kinds
    local kinds_list=""
    for kind in "${SKILL_KINDS[@]}"; do
        if [[ "$kinds_list" != *"|$kind|"* ]]; then
            kinds_list="${kinds_list}|$kind|"
        fi
    done
    local kind_count
    kind_count=$(echo "$kinds_list" | tr -cd '|' | wc -c)
    kind_count=$((kind_count / 2))

    # Start output
    cat << EOF
# Skill Reference

> **Auto-generated** from \`skill.yaml\` files. Do not edit manually.
> Last updated: $timestamp

## Overview

Total: **$skill_count skills** across $kind_count kinds.

| Skill | Kind | Version | Description |
|-------|------|---------|-------------|
EOF

    # Overview table
    for ((i=0; i<skill_count; i++)); do
        local name="${SKILL_NAMES[$i]}"
        local kind="${SKILL_KINDS[$i]}"
        local version="${SKILL_VERSIONS[$i]}"
        local desc="${SKILL_DESCRIPTIONS[$i]}"

        # Truncate description
        desc=$(truncate_string "$desc" 60)
        desc=$(escape_pipes "$desc")

        echo "| $name | $kind | $version | $desc |"
    done

    echo ""

    # Kind order for output
    local kind_order="gate scaffolder helper discipline meta frontend"

    # Get sorted unique kinds
    local sorted_kinds=""
    for k in $kind_order; do
        for kind in "${SKILL_KINDS[@]}"; do
            if [[ "$kind" == "$k" ]] && [[ "$sorted_kinds" != *"|$k|"* ]]; then
                sorted_kinds="${sorted_kinds}|$k|"
            fi
        done
    done
    # Add any remaining kinds not in order
    for kind in "${SKILL_KINDS[@]}"; do
        if [[ "$sorted_kinds" != *"|$kind|"* ]]; then
            sorted_kinds="${sorted_kinds}|$kind|"
        fi
    done

    # Detailed sections by kind
    for k in $kind_order unknown; do
        [[ "$sorted_kinds" != *"|$k|"* ]] && continue

        # Title case (bash 4+ compatible, with fallback)
        local kind_title
        if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
            kind_title="${k^}"
        else
            # Fallback for bash 3
            kind_title=$(echo "$k" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
        fi

        cat << EOF
---

## $kind_title Skills

EOF

        # Skills of this kind
        for ((i=0; i<skill_count; i++)); do
            [[ "${SKILL_KINDS[$i]}" != "$k" ]] && continue

            local name="${SKILL_NAMES[$i]}"
            local folder="${SKILL_FOLDERS[$i]}"
            local desc="${SKILL_DESCRIPTIONS[$i]}"
            local purpose="${SKILL_PURPOSES[$i]}"
            local skill_dir="$skills_dir/$folder"

            echo "### $name"
            echo ""

            # Description
            if [[ -n "$desc" ]] && [[ "$desc" != "—" ]]; then
                echo "**$desc**"
                echo ""
            fi

            # Purpose
            if [[ -n "$purpose" ]]; then
                echo "$purpose" | sed 's/^[[:space:]]*//'
                echo ""
            fi

            # Owns
            local owns
            owns=$(get_skill_owns "$skill_dir")
            if [[ -n "$owns" ]]; then
                echo "**Owns:**"
                echo "$owns" | while IFS= read -r item; do
                    [[ -n "$item" ]] && echo "- $item"
                done
                echo ""
            fi

            # Patterns
            local patterns
            patterns=$(get_skill_patterns "$skill_dir")
            if [[ -n "$patterns" ]]; then
                echo "**Patterns:**"
                echo ""
                echo "| ID | Description |"
                echo "|----|-------------|"
                echo "$patterns" | while IFS='|' read -r pid pdesc; do
                    pdesc=$(escape_pipes "$pdesc")
                    echo "| \`$pid\` | $pdesc |"
                done
                echo ""
            fi

            # Anti-patterns
            local anti_patterns
            anti_patterns=$(get_skill_anti_patterns "$skill_dir")
            if [[ -n "$anti_patterns" ]]; then
                echo "**Anti-patterns:**"
                echo ""
                echo "| ID | Description | Why Bad |"
                echo "|----|-------------|---------|"
                echo "$anti_patterns" | while IFS='|' read -r aid adesc awhy; do
                    adesc=$(escape_pipes "$adesc")
                    awhy=$(escape_pipes "$awhy")
                    echo "| \`$aid\` | $adesc | $awhy |"
                done
                echo ""
            fi

            # Non-negotiables (for discipline skills)
            local non_neg
            non_neg=$(get_skill_non_negotiables "$skill_dir")
            if [[ -n "$non_neg" ]]; then
                echo "**Non-negotiables:**"
                echo ""
                echo "$non_neg" | while IFS='|' read -r nid ndesc; do
                    echo "- \`$nid\`: $ndesc"
                done
                echo ""
            fi
        done
    done

    cat << EOF
---

*Generated by \`make skills-reference\`*
EOF
}

# ============================================================================
# MAIN FUNCTIONS
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output)
                [[ -z "${2:-}" ]] && die "Missing argument for --output" $ERR_INVALID_ARGS
                OUTPUT_FILE="$2"
                shift 2
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
                die "Unknown option: $1" $ERR_INVALID_ARGS
                ;;
        esac
    done

    # Set default output file
    OUTPUT_FILE="${OUTPUT_FILE:-$PROJECT_ROOT/$DEFAULT_OUTPUT_FILE}"
}

main() {
    parse_arguments "$@"

    local skills_dir="$PROJECT_ROOT/.claude/skills"

    if [[ ! -d "$skills_dir" ]]; then
        die "No .claude/skills directory found"
    fi

    # Create output directory if needed
    local output_dir
    output_dir=$(dirname "$OUTPUT_FILE")
    mkdir -p "$output_dir"

    # Generate reference
    generate_reference > "$OUTPUT_FILE"

    echo "Generated $OUTPUT_FILE"
}

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================
main "$@"