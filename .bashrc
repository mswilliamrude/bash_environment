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
	for rc in ~/.bashrc.d/*; do
		if [ -f "$rc" ]; then
			. "$rc"
		fi
	done
fi

unset rc
export LIBVIRT_DEFAULT_URI="qemu:///system"
function usessh-agent(){
    local _pid=${1}
    if [ -f /proc/${_pid}/cmdline ]; then
        _cmdline=$(strings /proc/${_pid}/cmdline)
        _loginuid=/proc/${sshagentpid}/loginuid
        if [[ "${_cmdline}" == "ssh-agent" &&  ${UID} == "$(<${_loginuid})" ]]; then
            export SSH_AUTH_SOCK=$(ls /tmp/*/agent.$((${_pid} -1)))
            export SSH_AGENT_PID=${1}
        fi
    fi
}

#
#  Check to see if ssh-agent is running; if so use it!
#

for file in $(compgen -G /tmp/*.${USER}.sshagent ); do
    t=$(cat ${file})
    sshagentpid=${t##* }; sshagentpid=${sshagentpid%*;}
    if [ -f /proc/${sshagentpid}/cmdline ]; then
        _cmdline=$(</proc/${sshagentpid}/cmdline 2> /dev/null)
        _loginuid=/proc/${sshagentpid}/loginuid
        if [[ "${_cmdline}" == "ssh-agent" &&  ${UID} == "$(<${_loginuid})" ]]; then
            eval $(cat ${file}) && ssh-add ~/.ssh/id_ed25519
        fi
    else
        rm -f ${file}
    fi
done

#
#  If there are no existing ssh-agent sessions running as the current user
#  launch one and add the default key
#
if [[ ! $(compgen -G "/tmp/*.${USER}.sshagent") ]]; then
    output=$(ssh-agent)
    sshagentpid=${output##* }; sshagentpid=${sshagentpid%*;}
    eval ${output}; ssh-add ~/.ssh/id_ed25519
    echo ${output} > /tmp/${sshagentpid}.${USER}.sshagent
fi
