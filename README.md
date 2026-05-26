# Azure Bastion Bash Routing Engine

A highly configurable, declarative Bash wrapper designed to simplify connecting to Azure virtual machines and internal network resources. 

Instead of memorizing complex `az CLI` commands, chaining `-L` SSH port forwards, and fighting with Windows MSYS2/Git Bash UNIX socket limitations, this routing engine allows you to define your infrastructure in a single configuration file and connect with a simple alias.

## The Problem It Solves

Enterprise Azure environments often feature a mix of architectures:
- VMs hidden behind Azure Bastion requiring standard SSH keys.
- VMs requiring Azure Active Directory (Entra ID) authentication.
- Deeply nested databases or APIs that require jumping through a Bastion, into a Jumpbox, and then port-forwarding across internal VNets.
- Strict JIT (Just-In-Time) access policies.

This repository standardizes access to all of them through a single command: `bastion <alias> [ssh]`.

## Key Features

- **Declarative Configuration:** Define your VMs, Resource Groups, Subscriptions, and dynamic port-forwards in a single `~/.bastion_topology.conf` file.
- **Unified Routing Engine:** Natively handles `flat` (Bastion tunnel), `flat-entra` (Entra ID), and `tiered` (Jumpbox/Proxy) topologies.
- **Cross-Platform:** The core routing logic (`30-azure_routing.sh`) is OS-agnostic. A dedicated `10-windows_env.sh` layer normalizes paths, `pageant`, and `ssh-agent` specifically for Windows/MSYS2 users without bleeding into the main engine.
- **Escape Hatches:** The `.bastion_profiles/` directory allows you to write discrete, custom bash scripts to handle extreme edge cases (like JIT temporal requests, reverse-shell beacons, or VPN proxies) that bypass the core engine.

## Installation

1. Clone the repository to your local machine.
2. Ensure your `~/.bashrc` sources the files in the `.bashrc.d/` directory.
3. Copy the example configuration file to your home directory (or keep it in the project root for local development):
   ```bash
   cp .bastion_topology.conf.example ~/.bastion_topology.conf
   ```
4. Edit `~/.bastion_topology.conf` with your actual Azure infrastructure details. (This file is explicitly git-ignored to prevent leaking sensitive network data).

## Usage

**List all configured VMs:**
```bash
list_vms
```

**Establish a background tunnel to a VM (and apply dynamic port forwards):**
```bash
bastion api0
```

**Connect interactively to a VM:**
```bash
bastion api0 ssh
```

**List all active connections and port forwards:**
```bash
list_connections
```

**Clean up / close connections:**
```bash
cleanup_tunnels api0   # Close tunnels for a specific alias
cleanup_tunnels all    # Close all active bastion and SSH tunnels
```

## Documentation

- [Network Architecture & Topologies](ARCHITECTURE.md) - Deep dive into how the routing engine handles `flat`, `flat-entra`, and `tiered` connections.
- [Escape Hatch Profiles](.bastion_profiles/README.md) - How to write custom profile overrides for edge cases like JIT access.
