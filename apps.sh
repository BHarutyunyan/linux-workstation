#!/usr/bin/env bash
# linux-workstation/apps.sh
#
# Keeps the same extra apps and the same dock on all my machines.
# The app list is apps.txt; the dock order is "favorite-apps" in gnome/settings.ini.
#
#     ./apps.sh save    on the laptop I changed: asks which new apps to add to
#                       apps.txt, saves the dock, then commits and pushes
#     ./apps.sh         on the other laptop: git pull, install what is missing,
#                       put the dock in the same order
#     ./apps.sh diff    only show apps here that apps.txt does not list
#     ./apps.sh dock    replace the dock here with the saved one
#
# Safe to run again: it only adds what is missing and never removes anything.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$REPO_DIR/apps.txt"
SETTINGS="$REPO_DIR/gnome/settings.ini"
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
diff_lines() {
	local known name
	known="$(sed 's/#.*//' "$LIST" | awk 'NF >= 2 { print $2 }')"

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

in_gnome() { [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v gsettings > /dev/null; }

DOCK_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/linux-workstation/dock-applied"

remember_dock() { mkdir -p "$(dirname "$DOCK_STATE")"; printf '%s\n' "$1" > "$DOCK_STATE"; }

# Put the dock in the order saved in gnome/settings.ini, but never throw away
# a dock I changed on this machine since the last sync.
apply_dock() {
	local fav cur last answer
	fav="$(grep -m 1 '^favorite-apps=' "$SETTINGS" | cut -d= -f2-)"
	if [ -z "$fav" ] || ! in_gnome; then
		info "dock: skipped (no saved order, or no GNOME session here)"
		return 0
	fi
	cur="$(gsettings get org.gnome.shell favorite-apps)"
	last="$(cat "$DOCK_STATE" 2>/dev/null || true)"
	if [ "$cur" = "$fav" ]; then
		info "ok      dock"
	elif [ -n "$last" ] && [ "$cur" = "$last" ]; then
		# The dock here is untouched since the last sync: take the new order.
		gsettings set org.gnome.shell favorite-apps "$fav"
		info "dock: same order as saved"
	elif [ -n "$last" ]; then
		warn "dock: you changed it here since the last sync, so it was kept."
		warn "To share this dock: ./apps.sh save. To take the saved one: ./apps.sh dock"
		return 0
	else
		# First sync on this machine: ask, because only I know which is right.
		read -r -p "    Dock here differs from the saved one. Use the saved one? [y/N] " answer < /dev/tty || answer=""
		case "$answer" in
			y|Y) gsettings set org.gnome.shell favorite-apps "$fav"; info "dock: same order as saved" ;;
			*)   warn "dock: kept this one. To share it: ./apps.sh save"; return 0 ;;
		esac
	fi
	remember_dock "$fav"
}

# git pull before installing. If apps.sh itself changed, start the new version.
pull_first() {
	local before
	if [ -n "${APPS_NO_PULL:-}" ] || [ ! -d "$REPO_DIR/.git" ]; then
		return 0
	fi
	before="$(git -C "$REPO_DIR" rev-parse HEAD)"
	if ! git -C "$REPO_DIR" pull --ff-only -q; then
		warn "git pull failed (offline, or local changes): using the files as they are"
		return 0
	fi
	if [ "$(git -C "$REPO_DIR" rev-parse HEAD)" != "$before" ]; then
		info "pulled new changes"
		APPS_NO_PULL=1 exec "$REPO_DIR/apps.sh" "$@"
	fi
}

# On the laptop I changed: new apps into apps.txt, dock into settings.ini, push.
save_all() {
	local line answer fav
	local -a new
	mapfile -t new < <(diff_lines)
	for line in "${new[@]}"; do
		read -r -p "    Add \"$line\" to every machine? [y/N] " answer < /dev/tty
		case "$answer" in
			y|Y) echo "$line" >> "$LIST"; info "added   $line" ;;
			*)   info "skipped $line" ;;
		esac
	done

	if in_gnome; then
		fav="$(gsettings get org.gnome.shell favorite-apps)"
		sed -i "s|^favorite-apps=.*|favorite-apps=$fav|" "$SETTINGS"
		info "dock order saved"
		remember_dock "$fav"
	fi

	if [ ! -d "$REPO_DIR/.git" ]; then
		warn "not a git clone: saved here only, nothing pushed"
		return 0
	fi
	if git -C "$REPO_DIR" diff --quiet -- apps.txt gnome/settings.ini; then
		info "nothing new to save"
		return 0
	fi
	# Only these two files: other unfinished work stays uncommitted.
	git -C "$REPO_DIR" commit -q -m "apps.sh save: apps and dock from $HOST" -- apps.txt gnome/settings.ini
	git -C "$REPO_DIR" push -q
	info "pushed. On the other laptop run: ./apps.sh"
}

[ "$(id -u)" -ne 0 ] || die "run it as your normal user, not with sudo"
[ -f "$LIST" ] || die "no list: $LIST"

case "${1:-install}" in
	install) pull_first "$@"; install_apps; apply_dock ;;
	save)    save_all ;;
	dock)    in_gnome || die "no GNOME session here"
	         gsettings set org.gnome.shell favorite-apps "$(grep -m 1 '^favorite-apps=' "$SETTINGS" | cut -d= -f2-)"
	         remember_dock "$(gsettings get org.gnome.shell favorite-apps)"; info "dock: same order as saved" ;;
	diff)    echo "On \"$HOST\" but not in apps.txt:"; diff_lines ;;
	*)       die "usage: ./apps.sh [save | diff | dock]" ;;
esac
