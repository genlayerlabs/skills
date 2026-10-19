---
name: genlayernode
description: Install, upgrade and diagnose Bradbury Phase 2 validator nodes with verified network identity, release artifacts and protocol manifests.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - WebFetch
  - AskUserQuestion
---

# Bradbury Phase 2 validator node

Use this skill for installation, upgrades, staking setup and monitoring on Linux.
It supports local hosts, SSH, GCP and AWS; keep credentials on the target host.
Read [bradbury-phase-2.md](bradbury-phase-2.md) before any operation. The canonical
machine-readable flow is [skill.yaml](skill.yaml).

## Explain the work before starting

State the selected host, operation and network, then outline these steps:

1. Verify host requirements and back up an existing installation.
2. Verify the chain genesis, AddressManager, RPC access and release artifacts.
3. Select a Phase 2-compatible CLI and register or inspect the validator.
4. Verify and install the exact node release and its GenVM dependencies.
5. Configure RPC/WS, trusted manifest, LLM providers and the operator keystore.
6. Start WebDriver, run doctor, then start the node and check health.
7. Configure optional monitoring with the operator's supplied endpoints.

Use existing operator authorization; do not ask again for routine authorized
steps. Obtain explicit authorization before signing staking transactions,
funding accounts, stopping a running node, or changing services when that action
is not already within the requested scope. Explain each consequential step.
Never redeploy consensus, change epoch timing or advance epochs during setup.

## Gather only missing inputs

- Host/location and access method; systemd, Docker Compose or manual run.
- Exact approved Phase 2 node release and compatible CLI version.
- Owner, operator and validator-wallet public addresses (distinct roles).
- RPC/WS endpoints and whether the assigned provider requires an API key.
- LLM provider choice, not its secret key.
- Optional monitoring destination and credential provisioning method.

Do not ask the user to paste private keys, keystore passwords, authenticated RPC
URLs or API keys in chat. Have the operator set secrets privately on the host in
a mode-0600 environment file. Display only whether each value is configured.
Do not print partial secrets, `.env`, authorization headers or raw provider errors.

## Non-negotiable preflight

- AMD64 Linux, 16 GB RAM, 8 cores, 128 GB SSD/NVMe, Python **3.10+** with pip and
  venv; Docker and Compose. The staking CLI also needs its supported Node.js version.
- Run `node scripts/check-network.mjs` from this skill's directory. Configure
  `BRADBURY_RPC_URL` privately to check an assigned endpoint. Chain ID 4221 alone
  is insufficient: older deployments reused it.
- Test the supplied WS endpoint with its required credentials. Anonymous HTTP
  success does not imply anonymous WS access; Conduit may return HTTP 401.
- Require a published tarball, signed checksums and trusted protocol manifest.
  A documentation example, Docker image or `latest` pointer is not release evidence.
- Use a new data directory when migrating from the previous network. Preserve
  old data and keystores; never apply ordinary same-chain DB-copy steps across networks.
- Check live stake requirements. Registration and delegation do not prove active
  consensus membership, especially during epoch 0.

## Procedures

| Operation | Procedure |
| --- | --- |
| Fresh setup | [install-procedure.md](install-procedure.md) |
| Upgrade | [update-procedure.md](update-procedure.md), [pre-update-checklist.md](pre-update-checklist.md) |
| Staking / operator proof | [staking-wizard-procedure.md](staking-wizard-procedure.md) |
| Shared checks | [common-procedures.md](common-procedures.md) |
| Monitoring | [monitoring-procedure.md](monitoring-procedure.md) |

Check [sharp-edges.yaml](sharp-edges.yaml) proactively and run the applicable
[validations.yaml](validations.yaml) checks. Do not claim readiness if the release,
manifest, WS credentials, LLM access or checks remain unavailable.

## Configuration contract

Use the selected release's `configs/node/config.yaml` as the base. Set:

- `rollup.genlayerchainrpcurl` and `rollup.genlayerchainwebsocketurl` to the verified
  endpoints. Keep keys separate in `GENLAYERNODE_ROLLUP_GENLAYERCHAINRPCKEY`.
- `consensus.consensusaddress` to the **AddressManager**, not ConsensusMain.
- `consensus.chainid: "4221"`, `consensus.genesis: 47930` and
  `consensus.manifestpath: "configs/node/protocol-manifest.json"`.
- `node.mode: validator`, `node.validatorWalletAddress` and `node.operatorAddress`
  using the actual registration. A full node is a separate explicit choice.

Use `GENLAYERNODE_PASSWORD` for the binary's keystore password. Docker Compose
reads `NODE_PASSWORD` and passes it to the binary as `GENLAYERNODE_PASSWORD`.
Never include passwords in the service's `ExecStart` arguments.

Run `python3 ./opt/genvm/current/bin/setup.py` from the final install location.
Run `./bin/genlayernode doctor` using the node's actual config, environment and
trusted manifest. Do not use obsolete `doctor check`, `--password`,
`--expected-consensus-address`, or `third_party/genvm` recipes for this release.

## Completion report

Report exact node/CLI/SDK versions, host, genesis and manifest verification,
registration transaction if one was authorized, node health and sync, and
monitoring delivery if configured. Clearly separate:

- checks passed locally / against a public RPC;
- node startup and doctor checks actually executed;
- registration versus active consensus participation;
- unresolved external prerequisites such as RPC keys or release publication.

Reference: [validator setup guide](https://docs.genlayer.com/validators/setup-guide).
During Phase 2 review, compare the [PR 705 preview](https://deploy-preview-705--genlayer-docs.netlify.app/validators/setup-guide)
against actual release artifacts; preview version examples may not be published yet.
