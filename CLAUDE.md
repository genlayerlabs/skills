# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository is a **Claude Code plugin marketplace** (`genlayerlabs`). It provides installable plugins that guide AI assistants through complex operational procedures.

### Installation

```bash
# Add the marketplace
/plugin marketplace add genlayerlabs/claude-code-skills

# Install a plugin
/plugin install genlayernode@genlayerlabs
```

## Marketplace Structure

```
.claude-plugin/
  marketplace.json              # Marketplace manifest
plugins/
  <plugin-name>/
    .claude-plugin/
      plugin.json               # Plugin manifest
    skills/
      <skill-name>/
        SKILL.md                # Skill entry point with frontmatter
        skill.yaml              # Machine-readable procedure definition
        validations.yaml        # Automated checks (pre/post)
        sharp-edges.yaml        # Known edge cases and gotchas
        collaboration.yaml      # Dependencies and composition
```

## Skill Architecture

Each skill is defined by multiple YAML/Markdown files:

- **SKILL.md** - Human-readable documentation with full procedure details, step-by-step instructions, and usage examples
- **skill.yaml** - Machine-readable procedure definition including inputs, patterns, anti-patterns, config wizard structure, and the main procedure flow
- **validations.yaml** - Automated checks (prerequisites, post-installation verification) with commands, expected results, and error messages
- **sharp-edges.yaml** - Known edge cases and gotchas with detection commands, impact descriptions, and fixes. These must be **proactively checked** during execution, not just used for reactive diagnosis
- **collaboration.yaml** - Dependencies on external tools and skill composition sequences

## Key Concepts

### Skill Structure
Skills follow a decision-tree pattern with:
- **Decision points** - Questions that branch the procedure
- **Patterns** - Reusable command sequences for common operations
- **Anti-patterns** - Things to avoid with explanations of why they're bad
- **Defaults** - Sensible default values

### Sharp Edges Philosophy
Edge cases in `sharp-edges.yaml` must be checked **before** each major phase, not after failures occur. Each edge includes:
- `detect` - How to identify the issue
- `impact` - What goes wrong if not addressed
- `fix` - How to resolve it
- `severity` - critical/high/medium

### Validation Timing
- `on_stop` validations - Must pass before procedure proceeds
- `on_warn` validations - Warnings that don't block but should be addressed

## Working with Skills

When modifying skills:
1. Keep SKILL.md and skill.yaml in sync - they describe the same procedure
2. Add new edge cases to sharp-edges.yaml when discovering failure modes
3. Add validation commands to validations.yaml for automated checking
4. Update collaboration.yaml when adding new dependencies or composition sequences

When a skill is invoked:
1. Display process overview at start
2. Check prerequisites from validations.yaml
3. Follow procedure from skill.yaml, checking sharp-edges.yaml proactively at each phase
4. Use config_wizard structure for interactive configuration
5. Run post-installation validations

## Security Constraints

Skills that handle secrets must follow strict masking requirements:
- Never display full API keys, passwords, or tokens
- Never execute remote commands that would expose secrets in output
- Use placeholders in generated configs, instruct users to set values manually

## Available Plugins

| Plugin | Skill | When to Use |
|--------|-------|-------------|
| `genlayernode` | `genlayernode` | Interactive wizard to set up a GenLayer validator node on Linux. |

## Development Skills

<!-- SKILLS_TABLE_START -->
| Skill | When to Use |
|-------|-------------|
| `commit` | Execute git commit with conventional commit message analysis |
| `create-skill` | Scaffold a new Claude Code skill using the multi-YAML patter |
| `docs-refresh` | Refresh documentation with deterministic generation from sou |
| `linear` | Create and manage Linear issues using templates for the GenL |
| `pr-create` | Creates GitHub pull requests with conventional commit-style  |
| `pr-merge` | Merge GitHub pull requests with strict CI validation. Never  |
| `validator-manage` | Manage GenLayer validators across testnets using the genlaye |
<!-- SKILLS_TABLE_END -->
