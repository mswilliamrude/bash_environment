# Bash Environment

A modular, cross-platform shell environment built around a declarative Azure Bastion routing engine. Designed for engineers who work daily with complex Azure networking topologies and want a single command to replace pages of `az CLI` incantations.

## Repository Structure

```
.bashrc                      # Entry point — sources .bashrc.d/* in order
.bashrc.d/
  01-windows_path.sh         # Windows PATH normalization
  10-windows_env.sh          # MSYS2/Cygwin identity, Pageant, plink resolution
  15-ssh_agent.sh            # Cross-platform SSH agent management
  20-vim.sh                  # Editor configuration
  30-azure_routing.sh        # Core Azure Bastion routing engine (600 lines)
  30-history.sh              # Shell history settings
.bastion_topology.conf.example  # Template for declarative VM configuration
.bastion_profiles/           # Escape hatch scripts for edge-case topologies
games/                       # ASCII terminal games (Space Invaders)
scripts/                     # Standalone utilities (invoked directly, not sourced)
```

## The Problem It Solves

Enterprise Azure environments feature a mix of access patterns:

- VMs behind Azure Bastion requiring standard SSH keys
- VMs requiring Azure Active Directory (Entra ID) authentication
- Deeply nested databases/APIs requiring multi-hop Bastion + Jumpbox + port-forwarding chains
- Strict JIT (Just-In-Time) access policies with temporal NSG rules

This repository standardizes access to all of them through a single command:

```bash
bastion <alias> [ssh]
```

## Key Features

- **Declarative Configuration** — Define VMs, Resource Groups, Subscriptions, and dynamic port-forwards in a single git-ignored `~/.bastion_topology.conf` file. Secrets never touch version control.
- **Unified Routing Engine** — Handles three topologies through one interface:
  - `flat` — Standard Azure Bastion tunnel directly to a target VM
  - `flat-entra` — Bastion tunnel with Entra ID (AAD) token authentication
  - `tiered` — Multi-hop routing via jumpbox with nested port forwarding
- **Cross-Platform** — OS guard clauses isolate Windows-specific logic (`10-windows_env.sh`) from the core engine. Works on Linux, macOS, and Windows (MSYS2/Git Bash/Cygwin).
- **Performance Caching** — VMID and IP lookups are cached with a 10-hour TTL to avoid repeated Azure API latency. Fast-path detection skips power-state queries when tunnels are already active.
- **Self-Healing** — IP and VMID caches are automatically invalidated on connection failure, forcing a fresh lookup on next attempt.
- **Escape Hatches** — The `.bastion_profiles/` directory accepts per-VM scripts that bypass the core engine entirely for edge cases (JIT access, VPN/SOCKS proxies, reverse-shell beacons).
- **SSH Agent Management** — A cross-platform agent script (`15-ssh_agent.sh`) that reuses existing agents, prunes stale tracking files, and auto-loads keys — supporting `/proc` (Linux), `ps` (macOS/BSD), and MSYS2.

## Installation

1. Clone the repository:
   ```bash
   git clone <repo-url> ~/git/bash_environment
   ```

2. Ensure your `~/.bashrc` sources the `.bashrc.d/` directory (the included `.bashrc` already does this):
   ```bash
   if [ -d ~/.bashrc.d ]; then
       for rc in ~/.bashrc.d/*; do
           [ -f "$rc" ] && . "$rc"
       done
   fi
   ```

3. Symlink or copy the modules you need into `~/.bashrc.d/`:
   ```bash
   ln -s ~/git/bash_environment/.bashrc.d/* ~/.bashrc.d/
   ```

4. Copy and configure the topology file:
   ```bash
   cp ~/git/bash_environment/.bastion_topology.conf.example ~/.bastion_topology.conf
   # Edit with your Azure infrastructure details
   ```

## Usage

```bash
# Show help and all configured VMs
bastion

# Establish a background tunnel (sets up port forwards)
bastion api0

# Drop into an interactive SSH session
bastion api0 ssh

# List all configured VMs and their routing settings
list_vms

# Show active connections and forwarded ports
list_connections

# Tear down tunnels
cleanup_tunnels api0   # Specific alias
cleanup_tunnels all    # Everything

# Override SSH username for a single connection
BASTION_USER="root" bastion api0 ssh

# Start/stop VMs directly (auto-generated aliases)
startapi0
stopapi0
```

## Configuration

The topology file uses a pipe-delimited format:

```bash
# alias|azure_name|resource_group|subscription|port|type|autostart|auth_type
BASTION_VMS=(
    "api0|vm-api-dev-01|rg-project-dev|Sub_Dev|12022|flat|true|azureuser"
    "jbox|vm-jumpbox-01|rg-sandbox|Sub_Sandbox|10022|tiered|false|entra"
    "secvdi|vm-secure-vdi-01|rg-secure|Sub_Secure|20000|flat-entra|false|entra"
)
```

Dynamic properties (port forwards, bastion overrides) are defined in `VM_PROPS`:

```bash
declare -A VM_PROPS
VM_PROPS["jbox_az_tunnels"]="2022:10.0.1.5:22 13389:10.0.1.6:3389"
VM_PROPS["jbox_plink_tunnels"]="2023:10.0.2.10:22"
VM_PROPS["jbox_fwd_ports"]="2022 13389 2023"
VM_PROPS["global_default_bastion"]="bst-default-region-01"
```

See [`.bastion_topology.conf.example`](.bastion_topology.conf.example) for a fully commented template.

## Architecture

The routing engine follows a simple dispatch flow:

```
User: bastion <alias> [ssh]
  |
  v
connect-vm() -- checks for escape hatch profile
  |
  +-- .bastion_profiles/<alias>.sh exists? --> source & run connect()
  |
  +-- Otherwise --> bastion() core engine
        |
        +-- Parse topology config
        +-- Set subscription context
        +-- Autostart VM if stopped (with fast-path skip)
        +-- Dispatch by topology type:
              flat       -> az network bastion tunnel (background) + ssh
              flat-entra -> az network bastion ssh --auth-type AAD
              tiered     -> az ssh vm --ip <jumpbox> + subshell port forwards
```

For the full network architecture, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Documentation

- [Network Architecture & Topologies](ARCHITECTURE.md) — How `flat`, `flat-entra`, and `tiered` connections work under the hood.
- [Escape Hatch Profiles](.bastion_profiles/) — Writing custom profile overrides for JIT, VPN, and reverse-shell patterns.
- [Topology Config Example](.bastion_topology.conf.example) — Fully annotated configuration template with ASCII topology diagram.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/) (`az`) installed and authenticated
- SSH client (OpenSSH or MSYS2 bundled SSH)
- For tiered topology on Windows: [PuTTY](https://www.putty.org/) (`plink.exe`, `pageant.exe`)

## License

Private repository. Internal use only.
