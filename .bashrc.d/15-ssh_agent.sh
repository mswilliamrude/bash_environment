# ==============================================================================
# Cross-platform SSH-Agent Management
# ==============================================================================
# Reuses an existing user-owned ssh-agent if one is running; otherwise launches
# a new one. Works on Linux (via /proc), macOS/BSD (via ps), and MSYS2/Cygwin.
#
# MSYS2 FIX: Uses ~/.ssh/agent.env as primary tracking file (persists across
# sessions, unlike /tmp which maps to volatile Windows temp dirs).
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

# --- Agent tracking file (persistent location) ------------------------------
_agent_env="${HOME}/.ssh/agent.env"
mkdir -p "${HOME}/.ssh" 2>/dev/null
chmod 700 "${HOME}/.ssh" 2>/dev/null

# --- Helper: check if agent is alive -----------------------------------------
_ssh_agent_alive() {
    # Method 1: If SSH_AUTH_SOCK is set and socket exists, agent is alive
    if [[ -n "${SSH_AUTH_SOCK}" ]]; then
        if [[ -S "${SSH_AUTH_SOCK}" ]]; then
            # Verify agent responds (ssh-add -l returns 0 or 1, not 2)
            "${_ssh_add_bin:-ssh-add}" -l &>/dev/null
            local _rc=$?
            # 0 = keys loaded, 1 = no keys but agent running, 2 = can't connect
            [[ $_rc -ne 2 ]] && return 0
        fi
    fi
    return 1
}

# --- Helper: is PID a live ssh-agent? ----------------------------------------
_ssh_agent_is_mine() {
    local _pid=$1
    [[ -z "${_pid}" || "${_pid}" == "0" ]] && return 1

    # MSYS2/Cygwin: /proc is limited, use ps directly
    if [[ "${OSTYPE}" == "msys"* || "${OSTYPE}" == "cygwin"* ]]; then
        ps -p "${_pid}" 2>/dev/null | grep -q ssh-agent && return 0
        return 1
    fi

    # Linux: use /proc if available
    if [[ -d /proc/${_pid} ]]; then
        [[ -r /proc/${_pid}/cmdline ]] || return 1
        local _cmd
        _cmd=$(tr -d '\0' </proc/${_pid}/cmdline 2>/dev/null)
        [[ "${_cmd##*/}" == "ssh-agent"* ]] || return 1

        # Check ownership
        if [[ -r /proc/${_pid}/status ]]; then
            local _ruid
            _ruid=$(awk '/^Uid:/ {print $2; exit}' /proc/${_pid}/status 2>/dev/null)
            [[ "${_ruid}" == "${UID}" ]] && return 0
        fi
        return 1
    fi

    # Fallback: ps (macOS, BSD)
    local _ps_out
    _ps_out=$(ps -o uid=,comm= -p "${_pid}" 2>/dev/null) || return 1
    local _ps_uid _ps_comm
    read -r _ps_uid _ps_comm <<<"${_ps_out}"
    [[ "${_ps_uid}" == "${UID}" && "${_ps_comm##*/}" == "ssh-agent" ]]
}

# --- Try to reuse existing agent ---------------------------------------------
_agent_attached=0

# Fast path: already have a working agent in environment
if _ssh_agent_alive; then
    _agent_attached=1
fi

# Try loading from persistent env file
if [[ "${_agent_attached}" == "0" && -f "${_agent_env}" ]]; then
    . "${_agent_env}" >/dev/null 2>&1
    
    if _ssh_agent_alive; then
        _agent_attached=1
    elif [[ -n "${SSH_AGENT_PID}" ]] && _ssh_agent_is_mine "${SSH_AGENT_PID}"; then
        _agent_attached=1
    else
        # Stale env file
        rm -f "${_agent_env}"
        unset SSH_AUTH_SOCK SSH_AGENT_PID
    fi
fi

# Legacy: check /tmp tracking files (for migration, will be cleaned up)
if [[ "${_agent_attached}" == "0" ]]; then
    for _file in /tmp/*.${USER}.sshagent 2>/dev/null; do
        [[ -e "${_file}" ]] || continue
        _agent_line=$(<"${_file}")
        _agent_pid=${_agent_line##* }
        _agent_pid=${_agent_pid%;*}

        if _ssh_agent_is_mine "${_agent_pid}"; then
            if [[ "${_agent_attached}" == "0" ]]; then
                eval "${_agent_line}" >/dev/null
                # Migrate to new location
                printf '%s\n' "${_agent_line}" > "${_agent_env}"
                chmod 600 "${_agent_env}"
                _agent_attached=1
            fi
            rm -f "${_file}"  # Clean up old format
        else
            rm -f "${_file}"
        fi
    done
fi

# --- Launch new agent if needed ----------------------------------------------
if [[ "${_agent_attached}" == "0" ]]; then
    _agent_output=$("${_ssh_agent_bin}" -s)
    eval "${_agent_output}" >/dev/null
    printf '%s\n' "${_agent_output}" > "${_agent_env}"
    chmod 600 "${_agent_env}"
    _agent_attached=1
fi

# --- Key loading (only if keys not already loaded) ---------------------------
if [[ -n "${_ssh_add_bin}" && "${_agent_attached}" == "1" ]]; then
    # Get currently loaded fingerprints
    _loaded_fps=$("${_ssh_add_bin}" -l 2>/dev/null | awk '{print $2}')
    
    # Helper to check if a key is already loaded
    _key_is_loaded() {
        local _keyfile=$1
        local _pubfile="${_keyfile}.pub"
        [[ -f "${_pubfile}" ]] || _pubfile="${_keyfile}"
        
        local _fp
        _fp=$(ssh-keygen -lf "${_pubfile}" 2>/dev/null | awk '{print $2}')
        [[ -n "${_fp}" ]] && printf '%s\n' "${_loaded_fps}" | grep -qxF "${_fp}"
    }

    # Auto-load preferred key (silently, no prompts)
    if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
        if ! _key_is_loaded "${HOME}/.ssh/id_ed25519"; then
            "${_ssh_add_bin}" "${HOME}/.ssh/id_ed25519" </dev/null >/dev/null 2>&1
            _loaded_fps=$("${_ssh_add_bin}" -l 2>/dev/null | awk '{print $2}')
        fi
    fi

    # Prompt for additional keys only on interactive TTY AND first attach
    # Skip if we're just re-sourcing bashrc (agent was already alive)
    if [[ -t 0 && -t 1 && -z "${_SSH_AGENT_PROMPT_DONE}" && -d "${HOME}/.ssh" ]]; then
        export _SSH_AGENT_PROMPT_DONE=1
        
        _candidates=()
        for _pub in "${HOME}"/.ssh/*.pub; do
            [[ -e "${_pub}" ]] || continue
            _priv=${_pub%.pub}
            [[ -f "${_priv}" ]] || continue
            [[ "${_priv}" == "${HOME}/.ssh/id_ed25519" ]] && continue
            
            if ! _key_is_loaded "${_priv}"; then
                _candidates+=("${_priv}")
            fi
        done

        if (( ${#_candidates[@]} > 0 )); then
            printf '\nAdditional SSH keys found in ~/.ssh:\n'
            _i=1
            for _priv in "${_candidates[@]}"; do
                printf '  %d) %s\n' "${_i}" "${_priv#${HOME}/.ssh/}"
                _i=$((_i + 1))
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
                printf '\n(timed out, skipping)\n'
            fi
            unset _i _choice _n
        fi
        unset _candidates _pub _priv
    fi
    unset _loaded_fps
    unset -f _key_is_loaded
fi

# --- Cleanup -----------------------------------------------------------------
unset _ssh_agent_bin _ssh_add_bin _candidate _agent_env \
      _file _agent_line _agent_pid _agent_output _agent_attached
unset -f _ssh_agent_alive _ssh_agent_is_mine
