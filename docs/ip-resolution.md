# IP Resolution (`resolve_target_ip`)

How the bastion engine turns a topology **name** into a connectable **IP address**,
regardless of whether that name refers to a standalone VM, a VM Scale Set (VMSS),
or a bare Public IP resource.

- **Defined in:** [`.bashrc.d/30-azure_routing.sh`](../.bashrc.d/30-azure_routing.sh)
- **Documented example profile:** [`.bastion_profiles/vmss-public-ip.sh.example`](../.bastion_profiles/vmss-public-ip.sh.example)

---

## The Problem

The obvious way to get a VM's IP is:

```bash
az vm list-ip-addresses -g "$rg" -n "$name" \
    --query "[].virtualMachine.network.publicIpAddresses[].ipAddress" -o tsv
```

This works **only** when `$name` is a standalone `Microsoft.Compute/virtualMachines`
resource. In real Azure topologies a bastion alias frequently points at something else:

| What the name really is           | `az vm list-ip-addresses` result |
| --------------------------------- | -------------------------------- |
| Standalone VM                     | IP returned ✅                    |
| **VM Scale Set (VMSS)**           | **empty, exit code 0** ❌         |
| **Standalone Public IP resource** | **empty, exit code 0** ❌         |

The dangerous part is the **exit code 0**: the command *succeeds* while returning
nothing, so a naive profile silently ends up with an empty IP and every downstream
tunnel fails with confusing errors (`connection refused`, empty `--ip`, etc.) that
look like a `.bashrc` or network problem but are really a resource-type mismatch.

### Example: a jumpbox alias that became a scale set

Consider a `jbox` alias whose topology name is `vmss-jumpbox-01`. Over time that name became:

- **not** a VM (the VM was replaced by a scale set `vmss-jumpbox`), and
- **is** the name of a standalone static Public IP resource holding, say, `203.0.113.10`.

So `az vm list-ip-addresses` returned empty, and `bastion jbox` couldn't find an IP.
The fix was not to hardcode the resource type, but to **probe each type in order**.

> `203.0.113.x` is the [RFC 5737](https://datatracker.ietf.org/doc/html/rfc5737)
> documentation range — a stand-in for a real public IP. Use your own resource
> names and addresses; never commit live infrastructure details to the repo.

---

## The Solution

`resolve_target_ip()` walks the possible resource types and returns the first IP it
finds. Private addresses are preferred by default (most bastion/tunnel flows want the
internal IP); pass a flag to prefer public.

```bash
resolve_target_ip "<resource_group>" "<name>" [prefer_public]
```

| Argument         | Required | Meaning                                                      |
| ---------------- | -------- | ------------------------------------------------------------ |
| `resource_group` | yes      | The RG containing the resource.                              |
| `name`           | yes      | VM / VMSS / Public IP resource name (usually `$az_name`).    |
| `prefer_public`  | no       | `1` = try public IPs before private. Default `0` (private first). |

**Returns:** the resolved IP on `stdout`, exit `0`. If nothing resolves, prints a
diagnostic to `stderr` and returns non-zero.

### Resolution order

Default (private-first):

```
1. VM   private IP   (az vm list-ip-addresses  .privateIpAddresses)
2. VMSS private IP   (az vmss nic list          [0].privateIPAddress)
3. VM   public  IP   (az vm list-ip-addresses  .publicIpAddresses)
4. Public IP resource (az network public-ip show  .ipAddress)
```

With `prefer_public=1`:

```
1. VM   public  IP
2. Public IP resource
3. VM   private IP
4. VMSS private IP
```

The `name` is also tried as a VMSS by stripping a trailing `-NN` instance suffix
(e.g. `myscaleset-01` -> scale set `myscaleset`).

### Caching

Results are cached for **10 hours** in `~/.bastion_ip_cache_<name>`, mirroring the
existing `get_vmid()` cache. Delete the file to force a fresh lookup:

```bash
rm -f ~/.bastion_ip_cache_<name>
```

---

## Usage in a Profile

Prefer the helper over an inline `az` call so every profile benefits from the
type-probing and caching:

```bash
# Private-preferred (typical tiered / internal tunnel target)
target_ip=$(resolve_target_ip "${rg}" "${az_name}")

# Public-preferred (e.g. a VMSS front-end reached over its public IP, like jbox)
target_ip=$(resolve_target_ip "${rg}" "${az_name}" 1)

if [[ -z "${target_ip}" ]]; then
    echo "ERROR: could not resolve an IP for ${az_name} in ${rg}." >&2
    echo "       Check the name/RG in ~/.bastion_topology.conf." >&2
    return 1 2>/dev/null || exit 1
fi
```

See [`vmss-public-ip.sh.example`](../.bastion_profiles/vmss-public-ip.sh.example)
for a complete, copy-pasteable profile.

---

## Troubleshooting

**`bastion <alias>` connects with an empty / wrong IP.**

1. Resolve the IP by hand and watch which strategy wins:
   ```bash
   az vm list-ip-addresses -g "$rg" -n "$name" -o tsv          # standalone VM?
   az vmss list -g "$rg" --query "[].name" -o table            # is it a VMSS?
   az network public-ip show -g "$rg" -n "$name" --query ipAddress -o tsv
   ```
2. If only the last command returns an address, the name is a **Public IP
   resource / VMSS front-end** — use `resolve_target_ip "$rg" "$name" 1`.
3. Clear the cache if the resource's IP changed:
   ```bash
   rm -f ~/.bastion_ip_cache_<name>
   ```
4. Verify the name/RG in `~/.bastion_topology.conf` still match a live resource —
   VMs get renamed or replaced by scale sets over time.
