# dotfiles · Linux Workstation Control Plane

A portable, opinionated Linux workstation environment for developers, system administrators and security-minded power users.

The repository is intentionally built around distribution-maintained software, explicit configuration profiles and recoverable security changes. It is not a package-manager replacement and it does not assume that every workstation should receive the same editor, firewall, DNS policy or hardening level.

## Entry points

| Assistant | Scope | Privileges |
| --- | --- | --- |
| `bash_setup.sh` | Packages, Bash/Zsh, aliases/functions, Git, SSH client, optional Vim and local utilities | User context; requests `sudo` only for package operations |
| `hardening_setup.sh` | Firewall, sysctl baseline, SSH server policy, security updates, Fail2Ban, optional DNS/USB/threat tooling and recovery | Root / `sudo` |

Both control planes support interactive menus and direct modes suitable for repeatable provisioning.

## Supported Linux families

The project targets package-management families rather than hard-coding individual releases:

| Family | Examples | Package source policy |
| --- | --- | --- |
| Debian | Debian, Ubuntu, Kali and close derivatives | Configured APT repositories |
| Arch | Arch and close derivatives | Official pacman repositories only |
| Fedora / RHEL-like | Fedora and compatible RPM systems | Configured DNF repositories |
| openSUSE / SUSE-like | Leap, Tumbleweed and compatible systems | Configured Zypper repositories |

Package availability is checked at runtime. Optional packages that do not exist in the configured official repositories are skipped rather than replaced with random third-party installers.

The bootstrap does **not** automatically add PPAs, COPRs, AUR helpers, external RPM repositories, GitHub release binaries or `curl | sh` installers.

## Quick start

Run the workstation assistant from a normal user checkout:

```bash
git clone https://github.com/sempitern0/dotfiles.git
cd dotfiles
./bash_setup.sh
```

Recommended baseline:

```bash
./bash_setup.sh --recommended
```

Other useful modes:

```bash
./bash_setup.sh --minimal
./bash_setup.sh --full
./bash_setup.sh --status
./bash_setup.sh --user alice --recommended
sudo ./hardening_setup.sh --audit
sudo ./hardening_setup.sh --recommended
```

`--full` means the complete dotfiles profile, including Vim. It does not silently opt the machine into strict hardening controls.

## Workstation profiles

### Minimal

Suitable for a temporary VM, lab machine or fresh administration host:

```text
Core official packages
Shell environment
Git + SSH client defaults
Portable commands
```

### Recommended

The normal developer/sysadmin workstation profile:

```text
Minimal
+ compiler/build toolchain
+ Python development baseline
+ network/process/storage diagnostics
+ fzf, ripgrep, bat, zoxide and terminal productivity tools where available
+ desktop clipboard/notification integration when relevant
```

Vim and system hardening remain optional.

### Full dotfiles

Adds the repository's pluginless Vim profile to Recommended.

The menu also supports multiple selections in one pass, for example:

```text
5,6,8,9,11
```

A recoverable failure in one module is shown in the run summary without terminating unrelated modules.

## Bash and Zsh parity

The workstation layer supports both Bash and Zsh.

The assistant always deploys the historical shared files:

```text
~/.bashrc
~/.bash.aliases
~/.bash.functions
```

`.bash.aliases` and `.bash.functions` are deliberately written so the same helper library can be consumed by Zsh.

When the account uses Zsh — notably fresh Kali desktop installations — the assistant additionally installs:

```text
~/.config/dotfiles/zsh.zsh
```

and adds one managed source line to the existing `~/.zshrc` instead of replacing the distribution/user configuration.

This preserves Kali-specific Zsh configuration while adding the same aliases, functions, fzf integration and Git-aware prompt used by Bash.

The target account is resolved from `--user`, `SUDO_USER`, the checkout owner or the login session. This avoids accidentally writing dotfiles to `/root` when the assistant is launched from `sudo -i` or another elevated shell.

## Terminal ergonomics

The managed shell layer includes:

- `refresh` to reload the active Bash/Zsh configuration;
- time, previous command status, `user@host`, current path and Git branch in the prompt;
- a dirty Git marker when tracked/staged files differ;
- Python virtual-environment indication;
- shared history behaviour suitable for multiple terminals;
- Bash completion where the distribution provides it;
- fzf Ctrl-R reverse-history integration;
- fzf Ctrl-T file selection and Alt-C directory selection where supported;
- ripgrep-backed fzf file discovery for large repositories;
- zoxide integration when installed;
- TTY-safe `stty` handling.

Useful helpers include:

```text
extract       backup       mkcd        up
gitroot       ftext        fcd         fpreview
hgrep         tre          pretty      myip
serve         fkill        genpass     genpassphrase
mkvenv        retry        sysupdate
```

`pretty file.txt` uses `bat`/`batcat` with line numbers and syntax colouring, falling back to `less` when unavailable.

The bootstrap creates user-local compatibility shims in `~/.local/bin` when the distribution exposes common tools under another executable name:

```text
bat  -> batcat     # Debian/Kali when applicable
fd   -> fdfind     # Debian/Kali when applicable
fzf  -> system fzf binary
```

No core command such as `cat`, `mkdir`, `mktemp` or `sudo` is globally replaced with surprising semantics.

## Aliases

The alias set focuses on operations that remain predictable without extra parameters:

- file listings (`ll`, `la`, `lt`, `tree`);
- Git (`gs`, `gd`, `gds`, `gl`, `gla`, `gf`);
- sockets and routes (`openports`, `listen`, `sockets`, `routes`, `netcon`);
- journals and failed units (`logs`, `jerr`, `journalerr`, `failed`);
- resource inspection (`topcpu`, `topmem`, `devices`, `mountedinfo`);
- safe rsync convenience commands;
- ripgrep shortcuts (`rgi`, `rgfiles`).

Destructive or argument-sensitive behaviour is implemented as functions instead of aliases.

## Git and SSH client configuration

Git policy is installed as:

```text
~/.config/git/dotfiles.gitconfig
```

and referenced from the user's global Git config with `include.path`. Personal identity remains outside the public repository.

SSH uses:

```text
~/.ssh/config
└── Include ~/.ssh/conf.d/*.conf

~/.ssh/conf.d/90-dotfiles.conf
```

Existing private keys and host definitions are preserved. No private-key filename is assumed.

## Vim is optional

The supplied Vim profile is deliberately **pluginless**. Opening Vim never downloads a plugin manager, theme, binary or remote configuration. Choose it explicitly from the assistant or use `--full`; the Recommended workstation profile does not touch Vim.

The profile keeps ordinary absolute line numbers and explicitly disables relative numbering. Persistent undo, swap and backup files live below `~/.local/state/vim` and `~/.cache/vim` instead of polluting project directories.

### Visual behaviour

The base colourscheme remains available offline, while the profile overrides the UI groups that matter most during long editing sessions. `CursorLine` uses a neutral charcoal background so syntax colours remain readable; search, incremental search, selections, matching parentheses and diff regions use dedicated high-contrast backgrounds.

Only the active window receives a full cursor-line highlight. This makes split layouts easier to scan without tinting every visible line.

### Leader key

The leader key is **Space**. The most useful mappings are:

| Mapping | Action |
| --- | --- |
| `Space w` | Save current file |
| `Space q` | Quit current window |
| `Space h` | Clear search highlighting |
| `Space e` | Toggle/open Vim's built-in file explorer (`Lexplore`) |
| `Space f` | Start `:find` for files below the project tree |
| `Space g` | Start project text search through `:grep` |
| `Space b` | List buffers and prompt for a buffer |
| `Space bn` / `Space bp` | Next / previous buffer |
| `Space bd` | Delete current buffer |
| `Space sv` | Vertical split |
| `Space sh` | Horizontal split |
| `Space sc` | Close current split |
| `Ctrl-h/j/k/l` | Move between splits |
| `Space co` / `Space cc` | Open / close quickfix results |
| `Space cn` / `Space cp` | Next / previous quickfix result |
| `Space p` in Visual mode | Paste without overwriting the yank register |

Standard Vim search navigation (`n` / `N`) and half-page scrolling (`Ctrl-d` / `Ctrl-u`) automatically recenter the current match/line.

### Practical workflows

**Find a file anywhere below the current project:**

```vim
<Space>f settings.py
```

The profile adds `**` to Vim's search path and ignores common generated trees such as `.git`, `node_modules`, `.venv`, `dist` and `build`.

**Search project contents with ripgrep:**

```vim
<Space>g TODO
```

When `rg` is installed, Vim uses `rg --vimgrep --smart-case` and loads matches into the quickfix list. Then use:

```text
Space co    open results
Space cn    next match
Space cp    previous match
Space cc    close results
```

Without `rg`, Vim keeps its normal built-in grep behaviour rather than failing startup.

**Work with two files side by side:**

```text
Space sv        create vertical split
Space f file    locate another file
Ctrl-h / Ctrl-l move left/right between splits
Space sc        close the current split
```

**Move between already-open files without plugins:**

```text
Space b         inspect buffers
Space bn        next buffer
Space bp        previous buffer
Space bd        close buffer
```

The goal is intentionally modest: provide fast project navigation and editing primitives using Vim itself, while leaving language servers, completion frameworks and plugin ecosystems as an explicit user choice rather than a bootstrap side effect.

## Portable commands

Scripts under `bash/bin/` are copied to `~/.local/bin`, so they keep working if the Git checkout is moved or deleted.

| Command | Purpose |
| --- | --- |
| `authaudit` | Recent SSH and sudo authentication activity |
| `monitorport` | Wait for a TCP endpoint with timeout/interval controls |
| `portcheck` | Local listening socket inventory |
| `openvpndown` | OpenVPN down-script network kill switch |
| `randomipzer` | Documentation/private IP generator for test fixtures |
| `dominfo` | DNS, TLS and WHOIS inventory |
| `httpcheck` | HTTP redirect, latency and security-header inspection |
| `sslcheck` | TLS certificate details and expiry thresholds |
| `pstree-info` | Process ancestry/details without shadowing the system `pstree` |

## Hardening workspace

The hardening assistant is designed for a **general-purpose developer/admin workstation**, not a blind server benchmark.

Start with:

```bash
sudo ./hardening_setup.sh --audit
```

Then, if appropriate:

```bash
sudo ./hardening_setup.sh --recommended
```

The interactive UI separates controls into:

```text
Start here
  - read-only posture audit
  - recommended workstation baseline

Baseline controls
  - network sysctl
  - kernel/memory sysctl
  - firewall
  - security updates
  - conditional SSH hardening
  - conditional Fail2Ban
  - MAC/time/exposure audit

Optional policy changes
  - Quad9 DNS
  - threat/audit tooling

High-impact controls
  - SSH key-only authentication
  - USBGuard
  - /dev/shm noexec
  - kernel protocol blacklist

Recovery
  - restore assistant snapshot
```

The Recommended baseline does **not** apply Quad9, USBGuard, key-only SSH or strict `/dev/shm`/module policies.

## Firewall policy

An already-active firewall frontend is preserved. If no frontend is installed, the automatic family defaults are:

```text
Debian / Ubuntu / Kali   -> UFW
Fedora / RHEL-like       -> firewalld
openSUSE / SUSE-like     -> firewalld
Arch                     -> nftables
```

All are installed from the distribution's configured official repositories.

The firewall workspace can also explicitly select UFW, nftables or firewalld.

Safety properties:

- UFW is enabled without `ufw reset`;
- firewalld keeps existing services/ports and operates on the active/default zone;
- nftables refuses to overwrite an existing non-empty custom ruleset;
- an active remote SSH port is preserved before a new baseline is enabled;
- HTTP/HTTPS are not opened automatically;
- successful execution verifies the selected frontend and loaded policy before reporting PASS.

## SSH hardening

The Recommended profile only modifies SSH when an SSH server is actually active/listening.

An installed but disabled `sshd` is left untouched and is never started by the assistant.

The explicit SSH module can prepare an already-installed server configuration, validates it with `sshd -t`, and reloads a service only when a reloadable `ssh.service`/`sshd.service` is active. Socket-activated or inactive SSH configurations no longer produce a spurious `ssh.service` failure.

Key-only authentication is a separate high-impact action requiring an existing `authorized_keys` file and literal confirmation.

## DNS policy

Quad9 remains optional. A host-wide resolver change can conflict with Active Directory, corporate split DNS, VPN search domains and local labs.

The module therefore requires explicit confirmation, uses NetworkManager/systemd-resolved where possible and does not make `/etc/resolv.conf` immutable.

## Recovery

User configuration backups are stored below:

```text
~/.local/state/dotfiles/backups/
```

System hardening snapshots are stored below:

```text
/var/backups/dotfiles-hardening/
```

Hardening snapshots record assistant-managed paths and previous systemd unit states before modification. Package installation is not blindly reversed during restore; policy/configuration and service state are restored instead.

## Error and stdin handling

The control planes intentionally do not use global `set -e` semantics.

Recoverable command failures are recorded and the interactive assistant continues. Confirmations read directly from `/dev/tty`, so piped stdin or command output cannot accidentally answer a destructive prompt.

`Ctrl+C` exits cleanly and the assistants never delete APT, dpkg, pacman, DNF or Zypper lock files.

## Supply-chain policy

The baseline preference order is:

1. configured distribution repositories;
2. a small portable package set;
3. graceful degradation when an optional package is unavailable.

The assistants do not automatically bootstrap AUR helpers, add third-party repositories, download executable release packages from GitHub, install Vim plugins or invoke remote shell installers.

## Before applying to an existing workstation

Start read-only:

```bash
./bash_setup.sh --status
sudo ./hardening_setup.sh --audit
```

For an account selected incorrectly by an elevated/root shell, specify it explicitly:

```bash
sudo ./bash_setup.sh --user kali --recommended
```

For remote hosts, keep an independent recovery path available before changing firewall, DNS or SSH authentication policy.

## Design model

```text
detect
  -> resolve the target account and shell
  -> show scope
  -> preserve state
  -> use the distribution's package provider
  -> apply only the selected module/profile
  -> validate
  -> report without collapsing unrelated workflows
  -> retain a recovery path for system policy changes
```

No framework, background agent or configuration-management runtime is required.

## License

MIT. See `LICENSE`.
