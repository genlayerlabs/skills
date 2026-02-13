---
name: docs-refresh
description: Refresh documentation with deterministic generation from source files. Use when user says /docs-refresh.
user-invocable: true
allowed-tools:
  - Read
  - Bash
  - Glob
  - Grep
  - Edit
  - Write
hooks:
  Stop:
    - type: command
      command: "task claude:validate-skill -- --skill docs-refresh"
---

# Docs Refresh

## Purpose

Keep generated documentation in sync with source files. Manages skill reference documentation and project-level Claude instructions.

## Quick Reference

- **Manages**: `docs/skills/REFERENCE.md`, `CLAUDE.md` (skills table)
- **Sources**: `.claude/skills/*/skill.yaml`
- **Stop hook**: `task claude:validate-skill -- --skill docs-refresh`

## Commands

```bash
# Regenerate all documentation
task docs:refresh

# Check if docs are in sync (CI mode)
task docs:refresh-check

# Regenerate skills reference only
task claude:skills-reference
```

## Outputs

| Artifact | Purpose |
|----------|---------|
| `docs/skills/REFERENCE.md` | Generated skill inventory with patterns and ownership |
| `CLAUDE.md` | Project instructions for Claude (includes skills table) |

## CLAUDE.md Skills Table

The skills table in `CLAUDE.md` lists all skills and when to use them. When adding/removing skills:

1. Update the skills table in `CLAUDE.md`
2. Run `task docs:refresh` to regenerate REFERENCE.md
3. Commit both files together

## When It Fails

1. **Skill reference out of sync**: Run `task docs:refresh` to regenerate
2. **Skill YAML invalid**: Fix syntax errors in skill.yaml files

## Automation

See `skill.yaml` for the full procedure and patterns.
See `sharp-edges.yaml` for common failure modes.
