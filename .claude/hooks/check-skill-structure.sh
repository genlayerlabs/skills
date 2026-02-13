#!/bin/bash
set -euo pipefail

# ============================================================================
# CHECK SKILL STRUCTURE (Hook)
# ============================================================================
# PostToolUse hook: Validate skill structure after creating/editing skill files.
# Runs after Write/Edit on .claude/skills/** to catch broken skills immediately.
#
# This is designed to be used as a Claude Code PostToolUse hook that receives
# JSON input via stdin with tool_input containing the file_path.
#
# Usage (as hook):
#     echo '{"tool_input":{"file_path":".claude/skills/code/skill.yaml"}}' | ./check-skill-structure.sh
#
# INPUTS:
#   stdin: JSON with tool_input.file_path or tool_input.filePath
#
# OUTPUTS:
#   Exit code 0 on success or when file is not a skill file
#   Exit code 2 on validation failure (with error messages to stderr)
#
# ============================================================================

# ============================================================================
# CONSTANTS
# ============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

# Exit codes
readonly SUCCESS=0
readonly ERR_VALIDATION=2

# ============================================================================
# MAIN LOGIC
# ============================================================================

# Use CLAUDE_PROJECT_DIR if available, otherwise use detected PROJECT_ROOT
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PROJECT_ROOT}"

# Read JSON from stdin
INPUT=$(cat)

# Extract file path from tool_input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')

# Exit early if no file path or not in .claude/skills/
if [[ -z "$FILE_PATH" || ! "$FILE_PATH" =~ \.claude/skills/ ]]; then
    exit $SUCCESS
fi

# Only check on skill definition files (not arbitrary files in skills/)
case "$FILE_PATH" in
    *skill.yaml|*SKILL.md|*validations.yaml|*collaboration.yaml|*sharp-edges.yaml)
        # Continue with validation
        ;;
    *)
        # Not a skill definition file
        exit $SUCCESS
        ;;
esac

# Change to project directory for task commands
cd "$PROJECT_DIR"

# Run structural validation (YAML parsing + required files)
# Note: Skills should use claude-skill- prefix
if ! task claude:validate-skill-yaml >/dev/null 2>&1; then
    echo "Skill structure validation failed" >&2
    echo "" >&2
    echo "Run 'task claude:validate-skill-yaml' for details:" >&2
    task claude:validate-skill-yaml 2>&1 | head -20 >&2
    exit $ERR_VALIDATION
fi

# Run semantic audit in warn mode (exit 0 even on warnings)
# This prints warnings but doesn't block
AUDIT_OUTPUT=$(task claude:audit-skills 2>&1) || true
if echo "$AUDIT_OUTPUT" | grep -qi "warning"; then
    echo "Skill audit warnings (non-blocking):" >&2
    echo "$AUDIT_OUTPUT" | grep -i "warning" >&2
fi

exit $SUCCESS