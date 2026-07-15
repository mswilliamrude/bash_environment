# Installation Guide

This guide covers setting up the bash environment on a fresh Windows machine
running MSYS2. The `scripts/install.sh` script automates the majority of this.

## Prerequisites

- [MSYS2](https://www.msys2.org/) installed at `C:\msys64\`
- A terminal launching MSYS2 bash, e.g.:
  ```
  C:\msys64\usr\bin\bash.exe -l -i
  ```

## Quick Start

```bash
# 1. Clone the repo
git clone git@github.com:mswilliamrude/bash_environment.git ~/git/bash_environment

# 2. Run the installer
bash ~/git/bash_environment/scripts/install.sh

# 3. Restart your MSYS2 shell
```

That's it. The installer handles everything below automatically.

---

## What install.sh Does

### 1. Packages

Installs the following via `pacman`:

**MSYS runtime** (`/usr/bin`):
| Package | Purpose |
|---|---|
| `git` | Version control |
| `rsync` | File sync — used in bastion workflows |
| `diffutils` | `diff`, `cmp`, `sdiff` |
| `tmux` | Terminal multiplexer |
| `vim` | Editor |
| `man-db` | Man pages |
| `openssh` | `ssh`, `ssh-agent`, `ssh-keygen` |
| `curl` | HTTP client |
| `wget` | HTTP downloader |
| `procps-ng` | `ps`, `kill` — required by tunnel detection in `30-azure_routing.sh` |
| `jq` | JSON processor — used for Azure CLI output parsing |
| `zip` / `unzip` | Archive tools |
| `dialog` | TUI library — required by `bastion_wizard` |
| `python` | MSYS Python 3 |
| `python-pip` | pip for MSYS Python |

**UCRT64 toolchain** (`/ucrt64/bin`):
| Package | Purpose |
|---|---|
| `mingw-w64-ucrt-x86_64-python` | UCRT64 Python 3 (ucrt-linked) |
| `mingw-w64-ucrt-x86_64-python-pip` | pip for UCRT64 Python |
| `mingw-w64-ucrt-x86_64-python-cryptography` | Cryptography primitives |
| `mingw-w64-ucrt-x86_64-python-httpx` | Async HTTP client |
| `mingw-w64-ucrt-x86_64-python-numpy` | Numerical computing |
| `mingw-w64-ucrt-x86_64-python-websockets` | WebSocket client/server |
| `mingw-w64-ucrt-x86_64-python-yaml` | YAML parsing |

**Third-party** (GitHub releases, installed via `pacman -U`):
| Package | Source |
|---|---|
| `mingw-w64-ucrt-x86_64-python-protocols` | [mswilliamrude/protocols](https://github.com/mswilliamrude/protocols) |

### 2. `/etc/nsswitch.conf`

Sets `db_home: windows` so MSYS2 uses your Windows user profile directory
(`C:\Users\<name>`) as `$HOME` instead of `/home/<name>`. This ensures
dotfiles, SSH keys, and configs stored in your Windows home are visible
without symlinks.

A backup is saved to `/etc/nsswitch.conf.orig` before any modification
(only on first run — never overwrites an existing `.orig`).

### 3. `~/.bashrc`

Copies the repo's `.bashrc` to `~/.bashrc`. A backup is saved to
`~/.bashrc.orig` on first run.

### 4. `~/.bashrc.d/`

Copies all module scripts from `repo/.bashrc.d/` into `~/.bashrc.d/`,
creating the directory if needed. Each file is backed up as `<file>.orig`
before being overwritten (once only).

| Script | Purpose |
|---|---|
| `01-windows_path.sh` | PATH normalization — MSYS2 vs Git for Windows detection |
| `10-windows_env.sh` | Windows environment setup, Pageant, plink resolution |
| `15-ssh_agent.sh` | Cross-platform SSH agent management |
| `20-vim.sh` | Editor configuration |
| `30-azure_routing.sh` | Azure Bastion routing engine |
| `30-history.sh` | Shell history settings |
| `40-completions.sh` | Tab completion for `bastion`, `connect-vm`, `cleanup_tunnels` |
| `50-bastion-wizard.sh` | Interactive TUI wizard for topology configuration |

### 5. `~/.bastion_profiles/`

Copies example escape-hatch profile scripts from `repo/.bastion_profiles/`
into `~/.bastion_profiles/`. Existing files are never overwritten — your
live profile scripts (e.g. `jbox.sh`) are safe.

### 6. `~/.bastion_topology.conf.example`

Copies the annotated topology template to `~/.bastion_topology.conf.example`
so you have it at hand. If no `~/.bastion_topology.conf` exists yet, one is
also created from the example as a starting point.

### 7. `~/.bash_profile`

Ensures login shells source `~/.bashrc`. MSYS2 launched with `-l` (login
shell) reads `~/.bash_profile` instead of `~/.bashrc` — without this, the
entire `.bashrc.d/` chain never fires.

The installer either:
- Creates `~/.bash_profile` from scratch if it doesn't exist
- Appends the source line to an existing `~/.bash_profile` if it's missing

A backup is saved to `~/.bash_profile.orig` before any modification.

> **Note:** `.bash_profile` is intentionally not tracked in this repo —
> it's machine-specific bootstrapping that the installer manages at runtime.

---

## Manual Setup (without install.sh)

If you prefer to set things up by hand:

```bash
# 1. Set db_home in nsswitch.conf
sudo sed -i 's/^db_home:.*/db_home: windows/' /etc/nsswitch.conf

# 2. Copy dotfiles
cp ~/git/bash_environment/.bashrc ~/.bashrc
cp -r ~/git/bash_environment/.bashrc.d/* ~/.bashrc.d/
cp ~/git/bash_environment/.bastion_topology.conf.example ~/.bastion_topology.conf.example

# 3. Create ~/.bash_profile if missing
cat >> ~/.bash_profile <<'EOF'
[[ -f ~/.bashrc ]] && source ~/.bashrc
EOF

# 4. Configure your topology
cp ~/.bastion_topology.conf.example ~/.bastion_topology.conf
# Edit ~/.bastion_topology.conf with your Azure infrastructure details

# 5. Restart your shell
```

---

## Post-Install

### Configure your topology

Edit `~/.bastion_topology.conf` with your Azure infrastructure details,
or use the interactive wizard:

```bash
bastion_wizard
```

### Verify everything loaded

```bash
bastion        # Should show help and configured VMs
list_vms       # Should list your configured VMs
```

### SSH Keys

Make sure your SSH keys are loaded before connecting:

```bash
ssh-add ~/.ssh/your_key
ssh-add -l    # List loaded keys
```

---

## Troubleshooting

**`bastion: command not found`**
- `~/.bashrc.d/30-azure_routing.sh` failed to source
- Check for a missing or misconfigured `~/.bastion_topology.conf`
- Run: `source ~/.bashrc.d/30-azure_routing.sh` and read the error

**`az: command not found`**
- Azure CLI not installed or not in PATH
- Check: `echo $PATH | tr ':' '\n' | grep -i azure`
- Install: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli

**Wrong `bash` being used (Git for Windows vs MSYS2)**
- `01-windows_path.sh` detects MSYS2 via presence of `/ucrt64/bin`
- Verify: `which bash` should return `/usr/bin/bash`
- If Git for Windows bash is winning, ensure you're launching via
  `C:\msys64\usr\bin\bash.exe -l -i` not `C:\Program Files\Git\bin\bash.exe`

**PATH duplicating on every new shell**
- `01-windows_path.sh` guards against re-sourcing — `/ucrt64/bin` must be
  the first entry in PATH for the guard to fire
- Run: `echo "${PATH%%:*}"` — should return `/ucrt64/bin`
