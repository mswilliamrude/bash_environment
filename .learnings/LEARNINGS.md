# Learnings

Corrections, insights, and knowledge gaps captured during development.

**Categories**: correction | insight | knowledge_gap | best_practice

---
## [LRN-$(date +%Y%m%d)-001] best_practice

**Logged**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Priority**: medium
**Status**: pending
**Area**: config

### Summary
When waiting for a background port forwarding tunnel to stabilize, use an active while-loop check with `netstat` instead of a static `sleep`.

### Details
Previously, the code used a naive `sleep 3` when waiting for an `az network bastion tunnel` to establish port forwarding before launching the SSH client. This is inefficient if the tunnel connects faster, and fails if it takes longer than 3 seconds.

### Suggested Action
Replaced the `sleep 3` with a while loop that checks `netstat -an | egrep -q "(127.0.0.1|0.0.0.0):${port}.*LISTEN"` every second, up to a 15-second timeout, before proceeding.

### Metadata
- Source: user_feedback
- Related Files: .bashrc.d/30-azure_routing.sh
- Tags: bash, optimization, azure-bastion

---
## [LRN-$(date +%Y%m%d)-002] optimization

**Logged**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Priority**: high
**Status**: pending
**Area**: config

### Summary
Cached the Azure VM Resource ID (`get_vmid`) for 10 hours to avoid slow `az vm show` lookups during `flat` and `flat-entra` connections.

### Details
The `flat` and `flat-entra` routing engines both call `get_vmid()` which executes an `az vm show --query id` command. This Azure API call is brutally slow. Even if the VM is running and the local tunnel port is cached, fetching the VMID blocks the entire connection sequence.

### Suggested Action
Modified the `get_vmid()` function in `.bashrc.d/30-azure_routing.sh` to use the same 10-hour UNIX timestamp caching mechanism (`~/.bastion_vmid_cache_<name>`) that we use for tiered IP lookups. Because an Azure VM's Resource ID never changes unless the VM is completely deleted and recreated, a 10-hour cache is extremely safe and saves ~5-10 seconds per connection.

### Metadata
- Source: user_feedback
- Related Files: .bashrc.d/30-azure_routing.sh
- Tags: bash, optimization, azure-cli

---
