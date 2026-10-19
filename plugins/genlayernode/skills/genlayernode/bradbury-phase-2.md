# Bradbury Phase 2 preflight

Run this before the generic install, update or staking procedures. Verify the chosen release explicitly; examples are not evidence that an artifact
is published or compatible with this deployment.

## Network identity

| Setting | Value |
| --- | --- |
| Network | `testnet-bradbury` (Orbit, not zkSync) |
| Public HTTP RPC | `https://rpc.testnet-chain.genlayer.com` |
| Public chain explorer | `https://scan.testnet-chain.genlayer.com` |
| Chain ID / native currency | `4221` / `GEN` (18 decimals) |
| Block-zero hash | `0x17d89764d4f4f963158fc4c5e8f2cb670c2837740b35f37081c12860c3df97e4` |
| AddressManager (`consensusaddress`) | `0x3F71AE080BD6270A91dBcc7960d88797828538E0` |
| Consensus start block (`consensus.genesis`) | `47930` (AddressManager creation block) |
| Staking / ConsensusMain | Resolve `getAddress("Staking")` / `getAddress("ConsensusMain")` on AddressManager |

AddressManager is the deployment anchor. Resolve the current Staking and ConsensusMain
entries through it and require code at those addresses; do not pin their initial
addresses as network identity. The trusted node manifest remains a separate
admission requirement and must match the approved deployment.

The chain genesis hash and consensus start block are different settings.
The legacy networks also used chain ID 4221. Do not accept chain ID alone, copy
an old Asimov/Bradbury registry, or silently fall back to an older RPC endpoint.

From this skill's directory, run:

```sh
node scripts/check-network.mjs
```

For an assigned authenticated endpoint, set `BRADBURY_RPC_URL` and `BRADBURY_RPC_KEY` (`X-AccessKey`) privately in the
operator's environment and run the same command. Never paste keys or authenticated
URLs into chat, command output, screenshots, or committed configuration.
If the check fails, stop before signing or starting the node and ask the RPC owner
to fix routing. A configured public hostname is not proof it is ready.

A successful HTTP check does not qualify a validator's WebSocket connection.
Create a key at [app.conduit.xyz/rpc-keys](https://app.conduit.xyz/rpc-keys).
Set it in the node's environment:

```sh
export GENLAYERNODE_ROLLUP_GENLAYERCHAINRPCKEY="<your Conduit API key>"
```

With Docker, add the same variable to the private `.env` file next to
`docker-compose.yaml`. Never put the key in RPC/WebSocket URLs or anywhere in
`config.yaml`. Current nodes send it as `X-AccessKey`.
Verify `eth_subscribe` / `eth_unsubscribe` with the assigned WS endpoint and key;
anonymous HTTP access does not establish WS readiness. Run doctor before startup.

Provision the trusted Phase 2 manifest and set `consensus.chainid: "4221"` and
`consensus.manifestpath: "configs/node/protocol-manifest.json"`. The HTTP and WS
provider key belongs in `GENLAYERNODE_ROLLUP_GENLAYERCHAINRPCKEY`; current nodes
send it as `X-AccessKey`. Conduit WS may reject unauthenticated connections.

## Release and CLI qualification

Choose an exact node release explicitly approved for **Bradbury Phase 2**. A
published Docker image does not prove that a matching binary tarball is available.
Check the release's binary download, checksum and bundled configuration. Do not
resolve a generic `latest` pointer and assume it is compatible.

The staking CLI must include an SDK version supporting this deployment's contracts.
In particular, Phase 2 validator registration uses an operator public key and
proof of possession; the old `validatorJoin(address)` flow is incompatible.
Confirm the CLI supplies these using its supported key-generation flow. Never
replace the proof with an empty value or ask for the operator's private key.
Do not tell an operator that upgrading `genlayer-js` independently has upgraded
the SDK bundled into their installed `genlayer` CLI.

Read the deployed validator and delegator minimum stake through the qualified
CLI/SDK. `42,000 GEN` is a protocol default, not a verified current network
requirement. The validator minimum applies to self-stake; delegation does not
replace it. Registration/delegation during epoch 0 does not itself establish
active-set membership. Report registration and activation separately.

## Configuration and state

For Bradbury Phase 2, generated configuration must use the AddressManager and
start block above, `NODE_ENV=testnet-bradbury`, and the assigned HTTP/WS endpoints.
Use the chosen release's configuration schema, GenVM layout and doctor syntax.
With the trusted manifest configured:

```sh
./bin/genlayernode doctor
```

Fund the operator with **GEN on the new L2**, not ETH from an older chain.
Preserve keystores and backups. When moving from the previous network, create a
fresh node database/data directory; do not reuse the old chain's synchronization
state. An ordinary same-network binary upgrade may follow the existing update
procedure after this identity check passes.

Never redeploy consensus, advance epochs, or change epoch timing as part of node
installation. Observe the existing activation schedule.

Sources: [deployment book](https://github.com/genlayerlabs/genlayer-consensus/blob/main/deployments/bradbury-phase-2.json)
and [deployment runbook](https://github.com/genlayerlabs/genlayer-consensus/blob/main/docs/deployment/bradbury-phase-2-runbook.md).
Public domain names are the operator-designated release endpoints; verify them
at execution time.
