Print() {
	local -r bracketColor="247" labelColor="$1" label="$2"; shift 2
	printf "$(tput setaf $bracketColor)[$(tput sgr0)$(tput setaf $labelColor)%s$(tput sgr0)$(tput setaf $bracketColor)]$(tput sgr0) %s\n" "$label" "$*"
}
ExpectArg() {
	local -n v="$1"; shift
	local -n c="$1"; shift
	local name="${1%%=*}"
	c=0
	if [[ "$1" == "${name}" ]]; then
		(( $# < 2 )) && >&2 Print 1 "${BASH_SOURCE[1]}" "$1 expects a value." && return 1
		v="$2"
		c=1
		return 0
	fi
	v="${1#*=}"
}
Define() {
	IFS=$'\n' read -r -d '' ${1} ||true
}
Join() {
	IFS="$1"; shift
	echo "$*"
}
SetupRoot() {
	mkdir -p "$*"/usr/{bin,lib,lib64}
	ln -sf usr/bin "$*"/bin
	ln -sf usr/bin "$*"/sbin
	ln -sf usr/lib "$*"/lib
	ln -sf usr/lib64 "$*"/lib64
	ln -sf bin "$*"/usr/sbin
	mkdir -p "$*"/{dev,etc,proc,run,sys,tmp}
}
KVersion() {
	make --directory=/usr/src/linux --quiet kernelversion
}
TarCp() {
	local f="$1"; shift
	local t="$1"; shift
	tar --directory="$f" --create --preserve-permissions "$@" . |
		tar --directory="$t" --extract --keep-directory-symlink
}
