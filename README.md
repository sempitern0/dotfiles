# dotfiles

Prepare a personal Linux workstation: Bash/Zsh, Git, SSH client, useful commands
and optional Vim. Packages come from your distribution's configured repositories.

**English** · [Español](README_ES.md) · [Full reference](docs/REFERENCE.md)

[Desktop profiles, compatibility and failures](docs/DESKTOP.md) · [Validation](docs/MAINTENANCE.md)

## Start here

Requirements: Linux, Bash 4.3+, Git, and an existing user account. Supported package
families: APT, pacman, DNF and Zypper. Use a normal user checkout; package operations
request `sudo` when necessary.

```bash
git clone https://github.com/sempitern0/dotfiles.git
cd dotfiles
./bash_setup.sh --plan
./bash_setup.sh --status
./bash_setup.sh --desktop     # from a graphical desktop terminal
```

Open a new terminal after setup. Prefer the menu? Run `./bash_setup.sh`.
The assistant replaces the managed Bash configuration after backing it up; Zsh
receives a managed include while preserving the existing `.zshrc`.

## Choose the scope

| Command | Result |
|---|---|
| `./bash_setup.sh --plan` | Preview package groups and deployment without changes |
| `./bash_setup.sh --user-only` | Deploy user files using existing tools; no package operations |
| `./bash_setup.sh --desktop` | Recommended + XDG/MIME utilities and fonts on graphical hosts |
| `./bash_setup.sh --status` | Read-only readiness; installs nothing |
| `./bash_setup.sh --minimal` | Core packages, shell, Git/SSH client and utilities |
| `./bash_setup.sh --recommended` | Minimal + development, diagnostics and terminal productivity |
| `./bash_setup.sh --full` | Full dotfiles profile, including pluginless Vim |
| `./bash_setup.sh --user alice --recommended` | Explicit target account, useful from elevated shells |
| `sudo ./hardening_setup.sh --audit` | Inspect system security posture |
| `sudo ./hardening_setup.sh --recommended` | Apply the separate workstation hardening baseline |

The desktop profile preserves your desktop environment, default applications and drivers.
Immutable/transactional hosts use `--user-only`; their package workflow stays native.
Profiles continue after task failures but return exit status 1 and list failures.

Vim and system hardening are separate choices. Recommended hardening excludes
Quad9 DNS, USBGuard, key-only SSH and strict `/dev/shm`/kernel-module policies.
There are no automatic AUR helpers, PPAs, plugin managers or remote shell installers.

## Make it yours

| What to customize | Repository source | Installed location |
|---|---|---|
| Bash startup, aliases and functions | `bash/conf/` | `~/.bashrc`, `~/.bash.aliases`, `~/.bash.functions` |
| Zsh integration | `zsh/conf/dotfiles.zsh` | `~/.config/dotfiles/zsh.zsh` |
| Git defaults | `git/.gitconfig` | `~/.config/git/dotfiles.gitconfig` |
| SSH defaults | `git/ssh/config` | `~/.ssh/conf.d/90-dotfiles.conf` |
| Vim | `vim/.vimrc` | `~/.vimrc` |
| Standalone commands | `bash/bin/` | `~/.local/bin/` |

Keep Git identity and private SSH keys outside this public repository. Edit the
source files before applying a profile; changes made only to managed installed
files may be replaced on the next run. Commands are copied and remain usable if
you move the checkout.

## Everyday shortcuts

| Task | Helpers |
|---|---|
| Navigate and search | `mkcd`, `up`, `gitroot`, `fcd`, `ftext` |
| Inspect files | `pretty`, `extract`, `backup` |
| Work on projects | `mkvenv`, `retry`, `serve` |
| Inspect connectivity | `portcheck`, `monitorport`, `httpcheck`, `sslcheck`, `dominfo` |
| Use optional Vim | Space = leader; `Space f` find, `Space g` search, `Space w` save |

The [reference](docs/REFERENCE.md) covers aliases, Vim mappings, firewall policy,
SSH/DNS choices and supported platforms in detail.

## Recovery and updates

User-file originals live under `~/.local/state/dotfiles/backups/<run-id>/`
(or the configured XDG state directory), with their absolute path reproduced below
that directory. Repeating a module within one run preserves the first backup.
A failed backup stops replacement of that file.

To restore one user file, inspect its backup and copy that specific file back to its
original path. Hardening has a separate **Recovery** menu and snapshots under
`/var/backups/dotfiles-hardening/`; restoring policy does not uninstall packages.

Before updating: inspect `git diff`, run `--status`, then apply the intended profile.
For a remote machine, keep an independent access path before changing SSH/firewall/DNS.

## Validate changes without configuring the host

```bash
python3 tools/verify.py
# CI requires the static analyzer:
python3 tools/verify.py --require-shellcheck
```

Tests use temporary files, mocked operations and loopback HTTP only. Real package installs and hardening must
be checked on disposable machines for each target distribution.

[MIT license](LICENSE).
