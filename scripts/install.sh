#!/usr/bin/env bash
# ==============================================================================
# install.sh — MSYS2 environment bootstrap for bash_environment
#
# Installs required packages and configures MSYS2 so that:
#   - The Windows user home directory is used as $HOME (db_home: windows)
#   - Core tools (git, rsync, python, pip, ssh, curl, jq, tmux, vim) are available
#   - Both MSYS and UCRT64 Python stacks are present
#   - UCRT64 Python libraries for crypto, HTTP, async, YAML, numpy are installed
#
# Usage:
#   bash scripts/install.sh
#
# Safe to re-run — all steps are idempotent.
# Must be run from an MSYS2 shell (bash.exe, ucrt64.exe, etc.)
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Guard: MSYS2 only
# ------------------------------------------------------------------------------
if [[ "${OSTYPE}" != "msys"* && "${OSTYPE}" != "cygwin"* ]]; then
    echo "ERROR: This script is intended for MSYS2 / Cygwin environments only."
    echo "       Detected OSTYPE=${OSTYPE}"
    exit 1
fi

if [[ ! -d "/ucrt64/bin" ]]; then
    echo "ERROR: /ucrt64/bin not found. This script requires a full MSYS2 installation."
    echo "       Download MSYS2 from https://www.msys2.org/"
    exit 1
fi

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*"; }
section() { echo ""; echo "==== $* ===="; }

# Back up a file with a .orig extension — only once, never overwrites the .orig.
# Usage: backup_orig /path/to/file
backup_orig() {
    local file="$1"
    local orig="${file}.orig"
    if [[ -f "${file}" && ! -f "${orig}" ]]; then
        cp "${file}" "${orig}"
        info "Backup saved: ${orig}"
    elif [[ -f "${orig}" ]]; then
        info "Backup already exists: ${orig} — skipping."
    fi
}

# ------------------------------------------------------------------------------
# 1. Update package database
# ------------------------------------------------------------------------------
section "Updating package database"
pacman -Sy --noconfirm
success "Package database updated."

# ------------------------------------------------------------------------------
# 2. Core MSYS packages (runtime tools — live in /usr/bin)
# ------------------------------------------------------------------------------
section "Installing core MSYS packages"

MSYS_PACKAGES=(
    # --- Version control & file sync ---
    git                 # Version control
    rsync               # File sync (used heavily in bastion workflows)
    diffutils           # diff, cmp, sdiff

    # --- Shell & terminal ---
    tmux                # Terminal multiplexer
    vim                 # Editor
    man-db              # Man pages

    # --- Network & SSH ---
    openssh             # ssh, ssh-agent, ssh-keygen
    curl                # HTTP client
    wget                # HTTP downloader

    # --- Process & system tools ---
    procps-ng           # ps, top, kill — required by 30-azure_routing.sh tunnel detection

    # --- Data & scripting ---
    jq                  # JSON processor — used for Azure CLI output parsing
    zip                 # Archive creation
    unzip               # Archive extraction

    # --- TUI ---
    dialog              # TUI dialog boxes — required by bastion_wizard
    python              # MSYS Python 3 (lives in /usr/bin)
    python-pip          # pip for MSYS Python
)

for pkg in "${MSYS_PACKAGES[@]}"; do
    if pacman -Q "${pkg}" &>/dev/null; then
        success "${pkg} already installed ($(pacman -Q "${pkg}" | awk '{print $2}'))"
    else
        info "Installing ${pkg}..."
        pacman -S --noconfirm "${pkg}"
        success "${pkg} installed."
    fi
done

# ------------------------------------------------------------------------------
# 3. UCRT64 packages (toolchain — live in /ucrt64/bin, linked against ucrt)
# ------------------------------------------------------------------------------
section "Installing UCRT64 toolchain packages"

UCRT64_PACKAGES=(
    # --- Python runtime (UCRT64, ucrt-linked — lives in /ucrt64/bin) ---
    mingw-w64-ucrt-x86_64-python        # UCRT64 Python 3 (for compiled extensions)
    mingw-w64-ucrt-x86_64-python-pip    # pip for UCRT64 Python

    # --- Python libraries ---
    mingw-w64-ucrt-x86_64-python-cryptography  # Cryptography primitives (SSH/TLS/auth)
    mingw-w64-ucrt-x86_64-python-httpx         # Modern async HTTP client
    mingw-w64-ucrt-x86_64-python-numpy         # Numerical computing
    mingw-w64-ucrt-x86_64-python-websockets    # WebSocket client/server
    mingw-w64-ucrt-x86_64-python-yaml          # YAML parsing (PyYAML)
)

for pkg in "${UCRT64_PACKAGES[@]}"; do
    if pacman -Q "${pkg}" &>/dev/null; then
        success "${pkg} already installed ($(pacman -Q "${pkg}" | awk '{print $2}'))"
    else
        info "Installing ${pkg}..."
        pacman -S --noconfirm "${pkg}"
        success "${pkg} installed."
    fi
done

# ------------------------------------------------------------------------------
# 4. Third-party packages (GitHub releases — not in pacman repos)
# ------------------------------------------------------------------------------
section "Installing third-party packages"

# Maps pacman package name (used for already-installed check) to download URL.
# Add more entries here as needed — one per line.
declare -A THIRD_PARTY_PACKAGES=(
    ["mingw-w64-ucrt-x86_64-python-protocols"]="https://github.com/mswilliamrude/protocols/releases/download/v1.0.0/mingw-w64-ucrt-x86_64-python-protocols-1.0.0-1-any.pkg.tar.zst"
)

for pkg_name in "${!THIRD_PARTY_PACKAGES[@]}"; do
    url="${THIRD_PARTY_PACKAGES[${pkg_name}]}"
    if pacman -Q "${pkg_name}" &>/dev/null; then
        success "${pkg_name} already installed ($(pacman -Q "${pkg_name}" | awk '{print $2}'))"
    else
        info "Installing ${pkg_name} from GitHub..."
        info "  ${url}"
        if pacman -U --noconfirm --noprogressbar \
                --config <(cat /etc/pacman.conf; echo -e "[options]\nSigLevel = Never") \
                "${url}"; then
            success "${pkg_name} installed."
        else
            warn "${pkg_name} install failed — check URL or network and retry."
        fi
    fi
done

# ------------------------------------------------------------------------------
# 4. Configure /etc/nsswitch.conf — set db_home to windows
#
# This makes MSYS2 use the Windows user profile directory (C:\Users\<name>)
# as $HOME instead of /home/<name>, so dotfiles, SSH keys, and configs stored
# in the Windows home are visible without symlinks.
# ------------------------------------------------------------------------------
section "Configuring /etc/nsswitch.conf"

NSSWITCH="/etc/nsswitch.conf"

if [[ ! -f "${NSSWITCH}" ]]; then
    warn "${NSSWITCH} not found — creating a minimal one."
    cat > "${NSSWITCH}" <<'EOF'
# /etc/nsswitch.conf — created by bash_environment install.sh

passwd: files db
group: files db

db_enum: cache builtin

db_home: windows
db_shell: cygwin desc
db_gecos: cygwin desc
EOF
    success "${NSSWITCH} created with db_home: windows."
else
    # Check current db_home value
    current=$(grep -E "^db_home:" "${NSSWITCH}" | awk '{print $2}' || true)

    if [[ "${current}" == "windows" ]]; then
        success "db_home already set to 'windows' — no change needed."
    else
        info "Current db_home: '${current:-not set}' — updating to 'windows'..."

        # Back up the original before modifying (only once)
        backup_orig "${NSSWITCH}"

        if grep -qE "^db_home:" "${NSSWITCH}"; then
            # Replace existing db_home line in place
            sed -i 's/^db_home:.*/db_home: windows/' "${NSSWITCH}"
        else
            # No db_home line exists — append it after db_enum if present, else at end
            if grep -qE "^db_enum:" "${NSSWITCH}"; then
                sed -i '/^db_enum:/a db_home: windows' "${NSSWITCH}"
            else
                echo "db_home: windows" >> "${NSSWITCH}"
            fi
        fi

        success "db_home set to 'windows'."
    fi
fi

# ------------------------------------------------------------------------------
# 5. Install ~/.bashrc
#
# Copies the repo's .bashrc into the user's home directory.
# Backs up any existing ~/.bashrc as ~/.bashrc.orig (once only).
# ------------------------------------------------------------------------------
section "Installing ~/.bashrc"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_BASHRC="${REPO_DIR}/.bashrc"

if [[ ! -f "${REPO_BASHRC}" ]]; then
    warn "Repo .bashrc not found at ${REPO_BASHRC} — skipping."
else
    backup_orig "${HOME}/.bashrc"
    cp "${REPO_BASHRC}" "${HOME}/.bashrc"
    success "~/.bashrc installed from repo."
fi

# ------------------------------------------------------------------------------
# 6. Install ~/.bashrc.d/
#
# Copies all module scripts from repo/.bashrc.d/ into ~/.bashrc.d/.
# Creates the directory if it doesn't exist.
# Backs up any existing file that would be overwritten as <file>.orig (once only).
# ------------------------------------------------------------------------------
section "Installing ~/.bashrc.d/"

REPO_BASHRC_D="${REPO_DIR}/.bashrc.d"
HOME_BASHRC_D="${HOME}/.bashrc.d"

if [[ ! -d "${REPO_BASHRC_D}" ]]; then
    warn "Repo .bashrc.d/ not found at ${REPO_BASHRC_D} — skipping."
else
    mkdir -p "${HOME_BASHRC_D}"
    info "Target directory: ${HOME_BASHRC_D}"

    for src in "${REPO_BASHRC_D}"/*; do
        [[ -f "${src}" ]] || continue
        filename="$(basename "${src}")"
        dest="${HOME_BASHRC_D}/${filename}"

        backup_orig "${dest}"
        cp "${src}" "${dest}"
        success "Installed: ~/.bashrc.d/${filename}"
    done
fi

# ------------------------------------------------------------------------------
# 7. Create and populate ~/.bastion_profiles/
#
# Copies the repo's .bastion_profiles/ contents (example scripts + README)
# into ~/.bastion_profiles/ so users have working templates to reference.
# The directory must exist even if empty — absence causes a warning on every
# shell start from 10-windows_env.sh.
# ------------------------------------------------------------------------------
section "Installing ~/.bastion_profiles/"

REPO_PROFILES="${REPO_DIR}/.bastion_profiles"
HOME_PROFILES="${HOME}/.bastion_profiles"

mkdir -p "${HOME_PROFILES}"

if [[ ! -d "${REPO_PROFILES}" ]]; then
    warn "Repo .bastion_profiles/ not found at ${REPO_PROFILES} — created empty directory."
else
    for src in "${REPO_PROFILES}"/*; do
        [[ -f "${src}" ]] || continue
        filename="$(basename "${src}")"
        dest="${HOME_PROFILES}/${filename}"

        # Never overwrite live profile scripts — only copy if destination absent
        if [[ -f "${dest}" ]]; then
            info "~/.bastion_profiles/${filename} already exists — skipping."
        else
            cp "${src}" "${dest}"
            success "Installed: ~/.bastion_profiles/${filename}"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 8. Install ~/.bastion_topology.conf.example
#
# Copies .bastion_topology.conf.example from the repo to the home directory
# so users have the annotated template at hand without cloning the repo path.
# Never overwrites an existing live ~/.bastion_topology.conf.
# ------------------------------------------------------------------------------
section "Installing ~/.bastion_topology.conf.example"

TOPOLOGY_EXAMPLE="${REPO_DIR}/.bastion_topology.conf.example"
TOPOLOGY_EXAMPLE_DEST="${HOME}/.bastion_topology.conf.example"
TOPOLOGY_LIVE="${HOME}/.bastion_topology.conf"

if [[ ! -f "${TOPOLOGY_EXAMPLE}" ]]; then
    warn "Topology example not found at ${TOPOLOGY_EXAMPLE} — skipping."
else
    # Always keep the example fresh — it's not sensitive
    cp "${TOPOLOGY_EXAMPLE}" "${TOPOLOGY_EXAMPLE_DEST}"
    success "~/.bastion_topology.conf.example installed."

    # Only create the live conf if one doesn't exist yet
    if [[ -f "${TOPOLOGY_LIVE}" ]]; then
        success "~/.bastion_topology.conf already exists — not overwriting."
    else
        cp "${TOPOLOGY_EXAMPLE}" "${TOPOLOGY_LIVE}"
        success "~/.bastion_topology.conf created from example."
        warn "Edit ~/.bastion_topology.conf with your Azure infrastructure details before running bastion."
    fi
fi

# ------------------------------------------------------------------------------
# 8. Ensure ~/.bash_profile sources ~/.bashrc
#
# Login shells (bash -l) read ~/.bash_profile, not ~/.bashrc.
# Without this, the entire .bashrc.d/ chain never fires on login.
# We write a minimal ~/.bash_profile if absent, or patch it if present
# but missing the source line. Backs up any existing file as .orig.
# ------------------------------------------------------------------------------
section "Configuring ~/.bash_profile"

BASH_PROFILE="${HOME}/.bash_profile"
SOURCE_LINE='[[ -f ~/.bashrc ]] && source ~/.bashrc'

if [[ ! -f "${BASH_PROFILE}" ]]; then
    info "~/.bash_profile not found — creating minimal one."
    cat > "${BASH_PROFILE}" <<'EOF'
# ~/.bash_profile — created by bash_environment install.sh
#
# Login shells (bash -l -i) read this file instead of ~/.bashrc.
# Source ~/.bashrc so the full .bashrc.d/* chain fires on login.

[[ -f ~/.bashrc ]] && source ~/.bashrc
EOF
    success "~/.bash_profile created."

elif grep -qF "${SOURCE_LINE}" "${BASH_PROFILE}"; then
    success "~/.bash_profile already sources ~/.bashrc — no change needed."

else
    info "~/.bash_profile exists but does not source ~/.bashrc — patching..."
    backup_orig "${BASH_PROFILE}"

    # Append the source line with a comment explaining why
    cat >> "${BASH_PROFILE}" <<'EOF'

# Added by bash_environment install.sh
# Login shells read ~/.bash_profile; source ~/.bashrc so .bashrc.d/* fires.
[[ -f ~/.bashrc ]] && source ~/.bashrc
EOF
    success "~/.bash_profile patched to source ~/.bashrc."
fi

# ------------------------------------------------------------------------------
# 9. Verify key binaries are resolvable
# ------------------------------------------------------------------------------
section "Verifying installed tools"

VERIFY_BINS=(git rsync ssh diff jq tmux vim python python3 pip pip3 curl wget ps)

all_ok=true
for bin in "${VERIFY_BINS[@]}"; do
    path=$(command -v "${bin}" 2>/dev/null || true)
    if [[ -n "${path}" ]]; then
        success "${bin} -> ${path}"
    else
        warn "${bin} not found in PATH — you may need to restart your shell."
        all_ok=false
    fi
done

# ------------------------------------------------------------------------------
# 8. Summary
# ------------------------------------------------------------------------------
section "Done"

if [[ "${all_ok}" == "true" ]]; then
    echo "All packages installed and configured successfully."
else
    echo "Installation complete with warnings (see above)."
    echo "If binaries are missing, restart your MSYS2 shell and re-run:"
    echo "  source ~/.bashrc"
fi

echo ""
echo "Next steps:"
echo "  1. Restart your MSYS2 shell to pick up the new \$HOME (if db_home was changed)"
echo "  2. Copy .bastion_topology.conf.example to ~/.bastion_topology.conf and configure it"
echo "  3. Run: bastion   (to verify the routing engine loaded correctly)"
