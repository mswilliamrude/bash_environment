# ==============================================================================
# Windows/MSYS2 PATH Modifications
# ==============================================================================
# Ensure this script ONLY executes if running on Windows (MSYS2 / Cygwin)
if [[ "${OSTYPE}" != "msys"* && "${OSTYPE}" != "cygwin"* ]]; then
    return 0
fi

# Append/prepend native toolchains to the path depending on the environment
if [[ -e /c/Program\ Files/Git/bin/bash.exe ]]; then
    # Git for Windows environment
    export PATH="/c/python/3.9.25/:${PATH}"
elif [[ -e /c/msys64/usr/bin/bash.exe ]]; then
    # MSYS2 Native Environment (e.g. UCRT64 or MINGW64)
    # 1. Base MSYS2 and System32 paths
    BASE_PATHS="/ucrt64/bin:/usr/local/bin:/usr/bin:/bin:/c/Windows/System32:/c/Windows:/c/Windows/System32/Wbem:/c/Windows/System32/WindowsPowerShell/v1.0"
    
    # 2. Add common CLI tools to the path if their directories exist
    AZURE_PATH="/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin"
    PUTTY_PATH="/c/Program Files/PuTTY"
    
    [[ -d "$AZURE_PATH" ]] && BASE_PATHS="${BASE_PATHS}:${AZURE_PATH}"
    [[ -d "$PUTTY_PATH" ]] && BASE_PATHS="${BASE_PATHS}:${PUTTY_PATH}"
    
    # 3. Export combined path, retaining whatever else MSYS2 inherited
    export PATH="${BASE_PATHS}:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl:${PATH}"
fi

#export PATH="/usr/local/bin":${PATH}
#export PYTHONPATH="/etc/psr:/c/python/3.9.25/Lib:C:\\Program Files\\Git\\etc\\psr:c:\\python\\3.9.25\\Lib"
#export PYTHONPATH="/etc/psr:/c/python/3.9.25/Lib"
#export PYTHONPATH="/usr/lib/python3.9:$(cygpath.exe -w '/c/Program Files/Git/etc/psr/')"
#export PYTHONPATH="/usr/lib/python3.9"
