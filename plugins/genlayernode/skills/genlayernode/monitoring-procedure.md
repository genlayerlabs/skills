# Bradbury monitoring

Use the selected release's Compose and `alloy-config.river` files. Obtain the
monitoring tenant endpoints and credentials from the Foundation's appointed
monitoring operator. Do not reuse credentials or destinations from an old example.

Provision these six values privately in the host's mode-0600 `.env`:

- `CENTRAL_MONITORING_URL`, `CENTRAL_MONITORING_USERNAME`, `CENTRAL_MONITORING_PASSWORD`
- `CENTRAL_LOKI_URL`, `CENTRAL_LOKI_USERNAME`, `CENTRAL_LOKI_PASSWORD`

Also configure `NODE_ID`, `VALIDATOR_NAME`, `NETWORK_NAME=bradbury-phase2`,
`NODE_METRICS_ENDPOINT` and `NODE_LOGS_PATH` for the actual installation. The
release's Compose monitoring profile requires all six destination/auth values.
A receiver without authentication still needs the release's documented placeholder
values; do not invent a working credential for a protected receiver.

```sh
docker compose --profile monitoring up -d
docker compose ps
```

Verify delivery in the intended dashboard and log stream, checking fresh sample
timestamps, validator labels and the correct network. A running Alloy container
is insufficient. Inspect sanitized logs if delivery fails; never print `.env` or
headers. For multiple nodes, use the release's `SCRAPE_TARGETS_JSON` format with
explicit addresses and labels rather than guessing instance endpoints.

For WebDriver resource metrics on a binary/systemd node, run the release's
read-only `docker-socket-proxy` and set `DOCKER_HOST=tcp://127.0.0.1:2375` only for
the node process. Do not export that variable into shells used for Docker
administration, give the node Docker-group membership, or mount the host socket.

Reference: [monitoring guide](https://docs.genlayer.com/validators/monitoring).

## Enable and diagnose delivery

Before starting Alloy, confirm `/metrics` returns Prometheus text and that the
configured log file exists and grows. Use the validator-wallet address for
`NODE_ID`; use a stable, distinct `VALIDATOR_NAME` per node. Prometheus and Loki
usernames may differ. Get both destination/auth pairs from the monitoring operator.

Start only the intended monitoring service and its dependencies:

```bash
docker compose --profile monitoring up -d alloy
docker compose ps alloy
```

For binary nodes, verify the endpoint as reached from the container; host loopback
inside Alloy is not the host's loopback. Use the release's host gateway mapping
and `NODE_METRICS_ENDPOINT`. Check the actual log directory bind mount against the
node's log configuration. Inspect logs locally for auth failures (401/403), wrong
receiver paths (404), throttling (429), connection failures and unreadable log
files. Redact secrets and authenticated URLs before sharing any output. Do not
validate receiver credentials by printing them or placing them in process arguments.

After a release-directory/symlink switch, recreate Alloy so its bind mounts follow
the new paths; restarting an old container can retain obsolete mounts:

```bash
docker compose --profile monitoring up -d --no-deps --force-recreate alloy
```

Verify new sample/log timestamps in the receiver. If they do not advance, inspect
mount sources, permissions, labels and receiver errors. Do not erase Alloy's WAL
or positions as a first response. Preserve its data across ordinary restarts.
For multiple nodes, configure distinct targets/labels and verify each one, rather
than accepting one successful sample as proof that every node is monitored.
