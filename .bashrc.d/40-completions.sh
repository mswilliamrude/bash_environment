# ==============================================================================
# Bash Tab Completions for Azure Bastion Routing Functions
# Depends on: 30-azure_routing.sh (VM_NAME and VM_PORT must be populated)
# ==============================================================================

# Guard: completions only work in bash with the completion system loaded
[[ -z "$BASH_VERSION" ]] && return
type complete &>/dev/null || return

# ------------------------------------------------------------------------------
# _bastion_aliases
# Returns the list of configured VM aliases from the VM_NAME associative array.
# ------------------------------------------------------------------------------
_bastion_aliases() {
    if [[ -n "$(declare -p VM_NAME 2>/dev/null)" ]]; then
        echo "${!VM_NAME[@]}"
    fi
}

# ------------------------------------------------------------------------------
# _bastion_ports
# Returns the list of configured ports from the VM_PORT associative array.
# ------------------------------------------------------------------------------
_bastion_ports() {
    if [[ -n "$(declare -p VM_PORT 2>/dev/null)" ]]; then
        echo "${VM_PORT[@]}"
    fi
}

# ------------------------------------------------------------------------------
# _complete_bastion
# Completes: bastion <alias> [ssh]
#   - First argument: VM alias from VM_NAME
#   - Second argument: 'ssh' (the only valid mode flag)
# ------------------------------------------------------------------------------
_complete_bastion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    local cmd="${COMP_WORDS[0]}"

    case "${COMP_CWORD}" in
        1)
            # Complete the VM alias
            COMPREPLY=( $(compgen -W "$(_bastion_aliases)" -- "${cur}") )
            ;;
        2)
            # Complete the optional mode flag
            COMPREPLY=( $(compgen -W "ssh" -- "${cur}") )
            ;;
        *)
            COMPREPLY=()
            ;;
    esac
}

# ------------------------------------------------------------------------------
# _complete_cleanup_tunnels
# Completes: cleanup_tunnels <alias|all>
#   - Offers all VM aliases plus the special 'all' keyword
# ------------------------------------------------------------------------------
_complete_cleanup_tunnels() {
    local cur="${COMP_WORDS[COMP_CWORD]}"

    if [[ "${COMP_CWORD}" -eq 1 ]]; then
        local aliases
        aliases=$(_bastion_aliases)
        COMPREPLY=( $(compgen -W "all ${aliases}" -- "${cur}") )
    else
        COMPREPLY=()
    fi
}

# ------------------------------------------------------------------------------
# _complete_sshbastion
# Completes: sshbastion <port>
#   - Offers the ports defined in VM_PORT
# ------------------------------------------------------------------------------
_complete_sshbastion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"

    if [[ "${COMP_CWORD}" -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$(_bastion_ports)" -- "${cur}") )
    else
        COMPREPLY=()
    fi
}

# Register completions
complete -F _complete_bastion    bastion
complete -F _complete_bastion    connect-vm
complete -F _complete_cleanup_tunnels cleanup_tunnels
complete -F _complete_sshbastion sshbastion
