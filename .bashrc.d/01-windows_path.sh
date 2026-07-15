# ==============================================================================
# Windows/MSYS2 PATH Modifications
# ==============================================================================
# Ensure this script ONLY executes if running on Windows (MSYS2 / Cygwin)
if [[ "${OSTYPE}" != "msys"* && "${OSTYPE}" != "cygwin"* ]]; then
    return 0
fi

# Detect which runtime is CURRENTLY EXECUTING, not just what's installed on disk.
# /ucrt64/bin is an MSYS2-only path — Git for Windows never has it.
# This discriminates correctly even when both are installed, and regardless of
# which MSYS2 launcher was used (bash.exe = MSYS subsystem, ucrt64.exe = UCRT64).
if [[ -d "/ucrt64/bin" ]]; then
    # MSYS2 environment — /ucrt64/bin exists regardless of launch subsystem.
    # Guard against re-sourcing: only rebuild PATH if /ucrt64/bin isn't already leading.
    if [[ "${PATH%%:*}" != "/ucrt64/bin" ]]; then

        # 1. Core MSYS2 toolchain paths — order matters, /ucrt64/bin leads
        PATH="/ucrt64/bin"
        PATH="${PATH}:/usr/local/bin"
        PATH="${PATH}:/usr/bin"
        PATH="${PATH}:/bin"

        # 2. Windows system paths
        PATH="${PATH}:/c/Windows/System32"
        PATH="${PATH}:/c/Windows"
        PATH="${PATH}:/c/Windows/System32/Wbem"
        PATH="${PATH}:/c/Windows/System32/WindowsPowerShell/v1.0"

        # 3. Optional CLI tools — only added if installed
        [[ -d "/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin" ]] && \
            PATH="${PATH}:/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin"
        [[ -d "/c/Program Files/PuTTY" ]] && \
            PATH="${PATH}:/c/Program Files/PuTTY"

        # 4. Perl paths (MSYS2 standard)
        PATH="${PATH}:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl"

        export PATH
    fi

elif [[ -e "/c/Program Files/Git/bin/bash.exe" ]]; then
    # Git for Windows only — no MSYS2 present
    # Prepend Python; leave the rest of the inherited Windows PATH intact
    export PATH="/c/python/3.9.25/:${PATH}"
fi

#export PATH="/usr/local/bin":${PATH}
#export PYTHONPATH="/etc/psr:/c/python/3.9.25/Lib:C:\\Program Files\\Git\\etc\\psr:c:\\python\\3.9.25\\Lib"
#export PYTHONPATH="/etc/psr:/c/python/3.9.25/Lib"
#export PYTHONPATH="/usr/lib/python3.9:$(cygpath.exe -w '/c/Program Files/Git/etc/psr/')"
#export PYTHONPATH="/usr/lib/python3.9"
