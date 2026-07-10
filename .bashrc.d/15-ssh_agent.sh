# ==============================================================================
# Cross-platform SSH-Agent Management
# ==============================================================================
# Reuses an existing user-owned ssh-agent if one is running; otherwise launches
# a new one. Works on Linux (via /proc), macOS/BSD (via ps), and MSYS2/Cygwin.
#
# MSYS2: Uses ~/.ssh/agent.env and tests agent via ssh-add -l (not socket test).
# ==============================================================================

# --- Locate ssh-agent --------------------------------------------------------
_ssh_agent_bin=""
if command -v ssh-agent >/dev/null 2>&1; then
    _ssh_agent_bin=$(command -v ssh-agent)
else
    for _candidate in \
        /usr/bin/ssh-agent \
        /usr/local/bin/ssh-agent \
        /opt/homebrew/bin/ssh-agent \
        /usr/pkg/bin/ssh-agent \
        /c/Program\ Files/Git/usr/bin/ssh-agent \
        /ucrt64/bin/ssh-agent \
        /mingw64/bin/ssh-agent
    do
        if [[ -x "${_candidate}" ]]; then
            _ssh_agent_bin="${_candidate}"
            break
        fi
    done
fi

if [[ -z "${_ssh_agent_bin}" ]]; then
    unset _ssh_agent_bin _candidate
    return 0 2>/dev/null || true
fi

# Resolve ssh-add
_ssh_add_bin=""
if command -v ssh-add >/dev/null 2>&1; then
    _ssh_add_bin=$(command -v ssh-add)
else
    _candidate="${_ssh_agent_bin%/ssh-agent}/ssh-add"
    [[ -x "${_candidate}" ]] && _ssh_add_bin="${_candidate}"
fi

# --- Agent tracking file -----------------------------------------------------
_agent_env="${HOME}/.ssh/agent.env"
mkdir -p "${HOME}/.ssh" 2>/dev/null
chmod 700 "${HOME}/.ssh" 2>/dev/null

# --- Helper: check if agent is alive (works on MSYS2) ------------------------
_ssh_agent_alive() {
    [[ -z "${SSH_AUTH_SOCK}" ]] && return 1
    # Don't use -S socket test — fails on MSYS2. Just ask ssh-add directly.
    # Returns: 0 = keys loaded, 1 = no keys but agent alive, 2 = can't connect
    "${_ssh_add_bin:-ssh-add}" -l &>/dev/null
    [[ $? -ne 2 ]]
}

# --- Try to reuse existing agent ---------------------------------------------
_agent_attached=0

# Fast path: already have a working agent in current environment
if _ssh_agent_alive; then
    _agent_attached=1
fi

# Try loading from persistent env file
if [[ "${_agent_attached}" == "0" && -f "${_agent_env}" ]]; then
    . "${_agent_env}" >/dev/null 2>&1
    
    if _ssh_agent_alive; then
        _agent_attached=1
    else
        # Stale env file — remove it
        rm -f "${_agent_env}"
        unset SSH_AUTH_SOCK SSH_AGENT_PID
    fi
fi

# --- Launch new agent if needed ----------------------------------------------
if [[ "${_agent_attached}" == "0" ]]; then
    eval "$("${_ssh_agent_bin}" -s)" >/dev/null
    # Save to persistent file
    {
        echo "SSH_AUTH_SOCK='${SSH_AUTH_SOCK}'; export SSH_AUTH_SOCK;"
        echo "SSH_AGENT_PID='${SSH_AGENT_PID}'; export SSH_AGENT_PID;"
    } > "${_agent_env}"
    chmod 600 "${_agent_env}"
    _agent_attached=1
fi

# --- Key loading (skip if already loaded) ------------------------------------
if [[ -n "${_ssh_add_bin}" && "${_agent_attached}" == "1" ]]; then
    # Get fingerprints of already-loaded keys
    _loaded_fps=$("${_ssh_add_bin}" -l 2>/dev/null | awk '{print $2}')
    
    # Check if a key is already loaded by fingerprint
    _key_is_loaded() {
        local _keyfile=$1
        local _pubfile="${_keyfile}.pub"
        [[ -f "${_pubfile}" ]] || _pubfile="${_keyfile}"
        [[ -f "${_pubfile}" ]] || return 1
        
        local _fp
        _fp=$(ssh-keygen -lf "${_pubfile}" 2>/dev/null | awk '{print $2}')
        [[ -n "${_fp}" ]] && echo "${_loaded_fps}" | grep -qF "${_fp}"
    }

    # Auto-load id_ed25519 silently (no passphrase prompt on re-source)
    _primary_key="${HOME}/.ssh/id_ed25519"
    if [[ -f "${_primary_key}" ]] && ! _key_is_loaded "${_primary_key}"; then
        # Only prompt if interactive, otherwise skip
        if [[ -t 0 && -t 1 ]]; then
            "${_ssh_add_bin}" "${_primary_key}"
        fi
        _loaded_fps=$("${_ssh_add_bin}" -l 2>/dev/null | awk '{print $2}')
    fi

    # Interactive key prompt — only on first attach, not re-source
    if [[ -t 0 && -t 1 && -z "${_SSH_AGENT_KEYS_OFFERED}" ]]; then
        export _SSH_AGENT_KEYS_OFFERED=1
        
        _candidates=()
        for _pub in "${HOME}"/.ssh/*.pub; do
            [[ -e "${_pub}" ]] || continue
            _priv="${_pub%.pub}"
            [[ -f "${_priv}" ]] || continue
            # Skip primary key (already handled above)
            [[ "${_priv}" == "${_primary_key}" ]] && continue
            # Skip if already loaded
            _key_is_loaded "${_priv}" && continue
            _candidates+=("${_priv}")
        done

        if (( ${#_candidates[@]} > 0 )); then
            printf '\nAdditional SSH keys found in ~/.ssh:\n'
            _i=1
            for _priv in "${_candidates[@]}"; do
                printf '  %d) %s\n' "${_i}" "${_priv##*/}"
                (( _i++ ))
            done
            printf 'Add which? [numbers space-separated, "a" for all, Enter to skip]: '
            if read -r -t 10 _choice; then
                case "${_choice}" in
                    ""|n|N) ;;
                    a|A|all)
                        for _priv in "${_candidates[@]}"; do
                            "${_ssh_add_bin}" "${_priv}"
                        done
                        ;;
                    *)
                        for _n in ${_choice}; do
                            if [[ "${_n}" =~ ^[0-9]+$ ]] && (( _n >= 1 && _n <= ${#_candidates[@]} )); then
                                "${_ssh_add_bin}" "${_candidates[$((_n - 1))]}"
                            fi
                        done
                        ;;
                esac
            else
                printf '\n(timed out)\n'
            fi
        fi
        unset _i _choice _n _candidates _pub _priv
    fi
    unset _loaded_fps _primary_key
    unset -f _key_is_loaded
fi

# --- Cleanup -----------------------------------------------------------------
unset _ssh_agent_bin _ssh_add_bin _candidate _agent_env _agent_attached
unset -f _ssh_agent_alive
