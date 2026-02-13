#!/bin/bash
set -euo pipefail

# ============================================================================
# CHECK SKILL YAML
# ============================================================================
# CI check: Validate all skill YAML files are well-formed and have required files.
#
# Enforces:
# - Stop hook discipline: SKILL.md Stop hook must call `task claude:validate-skill -- --skill <folder-name>`
# - Naming convention: frontmatter name must match directory name
# - Collaboration references: all referenced skills must exist
# - Validations integrity: on_stop IDs exist, type=command only (v1), required fields present
# - Task target existence: commands starting with `task <target>` must reference valid targets
#
# Usage:
#     ./check-skill-yaml.sh
#     ./check-skill-yaml.sh --debug
#
# INPUTS:
# Optional:
#   --debug          Enable debug logging
#   --help           Show usage information
#
# OUTPUTS:
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

# Skill prefix (empty = no prefix required)
readonly SKILL_PREFIX=""

# Global arrays
ERRORS=()
ALL_SKILLS=()

# Validation arrays (must be initialized globally for set -u compatibility)
VALIDATIONS_IDS=()
VALIDATIONS_TYPES=()
VALIDATIONS_COMMANDS=()
ON_STOP_IDS=()

# Task target cache (newline-delimited for bash 3 compatibility)
TASK_TARGET_CACHE_KEYS=""

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

CI check: Validate all skill YAML files are well-formed and have required files.

Options:
    --debug     Enable debug logging
    --help      Show this help message

Examples:
    $SCRIPT_NAME

EOF
}

# Check if yq is available
has_yq() {
    command -v yq >/dev/null 2>&1
}

# Check if a Task target exists (with caching)
# Uses newline-delimited cache for bash 3 compatibility (avoids substring collisions)
task_target_exists() {
    local target="$1"
    local cache_entry

    # Check cache (exact line match)
    while IFS= read -r cache_entry; do
        if [[ "$cache_entry" == "$target=true" ]]; then
            return 0
        elif [[ "$cache_entry" == "$target=false" ]]; then
            return 1
        fi
    done <<< "$TASK_TARGET_CACHE_KEYS"

    # Check if task target exists using task --list
    local exists=false
    if task --list 2>/dev/null | grep -q "\\b${target}\\b"; then
        exists=true
    fi

    # Cache result (newline-delimited)
    TASK_TARGET_CACHE_KEYS="${TASK_TARGET_CACHE_KEYS}
${target}=${exists}"

    [[ "$exists" == "true" ]]
}

# ============================================================================
# YAML PARSING FUNCTIONS
# ============================================================================

# Parse YAML frontmatter from SKILL.md
# Sets: FM_NAME, FM_HOOKS_STOP
parse_skillmd_frontmatter() {
    local skill_dir="$1"
    local skillmd="$skill_dir/SKILL.md"

    FM_NAME=""
    FM_HOOKS_STOP=""

    if [[ ! -f "$skillmd" ]]; then
        return 1
    fi

    # Extract frontmatter (between --- and ---)
    local frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$skillmd" | sed '1d;$d')

    if [[ -z "$frontmatter" ]]; then
        return 1
    fi

    if has_yq; then
        FM_NAME=$(echo "$frontmatter" | yq '.name // ""' 2>/dev/null || echo "")
        FM_HOOKS_STOP=$(echo "$frontmatter" | yq '.hooks.Stop[].command // ""' 2>/dev/null || echo "")
    else
        # Basic parsing
        FM_NAME=$(echo "$frontmatter" | grep -E '^name:' | sed 's/^name:[[:space:]]*//' | sed 's/^"//;s/"$//')
        # Look for command: anywhere in Stop section (grep -A5 to get more context)
        FM_HOOKS_STOP=$(echo "$frontmatter" | grep -A5 'Stop:' | grep 'command:' | head -1 | sed 's/.*command:[[:space:]]*//' | sed 's/^"//;s/"$//')
    fi

    return 0
}

# Check if YAML file is valid
check_yaml_valid() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        return 0
    fi

    if has_yq; then
        yq '.' "$file" >/dev/null 2>&1
        return $?
    else
        # Basic check - look for obvious YAML errors
        # This is limited without a proper YAML parser
        # Check for tabs (YAML doesn't like tabs)
        if grep -q $'\t' "$file"; then
            return 1
        fi
        return 0
    fi
}

# Parse validations.yaml
# Sets: VALIDATIONS_IDS, VALIDATIONS_TYPES, VALIDATIONS_COMMANDS, ON_STOP_IDS
parse_validations_yaml() {
    local skill_dir="$1"
    local validations_yaml="$skill_dir/validations.yaml"

    VALIDATIONS_IDS=()
    VALIDATIONS_TYPES=()
    VALIDATIONS_COMMANDS=()
    ON_STOP_IDS=()

    if [[ ! -f "$validations_yaml" ]]; then
        return 1
    fi

    if has_yq; then
        local count
        count=$(yq '.validations | length' "$validations_yaml" 2>/dev/null || echo "0")

        if [[ "$count" != "0" ]] && [[ "$count" != "null" ]]; then
            for ((i=0; i<count; i++)); do
                local vid vtype vcmd
                vid=$(yq ".validations[$i].id // \"\"" "$validations_yaml" 2>/dev/null)
                vtype=$(yq ".validations[$i].type // \"command\"" "$validations_yaml" 2>/dev/null)
                vcmd=$(yq ".validations[$i].command // \"\"" "$validations_yaml" 2>/dev/null)

                VALIDATIONS_IDS+=("${vid:-}")
                VALIDATIONS_TYPES+=("${vtype:-command}")
                VALIDATIONS_COMMANDS+=("${vcmd:-}")
            done
        fi

        local on_stop_count
        on_stop_count=$(yq '.on_stop | length' "$validations_yaml" 2>/dev/null || echo "0")

        if [[ "$on_stop_count" != "0" ]] && [[ "$on_stop_count" != "null" ]]; then
            for ((i=0; i<on_stop_count; i++)); do
                local oid
                oid=$(yq ".on_stop[$i]" "$validations_yaml" 2>/dev/null)
                if [[ -n "$oid" ]] && [[ "$oid" != "null" ]]; then
                    ON_STOP_IDS+=("$oid")
                fi
            done
        fi
    else
        # Basic parsing
        local in_validations=false
        local in_on_stop=false
        local current_id=""
        local current_type="command"
        local current_command=""

        while IFS= read -r line || [[ -n "$line" ]]; do
            local trimmed
            trimmed=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            [[ -z "$trimmed" ]] && continue
            [[ "$trimmed" =~ ^# ]] && continue

            if [[ "$trimmed" == "validations:" ]]; then
                in_validations=true
                in_on_stop=false
                continue
            fi

            if [[ "$trimmed" == "on_stop:" ]]; then
                if [[ -n "$current_id" ]]; then
                    VALIDATIONS_IDS+=("$current_id")
                    VALIDATIONS_TYPES+=("${current_type:-command}")
                    VALIDATIONS_COMMANDS+=("$current_command")
                    current_id=""
                    current_type="command"
                    current_command=""
                fi
                in_validations=false
                in_on_stop=true
                continue
            fi

            if [[ "$in_validations" == true ]]; then
                if [[ "$trimmed" =~ ^-[[:space:]]*id:[[:space:]]*(.*) ]]; then
                    if [[ -n "$current_id" ]]; then
                        VALIDATIONS_IDS+=("$current_id")
                        VALIDATIONS_TYPES+=("${current_type:-command}")
                        VALIDATIONS_COMMANDS+=("$current_command")
                    fi
                    current_id="${BASH_REMATCH[1]}"
                    current_id=$(echo "$current_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
                    current_type="command"
                    current_command=""
                elif [[ "$trimmed" =~ ^type:[[:space:]]*(.*) ]]; then
                    current_type="${BASH_REMATCH[1]}"
                    current_type=$(echo "$current_type" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
                elif [[ "$trimmed" =~ ^command:[[:space:]]*(.*) ]]; then
                    current_command="${BASH_REMATCH[1]}"
                    current_command=$(echo "$current_command" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
                fi
            fi

            if [[ "$in_on_stop" == true ]]; then
                if [[ "$trimmed" =~ ^-[[:space:]]*(.*) ]]; then
                    local oid="${BASH_REMATCH[1]}"
                    oid=$(echo "$oid" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
                    if [[ -n "$oid" ]]; then
                        ON_STOP_IDS+=("$oid")
                    fi
                fi
            fi
        done < "$validations_yaml"

        if [[ -n "$current_id" ]]; then
            VALIDATIONS_IDS+=("$current_id")
            VALIDATIONS_TYPES+=("${current_type:-command}")
            VALIDATIONS_COMMANDS+=("$current_command")
        fi
    fi

    return 0
}

# Parse collaboration.yaml references
# Sets: COLLAB_SKILL_REFS
parse_collaboration_yaml() {
    local skill_dir="$1"
    local collab_yaml="$skill_dir/collaboration.yaml"

    COLLAB_SKILL_REFS=()

    if [[ ! -f "$collab_yaml" ]]; then
        return 1
    fi

    if has_yq; then
        local deps
        deps=$(yq '.dependencies[].skill // ""' "$collab_yaml" 2>/dev/null || echo "")
        while IFS= read -r ref; do
            if [[ -n "$ref" ]] && [[ "$ref" != "null" ]]; then
                COLLAB_SKILL_REFS+=("$ref")
            fi
        done <<< "$deps"

        local seqs
        seqs=$(yq '.composition[].sequence[]' "$collab_yaml" 2>/dev/null || echo "")
        while IFS= read -r ref; do
            if [[ -n "$ref" ]] && [[ "$ref" != "null" ]]; then
                COLLAB_SKILL_REFS+=("$ref")
            fi
        done <<< "$seqs"

        local triggers
        triggers=$(yq '.triggers[].suggest // ""' "$collab_yaml" 2>/dev/null || echo "")
        while IFS= read -r ref; do
            if [[ -n "$ref" ]] && [[ "$ref" != "null" ]]; then
                COLLAB_SKILL_REFS+=("$ref")
            fi
        done <<< "$triggers"
    else
        while IFS= read -r line; do
            if [[ "$line" =~ skill:[[:space:]]*([a-zA-Z0-9_-]+) ]]; then
                COLLAB_SKILL_REFS+=("${BASH_REMATCH[1]}")
            fi
            if [[ "$line" =~ suggest:[[:space:]]*([a-zA-Z0-9_-]+) ]]; then
                COLLAB_SKILL_REFS+=("${BASH_REMATCH[1]}")
            fi
        done < "$collab_yaml"
    fi

    return 0
}

# ============================================================================
# CHECK FUNCTIONS
# ============================================================================

# Check Stop hook discipline
check_stop_hook_discipline() {
    local skill_dir="$1"
    local skill
    skill=$(basename "$skill_dir")

    # Only check if validations.yaml exists
    if [[ ! -f "$skill_dir/validations.yaml" ]]; then
        return 0
    fi

    if ! parse_skillmd_frontmatter "$skill_dir"; then
        ERRORS+=("$skill: SKILL.md missing or has no frontmatter, but validations.yaml exists")
        return 0
    fi

    if [[ -z "$FM_HOOKS_STOP" ]]; then
        ERRORS+=("$skill: validations.yaml exists but SKILL.md has no Stop hook")
        return 0
    fi

    local expected="task claude:validate-skill -- --skill $skill"
    if [[ "$FM_HOOKS_STOP" != *"$expected"* ]]; then
        ERRORS+=("$skill: Stop hook must call '$expected' (validations.yaml exists)")
    fi
}

# Check naming convention
check_naming_convention() {
    local skill_dir="$1"
    local skill
    skill=$(basename "$skill_dir")

    # Check prefix (skip if empty - no prefix required)
    if [[ -n "$SKILL_PREFIX" ]] && [[ "$skill" != ${SKILL_PREFIX}* ]]; then
        ERRORS+=("$skill: Directory name must start with '$SKILL_PREFIX'")
    fi

    # Check frontmatter name matches directory
    if parse_skillmd_frontmatter "$skill_dir"; then
        if [[ -n "$FM_NAME" ]] && [[ "$FM_NAME" != "$skill" ]]; then
            ERRORS+=("$skill: SKILL.md name '$FM_NAME' must equal directory name '$skill'")
        fi
    fi
}

# Check collaboration references
check_collaboration_references() {
    local skill_dir="$1"
    local skill
    skill=$(basename "$skill_dir")

    if [[ ! -f "$skill_dir/collaboration.yaml" ]]; then
        return 0
    fi

    parse_collaboration_yaml "$skill_dir"

    # Skip if no references found (avoid unbound variable error)
    if [[ ${#COLLAB_SKILL_REFS[@]} -eq 0 ]]; then
        return 0
    fi

    for ref in "${COLLAB_SKILL_REFS[@]}"; do
        local found=false
        for s in "${ALL_SKILLS[@]}"; do
            if [[ "$s" == "$ref" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == false ]]; then
            ERRORS+=("$skill: collaboration.yaml references non-existent skill '$ref'")
        fi
    done
}

# Check validations integrity
check_validations_integrity() {
    local skill_dir="$1"
    local skill
    skill=$(basename "$skill_dir")

    if [[ ! -f "$skill_dir/validations.yaml" ]]; then
        return 0
    fi

    parse_validations_yaml "$skill_dir"

    # Check each validation
    for ((i=0; i<${#VALIDATIONS_IDS[@]}; i++)); do
        local vid="${VALIDATIONS_IDS[$i]}"
        local vtype="${VALIDATIONS_TYPES[$i]}"
        local vcmd="${VALIDATIONS_COMMANDS[$i]}"

        # Check id exists
        if [[ -z "$vid" ]] || [[ "$vid" == "null" ]]; then
            ERRORS+=("$skill: validations.yaml validations[$i] missing 'id' field")
            continue
        fi

        # Check type is command (v1)
        if [[ "$vtype" != "command" ]]; then
            ERRORS+=("$skill: validations.yaml validation '$vid' has type '$vtype' (v1 supports 'command' only)")
        fi

        # Check command exists
        if [[ -z "$vcmd" ]] || [[ "$vcmd" == "null" ]]; then
            ERRORS+=("$skill: validations.yaml validation '$vid' missing 'command' field")
        fi
    done

    # Check on_stop IDs exist (bash 3.2 compatible: check length before iterating)
    if [[ ${#ON_STOP_IDS[@]} -gt 0 ]]; then
        for oid in "${ON_STOP_IDS[@]}"; do
            local found=false
            for vid in "${VALIDATIONS_IDS[@]}"; do
                if [[ "$vid" == "$oid" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == false ]]; then
                ERRORS+=("$skill: validations.yaml on_stop references non-existent validation '$oid'")
            fi
        done
    fi
}

# Check Task targets exist
check_task_targets() {
    local skill_dir="$1"
    local skill
    skill=$(basename "$skill_dir")

    if [[ ! -f "$skill_dir/validations.yaml" ]]; then
        return 0
    fi

    parse_validations_yaml "$skill_dir"

    for ((i=0; i<${#VALIDATIONS_IDS[@]}; i++)); do
        local vid="${VALIDATIONS_IDS[$i]:-unknown}"
        local vcmd="${VALIDATIONS_COMMANDS[$i]}"

        # Extract task target from command
        if [[ "$vcmd" =~ ^task[[:space:]]+([a-zA-Z0-9_:-]+) ]]; then
            local target="${BASH_REMATCH[1]}"
            if ! task_target_exists "$target"; then
                ERRORS+=("$skill: validations.yaml validation '$vid' references non-existent task target '$target'")
            fi
        fi
    done
}

# Check a single skill
check_skill() {
    local skill_dir="$1"
    local skill
    skill=$(basename "$skill_dir")

    # Check naming convention
    check_naming_convention "$skill_dir"

    # Check SKILL.md exists
    if [[ ! -f "$skill_dir/SKILL.md" ]]; then
        ERRORS+=("$skill: Missing SKILL.md")
    fi

    # Check YAML files parse
    for yaml_file in skill.yaml validations.yaml sharp-edges.yaml collaboration.yaml; do
        local path="$skill_dir/$yaml_file"
        if [[ -f "$path" ]]; then
            if ! check_yaml_valid "$path"; then
                ERRORS+=("$skill/$yaml_file: Invalid YAML")
            fi
        fi
    done

    # Check Stop hook discipline
    check_stop_hook_discipline "$skill_dir"

    # Check validations integrity
    check_validations_integrity "$skill_dir"

    # Check Task targets exist
    check_task_targets "$skill_dir"
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

main() {
    parse_arguments "$@"

    local skills_dir="$PROJECT_ROOT/.claude/skills"

    if [[ ! -d "$skills_dir" ]]; then
        echo "No .claude/skills directory found"
        exit $ERR_GENERAL
    fi

    # First pass: collect all skill names
    local skill_dirs=()

    for skill_dir in "$skills_dir"/*/; do
        [[ ! -d "$skill_dir" ]] && continue

        # Only check directories with SKILL.md or validations.yaml
        if [[ ! -f "$skill_dir/SKILL.md" ]] && [[ ! -f "$skill_dir/validations.yaml" ]]; then
            continue
        fi

        ALL_SKILLS+=("$(basename "$skill_dir")")
        skill_dirs+=("$skill_dir")
    done

    # Second pass: validate each skill
    for skill_dir in "${skill_dirs[@]}"; do
        check_skill "$skill_dir"
        check_collaboration_references "$skill_dir"
    done

    # Report results
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo "Found ${#ERRORS[@]} error(s):"
        for e in "${ERRORS[@]}"; do
            echo "  - $e"
        done
        exit $ERR_GENERAL
    fi

    echo "All ${#skill_dirs[@]} skill(s) valid"
    exit $SUCCESS
}

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================
main "$@"