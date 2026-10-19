# Install a Bradbury Phase 2 validator

Read [network preflight](bradbury-phase-2.md) and [SKILL.md](SKILL.md) first.

## 1. Host and release

Identify the target host and access method; execute all host operations there.
Check AMD64 Linux, 16 GB RAM, 8 cores, 128 GB SSD/NVMe, Docker Compose and Python
3.10+ with pip/venv. Use the operator-approved release version, not `latest`.
Check its publication before modifying the host:

```sh
version=<approved-published-version>
base=https://storage.googleapis.com/gh-af/genlayer-node/bin/amd64/${version}
curl -fI "${base}/genlayer-node-linux-amd64-${version}.tar.gz"
```

Download the tarball, `genlayer-node_${version}_SHA256SUMS` and
`genlayer-node_${version}_SHA256SUMS.sigstore.json` into a staging directory.
Verify before extraction:

```sh
cosign verify-blob \
  --bundle "genlayer-node_${version}_SHA256SUMS.sigstore.json" \
  --certificate-identity-regexp '^https://github\.com/genlayerlabs/genlayer-node/\.github/workflows/release-package\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "genlayer-node_${version}_SHA256SUMS"
sha256sum -c "genlayer-node_${version}_SHA256SUMS" --ignore-missing
```

Require a matching checksum entry and successful verification for the actual
tarball. A missing file or failed signature stops installation. See
[common-procedures.md](common-procedures.md) for path conventions.

## 2. Install and initialize GenVM

```sh
mkdir -p "/opt/genlayer-node/${version}"
tar -xzf "genlayer-node-linux-amd64-${version}.tar.gz" \
  -C "/opt/genlayer-node/${version}" --strip-components=1
cd "/opt/genlayer-node/${version}"
python3 ./opt/genvm/current/bin/setup.py
```

Run setup in the final directory: it writes absolute paths into GenVM binaries.
Do not move the installation afterward without rerunning setup.

## 3. Network configuration and manifest

Start from the selected release's config and Compose files. Apply the settings in
[bradbury-phase-2.md](bradbury-phase-2.md), including `chainid`, `manifestpath`,
AddressManager and block 47930. Save the trusted Phase 2 manifest from the
approved release/network publication at `configs/node/protocol-manifest.json`.
Do not generate a trust manifest from the RPC you are trying to authenticate.
The manifest must describe chain 4221 and the Phase 2 AddressManager.

Set HTTP and WS endpoints and provision any key privately as
`GENLAYERNODE_ROLLUP_GENLAYERCHAINRPCKEY`; the node sends `X-AccessKey`.
Run the network preflight against the selected HTTP endpoint and verify WS
subscription/unsubscription with that same identity. Do not log the key.

## 4. Validator identity and secrets

Use [staking-wizard-procedure.md](staking-wizard-procedure.md) on the owner's
machine, or inspect an existing Phase 2 registration. Transfer only the operator
keystore to the server using the selected secure access method.
The owner wallet remains off the node.

Create a private mode-0600 environment file. The binary needs
`GENLAYERNODE_PASSWORD`; Compose uses `NODE_PASSWORD`. Provision at least one
LLM provider key actually enabled by the selected release's module configuration.
Source a trusted environment file with `set -a; source .env; set +a` for a manual
binary run, without displaying it.

For a binary installation, import the operator using the release's supported
interactive/password input options; check `account import --help` first:

```sh
./bin/genlayernode account import --path /secure/operator-keystore.json \
  -c "$(pwd)/configs/node/config.yaml" --setup
```

The export passphrase and node password are separate secrets. Have the operator
provide them through supported private input; never interpolate them in generated
chat commands. Verify that the resulting public address matches the registration.
Set `node.mode: validator` and the validator-wallet address explicitly.

## 5. WebDriver and doctor

```sh
docker compose up -d
./bin/genlayernode doctor
```

Doctor must run with the same config, manifest and exported secrets as the node.
Resolve failed chain, manifest, wallet, GenVM, provider or WebDriver checks before
starting. Do not bypass manifest verification.

## 6. Start using the chosen method

### Binary / systemd

Run from the version directory. For a service, use an operator-selected dedicated
user that owns the installation's writable data and does not have Docker-socket
access. Example (substitute the selected version/user/path):

```ini
[Unit]
Description=GenLayer Bradbury validator
After=network-online.target docker.service
Wants=network-online.target

[Service]
User=genlayer
WorkingDirectory=/opt/genlayer-node/<version>
EnvironmentFile=/opt/genlayer-node/<version>/.env
ExecStart=/opt/genlayer-node/<version>/bin/genlayernode run -c /opt/genlayer-node/<version>/configs/node/config.yaml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Install/enable/start only within the operator's authorization. For manual operation,
run `./bin/genlayernode run -c "$(pwd)/configs/node/config.yaml"` under a supervised
terminal or process manager with the same environment.

### Docker Compose

Use the release's Compose file from the version directory. Pin `NODE_VERSION`.
Set `NODE_CONFIG_PATH`, `NODE_MANIFEST_PATH` and `NODE_DATA_PATH` as needed.
The node runs as uid 10001: grant it ownership of the **new installation's** data
directory. Do not recursively change ownership of unrelated or shared paths.

The config is read-only in the container. Import the operator into the writable
data mount and edit public addresses in the host config; do not use `--setup`
inside the container. Keep `genvm-module-web-docker.yaml` next to Compose.

```sh
docker compose --profile node run --rm --entrypoint /app/bin/genlayernode genlayer-node doctor
docker compose --profile node up -d
```

## 7. Verify

Inspect `/health`, sync metrics, service status and sanitized logs. Confirm the
configured validator and operator match registration and that operator GEN is
sufficient for gas. A running process or HTTP 200 alone does not prove eligibility
or consensus participation. Report epoch-0 waiting status honestly.
For optional telemetry follow [monitoring-procedure.md](monitoring-procedure.md).
