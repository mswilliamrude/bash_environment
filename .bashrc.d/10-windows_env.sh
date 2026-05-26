# ==============================================================================
# 0. OS Guard Clause
# Ensure this script ONLY executes if running on Windows (MSYS2 / Cygwin)
# ==============================================================================
if [[ "${OSTYPE}" != "msys"* && "${OSTYPE}" != "cygwin"* ]]; then
    return 0
fi

# ==============================================================================
# 1. Environment Normalization (MSYS2 / Git for Windows)
# ==============================================================================
export MSYS_NO_PATHCONV=1

profile_dir="${HOME}/.bastion_profiles"

cd ~

# ==============================================================================
# Global Identity Settings
# ==============================================================================
# Determine the correct Microsoft Alias/Username
# On Windows/MSYS2, USERNAME holds the actual Windows logon name (Microsoft alias),
# while USER might just be 'azureuser' if running in WSL or a generic Linux shell.
# We prioritize USERNAME first to ensure we get the real Microsoft alias.
if [[ -n "$USERNAME" ]]; then
    export AZ_USERNAME="$USERNAME"
elif [[ -n "$USER" ]]; then
    export AZ_USERNAME="$USER"
else
    # Fallback just in case
    export AZ_USERNAME="azureuser"
fi

# ==============================================================================
# 2. SSH & Identity
# ==============================================================================
sshagentpid=$(ps -ef | grep ssh-agent)
if [[ -z ${sshagentpid} ]]; then
    output=$(ssh-agent)
    sshagentpid=$(ps -ef | grep ssh-agent)
    sshagentpid=${sshagentpid#REDMOND+ *}
    read -r sshagentpid _ <<< "${sshagentpid}"
    echo ${output} > /tmp/${sshagentpid}.sshagent
    eval ${output}; ssh-add ~/.ssh/id_ed25519
else
    sshagentpid=${sshagentpid#REDMOND+ *}
    read -r sshagentpid _ <<< "${sshagentpid}"
    source /tmp/${sshagentpid}.sshagent
fi
# ==============================================================================
# Handle Pageant (for plink) - Only execute on Windows (MSYS/MINGW/CYGWIN)
# ==============================================================================
if [[ "${OSTYPE}" == "msys"* || "${OSTYPE}" == "cygwin"* ]]; then
    # 1. Find Pageant dynamically
    PAGEANT_EXE=$(command -v pageant.exe 2>/dev/null)
    if [[ -z "${PAGEANT_EXE}" ]]; then
        # Fallbacks for common install locations if not in PATH
        if [[ -f "/c/Program Files/PuTTY/pageant.exe" ]]; then
            PAGEANT_EXE="/c/Program Files/PuTTY/pageant.exe"
        elif [[ -f "/c/Program Files (x86)/PuTTY/pageant.exe" ]]; then
            PAGEANT_EXE="/c/Program Files (x86)/PuTTY/pageant.exe"
        fi
    fi

    # 2. Define PPK keys as an array (allows multiple keys)
    PPK_DIR="${HOME}/OneDrive - Microsoft/Documents"
    declare -a PPK_FILES=("putty.ppk") # Add more keys here like ("key1.ppk" "key2.ppk")

    # 3. Load Keys if Pageant was found and directory exists
    if [[ -n "${PAGEANT_EXE}" && -d "${PPK_DIR}" ]]; then
        # Check if Pageant is running
        if ! tasklist.exe 2>/dev/null | grep -iq "pageant.exe"; then
            # Not running: start it and pass all keys as arguments.
            # We use parameter expansion to prepend the directory to each array element
            (cd "${PPK_DIR}" && "${PAGEANT_EXE}" "${PPK_FILES[@]}" &)
        else
            # Already running: pass keys again to ensure they are loaded in memory
            (cd "${PPK_DIR}" && "${PAGEANT_EXE}" "${PPK_FILES[@]}")
        fi
    fi
fi

# Export preference for routing engine subshells on Windows
# Dynamically resolve plink.exe to avoid PATH issues in strict MSYS2 environments
PLINK_EXE=$(command -v plink.exe 2>/dev/null)
if [[ -z "${PLINK_EXE}" ]]; then
    if [[ -f "/c/Program Files/PuTTY/plink.exe" ]]; then
        PLINK_EXE="/c/Program Files/PuTTY/plink.exe"
    elif [[ -f "/c/Program Files (x86)/PuTTY/plink.exe" ]]; then
        PLINK_EXE="/c/Program Files (x86)/PuTTY/plink.exe"
    else
        PLINK_EXE="plink.exe" # Fallback to literal if totally lost
    fi
fi
export BASTION_SUBSHELL_CMD="${PLINK_EXE}"

