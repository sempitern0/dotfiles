# Maintenance review · 2026-10-14

[Quick start](../README.md) · [Inicio rápido](../README_ES.md)

## Changes

- Short English/Spanish entry points with task selection, customization paths and recovery.
- Detailed existing policies and Vim mappings remain in [the reference](REFERENCE.md).
- Configuration replacement now stops on backup failure and uses unique temporary
  sibling files for atomic replacement. Copy, permission and ownership errors propagate.
- The first original backup in a run is retained when a module is repeated.
  Failed partial backups are removed so retrying cannot accept an incomplete snapshot.
- Portable command deployment reuses the same backup/copy function rather than a
  second installation sequence. Symlink and SSH configuration changes also check backups.

## Validation

```bash
bash tests/backup-smoke.sh
```

Passed temporary-file regressions for original-backup retention, broken symlinks,
permissions, failed backups, partial-copy retry and failed deployment. All 26 shell
scripts/configuration files passed Bash syntax checks in the review environment.
Tests do not install packages or alter system policy.

Distribution-specific package installation, Zsh sessions, firewall/SSH changes and
system recovery still require disposable target hosts. The changes here concern
user-file deployment, not a redesign of the separate hardening snapshot engine.
