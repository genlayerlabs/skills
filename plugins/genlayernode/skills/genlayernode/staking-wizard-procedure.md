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
