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
