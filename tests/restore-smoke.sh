#!/usr/bin/env bash
# Temporary payloads only; actual host policy/service operations are stubbed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$ROOT/hardening_setup.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
printf previous >"$tmp/target"
printf original >"$tmp/source"
cp() { return 1; }
if restore_snapshot_payload "$tmp/source" "$tmp/target"; then exit 1; fi
[[ "$(cat "$tmp/target")" == previous ]]
unset -f cp
# Failed final rename must put the previous file back.
mv() { [[ "$3" != */original ]] || return 1; command mv "$@"; }
if restore_snapshot_payload "$tmp/source" "$tmp/target"; then exit 1; fi
[[ "$(cat "$tmp/target")" == previous ]]
unset -f mv
restore_snapshot_payload "$tmp/source" "$tmp/target"
[[ "$(cat "$tmp/target")" == original ]]
mkdir "$tmp/source-dir" "$tmp/target-dir"
printf nested >"$tmp/source-dir/config"
printf old >"$tmp/target-dir/old"
restore_snapshot_payload "$tmp/source-dir" "$tmp/target-dir"
[[ -f "$tmp/target-dir/config" && ! -e "$tmp/target-dir/old" ]]
ln -s missing "$tmp/link"
restore_snapshot_payload "$tmp/link" "$tmp/target"
[[ -L "$tmp/target" && "$(readlink "$tmp/target")" == missing ]]
# Missing payloads and malformed paths fail before confirmation or any writes.
snap="$tmp/snapshot"
mkdir -p "$snap/rootfs"
confirm_literal() { exit 99; }
printf 'PRESENT\t%s\n' "$tmp/absent" >"$snap/paths.tsv"
if restore_snapshot_dir "$snap"; then exit 1; fi
for entry in $'ABSENT\t/' $'ABSENT\t/etc/../etc/config' $'WRONG\t/etc/config'; do
    printf '%s\n' "$entry" >"$snap/paths.tsv"
    if restore_snapshot_dir "$snap"; then exit 1; fi
done
# Files in a checksummed snapshot are verified before restoration.
printf data >"$snap/rootfs/payload"
(cd "$snap" && sha256sum rootfs/payload >SHA256SUMS)
: >"$snap/paths.tsv"
printf corrupt >"$snap/rootfs/payload"
if restore_snapshot_dir "$snap"; then exit 1; fi
# Service-only/symlink-only snapshots can legitimately have no regular-file hashes.
rm "$snap/rootfs/payload"
: >"$snap/SHA256SUMS"
validate_restore_snapshot "$snap"
printf unrecorded >"$snap/rootfs/payload"
if validate_restore_snapshot "$snap"; then exit 1; fi
rm "$snap/rootfs/payload"
# Interrupted snapshots without hashes still allow explicitly confirmed recovery.
rm "$snap/SHA256SUMS"
printf 'PRESENT\t%s\n' "$tmp/recovered" >"$snap/paths.tsv"
mkdir -p "$snap/rootfs/${tmp#/}"
printf recovered >"$snap/rootfs/${tmp#/}/recovered"
confirm_literal() { return 0; }
command_exists() { return 1; }
service_exists() { return 1; }
systemctl() { return 0; }
sysctl() { return 0; }
restore_snapshot_dir "$snap"
[[ "$(cat "$tmp/recovered")" == recovered ]]
# Failed apply commands produce nonzero status after the files were restored.
systemctl() { return 1; }
if restore_snapshot_dir "$snap"; then exit 1; fi
printf 'PASS: staged file/directory/symlink restore, rename rollback, validation and partial failure status\n'
