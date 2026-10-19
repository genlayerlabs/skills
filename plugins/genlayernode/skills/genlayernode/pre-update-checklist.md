# Pre-update checklist

- Host, authorization, existing service and intended release identified.
- [Phase 2 preflight](bradbury-phase-2.md) passed: genesis, AddressManager and staking code.
- Current and target network identities match; otherwise use fresh chain state.
- Release tarball and signed checksums exist and verify; no guessed `latest`.
- Python 3.10+, pip/venv, capacity and Docker Compose verified.
- GenVM setup run in the target release's final location (`opt/genvm/current`).
- Trusted protocol manifest provisioned and referenced in config.
- HTTP/WS access and any RPC key available; anonymous HTTP is not a WS test.
- LLM keys available privately and providers enabled in the actual module config.
- Operator GEN balance and registered wallet/key correspondence checked.
- Consistent data backup plus keystore/config/manifest backup retained securely.
- Old and new processes will never share a writable database or run the same operator concurrently.
- Doctor passes before startup; rollback compatibility and monitoring checks planned.
