# ==============================================================================
# Cross-platform SSH-Agent Management
# ==============================================================================
# Reuses an existing user-owned ssh-agent if one is running; otherwise launches
# a new one. Works on Linux (via /proc), macOS/BSD (via ps), and MSYS2/Cygwin.
# Replaces the per-OS agent blocks that used to live in .bashrc and
# .bashrc.d/10-windows_env.sh.

# --- Locate ssh-agent --------------------------------------------------------
# command -v handles the common case (it's on PATH). If not, walk a list of
# known install locations across Linux, macOS (incl. Apple Silicon Homebrew),
# BSD, and MSYS2/Git-for-Windows.
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
    # No ssh-agent available on this host; silently bail so login still works.
    unset _ssh_agent_bin _candidate
    return 0 2>/dev/null || true
fi

# Resolve ssh-add the same way; needed for key loading later.
_ssh_add_bin=""
if command -v ssh-add >/dev/null 2>&1; then
    _ssh_add_bin=$(command -v ssh-add)
else
    # ssh-add almost always ships next to ssh-agent.
    _candidate="${_ssh_agent_bin%/ssh-agent}/ssh-add"
    [[ -x "${_candidate}" ]] && _ssh_add_bin="${_candidate}"
fi

# --- Helper: is PID a live ssh-agent owned by current user? ------------------
# Linux uses /proc (cheap, exact); other Unixes use ps (POSIX-portable).
_ssh_agent_is_mine() {
    local _pid=$1
    [[ -z "${_pid}" ]] && return 1

    # Fast path: Linux /proc
    if [[ -d /proc/${_pid} ]]; then
        # /proc/<pid>/cmdline is NUL-separated argv. Pre-strip NULs with `tr`
        # so bash doesn't print "ignored null byte" warnings (those warnings
        # are emitted by the shell itself and can't be silenced by `2>/dev/null`
        # on the surrounding subst). For ssh-agent (typically no args) the
        # result is just the binary path.
        # Also avoid bash's `$(< file)` form here — it returns empty when
        # stderr is redirected (a long-standing bash quirk).
        [[ -r /proc/${_pid}/cmdline ]] || return 1
        local _cmd
        _cmd=$(tr -d '\0' </proc/${_pid}/cmdline 2>/dev/null)
        [[ -z "${_cmd}" ]] && return 1
        [[ "${_cmd##*/}" == "ssh-agent"* ]] || return 1

        if [[ -r /proc/${_pid}/loginuid ]]; then
            local _uid
            _uid=$(</proc/${_pid}/loginuid)
            # 4294967295 (-1) means "not set" — fall through to status check
            if [[ "${_uid}" != "4294967295" && -n "${_uid}" ]]; then
                [[ "${_uid}" == "${UID}" ]] && return 0 || return 1
            fi
        fi
        # Fallback: parse real UID from /proc/<pid>/status
        local _ruid
        _ruid=$(awk '/^Uid:/ {print $2; exit}' /proc/${_pid}/status 2>/dev/null)
        [[ "${_ruid}" == "${UID}" ]]
        return $?
    fi

    # Portable path: ps. Use -o so we don't have to parse fixed columns.
    # macOS, BSD, and MSYS2 all support `ps -o pid=,uid=,comm= -p <pid>`.
    local _ps_out _ps_uid _ps_comm
    _ps_out=$(ps -o uid=,comm= -p "${_pid}" 2>/dev/null) || return 1
    read -r _ps_uid _ps_comm <<<"${_ps_out}"
    [[ "${_ps_uid}" == "${UID}" && "${_ps_comm##*/}" == "ssh-agent" ]]
}

# --- Reuse existing agent if one is ours -------------------------------------
# Convention: ssh-agent invocations write their `SSH_AUTH_SOCK=...; SSH_AGENT_PID=...;`
# output to /tmp/<pid>.<user>.sshagent so subsequent shells can source it.
# We walk all tracking files, prune any stale ones, and attach to the first
# valid agent we find (don't break early — pruning is important hygiene).
_agent_attached=0
for _file in /tmp/*.${USER}.sshagent; do
    # The glob expands to itself literally if no matches exist.
    [[ -e "${_file}" ]] || continue

    _agent_line=$(<"${_file}")
    # ssh-agent's eval block ends `...; echo Agent pid <PID>;` — pull PID
    # off the tail. Works whether the file is one line or three.
    _agent_pid=${_agent_line##* }
    _agent_pid=${_agent_pid%;*}

    if _ssh_agent_is_mine "${_agent_pid}"; then
        # Attach to the first valid agent we find; keep iterating to prune
        # any stale tracking files we encounter later.
        if [[ "${_agent_attached}" == "0" ]]; then
            eval "${_agent_line}" >/dev/null
            _agent_attached=1
        fi
    else
        # Stale tracking file (process is gone or belongs to someone else).
        rm -f "${_file}"
    fi
done

# --- Otherwise launch a fresh agent ------------------------------------------
if [[ "${_agent_attached}" == "0" ]]; then
    _agent_output=$("${_ssh_agent_bin}")
    _agent_pid=${_agent_output##* }
    _agent_pid=${_agent_pid%;*}
    eval "${_agent_output}" >/dev/null
    printf '%s\n' "${_agent_output}" >"/tmp/${_agent_pid}.${USER}.sshagent"
    _agent_attached=1
fi

# --- Key loading -------------------------------------------------------------
# Auto-add id_ed25519 if present, then offer any other private keys
# interactively. Skip the prompt for non-interactive shells.
if [[ -n "${_ssh_add_bin}" && "${_agent_attached}" == "1" ]]; then
    _loaded_fps=$("${_ssh_add_bin}" -l 2>/dev/null | awk '{print $2}')

    # 1. Auto-load the preferred key.
    if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
        _is_loaded=0
        if [[ -f "${HOME}/.ssh/id_ed25519.pub" ]]; then
            _fp=$(ssh-keygen -lf "${HOME}/.ssh/id_ed25519.pub" 2>/dev/null | awk '{print $2}')
        else
            _fp=$(ssh-keygen -lf "${HOME}/.ssh/id_ed25519" 2>/dev/null | awk '{print $2}')
        fi

        if [[ -n "${_fp}" ]] && printf '%s\n' "${_loaded_fps}" | grep -qxF "${_fp}"; then
            _is_loaded=1
        fi

        if [[ "${_is_loaded}" == "0" ]]; then
            "${_ssh_add_bin}" "${HOME}/.ssh/id_ed25519" >/dev/null 2>&1
            # Refresh loaded fingerprints in case we just added one
            _loaded_fps=$("${_ssh_add_bin}" -l 2>/dev/null | awk '{print $2}')
        fi
        unset _is_loaded _fp
    fi

    # 2. Only prompt for additional keys on an interactive TTY.
    if [[ -t 0 && -t 1 && -d "${HOME}/.ssh" ]]; then
        # Collect candidate private keys: anything in ~/.ssh that has a
        # matching .pub sibling and isn't already loaded. Using the .pub
        # marker is more reliable than name patterns and avoids known_hosts,
        # config, authorized_keys, etc.
        _candidates=()
        for _pub in "${HOME}"/.ssh/*.pub; do
            [[ -e "${_pub}" ]] || continue
            _priv=${_pub%.pub}
            [[ -f "${_priv}" ]] || continue
            # Skip the one we already auto-loaded.
            [[ "${_priv}" == "${HOME}/.ssh/id_ed25519" ]] && continue
            # Skip keys already in the agent (by fingerprint).
            _fp=$(ssh-keygen -lf "${_pub}" 2>/dev/null | awk '{print $2}')
            if [[ -n "${_fp}" ]] && printf '%s\n' "${_loaded_fps}" | grep -qxF "${_fp}"; then
                continue
            fi
            _candidates+=("${_priv}")
        done

        if (( ${#_candidates[@]} > 0 )); then
            printf '\nAdditional SSH keys found in ~/.ssh:\n'
            _i=1
            for _priv in "${_candidates[@]}"; do
                printf '  %d) %s\n' "${_i}" "${_priv#${HOME}/.ssh/}"
                _i=$((_i + 1))
            done
            printf 'Add which? [numbers space-separated, "a" for all, Enter to skip]: '
            # 10-second timeout so this never hangs a slow login.
            if read -r -t 10 _choice; then
                case "${_choice}" in
                    ""|n|N) ;;  # skip
                    a|A|all)
                        for _priv in "${_candidates[@]}"; do
                            "${_ssh_add_bin}" "${_priv}"
                        done
                        ;;
                    *)
                        for _n in ${_choice}; do
                            # Validate index, then load.
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
        unset _loaded_fps _candidates _pub _priv _fp
    fi
fi

# --- Cleanup -----------------------------------------------------------------
unset _ssh_agent_bin _ssh_add_bin _candidate \
      _file _agent_line _agent_pid _agent_output _agent_attached
