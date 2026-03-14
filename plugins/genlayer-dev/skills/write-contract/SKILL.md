---
name: write-contract
description: Write GenLayer intelligent contracts — storage types, decorators, non-deterministic blocks, equivalence principle patterns, and error handling.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - mcp__genlayer-docs__search_docs
  - mcp__genlayer-docs__fetch_url
---

# Writing Intelligent Contracts

Intelligent contracts are Python classes extending `gl.Contract`. State is persisted on-chain. Non-deterministic operations (LLM calls, web fetches) achieve consensus via the **Equivalence Principle**.

## Required File Headers

Every contract file **must** start with these two lines — deployment fails with `absent_runner_comment` without them:

```python
# v0.1.0
# { "Depends": "py-genlayer:latest" }
```

## Contract Skeleton

```python
# v0.1.0
# { "Depends": "py-genlayer:latest" }
from genlayer import *
import json

class MyContract(gl.Contract):
    owner: Address
    name: str
    count: u256
    items: TreeMap[str, str]
    tags: DynArray[str]

    def __init__(self, name: str):
        self.owner = gl.message.sender_address
        self.name = name
        self.count = u256(0)

    @gl.public.view
    def get_info(self) -> str:
        return json.dumps({"name": self.name, "count": int(self.count)})

    @gl.public.write
    def increment(self):
        self.count = u256(int(self.count) + 1)
```

## Storage Types

Never use plain `int`, `list`, or `dict` — they cause deployment failures.

| Python type | GenLayer type | Notes |
|-------------|---------------|-------|
| `int` | `u256` / `u8`–`u256` / `i8`–`i256` / `bigint` | No plain `int` |
| `list[T]` | `DynArray[T]` | |
| `dict[K, V]` | `TreeMap[K, V]` | Keys must be `str` or `u256` |
| `float`, `bool`, `str`, `bytes` | same | Work directly |
| `datetime` | `datetime.datetime` | |
| address | `Address` | |

**`u256` arithmetic** — convert to/from `int` explicitly (✅ tested):
```python
self.count = u256(int(self.count) + 1)
total = int(self.amount_a) + int(self.amount_b)
```

**Nested collections** — `TreeMap` can't hold `DynArray`. Use JSON strings (✅ tested):
```python
id_list = json.loads(self.index.get(key) or "[]")
id_list.append(new_id)
self.index[key] = json.dumps(id_list)
```

## Method Decorators

| Decorator | Purpose |
|-----------|---------|
| `@gl.public.view` | Read-only, free |
| `@gl.public.write` | Modifies state |
| `@gl.public.write.payable` | Modifies state + accepts tokens |
| `@gl.public.write.min_gas(leader=N, validator=N)` | Minimum gas for non-det operations |

## Transaction Context

```python
gl.message.sender_address    # caller (Address)
gl.message.value             # tokens sent (u256, payable only)
self.balance                 # this contract's token balance
```

## Error Handling

Use `gl.vm.UserError` — never bare `ValueError` or `Exception` (linter blocks deployment):

```python
if gl.message.sender_address != self.owner:
    raise gl.vm.UserError("Only owner can call this")
```

**Error prefix convention** (classifies failures for validator logic):
```python
raise gl.vm.UserError("[EXPECTED] Resource not found")   # business logic
raise gl.vm.UserError("[EXTERNAL] Fetch failed: 404")    # external API error
raise gl.vm.UserError("[TRANSIENT] Timeout on request")  # temporary failure
```

## Address Handling

Constructors must handle both `bytes` (test framework) and `str` (JS SDK) (✅ tested):

```python
def __init__(self, party_b: Address):
    if isinstance(party_b, (str, bytes)):
        party_b = Address(party_b)
    self.party_b = party_b
```

⚠️ In tests, `create_address()` returns raw `bytes`. Pass them directly or as `"0x" + addr.hex()`. Never pass `str(raw_bytes)` — that produces Python repr (`"b'\\xd8...'"`) and raises `binascii.Error`.

---

## Non-Deterministic Blocks

Non-det code **must** be inside a zero-argument function passed to an equivalence principle function. Storage is **not accessible** inside — copy to locals first.

```python
@gl.public.write
def evaluate(self, url: str):
    target = url        # capture for closure
    name = self.name    # copy storage to local

    def leader_fn():
        resp = gl.nondet.web.get(target)
        return gl.nondet.exec_prompt(f"Analyze {name}: {resp.body.decode()[:4000]}")

    # ... pass to equivalence principle function
```

### Web Access

```python
resp = gl.nondet.web.get(url)                              # resp.status, resp.body (bytes)
resp = gl.nondet.web.post(url, body="...", headers={})
text = gl.nondet.web.render(url, mode="text")              # JS-rendered → string
img  = gl.nondet.web.render(url, mode="screenshot")        # JS-rendered → bytes (PNG)
img  = gl.nondet.web.render(url, mode="screenshot", wait_after_loaded="1000ms")
```

`mode='text'`/`'html'` → string. `mode='screenshot'` → bytes — only mode compatible with `images=[...]`.

⚠️ `web.render(mode='screenshot')` cannot be mocked in direct tests (SDK v0.25.0 bug — returns empty bytes). To test visual contracts in direct mode, pass image bytes as a method argument.

### LLM Calls

```python
result = gl.nondet.exec_prompt("Your prompt here")
result = gl.nondet.exec_prompt("Describe this", images=[img_bytes])  # multimodal
```

`exec_prompt` return type is **not guaranteed to be `str`** across different GenVM backends. Always use this helper (✅ all edge cases tested):

```python
def _parse_llm_json(raw):
    if isinstance(raw, dict):
        return raw
    s = str(raw).strip().replace("```json", "").replace("```", "").strip()
    start, end = s.find("{"), s.rfind("}") + 1
    if start >= 0 and end > start:
        s = s[start:end]
    return json.loads(s)
```

---

## Equivalence Principle Patterns

### Pattern 1 — Partial Field Matching (default choice)

Leader and validator each run independently. Compare only objective decision fields — ignore subjective text (✅ tested):

```python
@gl.public.write
def resolve(self, match_id: str):
    url = self.matches[match_id]

    def leader_fn():
        web_data = gl.nondet.web.get(url)
        prompt = f"""
Find the match result. Page: {web_data.body.decode()[:4000]}
Return JSON: {{"score": "X:Y", "winner": 1 or 2 or 0 for draw, "analysis": "reasoning"}}
"""
        return _parse_llm_json(gl.nondet.exec_prompt(prompt))

    def validator_fn(leader_result) -> bool:
        if not isinstance(leader_result, gl.vm.Return):  # ✅ tested: correct type
            return False
        v = leader_fn()
        ld = leader_result.calldata
        # Only compare decision fields — analysis text will differ across LLMs
        return ld["winner"] == v["winner"] and ld["score"] == v["score"]

    result = gl.vm.run_nondet_unsafe(leader_fn, validator_fn)
    self.matches[match_id].winner = result["winner"]
    self.matches[match_id].analysis = result["analysis"]
```

### Pattern 2 — Numeric Tolerance

For prices or LLM scores that drift between leader and validator execution:

```python
def validator_fn(leader_result) -> bool:
    if not isinstance(leader_result, gl.vm.Return):
        return False
    v_price = leader_fn()
    l_price = leader_result.calldata
    if l_price == 0:
        return v_price == 0
    return abs(l_price - v_price) / abs(l_price) <= 0.02  # 2% tolerance

result = gl.vm.run_nondet_unsafe(leader_fn, validator_fn)
```

For LLM scores (0–10) — handle the zero/rejection gate:
```python
if l == 0 or v == 0:
    return l == v       # both must agree on rejection
return abs(l - v) <= 1  # ±1 otherwise
```

### Pattern 3 — LLM Comparison (Comparative)

When results are too rich for programmatic comparison — an LLM judges equivalence:

```python
result = gl.eq_principle.prompt_comparative(
    evaluate_fn,
    principle="`outcome` must match exactly. Other fields may differ.",
)
```

### Pattern 4 — Non-Comparative

Validators judge the leader's output against criteria without re-running the task. Use **only** for open-ended tasks with no web fetching (validators can't verify fetched data):

```python
result = gl.eq_principle.prompt_non_comparative(
    lambda: gl.nondet.web.get(url).body.decode(),
    task="Summarize in 2-3 sentences",
    criteria="Must capture the main point. Must be 2-3 sentences.",
)
```

⚠️ Never use for oracle/price/data contracts — validators only check if output looks reasonable, not if the fetched data is correct.

---

## `run_nondet_unsafe` vs `run_nondet`

| | `run_nondet_unsafe` | `run_nondet` |
|---|---|---|
| Validator exceptions | Unhandled = Disagree | Caught + compared automatically |
| Error handling | You implement in `validator_fn` | Built-in `compare_user_errors` callback |
| Use for | All custom patterns (recommended) | Convenience functions internally |

**Use `run_nondet_unsafe` for custom patterns.** Convenience functions (`strict_eq`, `prompt_comparative`, `prompt_non_comparative`) use `run_nondet` internally.

## Validator Result Types

```python
def validator_fn(leader_result) -> bool:
    if not isinstance(leader_result, gl.vm.Return):  # covers UserError + VMError
        return False
    data = leader_result.calldata
    # ...
```

`gl.vm.Return` and `gl.vm.UserError` are real classes — safe for `isinstance`. `gl.vm.Result` is a type alias — do not use in `isinstance`.

---

## Testing Validator Logic

Use `direct_vm.run_validator()` to test whether your validator agrees or disagrees. **Only works with `run_nondet_unsafe`** — `strict_eq` uses `spawn_sandbox()` which is not supported in the test mock (✅ tested):

```python
def test_validator_disagrees(direct_vm, direct_deploy):
    contract = direct_deploy("contracts/MyContract.py")
    direct_vm.sender = b'\x01' * 20

    # Leader run
    direct_vm.mock_llm(r".*", '{"winner": 1, "score": "2:1", "analysis": "A won"}')
    contract.resolve("match_1")

    # Swap mocks — different validator result
    direct_vm.clear_mocks()
    direct_vm.mock_llm(r".*", '{"winner": 2, "score": "0:1", "analysis": "B won"}')
    assert direct_vm.run_validator() is False

def test_validator_agrees(direct_vm, direct_deploy):
    contract = direct_deploy("contracts/MyContract.py")
    direct_vm.sender = b'\x01' * 20

    direct_vm.mock_llm(r".*", '{"winner": 1, "score": "2:1", "analysis": "A won"}')
    contract.resolve("match_1")
    # Same mock = same winner+score = validator agrees
    assert direct_vm.run_validator() is True
```

`run_validator()` raises `RuntimeError("No validator captured")` if called before any nondet method.

---

## Stable JSON Comparison

When comparing structured output between leader and validator, always serialize with `sort_keys=True` — key order is not guaranteed (✅ tested):

```python
json.dumps(result, sort_keys=True)  # stable for exact comparison
```

---

## Looking Up Docs

Use the `genlayer-docs` MCP server when you need detail beyond this skill:

```
search_docs(library="genlayer-docs", query="<topic>")
search_docs(library="genlayer-sdk", query="<topic>")
```

Examples:
- `search_docs(library="genlayer-docs", query="equivalence principle patterns")`
- `search_docs(library="genlayer-sdk", query="TreeMap DynArray storage")`
- `search_docs(library="genlayer-docs", query="security prompt injection")`

If the MCP server is unavailable, fetch docs directly:

| Topic | URL |
|-------|-----|
| **Intelligent Contracts overview** | https://docs.genlayer.com/developers/intelligent-contracts/introduction |
| **Storage types & features** | https://docs.genlayer.com/developers/intelligent-contracts/features/storage |
| **Equivalence Principle (full)** | https://docs.genlayer.com/developers/intelligent-contracts/equivalence-principle |
| **Development setup & workflow** | https://docs.genlayer.com/developers/intelligent-contracts/tooling-setup |
| **Debugging** | https://docs.genlayer.com/developers/intelligent-contracts/debugging |
| **Security & prompt injection** | https://docs.genlayer.com/developers/intelligent-contracts/security-and-best-practices |
| **Python SDK reference** | https://docs.genlayer.com/api-references/genlayer-py |
| **GenLayer Test reference** | https://docs.genlayer.com/api-references/genlayer-test |
| **GenLayer JS reference** | https://docs.genlayer.com/api-references/genlayer-js |
| **CLI reference** | https://docs.genlayer.com/api-references/genlayer-cli |
| **Python SDK source (API)** | https://sdk.genlayer.com/main/api/genlayer.html |
| **Contract examples** | https://github.com/genlayerlabs/genlayer-testing-suite/tree/main/tests/examples |
| **Project boilerplate** | https://github.com/genlayerlabs/genlayer-project-boilerplate |

See also: `genvm-lint`, `direct-tests`, `integration-tests`, and `genlayer-cli` skills for tooling.
