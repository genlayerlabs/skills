# GenLayer Staking Wizard Procedure

## Goal
Guide new validators through the `genlayer staking wizard` to register on-chain, create an operator key, and export the keystore for the validator server.

## Understanding Validator Addresses

GenLayer validators operate with **three separate addresses**:

| Address | Purpose | Where It Lives |
|---------|---------|----------------|
| **Owner** | Cold wallet. Signs staking transaction, controls withdrawals. | Local machine (never on server) |
| **Operator** | Hot wallet. Signs blocks, runs the node on behalf of the owner. | On the validator server |
| **Validator Wallet** | Smart contract deployed on-chain representing validator identity. | On-chain (returned by wizard after staking) |

**Key insight**: The owner stakes funds and designates an operator. The operator runs the node. If the server is compromised, only the operator key is at risk — staked funds remain safe.

Reference: https://docs.genlayer.com/validators/setup-guide#understanding-validator-addresses

## Prerequisites

Before running the wizard:

- **genlayer CLI** installed (`npm install -g genlayer`)
- An **owner account** with **42,000+ GEN** tokens on GenLayer Chain
- The CLI must be configured for the correct **network** (e.g., `testnet-asimov`)
- The owner account must be **unlocked**

### Verify Prerequisites

```bash
# Check CLI is installed
genlayer --version

# List existing accounts
genlayer account list

# Check balance of active account
genlayer account show

# Check current network
genlayer network list
```

### If No Account Exists

Create and fund an owner account first:

```bash
# Create owner account (interactive — asks for encryption password)
genlayer account create --name "My Validator Owner"

# Unlock the account (interactive — asks for password)
genlayer account unlock --account "My Validator Owner"

# Set as active
genlayer account use "My Validator Owner"

# Show address to fund
genlayer account show
# -> Send 42,000+ GEN to the displayed address
```

**IMPORTANT**: `account create` is interactive — it prompts for an encryption password (min 8 characters). This cannot be automated via piped input.

## Wizard Flow (7 Steps)

The wizard is **fully interactive** and runs in the terminal. It does NOT open a browser. All prompts require keyboard input.

### Invocation

```bash
# Full wizard (prompts for account and network)
genlayer staking wizard

# Skip account and network prompts
genlayer staking wizard --account "My Validator Owner" --network testnet-asimov

# Skip identity setup
genlayer staking wizard --account "My Validator Owner" --network testnet-asimov --skip-identity
```

### Step 1: Account Setup

**What happens**: Selects the owner account that will stake funds.

**Prompt**: "Select an account that will be the owner of the validator"

**Options**:
- Select from existing accounts (shows address for each)
- Create a new account

**Skipped if**: `--account` flag is provided.

**Output**:
```
Step 1: Account Setup
---------------------
Using account: My Validator Owner (0x01959d0ed126285cbed368a0d9e7c4eb14d2b77b)
```

### Step 2: Network Selection

**What happens**: Selects the target network.

**Prompt**: "Select network"

**Options**: Available networks (excludes "studionet"). Default: `testnet-asimov`.

**Skipped if**: `--network` flag is provided.

**Output**:
```
Step 2: Network Selection
-------------------------
Using network: Genlayer Asimov Testnet
```

### Step 3: Balance Check

**What happens**: Verifies the owner account has enough GEN to stake.

**Requirements**:
- After Epoch 0: Minimum 42,000 GEN + gas buffer (~0.01 GEN)
- During Epoch 0: No minimum enforced, but validator won't activate until minimum is met

**If balance insufficient**: Wizard displays error with required amount and exits. Fund the account and re-run.

**Output on success**:
```
Step 3: Balance Check
---------------------
Balance: 110050 GEN
Minimum stake required: 42000 GEN
Balance sufficient!
```

### Step 4: Operator Setup

**What happens**: Creates or selects the operator account and exports its keystore.

**Prompt**: "Do you want to use a separate operator address?"

**Recommended**: Yes — separating owner and operator improves security.

**Three paths**:

#### Path A: Same as Owner (Not recommended)
- Operator = Owner address
- No keystore export
- Only suitable for testing

#### Path B: Select Existing CLI Account
1. Lists available accounts
2. Asks for export filename (default: `{name}-keystore.json`)
3. Handles filename conflicts
4. Prompts for export password (min 8 characters)
5. Confirms password
6. Exports keystore to current directory

#### Path C: Create New Operator Account (Recommended)
1. Prompts for operator account name (e.g., "My Validator Operator")
2. Creates the account (prompts for encryption password, min 8 characters)
3. Prompts for export filename
4. Handles filename conflicts
5. Prompts for export password (min 8 characters) — **this is the passphrase needed for import on the server**
6. Confirms password
7. Exports keystore to current directory

**Output**:
```
Step 4: Operator Setup
----------------------
✔ Do you want to use a separate operator address? Yes
✔ How would you like to set up the operator? Create new operator account
✔ Enter a name for the operator account: My Validator Operator

✔ Enter a password to encrypt your keystore (minimum 8 characters): ********
✔ Confirm password: ********

✔ Account 'My Validator Operator' created at: ~/.genlayer/keystores/My Validator Operator.json
✔ Export keystore filename: My Validator Operator-keystore.json
✔ Enter password for exported keystore (needed to import in node): ********
✔ Confirm password: ********
✔ Enter password to unlock 'My Validator Operator': ********
✔ Account 'My Validator Operator' exported to: /current/dir/My Validator Operator-keystore.json

ℹ Address: 0x992fff41a1F49AF2043c2017B80F5a8d66f0a47B

========================================
  IMPORTANT: Transfer operator keystore
========================================
File: /current/dir/My Validator Operator-keystore.json
Transfer this file to your validator server and import it
into your validator node software.
========================================
```

**CRITICAL**: Save the exported keystore file and remember the export password. You need both to import the operator key on the validator server.

### Step 5: Stake Amount

**What happens**: User specifies how much GEN to stake.

**Prompt**: "Enter stake amount (min: 42000, max: {balance} GEN)"

**Input format**: Number with optional "GEN" suffix (e.g., `42000`, `100000gen`, `50000 GEN`)

**Confirmation**: "You will stake {amount}. Continue?" — answering "no" aborts the wizard.

**Output**:
```
Step 5: Stake Amount
--------------------
✔ Enter stake amount (min: 42000, max: 110050 GEN): 100000
✔ You will stake 100000. Continue? Yes
```

### Step 6: Join as Validator (On-chain Transaction)

**What happens**: Submits the staking transaction to the blockchain. This:
1. Stakes the specified GEN amount
2. Registers you as a validator
3. Deploys a validator wallet smart contract
4. Designates the operator address

**Output**:
```
Step 6: Join as Validator
-------------------------
⠴ Creating validator with 100000 GEN stake...
Result:
{
  transactionHash: '0xdbf14d7e...',
  validatorWallet: '0x1451c990fa6Fa23Bc2773266Fa022cBb369cE165',
  amount: '100000 GEN',
  operator: '0x992fff41a1f49af2043c2017b80f5a8d66f0a47b',
  blockNumber: '5414105'
}

✔ Validator created successfully!
```

**The `validatorWallet` address is what you'll configure in the node's config.yaml.**

### Step 7: Identity Setup (Optional)

**What happens**: Sets public metadata for your validator.

**Prompt**: "Would you like to set up your validator identity now?"

**If yes, collects** (all optional except moniker):
1. **Moniker** (required) — Display name
2. **Logo URL** — Link to validator logo image
3. **Website URL** — Validator website
4. **Description** — Free-text description
5. **Email** — Contact email
6. **Twitter handle**
7. **Telegram handle**
8. **GitHub handle**

**Skipped if**: `--skip-identity` flag is provided, or user answers "no".

**Can be done later**: `genlayer staking set-identity`

### Completion Summary

The wizard displays a summary with all addresses and next steps:

```
========================================
   Validator Setup Complete!
========================================

Summary:
  Validator Wallet:  0x1451c990fa6Fa23Bc2773266Fa022cBb369cE165
  Owner:             0x01959d0ed126285cbed368a0d9e7c4eb14d2b77b (My Validator Owner)
  Operator:          0x992fff41a1f49af2043c2017b80f5a8d66f0a47b (My Validator Operator)
  Staked Amount:     100000gen
  Network:           Genlayer Asimov Testnet

Next Steps:
  1. Transfer operator keystore to your validator server:
     /current/dir/My Validator Operator-keystore.json
  2. Import it into your validator node software
  3. Monitor your validator:
     genlayer staking validator-info --validator 0x1451c990...
  4. Lock your account when done: genlayer account lock
```

## What to Save After the Wizard

| Item | Where to Find | Needed For |
|------|--------------|------------|
| **Validator Wallet Address** | Wizard summary output | `config.yaml` → `node.validatorWalletAddress` |
| **Operator Address** | Wizard Step 4 output | `config.yaml` → `node.operatorAddress` |
| **Operator Keystore File** | Current directory (exported file) | Upload to server → import into node |
| **Export Passphrase** | You set it in Step 4 | Importing keystore on the server |
| **Owner Account Password** | You set it during account creation | Unlocking owner account for future operations |
| **Operator funded** | `genlayer account show --account "Operator"` | Operator needs GEN for gas fees to sign validation transactions |

## Post-Wizard: Fund the Operator Account

**CRITICAL**: The operator account needs GEN to pay gas fees for signing validation transactions. A newly created operator has **0 balance** and **will fail to validate without funds**. This step must be completed before the node can operate.

### Why the Operator Needs Funds

The operator is the "hot wallet" that runs on the validator server. Every time it participates in a validation round, it submits on-chain transactions that cost gas. Without GEN in the operator account, those transactions fail silently — the node appears online but produces no validations.

### Procedure

#### 1. Check Both Balances

Always check on-chain balances before transferring:

```bash
# Check owner balance (source of funds)
genlayer account show --account "Owner Account Name"

# Check operator balance (should be 0 for new operators)
genlayer account show --account "Operator Account Name"
```

#### 2. Decide How Much to Send

The amount depends on your owner's available balance and how long you want the operator to run without topping up:

| Usage | Approximate Cost |
|-------|-----------------|
| Single validation transaction | ~0.0001 GEN gas |
| Day of active validation | ~0.01-0.1 GEN |
| Recommended minimum | **10 GEN** (covers thousands of transactions) |
| Top-up threshold | Refund when < 1 GEN remaining |

**When choosing an amount, consider:**
- The owner's remaining balance (shown by `genlayer account show`)
- How frequently you want to monitor and top up
- Higher amounts = less frequent top-ups needed

#### 3. Transfer from Owner to Operator

The skill should present the user with options based on the owner's available balance:

**Option A: Default amount (10 GEN)** — Recommended minimum, covers thousands of transactions.

**Option B: Custom amount** — User types a specific amount. Useful if the owner has significant remaining balance and the user wants less frequent top-ups.

**Option C: Fund it myself** — Skip automated transfer. User will fund the operator externally (e.g., from an exchange or another wallet).

```bash
# Transfer GEN from owner to operator
genlayer account send <OPERATOR_ADDRESS> <AMOUNT>gen \
  --account "Owner Account Name" \
  --network testnet-asimov
```

Example:
```bash
# Owner has 60,050 GEN available, sending 50,000 to operator
genlayer account send 0x992fff41a1F49AF2043c2017B80F5a8d66f0a47B 50000gen \
  --account "Edgars Asimov" \
  --network testnet-asimov
```

#### 4. Verify Transfer

```bash
# Confirm operator now has funds
genlayer account show --account "Operator Account Name"
# Balance should match the transferred amount

# Confirm owner balance decreased accordingly
genlayer account show --account "Owner Account Name"
```

### Skill Execution Flow

When the skill runs this step, it should:

1. **Fetch on-chain balances** for both owner and operator
2. **Display both balances** to the user clearly
3. **Present funding options** with the owner's available balance visible:
   - Default (10 GEN) — with note that owner has X GEN available
   - Custom amount — user types amount, knowing the owner's balance
   - Fund myself — skip, user handles it externally
4. **Execute the transfer** if user chose option A or B
5. **Verify both balances** after transfer to confirm success

### Symptoms of Unfunded Operator

If the operator runs out of GEN:
- Node starts and connects to the network
- Validation transactions fail with gas-related errors in logs
- Validator appears online but misses validation rounds
- Lost rewards for every missed round
- May eventually be quarantined for inactivity

### When to Check

This step should be performed:
1. **After the wizard** — before uploading the keystore to the server
2. **Periodically** — monitor operator balance and top up when low
3. **After changing operator** — new operator always starts with 0 balance

## Verifying After the Wizard

```bash
# Check validator info on-chain
genlayer staking validator-info --validator <VALIDATOR_WALLET_ADDRESS>

# Expected output includes:
# - owner, operator addresses
# - vDeposit (staked amount)
# - selfStakePendingDeposits (shows activation epoch)
# - needsPriming status
# - live status (false until activated)
```

**Note on activation**: After staking, your deposit enters a pending state. It activates after a waiting period (typically 2 epochs). The `selfStakePendingDeposits` field shows the `activatesAtEpoch` value.

## Post-Wizard: Priming

After your deposit activates, you may need to prime the validator:

```bash
genlayer staking validator-prime --validator <VALIDATOR_WALLET_ADDRESS>
```

Check if priming is needed:
```bash
genlayer staking validator-info --validator <VALIDATOR_WALLET_ADDRESS>
# Look for: needsPriming: true/false
```

## Interactive Limitations

**IMPORTANT**: The staking wizard is fully interactive and requires a TTY terminal. It **cannot** be automated via:
- Piped stdin (`echo "yes" | genlayer staking wizard`)
- Non-interactive shells (CI/CD pipelines)
- Remote execution via `ssh --command` or `gcloud compute ssh --command`

The wizard must be run directly in a terminal where the user can type responses. When guiding users through this process:
1. Provide the exact command to run
2. Explain what each prompt will ask
3. Tell the user what to type at each step
4. Have them report back the output (especially addresses)

## Alternative: Individual CLI Commands

If the wizard cannot be used (e.g., automation, partial re-run), the same operations can be performed individually:

```bash
# 1. Create owner account (interactive — password prompt)
genlayer account create --name "My Validator Owner"
genlayer account unlock --account "My Validator Owner"

# 2. Create operator account (interactive — password prompt)
genlayer account create --name "My Validator Operator"
genlayer account unlock --account "My Validator Operator"

# 3. Export operator keystore (interactive — password prompt)
genlayer account export --account "My Validator Operator" --output "./operator-keystore.json"

# 4. Join as validator (non-interactive)
genlayer staking validator-join \
  --account "My Validator Owner" \
  --amount 42000gen \
  --operator 0x<OPERATOR_ADDRESS> \
  --network testnet-asimov

# 5. Set identity (non-interactive via individual fields, or interactive via wizard)
genlayer staking set-identity \
  --account "My Validator Owner" \
  --validator 0x<VALIDATOR_WALLET_ADDRESS>
```

**Note**: Steps 1-3 require interactive password prompts. Step 4 (`validator-join`) is non-interactive if all flags are provided. However, `account create`, `account unlock`, and `account export` always require interactive password input.

## Useful Post-Wizard Commands

```bash
# List all accounts
genlayer account list

# Show active account details and balance
genlayer account show

# Switch active account
genlayer account use "Account Name"

# Lock account when done (security best practice)
genlayer account lock --account "My Validator Owner"

# Check epoch info (staking parameters)
genlayer staking epoch-info --network testnet-asimov

# List active validators
genlayer staking active-validators --network testnet-asimov

# Change operator address later
genlayer staking set-operator \
  --account "My Validator Owner" \
  --validator 0x<VALIDATOR_WALLET_ADDRESS> \
  --operator 0x<NEW_OPERATOR_ADDRESS>
```

## Common Issues

### "Address is not a validator"
- The account address is not the validator wallet address
- Use the `validatorWallet` from the wizard output, not the owner address
- Correct: `genlayer staking validator-info --validator 0x<VALIDATOR_WALLET>`

### Balance Insufficient
- Fund the owner account with 42,000+ GEN
- Re-run the wizard after funding

### Account Locked
- Unlock before running wizard: `genlayer account unlock --account "Name"`

### Wizard Aborted
- If you answered "no" at the stake confirmation, wizard exits cleanly
- Re-run the wizard — no on-chain changes were made

### Export Password Forgotten
- The export password is needed to import the keystore on the server
- If forgotten, export again: `genlayer account export --account "Operator Name"`
- This creates a new keystore file with a new password

### Operator Address Already in Use
- An operator can only be assigned to one validator at a time
- Create a new operator account or use `set-operator` to reassign
