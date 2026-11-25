---
name: genvm-lint
description: Validate GenLayer intelligent contracts with the GenVM linter.
allowed-tools:
  - Bash
  - Read
---

# GenVM Lint

Validate intelligent contracts for safety, correctness, and SDK compliance.

## Setup

Requires `genvm-linter` (included in `requirements.txt` for boilerplate projects):

```bash
pip install genvm-linter
```

Contracts pinned to the v0.3 or v0.4 runners (the current `write-contract` headers) need `genvm-linter` 0.11.1 or later. As of 2026-11-23 that is a pre-release (0.11.1rc2), so install it with `pip install -U --pre genvm-linter` (without `-U`, pip keeps an installed 0.11.0). Version 0.11.0 only knows the legacy v0.2 runners: on a current contract `check` fails validation with `Failed to load SDK: "filename 'runners/py-genlayer/...tar' not found"`, and its lint step skips the storage and structure checks because it does not recognise `gl.contract.Contract` subclasses as contracts.

## Workflow

**Always lint before testing.** Run `genvm-lint check` after writing or modifying a contract. Fix all errors before running tests.

```bash
genvm-lint check contracts/my_contract.py
```

`check` runs both lint (AST safety) and validate (SDK semantics) in one pass.

## Commands

### check (recommended)
```bash
genvm-lint check contracts/my_contract.py
genvm-lint check contracts/my_contract.py --json  # Machine-readable output
```

### lint (fast AST checks only, ~50ms)
```bash
genvm-lint lint contracts/my_contract.py
```

Catches:
- Forbidden imports (`os`, `sys`, `subprocess`, `random`, etc.)
- Non-deterministic patterns (bare `float` usage)
- Contract header structure issues

### validate (SDK semantic checks, ~200ms)
```bash
genvm-lint validate contracts/my_contract.py
```

Validates:
- Types exist in SDK (`TreeMap`, `DynArray`, `Address`, etc.)
- Decorators correctly applied (`@gl.public.view`, `@gl.public.write`)
- Storage fields have valid types (no `dict`/`list`)
- Method signatures correct

### schema (extract ABI)
```bash
genvm-lint schema contracts/my_contract.py
genvm-lint schema contracts/my_contract.py --json
genvm-lint schema contracts/my_contract.py --output abi.json
```

### typecheck (Pyright/Pylance)
```bash
genvm-lint typecheck contracts/my_contract.py
genvm-lint typecheck contracts/my_contract.py --json
genvm-lint typecheck contracts/my_contract.py --strict
```

Runs Pyright with SDK paths auto-configured. Catches type mismatches, missing attributes, undefined variables. Pyright is not installed with the linter: `pip install pyright` first.

### download (pre-download GenVM artifacts)

The `genvm-manager` release names below need `genvm-linter` 0.11.1 or later. Version 0.11.0 only sees the releases of the archived `genvm` repository and fails on these names with `No GenVM runner bundle for v0.6.0-rc14`.

```bash
genvm-lint download                        # Latest
genvm-lint download --version v0.6.0-rc14  # Specific genvm-manager release
genvm-lint download --list                 # Show cached
genvm-lint download --available            # Show releases on GitHub
```

## Output Formats

### Human (default)
```
✓ Lint passed (3 checks)
✓ Validation passed
  Contract: MyContract
  Methods: 8 (5 view, 3 write)
```

### JSON (`--json`)
```json
{"ok":true,"lint":{"ok":true,"passed":3},"validate":{"ok":true,"contract":"MyContract","methods":8,"view_methods":5,"write_methods":3,"ctor_params":2}}
```

## Exit Codes

- `0` — All checks passed
- `1` — Lint or validation errors found
- `2` — Contract file not found
- `3` — SDK download failed

## Limits

`genvm-linter` 0.11.1rc2 reports E014 (`Class 'X' used in storage needs @allow_storage decorator`) for storage dataclasses decorated with `@gl.storage.allow`, because the lint step only recognizes the legacy decorator name. This is a false positive: `@allow_storage` does not exist on the v0.3 and v0.4 runners. When E014 is the only lint finding and validation passes, treat the check as passed and keep `@gl.storage.allow`.

A passing `check` proves the contract loads in the runner its header pins. It does not prove the target network ships that runner: a v0.3 pin (written for the retired Bradbury Phase 2) lints clean and is still rejected by Studio and Testnet Bradbury Phase 3. Confirm the pin with the dry-runs in the `write-contract` skill.

## Agent Workflow

When fixing lint errors iteratively:
1. Run `genvm-lint check contract.py --json`
2. Parse JSON for specific errors
3. Fix each error in the contract
4. Re-run check until `"ok": true` (or until the only finding left is the E014 false positive described in **Limits**, which keeps `"ok": false`)
5. Proceed to tests
