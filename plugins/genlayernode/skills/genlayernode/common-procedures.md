# Shared Bradbury procedures

Use [network preflight](bradbury-phase-2.md) for network identity and the
[installation procedure](install-procedure.md) for exact release verification.

## Locations

Use `/opt/genlayer-node/<version>` for a versioned installation. Run commands from
that directory. Required paths include `bin/genlayernode`, `opt/genvm/current`,
`configs/node/config.yaml`, `configs/node/protocol-manifest.json`, the release's
Compose/module files, and the configured data directory. Do not create a
`third_party/genvm` compatibility path for a current release.

For SSH/GCP/AWS, perform file transfer through the operator's existing access
method. Keep private keys and environment files mode 0600 and never print them.
Use a dedicated operator account; the owner key stays off the server.

## Health

```sh
curl -fsS http://localhost:9153/health
curl -fsS http://localhost:9153/metrics
systemctl is-active genlayer-node
```

Inspect relevant health/sync fields and recent sanitized logs. Do not equate
process liveness with chain synchronization or active-set membership. At epoch 0,
a registered, synchronized validator can correctly be awaiting activation.

## Secrets

For binary startup use `GENLAYERNODE_PASSWORD`. For Compose set `NODE_PASSWORD`;
the shipped Compose file maps it to the binary variable. The RPC provider key is
`GENLAYERNODE_ROLLUP_GENLAYERCHAINRPCKEY`; endpoints themselves contain no key.
Never display `.env`, request headers, keystore contents or partial key values.
Check only presence. Source only a trusted file, exporting its variables before
manual `doctor` or `run`; systemd loads it through `EnvironmentFile`.

## GenVM and doctor

```sh
python3 ./opt/genvm/current/bin/setup.py
./bin/genlayernode doctor
```

Run setup after installation at its final path. Doctor checks the configured
protocol manifest; do not replace that verification with an address-only flag.
Use the release's WebDriver config and provider definitions. An API key alone
does not enable a provider that is disabled in the module configuration.

## Configure the LLM module and strategy

Preserve the operator's chosen strategy during a same-network upgrade. Work on
the **new release's** files rather than copying an old module wholesale. From the
final release directory:

```bash
cp opt/genvm/current/config/genvm-modules-llm-release.yaml \
  opt/genvm/current/config/genvm-module-llm.yaml
```

The release template defines backend names and environment variables. Current
mappings include:

| Backend | Private environment variable |
| --- | --- |
| openrouter | OPENROUTERKEY |
| heurist | HEURISTKEY |
| comput3 | COMPUT3KEY |
| ionet | IOINTELLIGENCEKEY |
| libertai | LIBERTAI_API_KEY |
| morpheus | MORPHEUS_API_KEY |
| openai | OPENAIKEY |
| anthropic | ANTHROPICKEY |
| google | GEMINIKEY |
| xai | XAIKEY |
| atoma | ATOMAKEY |

Check the selected release's template for changes. For a single OpenRouter
provider with the default strategy, this edits only public configuration (Ubuntu's
`python3-yaml` package is installed by the host prerequisites):

```bash
python3 - <<'PY'
from pathlib import Path
import yaml
p = Path('opt/genvm/current/config/genvm-module-llm.yaml')
cfg = yaml.safe_load(p.read_text())
assert 'openrouter' in cfg['backends']
for name, backend in cfg['backends'].items():
    backend['enabled'] = name == 'openrouter'
p.write_text(yaml.safe_dump(cfg, sort_keys=False))
PY
```

Adapt the selected backend to the operator's choice; do not write actual keys in
YAML. Provision the matching environment variable privately. For the **greybox**
strategy, read the packaged `greybox-setup-guide.md`, set `lua_script_path` to the
packaged `genvm-llm-greybox.lua`, and retain the per-model `meta.greybox` text/image
chain definitions for the selected providers. A model without a chain entry is
not a fallback. Do not replace these definitions with arbitrary priority numbers.

For Docker, editing the host GenVM tree alone does not change the image. Add an
override file next to Compose:

```yaml
services:
  genlayer-node:
    volumes:
      - ./opt/genvm/current/config/genvm-module-llm.yaml:/app/opt/genvm/current/config/genvm-module-llm.yaml:ro
```

Name it `compose.llm.yaml` and consistently use
`docker compose -f docker-compose.yaml -f compose.llm.yaml ...` for doctor and
startup. Keep the image's GenVM precompilation entrypoint for normal startup.
Run doctor after enabling the provider; check actual LLM and web probes, not just
presence of environment variables.

## WebDriver, ports and permissions

```bash
docker compose up -d webdriver-container
docker compose ps webdriver-container
curl -fsS 'http://127.0.0.1:4444/healthcheck?mode=text&url=https%3A%2F%2Ftest-server.genlayer.com%2Fstatic%2Fgenvm%2Fhello.html'
ss -ltn
```

Wait for WebDriver's health check to pass. If a container name or port conflicts,
identify its owner before changing anything; do not remove an unrelated validator's
container. For multiple nodes, assign distinct container names, ports and data
paths. Keep `genvm-module-web-docker.yaml` mounted for container networking and
check the release's SSRF allowlist when `ADDRESS_FORBIDDEN` appears.

Create the dedicated service account if missing, and make only this new release's
writable paths owned by it. For systemd the service user must be able to write
node data and GenVM data/cache paths. Keep environment and keystore files private.
For Docker the equivalent UID is 10001. Never recursively chown a shared database
or another installation to make a failing startup disappear.

## Service operation and manual supervision

After installing the unit from the installation procedure:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now genlayer-node
systemctl is-active genlayer-node
systemctl is-enabled genlayer-node
```

Inspect recent logs locally, redacting authenticated URLs and secrets before
sharing. For manual operation, use an existing process supervisor or install
`tmux` and start an attached session (`tmux new -s genlayer`). Source the trusted
private environment there and run the binary; detach with Ctrl-B, D. A terminal
closed without supervision can stop the validator. Do not run manual and systemd
instances using the same operator simultaneously.

## Diagnose failures before restarting

- **GenVM setup/import failure:** check Python version, pip/venv, `libstdc++6`,
  disk space and network downloads. Rerun setup in the final directory. For an
  incompatible ELF/interpreter, verify architecture and the release package; do
  not substitute a different network's binary.
- **Operator has no funds:** query its GEN balance on the verified Phase 2 chain.
  Owner stake does not fund the operator. Request the required authorized gas
  transfer, wait for its receipt, and rerun doctor.
- **RPC outage:** compare a read-only check through a second verified endpoint.
  If several nodes lose the same provider together, investigate the provider
  before restarting healthy processes or editing staking state.
- **Temporary ban or delayed eligibility:** inspect CLI validator-info and epoch
  state, then diagnose the underlying RPC/LLM/web fault. Registration, priming,
  sufficient self-stake and activation are distinct checks. Do not unban or rotate
  an operator as an automatic repair.
- **LLM errors:** distinguish missing key, disabled backend, provider quota/auth
  failure and unsupported models. Keep provider response content and keys private;
  fix the selected module/configuration and rerun the probe.
- **No sync progress:** compare latest RPC block with `gen_syncing` and read the
  individual `/health` checks. Check WS authentication and manifest identity first.
  Do not delete the database as a generic recovery step.
- **Permission failure:** inspect ownership of the exact failing path and service
  UID. Check whether the data path is a symlink outside the container mount; mount
  the actual data directory instead of creating an escaping symlink.

## Apply an approved greybox/module update without replacing the node

The Lua script is loaded at LLM module startup. Editing it on disk does not reload
an already running module. Identify each node's configured GenVM manager address
(do not confuse it with the LLM bind port), stage the compatible Lua/YAML files in
that instance's `opt/genvm/current/config`, and preserve its provider settings.
For an authorized module restart, the current release supports:

```bash
GENVM_MANAGER_PORT=3999  # Replace with this instance's configured manager port.
curl -fsS -X POST "http://127.0.0.1:${GENVM_MANAGER_PORT}/module/stop" \
  -H 'Content-Type: application/json' -d '{"module_type":"Llm"}'
curl -fsS -X POST "http://127.0.0.1:${GENVM_MANAGER_PORT}/module/start" \
  -H 'Content-Type: application/json' -d '{"module_type":"Llm","config":null}'
```

Follow the selected release's manager authentication requirements. Apply per
instance; this is not an atomic fleet operation. For a read-only Docker mount,
ensure the updated file is the mounted file; recreate the affected container if
an atomic host-file replacement leaves it attached to an old inode. Verify the
LLM health probe and expected provider/model in sanitized logs. Do not send an
unsolicited on-chain test transaction merely to check a configuration update.
