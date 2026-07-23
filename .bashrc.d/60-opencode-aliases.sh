#!/usr/bin/env bash
# ==============================================================================
# ~/.bashrc.d/60-opencode-aliases.sh — opencode session shortcuts
#
# Aliases to resume opencode sessions for specific repos.
# Session IDs sourced from ~/.local/share/opencode/opencode.db
# Updated: 2026-07-23
# ==============================================================================

# Guard: only define if opencode is available
if ! command -v opencode &>/dev/null; then
    return 0
fi

# Resume the most recent opencode session for each repo
alias oc_azure-encrypted-transport='cd ~/source/repos/azure-encrypted-transport/ && opencode -s ses_099a7903effewRuEKTG4GAhKOA'
alias oc_azure-encrypted-transport2='cd ~/source/repos/azure-encrypted-transport/ && opencode -s ses_098fac8d8ffeYtkEXZDSrTgcl5'
alias oc_bash_environment='cd ~/source/repos/bash_environment/ && opencode -s ses_143e5af21ffe9WMHgMZgtql1rV'
alias oc_unimind_dev='cd ~/source/repos/unimind_dev/ && opencode -s ses_08490826cffeL1ekBPe3uGUnNc'
