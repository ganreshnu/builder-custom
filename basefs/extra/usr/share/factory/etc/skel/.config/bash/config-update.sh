#!/bin/env argscript

#
# config-update.sh
#
# Update my user configuration.
#

#
# define a usage function
#
Usage() {
	cat <<EOD
Usage: $(basename "$BASH_SOURCE") [OPTIONS]

Options:
  --help                         Show this message and exit.

Configures and updates my user configurations.
EOD
}

Argument() {
	return 0
}

Main() {
	for d in $(<"$HOME/.local/state/user_config_dirs"); do
		git -C "$HOME/$d" pull --quiet
	done
}

# vim: ft=bash
