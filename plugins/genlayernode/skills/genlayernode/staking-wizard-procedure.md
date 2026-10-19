# Bradbury Phase 2 staking wizard

Run [network/release preflight](bradbury-phase-2.md) before signing anything.
Use the exact qualified CLI version with the corresponding Phase 2 SDK. The
`genlayer` npm default tag may still select an older release; verify its version
and bundled SDK rather than assuming `npm install -g genlayer` is sufficient.

## Accounts

- Owner: cold account that funds staking and controls withdrawals; stays off-server.
- Operator: local CLI account used to sign the registration proof, then exported
  securely to the validator server. It needs GEN on the new L2 for transaction gas.
- Validator wallet: on-chain identity returned by successful registration.

Phase 2 `validatorJoin` requires an operator public key and proof of possession
bound to chain, owner and ValidatorWalletFactory. An external operator address
alone cannot produce that proof. Use the CLI's supported local-account/keystore
flow; never request private keys in chat or substitute an empty proof.

## Preflight and wizard

```sh
genlayer --version
genlayer network list
genlayer account list
genlayer staking epoch-info --network testnet-bradbury
genlayer staking wizard --network testnet-bradbury
```

If using a custom assigned RPC, use the installed CLI's documented `--rpc`
option/configuration after checking `--help`. Do not paste authenticated URLs.
Verify the network identity on that endpoint before the wizard.

Read the deployed self-stake/delegation minima. Do not hardcode 42,000 GEN or
claim epoch 0 has no minimum. Have the owner approve the stake amount and gas
before submission. A submitted transaction is not a successful registration:
require its successful receipt and validator-wallet event.

Record all three public addresses and back up both account keystores securely.
Only transfer the operator keystore to the node. Verify with:

```sh
genlayer staking validator-info --validator <validator-wallet> --network testnet-bradbury
genlayer staking validators --network testnet-bradbury
```

Registered validators can appear before they are in the active set. Check epoch,
minimum self-stake, priming and eligibility separately. Do not advance epochs
or promise activation as part of setup. Additional self-stake must come from the
position's permitted funding source; delegation does not replace self-stake.

Before any deposit, exit, claim, identity change or operator rotation, inspect
that installed version's `--help`, owner permissions and current on-chain state.
A proof used for registration cannot be replayed for an operator rotation:
rotation is bound to the validator wallet. The v0.40 CLI handles that context.

## Fresh owner/operator walkthrough

Run on the owner's machine in an interactive terminal; the wizard prompts for
private passwords locally. If using SSH, allocate a TTY. Do not feed private keys
or passwords into chat, shell history or command-line options.

```bash
genlayer account create --name "Bradbury Owner"
genlayer account use "Bradbury Owner"
genlayer account list
genlayer staking epoch-info --network testnet-bradbury
genlayer staking wizard --account "Bradbury Owner" --network testnet-bradbury
```

For an existing owner, select that account instead of creating another. Fund its
public address on the verified chain with the chosen self-stake amount plus gas
before confirming registration. In the wizard:

1. Confirm owner and network. Verify the displayed public address.
2. Review the current minimum and available balance; choose the authorized stake.
3. Create or select a separate local operator account so the CLI can sign the
   possession proof. An arbitrary external address cannot supply that proof.
4. Export the operator keystore with a strong export passphrase, and retain it
   privately. This passphrase becomes the node-keystore password when installing the encrypted
   file directly, and may differ from the CLI account password.
5. Review addresses, amount and gas, then submit only the authorized transaction.
6. Wait for the receipt. Record the validator-wallet contract address separately
   from the owner and operator EOA addresses. If identity setup is offered, use
   only the operator's intended public metadata.

If the export step was missed, export the existing operator instead of creating
another identity or registering again:

```bash
umask 077
genlayer account export --account "Bradbury Operator" --output ./operator-keystore.json
chmod 600 ./operator-keystore.json
```

The export command prompts for its passphrase and the source account password.
Back up the owner separately; the operator export cannot recover owner funds.
`account unlock` uses an OS keychain and may be unavailable on a headless server;
use the supported interactive encrypted-keystore flow instead of putting passwords
in argv or making a plaintext key file.

Fund the **registered operator** with an approved gas amount from the owner or
other authorized funding account, using the exact addresses recorded above:

```bash
genlayer account send <operator-address> <approved-amount> \
  --account "Bradbury Owner" --network testnet-bradbury
```

The amount accepts CLI GEN units, e.g. `0.1gen`; this is a syntax example, not a
universal gas budget. Verify the successful receipt and operator balance. Transfer
only the encrypted operator export over the approved SSH/cloud access method and
import it as in install-procedure.md. Delete the temporary transfer copy after
successful import while retaining a secure backup.

If a transaction times out, inspect its hash, receipt and current registration
before retrying. A repeated wizard submission can duplicate an operation that
already succeeded. If the wizard cannot prompt, fix terminal access; do not bypass
the proof or substitute the owner key on the server.
