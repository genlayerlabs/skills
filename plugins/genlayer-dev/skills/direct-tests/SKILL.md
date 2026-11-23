---
name: direct-tests
description: Write and run fast direct mode tests for GenLayer intelligent contracts.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
---

# Direct Mode Tests

Write fast, in-memory tests for intelligent contracts. No server, no Docker — tests run in ~30-50ms.

Contracts pinned to the v0.3 or v0.4 runners (see the `write-contract` skill) need `genlayer-test` 0.30.0 or later (`pip install -U genlayer-test`). Older versions fail at `direct_deploy`: with `urllib.error.HTTPError: HTTP Error 404` on a clean machine (they look for releases in the archived `genvm` repository), or with `ValueError: Runner hash ... not found` when an old GenVM bundle is already cached.

Legacy v0.2 contracts (`from genlayer import *`, `py-genlayer:1jb45aa8…` and older pins) go the other way: they do not load in direct mode on `genlayer-test` 0.30.0 (`DecodingError: unexpected end of memory`, then `ImportError: Failed to load contract`). Keep their direct tests on `genlayer-test` 0.29.x with a pinned SDK (`direct_deploy(..., sdk_version="v0.2.16")`), or migrate the contract first.

## Running Tests

```bash
pytest tests/direct/ -v
pytest tests/direct/test_specific.py -v
pytest tests/direct/test_specific.py::test_one_case -v
```

## Fixtures

Available from `genlayer-test` pytest plugin:

```python
def test_example(direct_vm, direct_deploy, direct_alice, direct_bob):
    # direct_vm      — VMContext with cheatcodes
    # direct_deploy  — deploy a contract file
    # direct_alice   — test address
    # direct_bob     — test address
    pass
```

All fixtures: `direct_vm`, `direct_deploy`, `direct_alice`, `direct_bob`, `direct_charlie`, `direct_owner`, `direct_accounts`

## Basic Test Pattern

```python
def test_set_and_get(direct_vm, direct_deploy, direct_alice):
    contract = direct_deploy("contracts/my_contract.py")
    direct_vm.sender = direct_alice

    contract.set_data("hello")

    result = contract.get_data(direct_alice)
    assert result == "hello"
```

## Mocking Web Requests

For contracts that call `gl.nondet.web.get()`:

```python
import json

def test_with_web_mock(direct_vm, direct_deploy, direct_alice):
    contract = direct_deploy("contracts/my_contract.py")
    direct_vm.sender = direct_alice

    # Pattern: regex matching on URL
    direct_vm.mock_web(
        r".*api\.example\.com/prices.*",
        {"status": 200, "body": '{"price": 42.5}'},
    )

    contract.update_price("ETH/USD")
    assert contract.get_price("ETH/USD") == 42.5
```

### Full mock format (when you need headers/method control)

```python
direct_vm.mock_web(
    r"api\.example\.com/data",
    {
        "response": {
            "status": 200,
            "headers": {},
            "body": json.dumps({"key": "value"}).encode()
        },
        "method": "GET"
    }
)
```

## Mocking LLM Responses

For contracts that call `gl.nondet.exec_prompt()`:

```python
direct_vm.mock_llm(
    r".*Extract the match result.*",  # Regex on prompt text
    json.dumps({"score": "2:1", "winner": 1}),
)
```

**Mock strings on the v0.3 and v0.4 runners.** `genlayer-test` 0.30.0 runs `json.loads` on every string mock before handing it to the contract, while the current SDK expects the text the model returned and parses JSON itself. So a mock string that happens to parse as JSON arrives as the wrong type:

- A JSON prompt (`exec_prompt(..., response_format="json")`) mocked as above fails with `NondetException: invalid nondeterministic response: JSON result is not text`.
- A text prompt mocked with `"42"`, `"true"` or a JSON object string fails with `NondetException: invalid nondeterministic response: text result is not a string`. Plain prose such as `"hello world"` is unaffected.

Until `genlayer-test` changes this, wrap the text the model would return in one more `json.dumps`:

```python
def llm_text(text: str) -> str:
    return json.dumps(text)

def llm_json(obj) -> str:
    return llm_text(json.dumps(obj))

direct_vm.mock_llm(r".*Extract the match result.*", llm_json({"score": "2:1", "winner": 1}))
direct_vm.mock_llm(r".*How many goals.*", llm_text("42"))
```

Checked on both runners with `genlayer-test` 0.30.0 on 2026-11-23.

## Clearing Mocks

```python
direct_vm.clear_mocks()  # Reset between test scenarios
```

## VMContext Cheatcodes

```python
# Set transaction sender
direct_vm.sender = direct_alice

# Set native value (wei)
direct_vm.value = 1000000000000000000  # 1 ETH

# Expect a revert
with direct_vm.expect_revert("Insufficient balance"):
    contract.withdraw(1000)

# Temporary sender change
with direct_vm.prank(direct_bob):
    contract.method()  # Called as bob

# Snapshot and restore state
snap_id = direct_vm.snapshot()
contract.modify_state()
direct_vm.revert(snap_id)  # State restored

# Set account balance
direct_vm.deal(direct_alice, 1000000000000000000)

# Time travel
direct_vm.warp("2024-06-01T12:00:00Z")
```

## Replaying the Validator

A direct call runs only the leader side. For contracts that use `gl.vm.run_nondet` (including helpers built on it), `genlayer-test` (0.24.0) captures the validator function so you can replay it with different mocks:

```python
def test_validator_rejects_different_data(direct_vm, direct_deploy, direct_alice):
    contract = direct_deploy("contracts/my_contract.py")
    direct_vm.sender = direct_alice

    direct_vm.mock_web(r".*api\.example\.com.*", {"status": 200, "body": '{"price": 42.5}'})
    contract.update_price("ETH/USD")  # leader runs, validator is captured

    # Swap mocks so the validator sees different external data, then replay
    direct_vm.clear_mocks()
    direct_vm.mock_web(r".*api\.example\.com.*", {"status": 200, "body": '{"price": 99}'})
    assert direct_vm.run_validator() is False

    # Optional overrides
    direct_vm.run_validator(leader_result={"price": 42.5})   # replace the leader's return value
    direct_vm.run_validator(leader_error=Exception("boom"))  # simulate a leader error
    direct_vm.run_validator(index=0)                         # pick an earlier run_nondet call
```

- Returns the validator's `bool`. Raises `RuntimeError` if no `run_nondet` call was captured.
- `direct_vm.clear_validators()` drops captured validators.

## SDK Loading Order

`direct_deploy` sets up the SDK before the contract is imported: it installs the WASI mock, adds the `genlayer` SDK to `sys.path` (the GenVM release comes from `sdk_version=` or the `GENVM_VERSION` environment variable, for example `GENVM_VERSION=v0.6.0-rc14`; when both are omitted, the loader asks GitHub for the newest GenVM release, downloads it (about 300 MB) if it is not cached, and falls back to the cache only when offline, so set `GENVM_VERSION` to keep runs reproducible and avoid a new download on every GenVM release; the contract header only supplies the runner hash within that release archive), then loads the contract. So:

- Do not `import genlayer` / `from genlayer import ...` at module top level of a test file; do it inside the test after `direct_deploy(...)`.
- Load contracts with `direct_deploy`, not a bare import of the contract file.

## Test Organization

```
tests/direct/
├── conftest.py           # Shared fixtures and mock helpers
├── test_<feature>.py     # Tests per feature/method
└── test_<feature>_web.py # Tests requiring web/LLM mocks
```

## What to Test in Direct Mode

| Category | Example |
|----------|---------|
| State transitions | Create → read back → verify fields |
| Validation / reverts | Invalid inputs, unauthorized callers |
| Access control | Owner-only methods, role checks |
| Edge cases | Empty state, boundary values, overflow |
| Web/LLM parsing | Mock responses → verify extraction logic |

## Common Patterns

### Testing access control
```python
def test_only_owner(direct_vm, direct_deploy, direct_alice, direct_bob):
    contract = direct_deploy("contracts/my_contract.py")

    direct_vm.sender = direct_alice
    contract.create_item("item_1")

    direct_vm.sender = direct_bob
    with direct_vm.expect_revert("Only owner"):
        contract.delete_item("item_1")
```

### Testing state transitions
```python
def test_state_flow(direct_vm, direct_deploy, direct_alice):
    contract = direct_deploy("contracts/my_contract.py")
    direct_vm.sender = direct_alice

    contract.create_item("item_1")
    assert contract.get_item("item_1")["status"] == "pending"

    contract.approve_item("item_1")
    assert contract.get_item("item_1")["status"] == "approved"
```

### Reusable mock helpers (conftest.py)
```python
import json

def mock_price_api(direct_vm, pair: str, price: float):
    """Mock a price API response."""
    direct_vm.mock_web(
        rf".*api\.example\.com/prices/{pair}.*",
        {"status": 200, "body": json.dumps({"price": price})},
    )
```

## Tips

- Always `direct_vm.sender = ...` before calling write methods
- Use `--json` flag on `genvm-lint check` before writing tests to understand the contract's interface
- `gl.vm.spawn_sandbox` is not supported by the direct runner in `genlayer-test` 0.30.0, inside or outside a nondet block (`ModuleNotFoundError: No module named 'cloudpickle'`, or `ValueError: unknown result code 14` when `cloudpickle` is installed); cover those paths with integration tests
- By default a direct call runs the leader function only — validator logic is not exercised. To replay it explicitly, use `direct_vm.run_validator()` (see "Replaying the Validator"). Use integration tests for full consensus validation.
- Import `genlayer` inside the test (or a fixture) only after `direct_deploy(...)` has run. In a clean pytest process the SDK is not on `sys.path` until then; a module-level `import genlayer` in a test file fails at collection time.
