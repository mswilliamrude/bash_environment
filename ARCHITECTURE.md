# Bash Environment Network Architecture

This document outlines the networking patterns and tunneling strategies utilized by the declarative Azure Bastion routing engine in this repository.

## Overview

The environment leverages a modular `.bashrc.d` architecture with a primary universal routing engine (`.bashrc.d/30-azure_routing.sh`). This engine parses a declarative, git-ignored configuration (`.bastion_topology.conf`) to dynamically establish SSH and port-forwarding connections to virtual machines, predominantly within Azure.

The architecture is designed to handle three main topologies via the core routing engine, while delegating extreme edge cases to discrete scripts ("escape hatches") in the `.bastion_profiles/` directory.

## Core Topologies

### 1. Flat Topology (`flat`)
Used for standard VMs accessible via Azure Bastion without Entra ID integration.

- **Mechanism:** Backgrounds an `az network bastion tunnel` process on a dynamically selected port.
- **Dynamic Port Forwarding:** Automatically checks `VM_PROPS[<alias>_az_tunnels]` for `-L` arguments and appends them to the SSH command, allowing you to proxy local traffic to inner virtual networks orthogonally.
- **SSH Client:** Falls back to native `ssh -p <port> user@localhost` instead of `az network bastion ssh`.
- **Reasoning:** MSYS2 `ssh` (used in Git Bash/Cygwin) cannot interact with Windows native UNIX sockets properly, leading to password prompts. The background tunnel + native SSH bypasses this limitation, allowing seamless `ssh-agent` authentication.

### 2. Flat Entra Topology (`flat-entra`)
Used for VMs integrated with Azure Active Directory (Entra ID) for SSH authentication.

- **Mechanism:** Leverages `az network bastion ssh --auth-type AAD`.
- **Reasoning:** Entra ID SSH uses short-lived certificates requested via the Azure CLI. Native OpenSSH requires complex `ProxyCommand` wrappers to accomplish this, so utilizing the Azure CLI directly is the most robust approach.
- **Note:** Because it utilizes the proprietary Azure CLI wrapper, dynamic port forwarding (`-L`) is not natively supported in interactive shell mode for this topology.

### 3. Tiered Topology (`tiered`)
Used for Private network segmentation where target VMs are only accessible via a Jumpbox.

- **Mechanism:** `az ssh vm` to the Jumpbox, dynamically injecting `-L` port forwarding rules (from `VM_PROPS[<alias>_az_tunnels]`) for target databases, APIs, or secondary VMs.
- **Subshell:** Once the jumpbox tunnel is established, a subshell using `plink.exe` (or MSYS2 SSH if preferred) can be instantiated to map local ports on the user's workstation through the jumpbox to the target resources (defined in `VM_PROPS[<alias>_plink_tunnels]`).

## The Escape Hatch (`.bastion_profiles/`)

For architectures that do not fit into the core topologies, the engine looks for a matching executable script in `.bastion_profiles/<vm-name>.sh`. If found, it abandons the core engine and executes the script's `connect()` function.

### JIT (Just-In-Time) Access
VMs secured behind strict Network Security Groups (NSGs) that require temporal access requests. The profile issues an `az security jit-policy access-request`, sleeps for the NSG rules to propagate, and then connects.

### VPN + SOCKS Proxy
Legacy or non-Azure on-premise systems that require establishing a local VPN client (e.g., OpenVPN) and routing SSH traffic through a `ProxyCommand` like `nc -X 5 -x 127.0.0.1:1080 %h %p`.

### Reverse-Shell Beacons
IoT edge devices or heavily firewalled internal hosts that dial out to a known Jump Server. The profile uses `ProxyJump` (`-J`) to connect to the Jump Server and then connects to the reverse-tunneled port bound to the Jump Server's localhost.

## Process Flow

1. User types `connect-vm <name>`.
2. Engine checks if `.bastion_profiles/<name>.sh` exists.
   - If **yes**, source it and run `connect()`. Stop.
3. If **no**, engine looks up `<name>` in `.bastion_topology.conf`.
4. Engine reads the `topology` attribute (flat, flat-entra, tiered).
5. Engine builds the dynamic connection arguments (ports, IPs, `-L` forwards).
6. Engine establishes the tunnel/connection.
