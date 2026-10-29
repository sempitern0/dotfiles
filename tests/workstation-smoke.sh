#!/usr/bin/env bash
# Only temp files and mocked package/desktop operations; no host writes.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$ROOT/bash_setup.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
TARGET_USER="$(id -un)" TARGET_GROUP="$(id -gn)" TARGET_HOME="$tmp/user"
TARGET_SHELL=/bin/bash
DOTFILES_BACKUP_HOME="$tmp/backups" DOTFILES_RUN_ID=test
mkdir -p "$TARGET_HOME/.ssh"
printf 'Host example.test\n    ServerAliveInterval 9\n    User personal\n' >"$TARGET_HOME/.ssh/config"
configure_ssh_client
cp "$TARGET_HOME/.ssh/config" "$tmp/first"
configure_ssh_client
cmp "$TARGET_HOME/.ssh/config" "$tmp/first"
if command -v ssh >/dev/null; then
    # Resolve the temporary home explicitly: ssh expands ~ via passwd, not $HOME.
    sed "s|~/.ssh/conf.d/|$TARGET_HOME/.ssh/conf.d/|" "$TARGET_HOME/.ssh/config" >"$tmp/ssh-config"
    config="$(ssh -G -F "$tmp/ssh-config" example.test 2>/dev/null)"
    [[ "$config" == *'serveraliveinterval 9'* && "$config" == *'user personal'* ]]
    config="$(ssh -G -F "$tmp/ssh-config" other.test 2>/dev/null)"
    [[ "$config" == *'serveraliveinterval 60'* && "$config" != *'user personal'* ]]
fi
# A directory destination must not silently receive the temporary source file.
printf source >"$tmp/source"
mkdir "$tmp/directory"
if copy_with_backup "$tmp/source" "$tmp/directory"; then exit 1; fi
# Failed tasks keep the menu running but make the aggregate result fail.
run_task "expected failure" false
[[ "$TASK_FAIL" == 1 && "$TASK_PASS" == 0 ]]
# Idempotent packages must not even refresh metadata; offline hosts can reapply.
pkg_installed() { return 0; }
pkg_refresh() { printf 'unexpected refresh' >&2; exit 99; }
install_packages existing
# A refresh failure must prevent installation; no lock deletion/retry loop.
pkg_installed() { return 1; }
pkg_refresh() { return 1; }
pkg_install() { printf 'unexpected install' >&2; exit 98; }
if install_packages missing; then exit 1; fi
# Empty availability must be a failure instead of claiming packages were installed.
pkg_refresh() { return 0; }
pkg_available() { return 1; }
if install_packages missing; then exit 1; fi
# A non-desktop target fails before running the recommended profile.
is_desktop_environment() { return 1; }
profile_recommended() { exit 97; }
if profile_desktop; then exit 1; fi
# End-to-end status propagation through main with no real setup operations.
prepare_context() { return 0; }
start_workstation_evidence() { return 0; }
profile_minimal() { run_task failure false; }
if main --minimal; then exit 1; fi
# A failed evidence directory prevents all profile tasks.
start_workstation_evidence() { return 1; }
profile_minimal() { exit 96; }
if main --minimal; then exit 1; fi
printf 'PASS: workstation failure propagation, packages, desktop gates, SSH precedence\n'
