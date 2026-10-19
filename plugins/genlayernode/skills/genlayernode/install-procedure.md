# Install a Bradbury Phase 2 validator

Read [network preflight](bradbury-phase-2.md) and [SKILL.md](SKILL.md) first.

## 1. Host and release

Identify the target host and access method; execute all host operations there.
Complete [host prerequisites](host-prerequisites.md), including installation of
missing dependencies and Docker daemon access. Use the operator-approved release
version, not `latest`.
Check its publication before modifying the host:

```sh
version=<approved-published-version>
base=https://storage.googleapis.com/gh-af/genlayer-node/bin/amd64/${version}
curl -fI "${base}/genlayer-node-linux-amd64-${version}.tar.gz"
```

Download all three artifacts into a new staging directory:

```bash
staging=$(mktemp -d)
cd "$staging"
for artifact in "genlayer-node-linux-amd64-${version}.tar.gz" \
  "genlayer-node_${version}_SHA256SUMS" \
  "genlayer-node_${version}_SHA256SUMS.sigstore.json"; do
  curl -fSL "${base}/${artifact}" -o "$artifact" || exit 1
done
```

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
sudo install -d -o "$(id -un)" -g "$(id -gn)" "/opt/genlayer-node/${version}"
tar -xzf "genlayer-node-linux-amd64-${version}.tar.gz" \
  -C "/opt/genlayer-node/${version}" --strip-components=1
cd "/opt/genlayer-node/${version}"
python3 ./opt/genvm/current/bin/setup.py
```

Run setup in the final directory: it writes absolute paths into GenVM binaries.
Do not move the installation afterward without rerunning setup. For Docker-only
operation, the image initializes GenVM itself; host Python setup is only needed
when executing the host binary. Extract the release configuration assets for both
modes. Follow [LLM configuration](common-procedures.md#configure-the-llm-module-and-strategy)
to select and enable the provider and, for Docker, mount the configured module.

## 3. Network configuration and manifest

Start from the selected release's config and Compose files. Apply the settings in
[bradbury-phase-2.md](bradbury-phase-2.md), including `chainid`, `manifestpath`,
AddressManager and block 47930. Save the trusted Phase 2 manifest from the
approved release/network publication at `configs/node/protocol-manifest.json`.
Do not generate a trust manifest from the RPC you are trying to authenticate.
The manifest must describe chain 4221 and the Phase 2 AddressManager.

Create a Conduit key at [app.conduit.xyz/rpc-keys](https://app.conduit.xyz/rpc-keys).
Set HTTP and WS endpoints and provision the key privately as
`GENLAYERNODE_ROLLUP_GENLAYERCHAINRPCKEY`; the node sends `X-AccessKey`.
Run the network preflight against the selected HTTP endpoint and verify WS
subscription/unsubscription with that same identity. Do not log the key.

## 4. Validator identity and secrets

Use [staking-wizard-procedure.md](staking-wizard-procedure.md) on the owner's
machine, or inspect an existing Phase 2 registration. Transfer only the operator
keystore to the server using the selected secure access method.
The owner wallet remains off the node.

Initialize a private environment file without overwriting an existing one:

```bash
umask 077
if [ ! -e .env ]; then cp .env.example .env; fi
chmod 600 .env
```

Edit values privately. The binary needs
`GENLAYERNODE_PASSWORD`; Compose uses `NODE_PASSWORD`. Provision at least one
LLM provider key actually enabled by the selected release's module configuration.
Source a trusted environment file with `set -a; source .env; set +a` for a manual
binary run, without displaying it.

For the CLI's encrypted Web3/geth-compatible operator export, install the encrypted
file directly into the configured keystore directory. With the release default
`datadir: ./data/node` and `node.keystoredir: keystore`:

```bash
install -d -m 700 ./data/node/keystore
test ! -e ./data/node/keystore/operator.json || exit 1
install -m 600 /secure/operator-keystore.json ./data/node/keystore/operator.json
```

Run as the selected service user, or set the destination ownership to that user.
Set `GENLAYERNODE_PASSWORD` privately to this file's **export passphrase**; this
method preserves the encryption and does not change its password. Adapt the
path when the configured data/keystore directories differ. Verify the export's
public address matches the registered operator, and set `node.mode: validator`,
`node.operatorAddress` and `node.validatorWalletAddress` explicitly in config.
Doctor must successfully unlock the keystore before startup.

The current binary's `account import --passphrase` does not prompt interactively
for the export password. Do not claim it does, put the password in argv, or use
`--setup` against Docker's read-only config. If re-encryption is required, use an
approved tool with private password input before transferring the encrypted file.

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
access. On a fresh installation, after configuring and initializing this version:

```bash
id genlayer >/dev/null 2>&1 || sudo useradd --system --home-dir /opt/genlayer-node \
  --shell /usr/sbin/nologin genlayer
# Only the newly created version directory; never a shared data parent.
sudo chown -R genlayer:genlayer "/opt/genlayer-node/${version}"
```

Keep the private environment and keystore files mode 0600. Example unit
(substitute the selected version/user/path):

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

The config is read-only in the container. Install the encrypted operator export
on the host into the actual data mount. With the default `./data:/app/data` mount
and `datadir: ./data/node`:

```bash
sudo install -d -m 700 -o 10001 -g 10001 ./data/node/keystore
test ! -e ./data/node/keystore/operator.json || exit 1
sudo install -m 600 -o 10001 -g 10001 /secure/operator-keystore.json \
  ./data/node/keystore/operator.json
```

Set `NODE_PASSWORD` privately to the encrypted export's passphrase. Set the public
operator/validator addresses on the host config and verify them with doctor.
Adapt both paths to `NODE_DATA_PATH` and the selected node data configuration.
Keep `genvm-module-web-docker.yaml` next to Compose. Use the LLM override described
in common procedures in every Compose invocation when selecting a custom provider.
The example below assumes the shipped image module is appropriate.

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
