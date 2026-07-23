# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]
then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
	# Pure-bash progress bar — pre-cache escape codes (zero tput forks)
	# Technique: bahamas10 / bash-tput pattern
	if [[ -t 2 ]]; then
		_RC_ESC=$'\033'
		_RC_RESET="${_RC_ESC}[0m"
		_RC_DIM="${_RC_ESC}[2m"
		_RC_BOLD="${_RC_ESC}[1m"
		_RC_GREEN="${_RC_ESC}[38;5;82m"
		_RC_CYAN="${_RC_ESC}[38;5;51m"
		_RC_BLUE="${_RC_ESC}[38;5;63m"
		_RC_YELLOW="${_RC_ESC}[38;5;226m"
		_RC_PURPLE="${_RC_ESC}[38;5;135m"
		_RC_CLRLINE="${_RC_ESC}[2K\r"
		_RC_BAR_FILL="█"
		_RC_BAR_EMPTY="░"
		_RC_BAR_WIDTH=24

		# Count scripts first (no forks — glob expansion)
		_rc_files=( ~/.bashrc.d/*.sh )
		_rc_total=${#_rc_files[@]}
		_rc_idx=0

		for rc in "${_rc_files[@]}"; do
			[[ -f "$rc" ]] || continue
			(( _rc_idx++ ))

			_rc_filled=$(( _RC_BAR_WIDTH * _rc_idx / _rc_total ))
			_rc_empty=$(( _RC_BAR_WIDTH - _rc_filled ))
			_rc_pct=$(( 100 * _rc_idx / _rc_total ))
			_rc_name="${rc##*/}"
			_rc_name="${_rc_name%.sh}"

			case "${_rc_name}" in
				01-*)      _rc_col="${_RC_YELLOW}" ;;
				10-*|15-*) _rc_col="${_RC_CYAN}" ;;
				20-*)      _rc_col="${_RC_BLUE}" ;;
				30-*)      _rc_col="${_RC_GREEN}" ;;
				40-*|50-*) _rc_col="${_RC_PURPLE}" ;;
				*)         _rc_col="${_RC_RESET}" ;;
			esac

			_rc_bar=""
			for (( i=0; i<_rc_filled; i++ )); do _rc_bar+="${_RC_BAR_FILL}"; done
			for (( i=0; i<_rc_empty;  i++ )); do _rc_bar+="${_RC_BAR_EMPTY}"; done

			printf "${_RC_CLRLINE} ${_RC_PURPLE}${_RC_BOLD}environment loading${_RC_RESET}  ${_RC_GREEN}${_RC_BOLD}[${_rc_bar}]${_RC_RESET} ${_RC_CYAN}${_RC_BOLD}%3d%%${_RC_RESET}  ${_rc_col}${_RC_DIM}%-26s${_RC_RESET}" \
				"$_rc_pct" "$_rc_name" >&2

			. "$rc"
		done

		# Final line: stays visible, prompt appears below it
		_rc_bar=""
		for (( i=0; i<_RC_BAR_WIDTH; i++ )); do _rc_bar+="${_RC_BAR_FILL}"; done
		printf "${_RC_CLRLINE} ${_RC_PURPLE}${_RC_BOLD}environment loading${_RC_RESET}  ${_RC_GREEN}${_RC_BOLD}[${_rc_bar}]${_RC_RESET} ${_RC_CYAN}${_RC_BOLD}100%%${_RC_RESET}  ${_RC_GREEN}${_RC_BOLD}✓ ready${_RC_RESET}\n" >&2

		# Unset all temp vars
		unset _RC_ESC _RC_RESET _RC_DIM _RC_BOLD _RC_GREEN _RC_CYAN
		unset _RC_BLUE _RC_YELLOW _RC_PURPLE _RC_CLRLINE
		unset _RC_BAR_FILL _RC_BAR_EMPTY _RC_BAR_WIDTH
		unset _rc_files _rc_total _rc_idx _rc_filled _rc_empty
		unset _rc_pct _rc_name _rc_bar _rc_col i
	else
		# Non-interactive — source silently
		for rc in ~/.bashrc.d/*.sh; do
			[[ -f "$rc" ]] && . "$rc"
		done
	fi
fi

unset rc
export LIBVIRT_DEFAULT_URI="qemu:///system"

# Cross-platform SSH-agent management lives in .bashrc.d/15-ssh_agent.sh
