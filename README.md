# dotfiles · Linux Workstation Control Plane

A portable, opinionated Linux workstation configuration for developers, system administrators and security-minded power users.

The repository is designed around a simple idea: a new desktop should become useful quickly **without turning the bootstrap script into a second package ecosystem**. Distribution repositories remain the source of software updates, personal configuration is preserved where practical, high-impact security changes are explicit, and every interactive workspace is usable without `fzf`, dialog, Python or a graphical session.

## What this repository configures

The project has two entry points:

| Assistant | Scope | Privileges |
| --- | --- | --- |
| `bash_setup.sh` | Developer/sysadmin packages, Bash, Git, SSH client, optional Vim and command-line utilities | Runs as the user; asks for `sudo` only for package operations |
| `hardening_setup.sh` | Host firewall, kernel/sysctl baseline, SSH server policy, security updates, Fail2Ban, optional DNS/USB/threat tooling and rollback | Root / `sudo` |

Both assistants are interactive but also expose direct modes for repeatable provisioning.

## Supported Linux families

The common control plane targets the major package-management families rather than individual distributions:

| Family | Examples | Package source policy |
| --- | --- | --- |
| Debian | Debian, Ubuntu and close derivatives | Configured APT repositories |
| Arch | Arch and close derivatives | Official pacman repositories only |
| Fedora / RHEL-like | Fedora and compatible RPM systems | Configured DNF repositories |
| openSUSE / SUSE-like | openSUSE Leap/Tumbleweed and compatible systems | Configured Zypper repositories |

Package availability is checked at runtime. A missing optional package is skipped instead of aborting the entire setup.

The assistants do **not** automatically add PPAs, COPRs, AUR helpers, third-party repositories, language-specific installers or GitHub release binaries. This keeps updates inside the operating system's normal security lifecycle.

## Quick start

Clone the repository and run the workstation assistant as your normal user:

```bash
git clone https://github.com/sempitern0/dotfiles.git
cd dotfiles
./bash_setup.sh
```

The recommended non-interactive-equivalent profile is:

```bash
./bash_setup.sh --recommended
```

It installs the portable core/developer/sysadmin package groups, desktop integration packages when a graphical session is detected, and then deploys Bash, Git/SSH client defaults and the repository utilities.

**It deliberately does not replace your Vim configuration and does not apply system hardening.**

Other useful entry points:

```bash
./bash_setup.sh --minimal
./bash_setup.sh --full
./bash_setup.sh --status
sudo ./hardening_setup.sh --audit
sudo ./hardening_setup.sh --recommended
```

`--full` means the complete *dotfiles* profile, including Vim. It does not silently opt the machine into strict hardening controls.

## Workstation profiles

### Minimal

Useful when opening a fresh VM, lab machine or temporary administration workstation:

```text
Core distribution packages
Bash configuration
Git + SSH client defaults
Portable repository utilities
```

### Recommended

The normal developer/sysadmin workstation profile:

```text
Minimal
+ compiler / build toolchain
+ Python development baseline
+ Git LFS / ShellCheck where available
+ network, process and storage diagnostics
+ terminal productivity tools
+ desktop clipboard/notification integration when relevant
```

### Full dotfiles

Adds the repository's pluginless Vim profile to Recommended.

The interactive menu can also execute any module independently, or multiple modules in one pass such as:

```text
5,6,8,9,11
```

Failures in one selected module are reported in the run summary and do not terminate unrelated tasks.

## Bash environment

The Bash profile is designed to stay useful on both full desktops and stripped-down administration systems.

It provides:

- XDG directory defaults without overriding values already chosen by the user;
- a compact prompt with command status, host, path and Git branch;
- history synchronization that appends and imports new history without clearing the active shell history;
- optional Bash completion, fzf and zoxide integration only when installed;
- safe TTY handling for `stty`, prompts and terminal formatting;
- editor selection based on installed tools instead of forcing Vim;
- aliases that avoid changing the semantics of core commands such as `mkdir`, `mktemp` or `sudo`.

Useful functions include `extract`, `backup`, `mkcd`, `up`, `gitroot`, `ftext`, `tre`, `myip`, `serve`, `fkill`, `genpass`, `genpassphrase`, `mkvenv`, `retry` and `sysupdate`.

A few intentional safety choices:

- `serve` binds to `127.0.0.1` by default; use `serve --public` when LAN exposure is actually wanted;
- `fkill` sends `TERM` by default; `fkill --force` is the explicit `KILL` path;
- rsync aliases do not imply `--delete`;
- no alias removes package-manager lock files;
- password generation avoids SIGPIPE-sensitive filtering pipelines.

## Git and SSH client configuration

The bootstrap no longer replaces `~/.gitconfig` wholesale.

The managed Git policy is installed as:

```text
~/.config/git/dotfiles.gitconfig
```

and is added to the user's global Git configuration through `include.path`.

Machine-specific identity can remain private in:

```text
~/.config/git/local.gitconfig
```

The public template intentionally contains no fake `user.name` or `user.email` values.

SSH follows the same model:

```text
~/.ssh/config
└── Include ~/.ssh/conf.d/*.conf

~/.ssh/conf.d/90-dotfiles.conf
```

No private-key filename is assumed and existing host entries are preserved.

## Vim is optional

The Vim configuration is no longer a hidden dependency of the workstation profile.

Choose it explicitly from the assistant or run the full dotfiles profile. The supplied `.vimrc` uses built-in Vim functionality and performs **no first-start network download**. There is no plugin manager bootstrap and no automatic `curl` of executable editor code.

The profile still provides persistent undo, recovery files, sensible indentation, built-in netrw navigation, split navigation, search behaviour and a compact statusline.

## Repository commands

Scripts under `bash/bin/` are copied to `~/.local/bin` rather than symlinked into the Git checkout. The commands therefore keep working if the repository is later moved or deleted.

Current tools include:

| Command | Purpose |
| --- | --- |
| `authaudit` | Recent SSH and sudo authentication activity from journald |
| `monitorport` | Wait for a TCP endpoint with interval/timeout control |
| `portcheck` | Local listening socket inventory |
| `openvpndown` | Explicit OpenVPN down-script kill switch for default-route interfaces |
| `randomipzer` | Documentation/private IP generator for test fixtures |
| `dominfo` | DNS, TLS and WHOIS domain inventory |
| `httpcheck` | HTTP redirect, latency and security-header inspection |
| `sslcheck` | TLS certificate details and expiry thresholds |
| `pstree-info` | Process details and process ancestry without forced sudo |

`openvpndown` refuses casual direct execution because its purpose is to disconnect network paths when an OpenVPN tunnel drops.

## Hardening workspace

The security assistant is aimed at **general-purpose Linux workstations**, not a blind CIS benchmark or a production server role.

Start with a read-only review:

```bash
sudo ./hardening_setup.sh --audit
```

The recommended profile applies controls that are normally compatible with programming, containers, VPNs and desktop applications:

```bash
sudo ./hardening_setup.sh --recommended
```

The balanced baseline includes:

- source-route and redirect rejection;
- loose reverse-path filtering suitable for common VPN/multihoming setups;
- SYN cookie, martian logging and safe ICMP protections;
- pointer, dmesg, ptrace, unprivileged BPF and protected-link controls;
- a host firewall without opening HTTP/HTTPS inbound ports;
- SSH hardening only when an SSH server already exists;
- automatic security updates where a generic native policy is safe;
- Fail2Ban only when an SSH server is present;
- SELinux/AppArmor, time sync and network-facing service auditing.

The recommended baseline intentionally does **not** disable IPv6, ping, TCP SACK/timestamps, user namespaces, IP forwarding, Bluetooth, CUPS, Avahi or other desktop services globally.

Those decisions depend on workload and network role.

### High-impact modules

The interactive hardening menu keeps compatibility-sensitive controls separate:

- SSH key-only authentication;
- host-wide Quad9 DNS;
- USBGuard;
- `/dev/shm` `noexec` policy;
- uncommon kernel-protocol blacklisting;
- optional antivirus/audit tooling.

These controls either require literal confirmation or provide a compatibility warning before making changes.

## Firewall behaviour

The firewall module detects an existing active frontend first.

- UFW is hardened **without `ufw reset`**.
- firewalld works on the interface's active/default zone and does not delete existing services or ports.
- nftables refuses to replace a non-empty existing ruleset.
- an existing remote SSH session has its destination port preserved before a new baseline becomes active.
- TCP/80 and TCP/443 are never opened simply because this is a developer workstation.

This avoids the common failure mode where a generic hardening script silently destroys application, VPN, container or remote-administration firewall state.

## DNS policy

Quad9 is optional rather than part of the recommended profile.

A global resolver change can break:

- Active Directory DNS;
- corporate split DNS;
- VPN-provided search domains;
- lab networks and local service discovery.

The module therefore requires explicit confirmation, prefers `systemd-resolved` or NetworkManager, and never applies an immutable flag to `/etc/resolv.conf`.

## Recovery and backups

User configuration replacement creates timestamped copies below:

```text
~/.local/state/dotfiles/backups/
```

System hardening creates change-aware snapshots below:

```text
/var/backups/dotfiles-hardening/
```

A hardening snapshot records only paths that the assistant is about to change plus the previous enabled/active state of managed systemd units. The Restore workspace can return those files and services to their recorded state.

This is intentionally different from a generic "restore defaults" routine: the assistant does not guess that Bluetooth, CUPS, Avahi, ModemManager or another unrelated service was enabled before hardening.

A system backup/snapshot outside this repository is still recommended before major OS upgrades or storage changes.

## Error handling and terminal behaviour

The control planes intentionally avoid global `set -e` behaviour.

In an interactive administrator tool, a missing optional package, empty `grep` result or unavailable service should not terminate an unrelated workflow. Each module returns a status, `run_task` records it, and the assistant continues when the failure is recoverable. If an external consumer deliberately closes stdout early (for example `... | head -1`), normal Unix `SIGPIPE` semantics are preserved rather than hidden.

Interactive input is read from `/dev/tty` rather than consuming pipeline/stdin data. This allows commands and subprocess output to be redirected without accidentally answering a destructive confirmation prompt.

`Ctrl+C` exits cleanly and **never removes APT, dpkg, pacman, DNF or Zypper lock files**.

## Package and supply-chain policy

The baseline intentionally favours:

1. the distribution's configured repositories;
2. a smaller portable package set;
3. optional features that degrade cleanly when a package is unavailable.

The assistants do not automatically install an AUR helper, add external repositories, download `.deb`/`.rpm` releases from GitHub, bootstrap Vim plugins, or pipe remote scripts into a shell.

Language ecosystems such as Rust, Node.js, Go toolchains, SDKMAN or Python application managers are deliberately outside the generic bootstrap. Their lifecycle and version policy should be selected per developer/project rather than forced at machine provisioning time.

## Before applying on an existing workstation

Review the changed files and start with:

```bash
./bash_setup.sh --status
sudo ./hardening_setup.sh --audit
```

Then apply individual modules or the recommended profiles.

For remote hosts, keep an independent console/recovery path available before changing firewall, DNS or SSH authentication policy.

## Design goals

```text
detect
  -> show scope
  -> preserve existing state
  -> apply only the selected module
  -> validate
  -> report warnings without collapsing the whole assistant
  -> keep a recovery path for system policy changes
```

The repository is meant to be understandable and editable. Bash remains the orchestration layer; no framework or background agent is required.

## License

MIT. See `LICENSE`.
