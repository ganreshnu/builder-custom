#
# bash/profile
#

PATH="$HOME/.local/bin:$PATH"

for d in $(<"${XDG_STATE_HOME:-$HOME/.local/state}/user_config_dirs"); do
	[[ -f "$HOME/$d/.bash_profile" ]] && . "$HOME/$d/.bash_profile"
done
unset d

# rc='"${XDG_CONFIG_HOME:-$HOME/.config}/bash/rc"'
# if ! grep -q ". $rc" "$HOME/.bashrc"; then
# 	echo ". $rc" >> "$HOME/.bashrc"
# fi

# vim: ft=bash
