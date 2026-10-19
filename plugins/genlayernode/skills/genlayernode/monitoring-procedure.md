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
