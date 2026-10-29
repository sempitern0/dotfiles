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

## Desktop and operational review · 2026-10-29

[Deployment / Despliegue](DESKTOP.md)

- Added a dedicated desktop profile, read-only plan and user-only deployment.
- Blocked package providers on immutable/transactional hosts and checked actual
  package-manager availability. Installed groups skip refresh; refresh failures stop.
- Made failed tasks visible as FAIL and reflected them in both assistants' exit status.
- Preserved personal SSH precedence with an idempotent managed block at the end.
- Prevented directory destinations from accepting configuration files accidentally.
- Fixed hardening snapshot retry: partial copies never count as complete backups.
- Made Vim package installation explicit in the full profile, outside core packages.
- Fixed HTTP false success on connection errors and stale redirect-header attribution.
- Repaired existing HTML filter regressions exposed by running the dormant tests:
  granular JSON/text selection and audio/subtitle output now match the advertised flags.
- Existing extractor smoke tests now invoke Bash, matching tracked non-executable files.
- Added an offline verifier and CI with ShellCheck at error severity; warnings/style
  debt are not a zero-warning certification.

Run `python3 tools/verify.py --require-shellcheck`. Tests exercise temporary user
files, failed backup/refresh operations, desktop gates, SSH precedence and idempotency,
profile exit status, HTML filters and loopback-only HTTP redirects/errors. No package
transaction or hardening policy is executed. Graphical desktop, package-manager,
Windows, domain and full host recovery acceptance were not performed here.

Resumen: nuevos perfiles desktop/user-only/plan; errores propagados, prioridades SSH
conservadas, copias de hardening recuperables tras fallos y diagnósticos HTTP/HTML
corregidos. Las pruebas son aisladas; sigue pendiente la aceptación nativa de cada
distribución y sus políticas de recuperación.
