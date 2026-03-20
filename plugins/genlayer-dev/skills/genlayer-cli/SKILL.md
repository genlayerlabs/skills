---
name: genlayer-cli
description: Use the GenLayer CLI to deploy, interact with, and debug intelligent contracts.
allowed-tools:
  - Bash
  - Read
---

# GenLayer CLI

The `genlayer` CLI manages contract deployment, interaction, transaction inspection, and network configuration. Works with GenLayer Studio (local), studio.genlayer.com, and Testnet Bradbury.

## Setup

```bash
npm install -g genlayer
```

## Network Configuration

```bash
genlayer network set                    # Interactive selector
genlayer network set testnet-bradbury   # Direct
genlayer network info                   # Show current network config
genlayer network list                   # List all networks
```

Networks: `localnet`, `studionet`, `testnet-asimov`, `testnet-bradbury`

**Always use `genlayer network set` instead of `--rpc`** for built-in networks. The `--rpc` flag bypasses the chain configuration (consensus contract ABI, `isStudio` flag, etc.) and will cause transaction polling failures. Only use `--rpc` for custom/private networks not in the built-in list.

## Account Management

```bash
genlayer account                        # Show active account (address, balance, network)
genlayer account list                   # List all accounts
genlayer account create --name dev1     # Create new account
genlayer account use dev1               # Set active account
genlayer account unlock                 # Cache key in OS keychain (no password prompts)
genlayer account lock                   # Remove from keychain

# Import from private key or keystore
genlayer account import --name imported --private-key 0x...
genlayer account import --name imported --keystore ./keystore.json

# Send tokens
genlayer account send 0x123...abc 10gen
```

Amount formats: `"10gen"`, `"0.5gen"`, or raw wei `"1000000000000000000"`

### Non-interactive usage (CI/CD, containers, agents)

`account create`, `account import`, and `account send` accept `--password <password>` to skip interactive prompts:

```bash
genlayer account create --name dev1 --password "mypassword"
genlayer account import --name imported --private-key 0x... --password "mypassword"
```

`account unlock` requires an OS keychain (macOS Keychain, GNOME Keyring, etc.) and will fail in headless containers. When the account is locked, commands that sign transactions (`deploy`, `write`, `appeal`, `account send`) will prompt for the keystore password. To automate these, pipe the password via stdin:

```bash
echo "mypassword" | genlayer deploy --contract contracts/my_contract.py --args "arg1"
```

## Funding Testnet Accounts

New accounts start with 0 GEN. To deploy or write on testnets, fund the account first.

**Faucet**: [https://testnet-faucet.genlayer.foundation/](https://testnet-faucet.genlayer.foundation/)

1. Get your address: `genlayer account` → copy the `address` field
2. Go to the faucet URL, paste the address, and claim 100 GEN (once per 24 hours)
3. Verify: `genlayer account` should show the updated balance

The faucet uses Cloudflare Turnstile and cannot be automated from CLI — the user must claim manually in a browser. Works for both Testnet Bradbury and Testnet Asimov.

## Contract Deployment

```bash
# Deploy a specific contract
genlayer deploy --contract contracts/my_contract.py
genlayer deploy --contract contracts/my_contract.py --args "arg1" 42

# Run all deploy scripts in deploy/ folder
genlayer deploy
```

## Contract Interaction

### Read (no transaction)
```bash
genlayer call <address> <method>
genlayer call 0x123...abc get_data --args "key1"
```

### Write (sends transaction)
```bash
genlayer write <address> <method>
genlayer write 0x123...abc set_data --args "hello"
```

### Inspect contract
```bash
genlayer schema <address>   # Method signatures and types
genlayer code <address>     # Source code
```

## Transaction Debugging

The most useful debugging command — inspect what happened in a transaction:

```bash
# Get full receipt (waits for FINALIZED by default)
genlayer receipt <txHash>

# Get just stdout or stderr from execution
genlayer receipt <txHash> --stdout
genlayer receipt <txHash> --stderr

# Wait for specific status
genlayer receipt <txHash> --status PENDING
genlayer receipt <txHash> --status FINALIZED

# Custom retry behavior
genlayer receipt <txHash> --retries 50 --interval 3000
```

Transaction statuses: `SUBMITTED` → `PENDING` → `FINALIZED`

## Appeal a Transaction

Challenge a transaction result to trigger re-evaluation by validators:

```bash
genlayer appeal <txHash>
```

## Local Studio Management

```bash
genlayer init                               # Initialize environment
genlayer init --numValidators 10 --headless  # Customize
genlayer up                                 # Start Studio
genlayer up --reset-db                      # Fresh start
genlayer stop                               # Stop all services
```

### Local Validator Management

```bash
genlayer localnet validators get                          # List all
genlayer localnet validators count                        # Count
genlayer localnet validators create --stake 50            # Add one
genlayer localnet validators create-random --count 3      # Add multiple
genlayer localnet validators update 0x... --model gpt-4   # Change model
genlayer localnet validators delete --address 0x...       # Remove
```

## Debugging Workflow

When a transaction fails or produces unexpected results:

1. **Get the receipt**: `genlayer receipt <txHash> --stdout --stderr`
2. **Check contract schema**: `genlayer schema <address>` (verify method exists, correct args)
3. **Read contract source**: `genlayer code <address>` (verify deployed code matches local)
4. **Try a read call**: `genlayer call <address> <view_method>` (check current state)
5. **Appeal if needed**: `genlayer appeal <txHash>` (re-run consensus)

## Project Scaffolding

```bash
genlayer new myproject          # Create from template
genlayer new myproject --path ./projects/
```

## Configuration

```bash
genlayer config get                         # Show all config
genlayer config get network                 # Specific key
genlayer config set network=testnet-bradbury
genlayer config reset network               # Restore default
```
