# ==============================================================================
# Vim & Editor Normalization
# ==============================================================================

# Enable vi mode for the bash command line
set -o vi

# Helper function to ensure a file contains a specific string
function file_needs(){
    local filename=${1};shift
    local contains="${@}"
    
    # Touch the file if it doesn't exist yet to prevent read errors
    [[ ! -f "${filename}" ]] && touch "${filename}"
    
    local contents="$(< "${filename}")"
    if ! [[ "${contents}" == *"${contains}"* ]]; then
        echo "adding ${contains} to the end of ${filename}"
        echo "${contains}" >> "${filename}"
    fi
}

# Ensure baseline ~/.vimrc settings
file_needs ${HOME}/.vimrc "set tabstop=4"
file_needs ${HOME}/.vimrc "set shiftwidth=4"
file_needs ${HOME}/.vimrc "set expandtab"
file_needs ${HOME}/.vimrc "colorscheme desert"
