# ==============================================================================
# 3. Azure Topology Database (Dynamic Configuration)
# Decouples sensitive data from logic so this script can be safely versioned.
# ==============================================================================

# Support loading the topology from either the git root (for dev) or the home directory (production)
if [[ -f "${PWD}/.bastion_topology.conf" ]]; then
    TOPOLOGY_FILE="${PWD}/.bastion_topology.conf"
elif [[ -f "${HOME}/.bastion_topology.conf" ]]; then
    TOPOLOGY_FILE="${HOME}/.bastion_topology.conf"
else
    echo "WARNING: Topology file not found in ${PWD} or ${HOME}"
    echo "Please copy .bastion_topology.conf.example to your home directory and configure it."
    # Prevent execution of dependent functions if config is missing
    return 1
fi

# Load the declarative data
source "${TOPOLOGY_FILE}"

declare -A VM_NAME VM_RG VM_SUB VM_PORT VM_TYPE VM_AUTOSTART VM_AUTH

# Parse the BASTION_VMS array and populate the associative arrays and aliases
for vm_entry in "${BASTION_VMS[@]}"; do
    IFS='|' read -r short az_name rg sub port type autostart auth <<< "${vm_entry}"
    
    # Skip comments and empty lines
    [[ "${short}" =~ ^#.*$ || -z "${short}" ]] && continue

    # Trim carriage returns (Windows compat) and enforce lowercase for validation
    type=$(echo "${type}" | tr -d '\r')
    type="${type,,}"

    autostart=$(echo "${autostart}" | tr -d '\r')
    autostart="${autostart,,}"

    auth=$(echo "${auth}" | tr -d '\r')
    auth="${auth,,}"

    # Default autostart to true if empty
    autostart=${autostart:-true}

    # Default auth to ssh if empty
    auth=${auth:-ssh}

    VM_NAME[$short]=$az_name
    VM_RG[$short]=$rg
    VM_SUB[$short]=$sub
    VM_PORT[$short]=$port
    VM_TYPE[$short]=${type}
    VM_AUTOSTART[$short]=${autostart}
    VM_AUTH[$short]=${auth}

    alias start${short}="az vm start --resource-group ${rg} --name ${az_name}"
    alias stop${short}="az vm deallocate --resource-group ${rg} --name ${az_name}"
done

# ==============================================================================
# 4. Helper Functions
# ==============================================================================

function get_vmid(){
    local rg=${1}
    local name=${2}
    local CACHE_FILE="${HOME}/.bastion_vmid_cache_${name}"
    local CACHE_EXPIRY=$(( 10 * 3600 )) # 10 hours in seconds
    local CURRENT_TIME=$(date +%s)
    local vmid=""

    # Check cache first
    if [[ -f "$CACHE_FILE" ]]; then
        read -r cache_time cached_vmid < "$CACHE_FILE"
        if (( CURRENT_TIME - cache_time < CACHE_EXPIRY )) && [[ -n "$cached_vmid" ]]; then
            echo "$cached_vmid"
            return
        fi
    fi

    # Cache miss or expired, fetch from Azure
    vmid=$(az vm show \
        -g "${rg}" \
        -n "${name}" \
        --query id -o tsv)
    
    if [[ -n "$vmid" ]]; then
        echo "${CURRENT_TIME} ${vmid}" > "$CACHE_FILE"
        echo "${vmid}"
    fi
}



function az_subscription(){
    local verb=${1}; shift
    local noun="${@}"
    if [[ "${verb,,}" == "get" ]]; then
        noun=$(az account show --query name -o tsv 2>/dev/null)
        echo "${noun}"
    elif [[ "${verb,,}" == "set" ]]; then
        # FAST-PATH: Only switch subscriptions if we aren't already on the target one
        local current_sub=$(az account show --query name -o tsv 2>/dev/null | tr -d '\r')
        if [[ "$current_sub" != "$noun" ]]; then
            echo "Switching Azure context to subscription: ${noun}..."
            az account set --subscription "${noun}"
        fi
    fi
}

# Show available environments based on dictionary data
function list_vms() {
    echo "Available VMs mapped in: ${TOPOLOGY_FILE}"
    echo "To add or modify VMs, edit your local topology configuration file."
    echo "Format: alias|azure_name|resource_group|subscription|port|type|autostart|auth_type"
    echo ""
    printf "%-10s | %-12s | %-10s | %-10s | %-10s | %-30s | %-35s\n" "ALIAS" "TYPE" "PORT" "AUTOSTART" "AUTH" "RESOURCE GROUP" "AZURE NAME"
    printf -- "-%.0s" {1..130}
    echo ""
    for short in "${!VM_NAME[@]}"; do
        printf "%-10s | %-12s | %-10s | %-10s | %-10s | %-30s | %-35s\n" \
            "$short" "${VM_TYPE[$short]}" "${VM_PORT[$short]}" "${VM_AUTOSTART[$short]}" "${VM_AUTH[$short]}" "${VM_RG[$short]}" "${VM_NAME[$short]}"
    done
}

# Show active connection status
function list_connections() {
    echo "Active Bastion & SSH Connections:"
    echo ""
    printf "%-10s | %-22s | %-10s | %-15s | %-35s | %-20s\n" "ALIAS" "CONN TYPE" "PORT" "STATUS" "AZURE NAME" "FWD PORTS"
    printf -- "-%.0s" {1..124}
    echo ""
    for short in "${!VM_NAME[@]}"; do
        local port="${VM_PORT[$short]}"
        local az_name="${VM_NAME[$short]}"
        local vtype="${VM_TYPE[$short]}"
        local status="Offline"
        local fwd_ports_disp="-"
        local conn_type="${vtype}"



        # Check for standard bastion tunnel
        if ps -ef | grep -v grep | grep "az network bastion tunnel" | grep -q "port ${port}"; then
            status="Active"
        fi

        # Check for registered forward ports
        local port_file="${HOME}/.bastion_fwd_ports_${short}"
        if [[ -f "$port_file" ]]; then
            local active_ports=$(<"$port_file")
            fwd_ports_disp="$active_ports"

            # Since az ssh vm connects to an IP, az_name is NOT in the process list.
            # We verify it's active by checking if its forwarded ports exist in ps -ef.
            for p in $active_ports; do
                if ps -ef | grep -v grep | grep -E -q " ${p}(:| )"; then
                    status="Active"
                    break
                fi
            done
        fi

        printf "%-10s | %-22s | %-10s | %-15s | %-35s | %-20s\n" \
            "$short" "$conn_type" "$port" "$status" "$az_name" "$fwd_ports_disp"
    done
}

# Cleanup active connections/tunnels
function cleanup_tunnels() {
    local target=$1
    if [[ -z "$target" ]]; then
        echo "Usage: cleanup_tunnels <alias|all>"
        echo ""
        list_connections
        return 1
    fi

    if [[ "${target,,}" == "all" ]]; then
        echo "Cleaning up ALL SSH and Bastion tunnels..."
        local pids=$(ps -ef | grep -v grep | grep -E "az network bastion tunnel|az ssh vm|plink\.exe.*-L" | awk '{print $2}')
        if [[ -n "$pids" ]]; then
            echo "$pids" | xargs kill -9 2>/dev/null
        fi
        rm -f "${HOME}/.bastion_fwd_ports_"*
        echo "Done."
        return 0
    fi

    if [[ -n "${VM_PORT[$target]}" ]]; then
        local port="${VM_PORT[$target]}"
        local az_name="${VM_NAME[$target]}"
        echo "Cleaning up tunnels for ${target}..."

        # Kill az network bastion for this port
        local bpids=$(ps -ef | grep -v grep | grep "az network bastion tunnel" | grep "port ${port}" | awk '{print $2}')
        if [[ -n "$bpids" ]]; then
            echo "$bpids" | xargs kill -9 2>/dev/null
        fi

        # Kill az ssh vm for this target
        local spids=$(ps -ef | grep -v grep | grep "az ssh vm" | grep "${az_name}" | awk '{print $2}')
        if [[ -n "$spids" ]]; then
            echo "$spids" | xargs kill -9 2>/dev/null
        fi

        # Clean up any dynamically registered forwarded ports
        local port_file="${HOME}/.bastion_fwd_ports_${target}"
        if [[ -f "$port_file" ]]; then
            local active_ports=$(<"$port_file")
            for p in $active_ports; do
                local ppids=$(ps -ef | grep -v grep | grep -E " ${p}(:| )" | awk '{print $2}')
                if [[ -n "$ppids" ]]; then
                    echo "$ppids" | xargs kill -9 2>/dev/null
                fi
            done
            rm -f "$port_file"
        fi

        echo "Done."
    else
        echo "Error: Unknown VM '$target'."
        return 1
    fi
}

# ==============================================================================
# 5. Core Bastion Function
# ==============================================================================

function bastion(){
    local vm=$1
    local mode=${2,,} # Optional second argument (e.g., 'ssh' or 'interactive')

    # If no arguments provided, show help and available VMs gracefully without an error
    if [[ -z "$vm" ]]; then
        echo "================================================================================"
        echo "                              BASTION MANAGER"
        echo "================================================================================"
        echo "Usage: bastion <alias> [ssh]"
        echo ""
        echo "  <alias> : Connects to the host (usually backgrounds to set up port forwards)"
        echo "  ssh     : Optional. Bypasses the background tunnel and drops you into a fully"
        echo "            interactive SSH session. (Supports Entra ID / AAD authentication!)"
        echo "            Example: bastion secvdi ssh"
        echo ""
        echo "Related Commands:"
        echo "  list_vms         : Shows all configured VMs and their routing settings"
        echo "  list_connections : Shows all active background tunnels and forwarded ports"
        echo "  cleanup_tunnels  : Closes active connections (Usage: cleanup_tunnels <alias|all>)"
        echo "================================================================================"
        echo ""
        list_vms
        return 0
    fi

    # Validate VM exists in our table
    if [[ -z "${VM_NAME[$vm]}" ]]; then
        echo "Error: Unknown VM '$vm'."
        list_vms
        return 1
    fi

    # Export mode so profile scripts can read it
    export BASTION_MODE="$mode"

    local az_name="${VM_NAME[$vm]}"
    local rg="${VM_RG[$vm]}"
    local sub="${VM_SUB[$vm]}"
    local port="${VM_PORT[$vm]}"
    local vtype="${VM_TYPE[$vm]}"
    local autostart_flag="${VM_AUTOSTART[$vm]}"
    local auth_flag="${VM_AUTH[$vm]}"
    
    # Retrieve dynamic bastion name from config, fallback to default generic name
    local bastion_name="${VM_PROPS[${vm}_bastion_name]:-${VM_PROPS[global_default_bastion]:-bst-default-region-01}}"
    local bastion_rg="${VM_PROPS[${vm}_bastion_rg]:-${rg}}"

    # Determine the SSH identity to use.
    # We do NOT overwrite the global $USER variable, as MSYS2/Linux uses it heavily.
    # Instead, we define a scoped variable for the SSH target username.
    local SSH_TARGET_USER=""
    
    # Check if the user is overriding the identity via environment variable (e.g. BASTION_USER="root" bastion api0)
    if [[ -n "$BASTION_USER" ]]; then
        SSH_TARGET_USER="$BASTION_USER"
    elif [[ "$auth_flag" == "entra" ]]; then
        SSH_TARGET_USER="${AZ_USERNAME:-$USER}"
    elif [[ -n "$auth_flag" && "$auth_flag" != "ssh" ]]; then
        SSH_TARGET_USER="$auth_flag"
    else
        SSH_TARGET_USER="azureuser"
    fi

    echo "Selected VM: ${az_name} (Type: ${vtype}, Port: ${port}, Autostart: ${autostart_flag}, Auth: ${auth_flag}, User: ${SSH_TARGET_USER})"

    # Export authentication type so profile scripts can use it
    export VM_AUTH_TYPE="$auth_flag"

    # Set subscription
    az_subscription set "${sub}"

    if [[ "${autostart_flag,,}" != "false" && "${autostart_flag,,}" != "no" ]]; then
        # FAST-PATH: If the local port is bound, or an active az ssh tunnel exists, 
        # the VM is almost certainly running. Skip the brutal Azure API query.
        if netstat -an | egrep -q "(127.0.0.1|0.0.0.0):${port}.*LISTEN" || [[ "$(ps -ef | grep "az ssh vm" | grep "${az_name}" | wc -l)" -gt 0 ]]; then
            echo "${vm} tunnel detected in background. Skipping Azure power state check..."
        else
            echo "Checking to see if ${az_name} is running.. this may take a hot minute..."
            local running
            running=$(az vm show -d -g "${rg}" --name "${az_name}" --query "powerState" -o tsv 2>/dev/null || echo "VM stopped")

            if [[ "${running,,}" == *"stopped"* ]]; then
                echo "Launching ${vm} (${az_name})..."
                az vm start -g "${rg}" -n "${az_name}"
            else
                echo "${vm} (${az_name}) already running..."
            fi
        fi
    else
        echo "Autostart disabled for ${vm}, assuming it is already running..."
    fi

    # ==========================================================================
    # Connection Logic (Unified Routing Engine)
    # ==========================================================================
    
    # Check if we need to append dynamic SSH port forwarding (-L) arguments.
    # This treats port forwarding as an orthogonal feature to the base topology.
    local dynamic_ssh_args=()
    if [[ -n "${VM_PROPS[${vm}_az_tunnels]}" ]]; then
        for tunnel in ${VM_PROPS[${vm}_az_tunnels]}; do
            dynamic_ssh_args+=("-L" "$tunnel")
        done
        # Register forwarded ports for future cleanup
        if [[ -n "${VM_PROPS[${vm}_fwd_ports]}" ]]; then
            echo "${VM_PROPS[${vm}_fwd_ports]}" > "${HOME}/.bastion_fwd_ports_${vm}"
        fi
    fi

    # Check if we need to launch a background subshell for nested routing.
    local subshell_cmd="${BASTION_SUBSHELL_CMD:-plink}"
    local dynamic_subshell_args=()
    
    if [[ -n "${VM_PROPS[${vm}_plink_tunnels]}" ]]; then
        # Default entry port is 2022, but allow override
        local entry_port="${VM_PROPS[${vm}_plink_entry_port]:-2022}"
        
         if [[ "${subshell_cmd}" == *plink.exe ]]; then
             dynamic_subshell_args=("-P" "${entry_port}" "-N" "-batch" "-agent" "${SSH_TARGET_USER}@localhost")
         else
             # Native ssh fallback for Linux/macOS
             dynamic_subshell_args=("-p" "${entry_port}" "-N" "-o" "StrictHostKeyChecking=no" "${SSH_TARGET_USER}@localhost")
        fi
        
        for tunnel in ${VM_PROPS[${vm}_plink_tunnels]}; do
            dynamic_subshell_args+=("-L" "$tunnel")
        done
    fi

    case "${vtype}" in
        
        "flat")
            # ------------------------------------------------------------------
            # ENGINE: Flat Topology (Standard Azure Bastion Tunnel)
            # Local -> Azure Bastion -> Target VM
            # ------------------------------------------------------------------
            
            # 1. Ensure background port-forwarding tunnel is running
            local tunnel_was_running="false"
            
            # Use netstat to check if the specific port is already bound locally (LISTENING)
            # This is vastly more reliable than parsing the MSYS2 ps process tree for python.exe arguments
                if netstat -an | egrep -q "(127.0.0.1|0.0.0.0):${port}.*LISTEN"; then
                echo "Bastion for ${vm} port forwarding is already running using port ${port}"
                echo "${port}" > "${HOME}/.bastion_fwd_ports_${vm}"
                tunnel_was_running="true"
            else
                local VMID=$(get_vmid "${rg}" "${az_name}")
                echo "Creating bastion tunnel using local port ${port}"
                echo "${port}" > "${HOME}/.bastion_fwd_ports_${vm}"

                az network bastion tunnel \
                    --name "${bastion_name}" \
                    --resource-group "${bastion_rg}" \
                    --target-resource-id "${VMID}" \
                    --resource-port 22 \
                    --port "${port}" > /dev/null 2>&1 &
            fi

            # 2. If 'ssh' mode was requested, open interactive shell
            if [[ "$BASTION_MODE" == "ssh" ]]; then
                echo "Mode: SSH Interactive. Establishing connection to ${az_name} via Bastion..."
                
                # Fast-path: Wait actively for the tunnel port to open instead of a dumb sleep
                if [[ "$tunnel_was_running" == "true" ]]; then
                    echo "Tunnel already established. Connecting immediately..."
                else
                    echo "Waiting for new tunnel to stabilize on port ${port}..."
                    local attempts=0
                    while ! netstat -an | egrep -q "(127.0.0.1|0.0.0.0):${port}.*LISTEN"; do
                        if (( attempts > 15 )); then
                            echo "Warning: Tunnel didn't seem to stabilize after 15 seconds. Attempting SSH anyway..."
                            break
                        fi
                        sleep 1
                        ((attempts++))
                    done
                fi
                
                # Apply dynamic forwarding args if defined
                ssh -p "${port}" "${dynamic_ssh_args[@]}" -o StrictHostKeyChecking=no "${SSH_TARGET_USER}@localhost"
            fi
            ;;

        "flat-entra")
            # ------------------------------------------------------------------
            # ENGINE: Flat Topology (Entra ID Auth / AAD Token)
            # ------------------------------------------------------------------
            local VMID=$(get_vmid "${rg}" "${az_name}")
            
            # Note: For Entra ID, we generally don't background the Bastion tunnel 
            # if we are doing direct SSH because `az network bastion ssh` handles both.
            # However, if we need port forwarding without an interactive shell, 
            # we must fall back to the standard tunnel mechanism.
            
            if [[ "$BASTION_MODE" == "ssh" ]]; then
                echo "Mode: SSH Interactive. Establishing connection to ${az_name} via Entra ID Bastion..."
                
                # Unfortunately, `az network bastion ssh` does not support passing arbitrary -L flags natively.
                # If we have dynamic_ssh_args, we cannot easily use the native wrapper. 
                # (A known limitation of the Azure CLI Entra ID implementation).
                if [[ ${#dynamic_ssh_args[@]} -gt 0 ]]; then
                    echo "WARNING: Dynamic port forwards (-L) are not supported natively by 'az network bastion ssh'."
                    echo "Traffic will not be forwarded. Use standard 'flat' or 'tiered' topologies for advanced routing."
                fi

                az network bastion ssh \
                    --name "${bastion_name}" \
                    --resource-group "${bastion_rg}" \
                    --target-resource-id "${VMID}" \
                    --auth-type AAD \
                    --username "${SSH_TARGET_USER}"
            else
                # Background Mode
                local tunnel_was_running="false"
            if netstat -an | egrep -q "(127.0.0.1|0.0.0.0):${port}.*LISTEN"; then
                    echo "Bastion for ${vm} port forwarding is already running using port ${port}"
                    echo "${port}" > "${HOME}/.bastion_fwd_ports_${vm}"
                    tunnel_was_running="true"
                else
                    echo "Mode: Background Tunnel. Establishing connection to ${az_name} on local port ${port}..."
                    echo "${port}" > "${HOME}/.bastion_fwd_ports_${vm}"

                    az network bastion tunnel \
                        --name "${bastion_name}" \
                        --resource-group "${bastion_rg}" \
                        --target-resource-id "${VMID}" \
                        --resource-port 22 \
                        --port "${port}" > /dev/null 2>&1 &
                fi
            fi
            ;;

        "tiered")
            # ------------------------------------------------------------------
            # ENGINE: Tiered Topology (Direct IP Routing + Jumpbox)
            # Local -> az ssh vm -> Jumpbox IP
            # ------------------------------------------------------------------
            local CACHE_FILE="${HOME}/.bastion_ip_cache_${vm}"
            local CURRENT_TIME=$(date +%s)
            local CACHE_EXPIRY=36000 # 10 hours in seconds
            local jumpbox_ip=""

            if [[ -f "$CACHE_FILE" ]]; then
                read -r cache_time cached_ip < "$CACHE_FILE"
                # Check if the cache is younger than 10 hours and not empty
                if (( CURRENT_TIME - cache_time < CACHE_EXPIRY )) && [[ -n "$cached_ip" ]]; then
                    jumpbox_ip="$cached_ip"
                    echo "Using cached IP address for ${az_name}: ${jumpbox_ip}"
                fi
            fi

            if [[ -z "$jumpbox_ip" ]]; then
                echo "Obtaining IP address of ${az_name} from Azure... this may take a minute..."
                jumpbox_ip=$(az vm list-ip-addresses -g "${rg}" -n "${az_name}" \
                    --query "[].virtualMachine.network.publicIpAddresses[].ipAddress" -o tsv)
                
                # Strip potential carriage returns
                jumpbox_ip=$(echo "$jumpbox_ip" | tr -d '\r')

                if [[ -n "$jumpbox_ip" ]]; then
                    echo "${CURRENT_TIME} ${jumpbox_ip}" > "$CACHE_FILE"
                else
                    echo "Error: Failed to retrieve IP address for ${az_name}."
                    return 1
                fi
            fi

            local az_ssh_args=("-o" "StrictHostKeyChecking=no")
            
            # Combine base args with our orthogonally defined dynamic args
            az_ssh_args+=("${dynamic_ssh_args[@]}")

            # 3. Execute Tiered Connections
            if [[ "$BASTION_MODE" == "ssh" ]]; then
                echo "Mode: SSH Interactive. Establishing tiered connection to ${az_name}..."
                
                # Stand up subshell in background if defined
                if [[ ${#dynamic_subshell_args[@]} -gt 0 ]]; then
                    (
                        sleep 10
                        echo -e "\n--> [Subshell] Attempting to launch ${subshell_cmd} port forwards..."
                        "${subshell_cmd}" "${dynamic_subshell_args[@]}" > /dev/null 2>&1
                    ) &
                fi
                
                # Foreground the interactive SSH session
                az ssh vm --ip "${jumpbox_ip}" -- "${az_ssh_args[@]}"
                local ssh_exit=$?
                
                # Self-healing: If the connection drops or fails to connect, invalidate the IP cache
                if [ $ssh_exit -ne 0 ]; then
                    echo "Error: Connection dropped or failed (Exit code: $ssh_exit). Invalidating IP cache for ${vm}..."
                    rm -f "$CACHE_FILE"
                fi
            else
                echo "Mode: Background Tunnel. Establishing tiered connection to ${az_name}..."
                
                # Background the SSH session
                az_ssh_args+=("-N" "-T")
                az ssh vm --ip "${jumpbox_ip}" -- "${az_ssh_args[@]}" > /dev/null 2>&1 &
                local ssh_pid=$!
                
                echo "Waiting 5 seconds for Azure SSH tunnel to establish..."
                sleep 5
                
                # Check if the tunnel process is still alive after settling
                if kill -0 $ssh_pid 2>/dev/null; then
                    # Stand up subshell in background if defined
                    if [[ ${#dynamic_subshell_args[@]} -gt 0 ]]; then
                        "${subshell_cmd}" "${dynamic_subshell_args[@]}" > /dev/null 2>&1 &
                        echo "Tiered tunnels established successfully based on ${vm} profile."
                    else
                        echo "Tunnel established successfully."
                    fi
                else
                    echo "Error: az ssh vm failed to connect or dropped immediately. Invalidating IP cache for ${vm}..."
                    rm -f "$CACHE_FILE"
                fi
            fi
            ;;
            
        *)
            echo "Error: Unknown topology type '${vtype}' for VM '${vm}'."
            echo "Must be 'flat', 'flat-entra', or 'tiered'."
            return 1
            ;;
    esac
}

function sshbastion(){
    ssh -p ${1} -o StrictHostKeyChecking=no azureuser@localhost
}

# rsync -avSHP -e 'ssh -p 12022 -o StrictHostKeyChecking=no' --exclude='.git*' --exclude '.venv' --exclude '__pycache__' --exclude='debug.out' --delete ./ms_aipsr/ azureuser@localhost:~/git/aipsr/; rsync -avSHP -e 'ssh -p 11022 -o stricthostkeychecking=no' --exclude='.git*' --exclude '.venv' --exclude '__pycache__' --exclude='debug.out' --delete ./ms_aipsr azureuser@localhost:~/git/
#



# ==============================================================================
# 6. Profile Escape Hatch & Wrapper
# ==============================================================================
function connect-vm() {
    local target=$1
    local mode=$2

    if [[ -z "$target" ]]; then
        bastion ""
        return 0
    fi

    # Check for escape hatch profile
    local profile_path="${HOME}/.bastion_profiles/${target}.sh"
    
    if [[ -x "$profile_path" ]]; then
        echo "=> [Escape Hatch] Found executable profile: ${profile_path}"
        # Source the profile and run its connect function
        source "$profile_path"
        if type connect >/dev/null 2>&1; then
            connect "$mode"
        else
            echo "Error: Profile ${profile_path} does not define a connect() function."
            return 1
        fi
    elif [[ -f "$profile_path" ]]; then
        echo "Error: Profile ${profile_path} exists but is not executable. Please run: chmod +x ${profile_path}"
        return 1
    else
        # Fallback to core engine
        bastion "$target" "$mode"
    fi
}
