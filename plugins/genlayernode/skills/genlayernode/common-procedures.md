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
