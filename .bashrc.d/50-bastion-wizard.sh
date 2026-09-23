#!/usr/bin/env bash
# ==============================================================================
# 50-bastion-wizard.sh — Interactive TUI wizard for ~/.bastion_topology.conf
#
# Provides a dialog-based menu to add, edit, delete, and view VM entries
# in the bastion topology configuration file.
#
# Requires: dialog (pacman -S dialog)
# Usage:    bastion_wizard
# ==============================================================================

# ------------------------------------------------------------------------------
# Guard: only define if dialog is available
# ------------------------------------------------------------------------------
if ! command -v dialog &>/dev/null; then
    bastion_wizard() {
        echo "ERROR: 'dialog' is not installed."
        echo "       Run: pacman -S dialog   or re-run scripts/install.sh"
    }
    return 0
fi

# ==============================================================================
# Constants
# ==============================================================================
_BW_CONF="${HOME}/.bastion_topology.conf"
_BW_TMP=$(mktemp -d)
_BW_RESULT="${_BW_TMP}/result"
_BW_H=20
_BW_W=60

# Cleanup temp dir on exit
trap 'rm -rf "${_BW_TMP}"' EXIT

# ==============================================================================
# Helpers
# ==============================================================================

# _bw_conf_check — ensure the topology file exists before proceeding
_bw_conf_check() {
    if [[ ! -f "${_BW_CONF}" ]]; then
        dialog --title "No Config Found" --msgbox \
"\nNo topology file found at:\n\n  ${_BW_CONF}\n\nRun scripts/install.sh first, then\nedit the file to get started." \
            10 52
        return 1
    fi
    return 0
}

# _bw_input — single inputbox wrapper
# Usage: _bw_input <title> <prompt> <default>  →  sets _BW_VAL
_bw_input() {
    local title="$1" prompt="$2" default="$3"
    dialog --title "${title}" \
           --inputbox "${prompt}" \
           10 52 "${default}" 2>"${_BW_RESULT}"
    local rc=$?
    _BW_VAL=$(<"${_BW_RESULT}")
    return $rc
}

# _bw_radiolist — radio selection wrapper
# Usage: _bw_radiolist <title> <prompt> <default> item1 item2 ...  →  sets _BW_VAL
_bw_radiolist() {
    local title="$1" prompt="$2" default="$3"
    shift 3
    local items=()
    for item in "$@"; do
        if [[ "${item}" == "${default}" ]]; then
            items+=("${item}" "" "on")
        else
            items+=("${item}" "" "off")
        fi
    done
    dialog --title "${title}" \
           --radiolist "${prompt}" \
           12 52 "$#" "${items[@]}" 2>"${_BW_RESULT}"
    local rc=$?
    _BW_VAL=$(<"${_BW_RESULT}")
    return $rc
}

# _bw_parse_vms — parse BASTION_VMS from the conf into parallel arrays
# Populates: _BW_ALIASES, _BW_ENTRIES (alias → raw pipe string)
_bw_parse_vms() {
    _BW_ALIASES=()
    declare -gA _BW_ENTRIES=()
    declare -gA _BW_PROPS_RAW=()

    local in_vms=0 in_props=0
    while IFS= read -r line; do
        # Strip leading whitespace and carriage returns
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line//$'\r'/}"

        # Skip comments and empty lines
        [[ "${line}" =~ ^#.*$ || -z "${line}" ]] && continue

        # Detect array boundaries
        [[ "${line}" =~ ^BASTION_VMS=\( ]] && { in_vms=1; continue; }
        [[ "${line}" =~ ^declare\ -A\ VM_PROPS ]] && { in_vms=0; in_props=1; continue; }
        [[ $in_vms -eq 1 && "${line}" == ")" ]] && { in_vms=0; continue; }
        [[ $in_props -eq 1 && "${line}" == ")" ]] && { in_props=0; continue; }

        if [[ $in_vms -eq 1 ]]; then
            # Strip surrounding quotes and whitespace
            local entry="${line//\"/}"
            entry="${entry// /}"
            local alias="${entry%%|*}"
            [[ -z "${alias}" ]] && continue
            _BW_ALIASES+=("${alias}")
            _BW_ENTRIES["${alias}"]="${entry}"
        fi

        if [[ $in_props -eq 1 ]]; then
            # e.g. VM_PROPS["jbox_az_tunnels"]="2022:x.x.x.x:22"
            if [[ "${line}" =~ ^VM_PROPS\[\"([^\"]+)\"\]=\"(.*)\"$ ]]; then
                _BW_PROPS_RAW["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
            fi
        fi
    done < "${_BW_CONF}"
}

# _bw_field — extract a field by index (1-based) from a pipe-delimited entry
_bw_field() {
    local entry="$1" idx="$2"
    echo "${entry}" | cut -d'|' -f"${idx}"
}

# _bw_write_conf — rewrite ~/.bastion_topology.conf from current _BW_ENTRIES/_BW_PROPS_RAW
_bw_write_conf() {
    # Back up before every write
    cp "${_BW_CONF}" "${_BW_CONF}.bak"

    # Preserve everything above BASTION_VMS= and below VM_PROPS
    local header="" footer="" in_managed=0 past_props=0
    while IFS= read -r line; do
        local stripped="${line//$'\r'/}"
        if [[ "${stripped}" =~ ^BASTION_VMS=\( ]]; then
            in_managed=1
            continue
        fi
        if [[ $in_managed -eq 1 ]]; then
            # Skip until we're past the VM_PROPS block
            [[ "${stripped}" =~ ^declare\ -A\ VM_PROPS ]] && continue
            [[ "${stripped}" =~ ^VM_PROPS\[ ]] && continue
            if [[ "${stripped}" == ")" ]]; then
                past_props=1
                in_managed=0
                continue
            fi
            continue
        fi
        if [[ $past_props -eq 1 ]]; then
            footer+="${line}"$'\n'
        else
            header+="${line}"$'\n'
        fi
    done < "${_BW_CONF}"

    {
        # Write header (everything before BASTION_VMS)
        printf '%s' "${header}"

        # Write BASTION_VMS array
        echo 'BASTION_VMS=('
        for alias in "${_BW_ALIASES[@]}"; do
            echo "    \"${_BW_ENTRIES[${alias}]}\""
        done
        echo ')'
        echo ''

        # Write VM_PROPS
        echo 'declare -A VM_PROPS'
        echo ''
        for key in "${!_BW_PROPS_RAW[@]}"; do
            echo "VM_PROPS[\"${key}\"]=\"${_BW_PROPS_RAW[${key}]}\""
        done
        echo ''

        # Write footer (everything after the managed block)
        printf '%s' "${footer}"
    } > "${_BW_CONF}"
}

# ==============================================================================
# VM Field Collection (shared by Add and Edit)
# ==============================================================================
_bw_collect_fields() {
    local alias="$1" az_name="$2" rg="$3" sub="$4" \
          port="$5" vtype="$6" autostart="$7" auth="$8"

    # Step 1 — Alias
    _bw_input "Add VM (1/8) — Alias" \
        "\nShort name used in CLI commands\ne.g.  api0, jbox, secvdi" \
        "${alias}" || return 1
    alias="${_BW_VAL}"
    [[ -z "${alias}" ]] && { dialog --msgbox "\nAlias cannot be empty." 6 40; return 1; }

    # Step 2 — Azure VM Name
    _bw_input "Add VM (2/8) — Azure VM Name" \
        "\nExact Azure resource name\ne.g.  vm-api-dev-01" \
        "${az_name}" || return 1
    az_name="${_BW_VAL}"
    [[ -z "${az_name}" ]] && { dialog --msgbox "\nAzure VM name cannot be empty." 6 40; return 1; }

    # Step 3 — Resource Group
    _bw_input "Add VM (3/8) — Resource Group" \
        "\nAzure Resource Group containing this VM\ne.g.  rg-project-dev" \
        "${rg}" || return 1
    rg="${_BW_VAL}"
    [[ -z "${rg}" ]] && { dialog --msgbox "\nResource Group cannot be empty." 6 40; return 1; }

    # Step 4 — Subscription
    _bw_input "Add VM (4/8) — Subscription" \
        "\nAzure Subscription name\ne.g.  Sub_Dev_Environment" \
        "${sub}" || return 1
    sub="${_BW_VAL}"
    [[ -z "${sub}" ]] && { dialog --msgbox "\nSubscription cannot be empty." 6 40; return 1; }

    # Step 5 — Port (with validation + duplicate check)
    while true; do
        _bw_input "Add VM (5/8) — Local Port" \
            "\nLocal port for the tunnel (1024-65535)\nMust be unique across all VM entries\ne.g.  12022" \
            "${port}" || return 1
        port="${_BW_VAL}"

        if ! [[ "${port}" =~ ^[0-9]+$ ]] || (( port < 1024 || port > 65535 )); then
            dialog --msgbox "\nPort must be a number between 1024 and 65535." 6 48
            continue
        fi

        # Check for port collision (skip collision check if editing same alias)
        local collision=0
        for a in "${_BW_ALIASES[@]}"; do
            [[ "${a}" == "${alias}" ]] && continue
            local existing_port
            existing_port=$(_bw_field "${_BW_ENTRIES[${a}]}" 5)
            if [[ "${existing_port}" == "${port}" ]]; then
                dialog --msgbox "\nPort ${port} is already used by '${a}'.\nPlease choose a different port." 7 48
                collision=1
                break
            fi
        done
        [[ $collision -eq 0 ]] && break
    done

    # Step 6 — Topology Type
    _bw_radiolist "Add VM (6/8) — Topology Type" \
        "\nSelect the routing topology:" \
        "${vtype:-flat}" flat flat-entra tiered || return 1
    vtype="${_BW_VAL}"

    # Step 7 — Autostart
    _bw_radiolist "Add VM (7/8) — Autostart" \
        "\nStart VM automatically if stopped?" \
        "${autostart:-true}" true false || return 1
    autostart="${_BW_VAL}"

    # Step 8 — Auth Type
    _bw_radiolist "Add VM (8/8) — Auth Type" \
        "\nSSH identity / authentication method:" \
        "${auth:-ssh}" ssh entra custom || return 1
    auth="${_BW_VAL}"

    if [[ "${auth}" == "custom" ]]; then
        _bw_input "Add VM (8/8) — Custom Username" \
            "\nEnter the SSH username to use:" \
            "" || return 1
        auth="${_BW_VAL}"
        [[ -z "${auth}" ]] && auth="azureuser"
    fi

    # --- Optional: Port Forwards ---
    local az_tunnels="" plink_tunnels="" plink_entry_port="" fwd_ports=""
    local fwd_user="" fwd_identity=""
    local bastion_name_override="" bastion_rg_override=""
    local existing_az_tunnels="${_BW_PROPS_RAW["${alias}_az_tunnels"]:-}"
    local existing_plink_tunnels="${_BW_PROPS_RAW["${alias}_plink_tunnels"]:-}"
    local existing_plink_entry="${_BW_PROPS_RAW["${alias}_plink_entry_port"]:-2022}"
    local existing_fwd_user="${_BW_PROPS_RAW["${alias}_fwd_user"]:-}"
    local existing_fwd_identity="${_BW_PROPS_RAW["${alias}_fwd_identity"]:-}"
    local existing_bastion_name="${_BW_PROPS_RAW["${alias}_bastion_name"]:-}"
    local existing_bastion_rg="${_BW_PROPS_RAW["${alias}_bastion_rg"]:-}"

    # --- Bastion overrides (all topology types) ---
    _bw_input "Bastion Override (optional)" \
        "\nAzure Bastion resource name for this VM.\nOnly needed if this VM is NOT reachable via\nthe global default Bastion — e.g. it lives in\na separate subscription or secure environment.\nLeave blank to use global_default_bastion." \
        "${existing_bastion_name}" || return 1
    bastion_name_override="${_BW_VAL}"

    if [[ -n "${bastion_name_override}" ]]; then
        _bw_input "Bastion RG Override (optional)" \
            "\nResource Group containing the Bastion above.\nOnly needed if the Bastion lives in a different\nRG than the VM itself.\nLeave blank to use this VM's resource group." \
            "${existing_bastion_rg}" || return 1
        bastion_rg_override="${_BW_VAL}"
    fi

    if [[ "${vtype}" == "flat" || "${vtype}" == "flat-entra" || "${vtype}" == "tiered" ]]; then
        _bw_input "Port Forwards (optional)" \
            "\nSSH -L mappings injected into the Bastion tunnel.\nExposes private network services (DBs, APIs)\non localhost without a separate tunnel step.\nFormat: local_port:remote_ip:remote_port\ne.g.  5432:10.0.1.5:5432 6379:10.0.1.6:6379\nLeave blank to skip." \
            "${existing_az_tunnels}" || return 1
        az_tunnels="${_BW_VAL}"
    fi

    # fwd_user / fwd_identity only relevant for flat-entra (port-forward SSH
    # needs a different identity than the Entra interactive session)
    if [[ "${vtype}" == "flat-entra" && -n "${az_tunnels}" ]]; then
        _bw_input "Port Forward User (optional)" \
            "\nSSH username for the port-forward session.\nflat-entra VMs use Entra ID (AAD) for the\ninteractive session, but port-forward SSH\nneeds a regular key-based identity — which\nmay have a different username format.\ne.g.  user@contoso.com\nLeave blank to use the VM auth setting." \
            "${existing_fwd_user}" || return 1
        fwd_user="${_BW_VAL}"

        _bw_input "Port Forward Identity (optional)" \
            "\nPath to SSH private key for the port-forward\nsession. Only needed if the key for port\nforwarding differs from your ssh-agent default.\nSupports ~ expansion.\ne.g.  ~/.ssh/id_entra\nLeave blank to use ssh-agent default." \
            "${existing_fwd_identity}" || return 1
        fwd_identity="${_BW_VAL}"
    fi

    if [[ "${vtype}" == "tiered" ]]; then
        _bw_input "Plink Tunnels (optional)" \
            "\nDeep subshell tunnel mappings injected into\nthe background plink process. Use this to reach\nhosts only accessible FROM the jumpbox — not\ndirectly via Bastion.\nFormat: local_port:remote_ip:remote_port\ne.g.  2023:192.168.1.25:22 8443:172.16.30.2:443\nLeave blank to skip." \
            "${existing_plink_tunnels}" || return 1
        plink_tunnels="${_BW_VAL}"

        _bw_input "Plink Entry Port (optional)" \
            "\nPort that plink uses to enter the jumpbox for\nthe subshell tunnel session. Only change this\nif the jumpbox SSH port forwarded by az_tunnels\nis not 2022.\nDefault: 2022" \
            "${existing_plink_entry}" || return 1
        plink_entry_port="${_BW_VAL:-2022}"
    fi

    # Build fwd_ports from az_tunnels + plink_tunnels (extract local ports)
    if [[ -n "${az_tunnels}" || -n "${plink_tunnels}" ]]; then
        local all_tunnels="${az_tunnels} ${plink_tunnels}"
        fwd_ports=""
        for t in $all_tunnels; do
            local lp="${t%%:*}"
            [[ -n "${lp}" ]] && fwd_ports+="${lp} "
        done
        fwd_ports="${fwd_ports% }"
    fi

    # --- Confirm ---
    local confirm_text="\n"
    confirm_text+="  alias       : ${alias}\n"
    confirm_text+="  vm name     : ${az_name}\n"
    confirm_text+="  rg          : ${rg}\n"
    confirm_text+="  sub         : ${sub}\n"
    confirm_text+="  port        : ${port}\n"
    confirm_text+="  type        : ${vtype}\n"
    confirm_text+="  autostart   : ${autostart}\n"
    confirm_text+="  auth        : ${auth}\n"
    [[ -n "${bastion_name_override}" ]] && confirm_text+="  bastion     : ${bastion_name_override}\n"
    [[ -n "${bastion_rg_override}" ]]   && confirm_text+="  bastion rg  : ${bastion_rg_override}\n"
    [[ -n "${az_tunnels}" ]]            && confirm_text+="  tunnels     : ${az_tunnels}\n"
    [[ -n "${fwd_user}" ]]             && confirm_text+="  fwd user    : ${fwd_user}\n"
    [[ -n "${fwd_identity}" ]]         && confirm_text+="  fwd key     : ${fwd_identity}\n"
    [[ -n "${plink_tunnels}" ]]         && confirm_text+="  plink       : ${plink_tunnels}\n"
    [[ -n "${plink_entry_port}" && "${plink_entry_port}" != "2022" ]] && \
                                          confirm_text+="  plink port  : ${plink_entry_port}\n"
    confirm_text+="\n  Write to ~/.bastion_topology.conf?"

    dialog --title "Confirm Entry" --yesno "${confirm_text}" 22 60 || return 1

    # --- Commit to in-memory state ---
    # Remove old alias entry if editing (alias may have changed)
    local new_aliases=()
    for a in "${_BW_ALIASES[@]}"; do
        [[ "${a}" == "${alias}" ]] || new_aliases+=("${a}")
    done
    new_aliases+=("${alias}")
    _BW_ALIASES=("${new_aliases[@]}")

    _BW_ENTRIES["${alias}"]="${alias}|${az_name}|${rg}|${sub}|${port}|${vtype}|${autostart}|${auth}"

    # Clear all existing props for this alias before re-setting
    for key in "${!_BW_PROPS_RAW[@]}"; do
        [[ "${key}" == "${alias}_"* ]] && unset "_BW_PROPS_RAW[${key}]"
    done

    # Re-set props from collected values
    [[ -n "${az_tunnels}" ]]            && _BW_PROPS_RAW["${alias}_az_tunnels"]="${az_tunnels}"
    [[ -n "${fwd_user}" ]]             && _BW_PROPS_RAW["${alias}_fwd_user"]="${fwd_user}"
    [[ -n "${fwd_identity}" ]]         && _BW_PROPS_RAW["${alias}_fwd_identity"]="${fwd_identity}"
    [[ -n "${plink_tunnels}" ]]         && _BW_PROPS_RAW["${alias}_plink_tunnels"]="${plink_tunnels}"
    [[ -n "${fwd_ports}" ]]             && _BW_PROPS_RAW["${alias}_fwd_ports"]="${fwd_ports}"
    [[ -n "${bastion_name_override}" ]] && _BW_PROPS_RAW["${alias}_bastion_name"]="${bastion_name_override}"
    [[ -n "${bastion_rg_override}" ]]   && _BW_PROPS_RAW["${alias}_bastion_rg"]="${bastion_rg_override}"
    [[ -n "${plink_entry_port}" && "${plink_entry_port}" != "2022" ]] && \
        _BW_PROPS_RAW["${alias}_plink_entry_port"]="${plink_entry_port}"

    _bw_write_conf
    dialog --title "Saved" --msgbox "\nEntry '${alias}' saved to\n${_BW_CONF}" 8 52

    return 0
}

# ==============================================================================
# Main Menu Actions
# ==============================================================================

_bw_add() {
    _bw_collect_fields "" "" "" "" "" "flat" "true" "ssh"
}

_bw_edit() {
    if [[ ${#_BW_ALIASES[@]} -eq 0 ]]; then
        dialog --msgbox "\nNo VM entries found in config." 7 44
        return
    fi

    # Build menu list: alias  az_name
    local items=()
    for alias in "${_BW_ALIASES[@]}"; do
        local az_name
        az_name=$(_bw_field "${_BW_ENTRIES[${alias}]}" 2)
        items+=("${alias}" "${az_name}")
    done

    dialog --title "Edit VM — Select Alias" \
           --menu "\nChoose a VM entry to edit:" \
           16 52 8 "${items[@]}" 2>"${_BW_RESULT}" || return

    local selected
    selected=$(<"${_BW_RESULT}")

    local entry="${_BW_ENTRIES[${selected}]}"
    _bw_collect_fields \
        "$(_bw_field "${entry}" 1)" \
        "$(_bw_field "${entry}" 2)" \
        "$(_bw_field "${entry}" 3)" \
        "$(_bw_field "${entry}" 4)" \
        "$(_bw_field "${entry}" 5)" \
        "$(_bw_field "${entry}" 6)" \
        "$(_bw_field "${entry}" 7)" \
        "$(_bw_field "${entry}" 8)"
}

_bw_delete() {
    if [[ ${#_BW_ALIASES[@]} -eq 0 ]]; then
        dialog --msgbox "\nNo VM entries found in config." 7 44
        return
    fi

    local items=()
    for alias in "${_BW_ALIASES[@]}"; do
        local az_name
        az_name=$(_bw_field "${_BW_ENTRIES[${alias}]}" 2)
        items+=("${alias}" "${az_name}")
    done

    dialog --title "Delete VM — Select Alias" \
           --menu "\nChoose a VM entry to delete:" \
           16 52 8 "${items[@]}" 2>"${_BW_RESULT}" || return

    local selected
    selected=$(<"${_BW_RESULT}")
    local az_name
    az_name=$(_bw_field "${_BW_ENTRIES[${selected}]}" 2)

    dialog --title "Confirm Delete" \
           --yesno "\nDelete '${selected}' (${az_name})?\n\nThis will also remove all associated\nVM_PROPS entries." \
           10 52 || return

    # Remove from aliases array
    local new_aliases=()
    for a in "${_BW_ALIASES[@]}"; do
        [[ "${a}" == "${selected}" ]] || new_aliases+=("${a}")
    done
    _BW_ALIASES=("${new_aliases[@]}")
    unset "_BW_ENTRIES[${selected}]"

    # Remove all VM_PROPS for this alias
    for key in "${!_BW_PROPS_RAW[@]}"; do
        [[ "${key}" == "${selected}_"* ]] && unset "_BW_PROPS_RAW[${key}]"
    done

    _bw_write_conf
    dialog --msgbox "\n'${selected}' deleted from config." 7 44
}

_bw_show() {
    if [[ ${#_BW_ALIASES[@]} -eq 0 ]]; then
        dialog --msgbox "\nNo VM entries found in config." 7 44
        return
    fi

    local text="\n"
    printf -v header "  %-10s %-12s %-6s %-10s %s" "ALIAS" "TYPE" "PORT" "AUTH" "AUTOSTART"
    text+="${header}\n"
    text+="  $(printf '%.0s─' {1..52})\n"

    for alias in "${_BW_ALIASES[@]}"; do
        local entry="${_BW_ENTRIES[${alias}]}"
        local vtype port auth autostart
        vtype=$(_bw_field "${entry}" 6)
        port=$(_bw_field "${entry}" 5)
        auth=$(_bw_field "${entry}" 8)
        autostart=$(_bw_field "${entry}" 7)
        printf -v row "  %-10s %-12s %-6s %-10s %s" \
            "${alias}" "${vtype}" "${port}" "${auth}" "${autostart}"
        text+="${row}\n"

        # Show any VM_PROPS for this alias
        for key in "${!_BW_PROPS_RAW[@]}"; do
            if [[ "${key}" == "${alias}_"* ]]; then
                local prop="${key#${alias}_}"
                text+="    ${prop}: ${_BW_PROPS_RAW[${key}]}\n"
            fi
        done
    done

    local global_bastion="${_BW_PROPS_RAW["global_default_bastion"]:-not set}"
    text+="\n  Global bastion: ${global_bastion}\n"

    dialog --title "Current Configuration" \
           --msgbox "${text}" \
           $(( ${#_BW_ALIASES[@]} * 2 + 12 )) 62
}

_bw_global_bastion() {
    local current="${_BW_PROPS_RAW["global_default_bastion"]:-}"
    _bw_input "Global Default Bastion" \
        "\nAzure Bastion resource name used as\nthe default for all flat/flat-entra VMs\ne.g.  bst-default-region-01" \
        "${current}" || return
    [[ -z "${_BW_VAL}" ]] && return
    _BW_PROPS_RAW["global_default_bastion"]="${_BW_VAL}"
    _bw_write_conf
    dialog --msgbox "\nGlobal bastion set to:\n  ${_BW_VAL}" 8 52
}

# ==============================================================================
# Entry Point
# ==============================================================================
bastion_wizard() {
    _bw_conf_check || return 1

    # Load current state
    declare -gA _BW_ENTRIES=()
    declare -gA _BW_PROPS_RAW=()
    _BW_ALIASES=()
    _bw_parse_vms

    while true; do
        dialog --title "BASTION WIZARD" \
               --menu "\nConfigure your Azure Bastion\ntopology entries\n" \
               16 52 6 \
               "1" "Add VM" \
               "2" "Edit VM" \
               "3" "Delete VM" \
               "4" "Show Config" \
               "5" "Set Global Bastion" \
               "6" "Exit" \
               2>"${_BW_RESULT}" || break

        local choice
        choice=$(<"${_BW_RESULT}")

        case "${choice}" in
            1) _bw_add            ; _bw_parse_vms ;;
            2) _bw_edit           ; _bw_parse_vms ;;
            3) _bw_delete         ; _bw_parse_vms ;;
            4) _bw_show           ;;
            5) _bw_global_bastion ; _bw_parse_vms ;;
            6) break              ;;
        esac
    done

    clear
}
