#!/bin/bash
set -eu

Main() {
	local username=
	until [[ -n "${username}" ]]; do
		read -p "Please enter a username: " username
	done
	useradd --create-home --groups wheel,dialout "${username}"
	passwd "${username}"
}
Main "$@"
