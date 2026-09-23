# Bastion Profiles (The "Escape Hatch")

The core routing engine (located in `~/.bashrc.d/30-azure_routing.sh`) is designed to handle 99% of your SSH and Bastion connections dynamically. By reading `~/.bastion_topology.conf`, it automatically builds port-forwarding rules, proxy jumps, and Entra ID authentication flows.

However, complex enterprise networks always have **edge cases**.

If you need to execute a connection flow that the universal engine doesn't understand, you can create a custom profile script here.

## How it Works
When you type `bastion <alias>`, the engine first checks if `~/.bastion_profiles/<alias>.sh` exists. 
- **If it does:** It sources your custom script and *skips* the universal engine.
- **If it doesn't:** It falls back to the universal engine driven by `~/.bastion_topology.conf`.

This allows you to write custom connection logic without rewriting the core bash environment.

---

## Edge Case Scenarios

Below are three advanced architectural scenarios. We have provided working `.example` scripts for each. To use them, copy the `.example` file, remove the `.example` extension, and ensure your `~/.bastion_topology.conf` has a matching entry for the alias.

### Scenario 1: Just-In-Time (JIT) Elevation
**Profile:** [`prod-db.sh.example`](prod-db.sh.example)

**The Challenge:** Production databases often require Just-In-Time (JIT) access. You must request access via the Azure API and wait for temporary firewall rules to provision before you can connect.
**The Config Addition:** Define `prod-db` in your `BASTION_VMS` array. Add `VM_PROPS["prod-db_jit_port"]="22"` to define the port you are requesting.

```text
  [Local Machine]
         |
  (1. az security jit request)
         |
  (2. wait 30s for FW rules)
         |
  [Azure Bastion]
         |
   [Prod DB VM]
```

### Scenario 2: VPN + Local Container Proxy (Air-Gapped)
**Profile:** [`legacy-box.sh.example`](legacy-box.sh.example)

**The Challenge:** A legacy server is only accessible via a specialized, containerized VPN client (e.g., an OpenVPN tunnel running in local Docker). You must proxy your SSH traffic through that local container's SOCKS5 proxy to reach the destination.
**The Config Addition:** Define `legacy-box` in your `BASTION_VMS` array. 

```text
      [Local Machine]
             |
  (1. docker run openvpn-client)
             |
     [Local SOCKS5 Proxy]
        localhost:1080
             |
  (2. ssh -o ProxyCommand=nc -X ...)
             |
     [Legacy Jumpbox]
```

### Scenario 3: Deep Reverse-Shell Beacon (IoT / Edge)
**Profile:** [`iot-edge-01.sh.example`](iot-edge-01.sh.example)

**The Challenge:** An IoT device behind a strict physical firewall cannot accept inbound SSH. Instead, it maintains a reverse SSH tunnel *out* to an Azure Relay server. You must SSH into the Relay Server, and then pivot backward into the Edge device's reverse tunnel.
**The Config Addition:** Define `iot-edge-01` in your `BASTION_VMS` array. Map `VM_PROPS["iot-edge-01_relay_ip"]` and `VM_PROPS["iot-edge-01_reverse_port"]`.

```text
                                  [IoT Edge Device]
                                          |
                                (Outbound Reverse Tunnel)
                                          |
  [Local Machine]                 [Azure Relay Server]
         |                                |
  (1. az network bastion tunnel)          |
         |                                |
         +--------------------------------+
             (2. ssh -p 4444 localhost)
```

### Scenario 4: VM Scale Set behind a Public IP resource
**Profile:** [`vmss-public-ip.sh.example`](vmss-public-ip.sh.example)

**The Challenge:** The alias points at a name that is **not** a standalone VM — it is
a VM Scale Set (VMSS), and its reachable address lives on a dedicated Public IP
resource of the same name (often a load-balancer front end). The classic
`az vm list-ip-addresses` returns **empty with exit code 0** for a VMSS or a bare
Public IP resource, so a naive profile silently ends up with no IP and the tunnel
fails for reasons that look unrelated.

**The Fix:** Use the shared [`resolve_target_ip()`](../docs/ip-resolution.md) helper
(defined in `.bashrc.d/30-azure_routing.sh`). It probes VM → VMSS → Public IP
resource types in order and returns the first hit, private-first by default (pass `1`
to prefer public). No hardcoding of resource type; results cached for 10h.

```text
  [Local Machine]
         |
  (1. resolve_target_ip: VM? VMSS? Public IP resource?)
         |
   [Public IP: x.x.x.x]  <-- VMSS front end
         |
  (2. az ssh vm --ip x.x.x.x)
         |
     [VMSS instance]
```

See [docs/ip-resolution.md](../docs/ip-resolution.md) for the full resolution order,
caching behavior, and troubleshooting steps.
