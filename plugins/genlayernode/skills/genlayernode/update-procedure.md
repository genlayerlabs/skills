# Upgrade a Bradbury Phase 2 node

Read [network preflight](bradbury-phase-2.md) and the [pre-update checklist](pre-update-checklist.md).
An ordinary upgrade preserves state only when the existing node is already on the
same genesis and AddressManager. A move from Asimov or old Bradbury is a network
migration: preserve the old installation and create fresh chain state.

1. Identify the host, running service/container, exact version, public validator
   and operator addresses, and the config/data/manifest paths. Never print secrets.
2. Verify the target release is published and approved for Phase 2. Download and
   verify its signed checksums as in [installation](install-procedure.md).
3. Extract into a new version directory and run
   `python3 ./opt/genvm/current/bin/setup.py` there. Stage the release's current
   config, Compose, WebDriver module and monitoring assets; do not overwrite them
   with old release templates. Carry forward only compatible operator settings.
4. Preserve the trusted Phase 2 manifest and check `consensus.manifestpath`.
   Verify HTTP genesis/contracts and authenticated WS access.
5. Back up keystores, private environment files, manifest, config and the database
   using a consistent snapshot supported by the release. Do not copy a live
   database and call it a recoverable backup.
6. With authorization, stop the old service before giving the new process access
   to its keystore or writable state. Never run two validators with the same key.
7. Run doctor with the new binary, config and environment. If it fails, stop and
   diagnose. Start the new service only after required checks pass.
8. Verify health, synchronization, operator balance and logs. Observe the node
   long enough to distinguish initialization/precompilation from a restart loop.
   Record the versions and checks performed.

Rollback uses the preserved installation and a compatible backup. Never assume
an older binary can read a database migrated by a newer binary. Keep the old node
stopped until its rollback state is known to be compatible.

A restart entails interruption; this procedure does not promise zero downtime.
No consensus deployment or epoch changes are part of an upgrade.

## State handover and rollback details

Before the maintenance window, record the resolved data/keystore paths (including
symlink targets), service user, active release and backup location. For the same
network, preserve the existing database through an explicitly configured data
path only when the release supports that migration. Never point a Phase 2 node at
old Bradbury or Asimov state. A database symlink used by a host binary can escape a
Docker bind mount; container migrations must mount the real directory.

Prepare the new release, dependencies, GenVM setup and public config while the old
node still runs. Preserve the LLM strategy using the new release's template as
explained in common procedures. Do not start the new validator until the old one
has stopped. Take a consistent database backup during the stop window if the
release provides no online snapshot mechanism. Keep the private backup readable
only by the selected administrator/service identity.

For systemd, update `WorkingDirectory`, `ExecStart` and `EnvironmentFile` together,
then `systemctl daemon-reload`. For Compose, use the new version directory and its
actual config/data/LLM mounts. If compatibility symlinks already exist, switch
all relevant release assets, including `opt`, configs, module files, Compose and
Alloy configuration; do not carry over a legacy `third_party` path.

After startup, verify sync, LLM/web probes and operator identity. If monitoring is
enabled, recreate Alloy with the new paths as described in monitoring-procedure.md.
Rollback means stopping the new process first, restoring a compatible database
backup when needed, restoring the old service paths/config and starting exactly
one old process. Recheck health and telemetry; merely switching a binary symlink
does not undo a database migration.
