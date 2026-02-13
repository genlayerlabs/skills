---
name: create-skill
description: Scaffold a new skill directory using the multi-YAML pattern. Use when user says /create-skill.
user-invocable: true
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob]
hooks:
  Stop:
    - type: command
      command: "task claude:validate-skill -- --skill create-skill"
  PostToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "$CLAUDE_PROJECT_DIR/.claude/hooks/check-skill-structure.sh"
---

# Create Skill

## Purpose
Create a new `.claude/skills/{folder-name}/` skill scaffold that follows the multi-YAML pattern.
This skill produces the canonical file set and wires the Stop hook to `task claude:validate-skill`.

## Quick Reference
- Creates: SKILL.md, skill.yaml, collaboration.yaml (+ validations.yaml, sharp-edges.yaml for non-helpers)
- Requires: folder name, kind, description
- Stop hook: `task claude:validate-skill -- --skill create-skill`

## Post-Creation Verification

The Stop hook runs three checks to ensure every created skill is valid:

1. **Structural**: `task claude:validate-skill-yaml` - YAML parses, required files exist
2. **Semantic**: `task claude:audit-skills-strict` - Multi-YAML pattern compliance
3. **Documentation**: `task claude:audit-skills` - Verifies skill is documented in CLAUDE.md

**IMPORTANT**: After creating skill files, you MUST add the skill to CLAUDE.md under "### Skill kinds". The audit will fail if the skill is not documented.

## Automation
See `skill.yaml` for the full procedure and patterns.
See `sharp-edges.yaml` for common failure modes.

## PostToolUse Hook (Automatic)

This skill includes a **PostToolUse hook** that runs automatically after every `Edit` or `Write` operation on skill files (`.claude/skills/**`). It catches broken skills immediately.

**Behavior:**
- Triggers on skill definition files: skill.yaml, SKILL.md, validations.yaml, collaboration.yaml, sharp-edges.yaml
- Runs `task claude:validate-skill-yaml` (structural check)
- Runs `task claude:audit-skills` in warn mode (semantic check, non-blocking)
- Exit 2 only if YAML is invalid or required files are missing

Hook script: `.claude/hooks/check-skill-structure.sh`