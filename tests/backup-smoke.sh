#!/usr/bin/env bash
# Exercises only temporary files; never installs packages or changes host policy.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$ROOT/lib/common.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
TARGET_USER="$(id -un)"
TARGET_GROUP="$(id -gn)"
DOTFILES_BACKUP_HOME="$tmp/backups"
DOTFILES_RUN_ID=test
mkdir -p "$tmp/work space"
dest="$tmp/work space/config"
src="$tmp/source"
printf original > "$dest"
printf first > "$src"
copy_with_backup "$src" "$dest" "$TARGET_USER" 0600
[[ "$(cat "$dest")" == first ]]
printf second > "$src"
copy_with_backup "$src" "$dest" "$TARGET_USER" 0600
[[ "$(cat "$DOTFILES_BACKUP_HOME/test/${dest#/}")" == original ]]
[[ "$(stat -c %a "$dest")" == 600 ]]
# Broken symlinks are valid originals and must remain symlinks in the backup.
ln -s missing "$tmp/link"
copy_with_backup "$src" "$tmp/link" "$TARGET_USER" 0644
[[ "$(readlink "$DOTFILES_BACKUP_HOME/test/${tmp#/}/link")" == missing ]]
[[ ! -L "$tmp/link" ]]
# A failed backup must prevent replacement, even without global errexit.
(
    backup_path() { return 1; }
    if copy_with_backup "$src" "$dest" "$TARGET_USER" 0600; then exit 1; fi
    [[ "$(cat "$dest")" == second ]]
)
# Partial backup copies must not masquerade as a completed snapshot on retry.
(
    cp() { touch "${@: -1}"; return 1; }
    if backup_path "$src"; then exit 1; fi
    [[ ! -e "$DOTFILES_BACKUP_HOME/test/${src#/}" ]]
)
backup_path "$src"
[[ "$(cat "$DOTFILES_BACKUP_HOME/test/${src#/}")" == second ]]
# Copy failure leaves the deployed file intact and removes temporary siblings.
(
    cp() { return 1; }
    if copy_with_backup "$src" "$dest" "$TARGET_USER" 0600; then exit 1; fi
    [[ "$(cat "$dest")" == second ]]
)
! compgen -G "${dest}.dotfiles.*" >/dev/null
printf 'PASS: original backups, symlinks, permissions and failed writes\n'
