---
name: integration-tests
description: Write and run integration tests against a GenLayer environment.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
---

# Integration Tests

Run contracts against a real GenLayer environment (GLSim, Studio, or testnet) with full consensus validation.

Studio v0.123 and later (`studionet`, `studio_devnet`, a current local Studio) need `genlayer-test` 0.30.0 or later with `genlayer-py` 0.19.0 or later (`pip install -U genlayer-test genlayer-py`; naming both matters, because pip keeps an installed `genlayer-py` 0.19 release candidate otherwise). The matching JavaScript and CLI versions are `genlayer-js` 2.0.0 and CLI 0.40.0. See the [Consensus v0.6 migration guide](https://docs.genlayer.com/developers/consensus-v06-migration).

## Running Tests

```bash
# Against default network (from gltest.config.yaml)
gltest tests/integration/ -v -s

# Against specific network
gltest tests/integration/ -v -s --network localnet
gltest tests/integration/ -v -s --network studionet
gltest tests/integration/ -v -s --network testnet_bradbury
```

Always use `-v -s` for visible output during development.

## Test Pattern

```python
from gltest import get_contract_factory
from gltest.assertions import tx_execution_succeeded

def test_full_flow():
    factory = get_contract_factory("MyContract")
    contract = factory.deploy(args=[])

    # Write methods return transaction receipts
    tx_receipt = contract.set_data(args=["hello"]).transact()
    assert tx_execution_succeeded(tx_receipt)

    # Read methods return values directly
    result = contract.get_data(args=[contract.address]).call()
    assert result == "hello"
```

This fee-less form only works on networks that charge no fees (GLSim, a Studio configured gasless). On `studionet` the deploy reverts before the assertions run: use the fee-bearing form below.

### Fees on Studio v0.123 and later

`studionet` and `studio_devnet` (studio-dev.genlayer.com) charge fees: a deploy or write sent without a fee distribution reverts with `FeesDistributionMissing`. `genlayer-test` does not add fees on its own; it passes `fees=` through to `genlayer-py`. Quote them from the network and pass them along:

```python
from gltest import get_contract_factory
from gltest.assertions import tx_execution_succeeded


FEE_KEYS = ("distribution", "messageAllocations", "feeValue")


def _fees(estimate):
    # messageAllocations is present when the write emits messages to other contracts
    return {key: estimate[key] for key in FEE_KEYS if key in estimate}


def test_full_flow(gl_client, default_account):
    factory = get_contract_factory("MyContract")
    contract = factory.deploy(args=[], fees=_fees(gl_client.estimate_transaction_fees()))

    # Simulates the write and sizes the deposit for it (genlayer-py supports this on Studio networks only)
    estimate = gl_client.estimate_transaction_fees_for_write(
        address=contract.address,
        function_name="set_data",
        account=default_account,
        args=["hello"],
    )
    tx_receipt = contract.set_data(args=["hello"]).transact(fees=_fees(estimate))
    assert tx_execution_succeeded(tx_receipt)
```

- `estimate["policy"]["enabled"]` tells whether the network charges fees. Decide from it, not from the network name.
- Accounts need no funding on `studionet`: a 0 GEN balance works as long as the transaction carries the estimated fees, and the unused part of the deposit is refunded.
- `gltest --fee-profile artifacts/fee-profile.json` records the fees the test run consumed (read from the receipts, which Studio networks expose) as a profile for the CLI (`--fee-profile`) and frontends. Cover every branch that emits messages to other contracts.

`ACCEPTED` and `FINALIZED` are transaction lifecycle states, not proof that
contract execution succeeded. A transaction can be accepted and finalized with
an execution error, and failed execution applies no state changes. For deploy
transactions, failed execution means no contract is created.

Always assert `tx_execution_succeeded(receipt)` before reading state, checking
schema/code, or treating a missing contract as an infrastructure issue.

## Key Differences from Direct Mode

| | Direct Mode | Integration Tests |
|---|---|---|
| Speed | ~30ms | ~seconds to minutes |
| Server required | No | Yes (GLSim, Studio, or testnet) |
| Consensus | Leader only | Full leader + validators |
| Write methods | Return values directly | Return transaction receipts |
| Read methods | Return values directly | Use `.call()` |
| Mocking | `mock_web()` / `mock_llm()` | Real web/LLM calls |

## Write vs Read Calls

**Write methods** (state-changing):
```python
# .transact() submits and waits for consensus
tx_receipt = contract.method_name(args=[arg1, arg2]).transact()
assert tx_execution_succeeded(tx_receipt)
```

**Read methods** (view-only):
```python
# .call() reads without transaction
result = contract.view_method(args=[arg1]).call()
```

## Configuration (gltest.config.yaml)

```yaml
networks:
  default: localnet
  localnet:
    # GenLayer Studio running locally
  studionet: {}
    # studio.genlayer.com: no funding needed (0 GEN balance is fine), but every deploy and write must carry fees
  testnet_bradbury:
    accounts:
      - "${ACCOUNT_PRIVATE_KEY_1}"
      - "${ACCOUNT_PRIVATE_KEY_2}"

paths:
  contracts: contracts/
```

`genlayer-test` 0.30.0 accepts only `networks`, `paths` and `environment` at the top level, needs `networks.default`, and rejects an empty entry for any network other than `localnet` (hence `studionet: {}`).

## Test Markers

```python
import pytest

@pytest.mark.slow
def test_expensive_operation():
    """Excluded by default. Run with: gltest -m slow"""
    pass
```

## Environments

- **GLSim** (`pip install genlayer-test[sim]`, `glsim --port 4000 --validators 5`) — lightweight, no Docker, ~1s startup. Runs Python natively, not in GenVM. Good for fast iteration.
- **Studio local** (`genlayer up`) — full GenVM, real consensus, Docker required. Validates runtime compatibility.
- **studio.genlayer.com** (StudioNet) — hosted Studio, no setup, rate-limited (see Common Issues). **No tokens required, but not gasless:** since Studio v0.123 every deploy and write must carry estimated fees (see "Fees on Studio v0.123 and later"). Accounts with 0 GEN balance can then deploy and run tests normally.
- **Testnet Bradbury** — real network, requires funded accounts.

## When to Use Integration Tests

- Validating consensus (leader + validators agree)
- Testing real web requests and LLM calls
- Pre-deployment smoke tests
- Verifying contract works in actual GenVM (not just Python runner)

Direct mode should cover most logic testing. Use integration tests for final validation before deploying.

## Common Issues

### "Transaction not found" errors
Clear cache: `rm -rf .gltest_cache`

### `FeesDistributionMissing` revert
The deploy or write carried no fees. Pass `fees=` as shown in "Fees on Studio v0.123 and later". With `genlayer-test` older than 0.30.0, upgrade first.

### Slow tests
Run single tests during development:
```bash
gltest tests/integration/test_file.py::test_specific -v -s
```

### JSON serialization
When working with mock validators, convert to dicts:
```python
transaction_context = {"validators": [v.to_dict() for v in mock_validators]}
```

### Studio rate limits (HTTP 429 / -32429)
`studio.genlayer.com` enforces per-IP limits: **60 req/min, 1000 req/hr, 10000 req/day**. Limits aren't permanent — once tripped, further requests are rejected until the current window resets (next minute / hour / day cycle). Throttle batch tests, run heavy suites against `localnet` (GLSim or local Studio), or pace `.transact()` calls.

`-32028` is the related pending-queue cap — **up to 32 in-flight txs per sender**; a separate cap also applies per contract to prevent flooding the shared Studio. Wait for receipts before submitting the next batch instead of firing in parallel.
