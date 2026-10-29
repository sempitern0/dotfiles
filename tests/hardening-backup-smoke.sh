#!/usr/bin/env bash
# Sources definitions only and redirects all snapshot writes to a temporary tree.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$ROOT/hardening_setup.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
HARDENING_ROOT="$tmp/snapshots"
DOTFILES_RUN_ID=test
TARGET_USER="$(id -un)"
original="$tmp/config"
printf original >"$original"
# Simulate a failed partial copy without terminating the shell.
cp() { touch "${@: -1}"; return 1; }
if hardening_backup_path "$original"; then exit 1; fi
[[ -z "${HARDENING_BACKED[$original]:-}" ]]
[[ ! -e "$HARDENING_SNAPSHOT/rootfs/${original#/}" ]]
[[ ! -s "$HARDENING_MANIFEST" ]]
unset -f cp
hardening_backup_path "$original"
[[ "${HARDENING_BACKED[$original]}" == 1 ]]
printf changed >"$original"
hardening_backup_path "$original"
[[ "$(cat "$HARDENING_SNAPSHOT/rootfs/${original#/}")" == original ]]
[[ "$(wc -l <"$HARDENING_MANIFEST")" == 1 ]]
ln -s missing "$tmp/link"
hardening_backup_path "$tmp/link"
[[ "$(readlink "$HARDENING_SNAPSHOT/rootfs/${tmp#/}/link")" == missing ]]
hardening_backup_path "$tmp/absent"
grep -Fq $'ABSENT\t'"$tmp/absent" "$HARDENING_MANIFEST"
printf 'PASS: hardening snapshot partial-copy retry, originals, symlinks and absent paths\n'
