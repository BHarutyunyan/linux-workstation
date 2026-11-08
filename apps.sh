#!/usr/bin/env bash
# linux-workstation/apps.sh
#
# Keeps the same extra apps on all my machines. The list is apps.txt.
#
#     ./apps.sh         install what apps.txt lists and this machine is missing
#     ./apps.sh diff    show apps on this machine that apps.txt does not list
#
# New app on one laptop: "./apps.sh diff", copy its line into apps.txt,
# commit and push. Other laptop: "git pull && ./apps.sh".
# Safe to run again: it only adds what is missing and never removes anything.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$REPO_DIR/apps.txt"
HOST="$(hostname)"

info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m    ! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

is_apt()     { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"; }
is_snap()    { snap list "$1" > /dev/null 2>&1; }
is_flatpak() { flatpak info "$1" > /dev/null 2>&1; }

# Print "type name options" for each line of apps.txt meant for this machine.
read_list() {
	local line type name host word
	local -a field opts
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%%#*}"                     # drop notes
		read -r -a field <<< "$line"
		[ "${#field[@]}" -ge 2 ] || continue
		type="${field[0]}" name="${field[1]}" host="" opts=()
		for word in "${field[@]:2}"; do
			case "$word" in
				host=*) host="${word#host=}" ;;
				*)      opts+=("$word") ;;
			esac
		done
		# host=Y520: only where the hostname contains Y520, in any case.
		if [ -n "$host" ] && [[ "${HOST,,}" != *"${host,,}"* ]]; then
			continue
		fi
		echo "$type $name ${opts[*]}"
	done < "$LIST"
}

flathub_ready() {
	if ! command -v flatpak > /dev/null; then
		sudo apt-get install -y -q flatpak
		warn "flatpak is new here: log out and in once, so its apps show in the menu"
	fi
	sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

# shellcheck disable=SC2086  # $opts holds separate words (like --classic) on purpose
install_apps() {
	local entry type name opts apt_updated=0 flathub=0
	local -a entries
	# Read the whole list first: apt and snap must not eat the loop's input.
	mapfile -t entries < <(read_list)
	for entry in "${entries[@]}"; do
		read -r type name opts <<< "$entry"
		case "$type" in
			apt)
				if is_apt "$name"; then info "ok      $name"; continue; fi
				if [ "$apt_updated" = 0 ]; then sudo apt-get update -q; apt_updated=1; fi
				sudo apt-get install -y -q $opts "$name"
				;;
			snap)
				if is_snap "$name"; then info "ok      $name"; continue; fi
				sudo snap install "$name" $opts
				;;
			flatpak)
				if [ "$flathub" = 0 ]; then flathub_ready; flathub=1; fi
				if is_flatpak "$name"; then info "ok      $name"; continue; fi
				sudo flatpak install -y --noninteractive flathub "$name"
				;;
			*)
				warn "$name: unknown type \"$type\" (use apt, snap or flatpak)"
				continue
				;;
		esac
		info "installed $name"
	done
}

# Apps that are here but not in apps.txt, printed as ready lines for apps.txt.
show_diff() {
	local known name
	known="$(sed 's/#.*//' "$LIST" | awk 'NF >= 2 { print $2 }')"
	echo "On \"$HOST\" but not in apps.txt (copy the lines you want everywhere):"

	# snap: skip what Ubuntu itself brings
	snap list 2>/dev/null | awk 'NR > 1 { print $1 }' | while read -r name; do
		case "$name" in
			bare|core*|gnome-*|gtk-common-themes|mesa-*|snapd*|snap-store|firefox \
			|firmware-updater|desktop-security-center|prompting-client) continue ;;
		esac
		grep -qxF "$name" <<< "$known" || echo "snap     $name"
	done

	if command -v flatpak > /dev/null; then
		flatpak list --app --columns=application 2>/dev/null | while read -r name; do
			grep -qxF "$name" <<< "$known" || echo "flatpak  $name"
		done
	fi

	# apt: only what I installed by hand ("apt install ..." in the apt log),
	# still installed, and not already handled by install.sh
	zgrep -h '^Commandline: apt\(-get\)\? install ' /var/log/apt/history.log* 2>/dev/null \
		| tr ' ' '\n' \
		| grep -vx -e 'Commandline:' -e apt -e apt-get -e install \
		| grep -v -e '^-' -e '/' -e '=' -e '^$' \
		| sort -u | while read -r name; do
			grep -qw -- "$name" "$REPO_DIR/install.sh" && continue
			is_apt "$name" || continue
			grep -qxF "$name" <<< "$known" || echo "apt      $name"
		done
}

[ "$(id -u)" -ne 0 ] || die "run it as your normal user, not with sudo"
[ -f "$LIST" ] || die "no list: $LIST"

case "${1:-install}" in
	install) install_apps ;;
	diff)    show_diff ;;
	*)       die "usage: ./apps.sh [diff]" ;;
esac
