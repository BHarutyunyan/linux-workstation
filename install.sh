#!/usr/bin/env bash
# linux-workstation/install.sh
#
# One command that turns a fresh Ubuntu 26.04 LTS desktop into my workstation:
# terminal settings, ufw firewall, SSH key-only login, n8n in Docker and
# Ollama with a small local model (both reachable only from this machine),
# my apps, and my GNOME desktop (keys, layouts, theme, extensions).
#
# One command on a fresh machine (wget and tar are there from the start;
# git and curl are not), run as your normal user from the home folder:
#     cd ~ && wget -qO- https://github.com/BHarutyunyan/linux-workstation/archive/main.tar.gz | tar xz && ~/linux-workstation-main/install.sh
# Or from a clone:  ./install.sh
# It asks for your sudo password once. It is safe to run again: every step
# checks before it changes anything.
#
# Options (environment variables):
#     GITHUB_USER=name   whose public SSH keys to trust   (default BHarutyunyan)
#     OLLAMA_MODEL=name  which model to download          (default qwen2.5:1.5b)
#     GIT_EMAIL=address  git commit email; skipped if empty
#     SKIP_APPS=1        skip desktop apps (faster test runs)
#     SKIP_DESKTOP=1     skip GNOME settings and extensions

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_USER="${GITHUB_USER:-BHarutyunyan}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:1.5b}"
GIT_NAME="${GIT_NAME:-Anmahana}"
GIT_EMAIL="${GIT_EMAIL:-}"
SKIP_APPS="${SKIP_APPS:-0}"
SKIP_DESKTOP="${SKIP_DESKTOP:-0}"
LOG="$HOME/linux-workstation-install.log"
STAMP="$(date +%Y%m%d-%H%M%S)"
TMP_DIR="$(mktemp -d)"
export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------- helpers ---

step() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m    ! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

apt_install() {
	sudo apt-get install -y -q "$@"
}

is_installed() {
	dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

# Put a symlink at $2 that points to $1 in this repo.
# An existing real file is kept as <name>.bak-<date>, never deleted.
link_file() {
	local src="$1" dest="$2"
	if [ "$(readlink "$dest" 2>/dev/null || true)" = "$src" ]; then
		info "ok      $dest"
		return 0
	fi
	mkdir -p "$(dirname "$dest")"
	if [ -e "$dest" ] || [ -L "$dest" ]; then
		mv "$dest" "$dest.bak-$STAMP"
		info "backup  $dest -> $dest.bak-$STAMP"
	fi
	ln -s "$src" "$dest"
	info "linked  $dest"
}

cleanup() {
	rm -rf "$TMP_DIR"
	if [ -n "${SUDO_KEEPALIVE_PID:-}" ]; then
		kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
	fi
}
trap cleanup EXIT

# -------------------------------------------------------------- preflight ---

preflight() {
	[ "$EUID" -ne 0 ] || die "Run as your normal user, not with sudo. The script asks for sudo itself."
	# shellcheck source=/dev/null
	. /etc/os-release
	[ "${ID:-}" = "ubuntu" ] || die "This script is for Ubuntu (found: ${ID:-unknown})."
	if [ "${VERSION_ID:-}" != "26.04" ]; then
		warn "Made for Ubuntu 26.04; this is ${VERSION_ID:-unknown}. GNOME extensions may not match."
	fi

	# Guard against running it on the wrong laptop (it happened once).
	if [ "${ASSUME_YES:-0}" != "1" ]; then
		local answer
		read -r -p "Set up THIS machine, \"$(hostname)\"? Type yes: " answer
		[ "$answer" = "yes" ] || die "Stopped. Nothing was changed."
	fi

	step "Asking for the sudo password once"
	sudo -v
	# Keep sudo alive until the script ends, so long downloads don't ask again.
	while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done &
	SUDO_KEEPALIVE_PID=$!
}

# ------------------------------------------------------ 2. terminal settings ---

setup_terminal() {
	step "2. Terminal settings: .bashrc, vim, git"
	link_file "$REPO_DIR/dotfiles/bashrc"                         "$HOME/.bashrc"
	link_file "$REPO_DIR/dotfiles/.bash_aliases"                  "$HOME/.bash_aliases"
	link_file "$REPO_DIR/dotfiles/.vimrc"                         "$HOME/.vimrc"
	link_file "$REPO_DIR/dotfiles/.vim/mycolors.vim"              "$HOME/.vim/mycolors.vim"
	link_file "$REPO_DIR/dotfiles/.vim/after/plugin/42header.vim" "$HOME/.vim/after/plugin/42header.vim"

	git config --global user.name "$GIT_NAME"
	git config --global color.ui true
	if [ -n "$GIT_EMAIL" ]; then
		git config --global user.email "$GIT_EMAIL"
	else
		info "GIT_EMAIL not set: run later  git config --global user.email you@example.com"
	fi
}

# ---------------------------------------------- 1. updates and basic tools ---

setup_packages() {
	step "1. System update and basic tools"
	sudo apt-get update -q
	sudo apt-get upgrade -y -q
	apt_install curl gnupg jq zstd git vim valgrind shellcheck \
		python3-pip python3-venv restic keepassxc gh
	if [ ! -x "$HOME/.venv/bin/python" ]; then
		python3 -m venv "$HOME/.venv"
		info "created ~/.venv"
	fi
}

# ------------------------------------------------------------- 3. firewall ---

setup_firewall() {
	step "3. Firewall (ufw): block all incoming except SSH"
	apt_install ufw
	sudo ufw default deny incoming
	sudo ufw default allow outgoing
	sudo ufw allow 22/tcp
	sudo ufw --force enable
}

# ------------------------------------------------------ 4. SSH key-only login ---

setup_ssh() {
	step "4. SSH: key-only login"
	apt_install openssh-server

	local keys
	keys="$(curl -fsSL "https://github.com/${GITHUB_USER}.keys" || true)"
	if [ -z "$keys" ]; then
		# Never switch passwords off without a key in place: that is a lockout.
		warn "No public keys found at https://github.com/${GITHUB_USER}.keys"
		warn "Password login is left ON. Add a key to GitHub and run the script again."
		return 0
	fi

	install -d -m 700 "$HOME/.ssh"
	touch "$HOME/.ssh/authorized_keys"
	chmod 600 "$HOME/.ssh/authorized_keys"
	local key added=0
	while IFS= read -r key; do
		[ -n "$key" ] || continue
		if ! grep -qxF "$key" "$HOME/.ssh/authorized_keys"; then
			printf '%s\n' "$key" >> "$HOME/.ssh/authorized_keys"
			added=$((added + 1))
		fi
	done <<< "$keys"
	info "keys from GitHub: $added new"

	# sshd uses the FIRST value it reads, and files in sshd_config.d are read
	# in name order, so "00-" wins over Ubuntu's own 50-cloud-init.conf.
	local conf=/etc/ssh/sshd_config.d/00-linux-workstation.conf
	sudo tee "$conf" > /dev/null <<'EOF'
# Written by linux-workstation/install.sh
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
	sudo install -d -m 755 /run/sshd
	if ! sudo sshd -t; then
		sudo rm -f "$conf"
		die "sshd rejected the new settings; they were removed and SSH was not restarted."
	fi
	sudo systemctl enable --now ssh
	sudo systemctl restart ssh
}

# --------------------------------------------------------------- 5. Docker ---

setup_docker() {
	step "5. Docker"
	apt_install docker.io
	sudo systemctl enable --now docker
	# On purpose I do NOT add myself to the "docker" group: membership in it
	# equals root access. The script uses "sudo docker" instead.
}

# ------------------------------------------------------- 6. n8n in Docker ---

setup_n8n() {
	step "6. n8n in Docker, only on 127.0.0.1:5678"
	if sudo docker container inspect n8n > /dev/null 2>&1; then
		sudo docker start n8n > /dev/null
		info "container n8n already exists; started"
	else
		sudo docker volume create n8n_data > /dev/null
		# "127.0.0.1:" matters: Docker writes its own firewall rules and goes
		# around ufw, so "-p 5678:5678" would open n8n to the whole network.
		sudo docker run -d --name n8n --restart unless-stopped \
			-p 127.0.0.1:5678:5678 \
			-e GENERIC_TIMEZONE=Asia/Yerevan -e TZ=Asia/Yerevan \
			-v n8n_data:/home/node/.n8n \
			docker.n8n.io/n8nio/n8n > /dev/null
		info "container n8n created"
	fi
}

# --------------------------------------------------------------- 7. Ollama ---

setup_ollama() {
	step "7. Ollama, only on 127.0.0.1:11434, model $OLLAMA_MODEL"
	if ! command -v ollama > /dev/null; then
		# Manual install instead of "curl ollama.com/install.sh | sh": that
		# script tries to install NVIDIA CUDA drivers when it sees an NVIDIA
		# card (the Legion has a GTX 1050). Here the model runs on the CPU.
		curl -fsSL https://ollama.com/download/ollama-linux-amd64.tar.zst \
			| sudo tar x --zstd -C /usr
		info "ollama installed to /usr"
	fi
	if ! id ollama > /dev/null 2>&1; then
		sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
	fi
	sudo usermod -a -G ollama "$USER"

	sudo tee /etc/systemd/system/ollama.service > /dev/null <<'EOF'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="OLLAMA_HOST=127.0.0.1:11434"

[Install]
WantedBy=multi-user.target
EOF
	sudo systemctl daemon-reload
	sudo systemctl enable --now ollama

	local i up=0
	for i in $(seq 1 30); do
		if curl -fs http://127.0.0.1:11434/api/version > /dev/null; then up=1; break; fi
		sleep 1
	done
	[ "$up" = "1" ] || die "Ollama did not start after ${i}s; see: journalctl -u ollama"

	if ollama list | awk 'NR > 1 {print $1}' | grep -qx "$OLLAMA_MODEL"; then
		info "model $OLLAMA_MODEL already downloaded"
	else
		ollama pull "$OLLAMA_MODEL"
	fi
}

# ----------------------------------------------------------------- 8. apps ---

setup_apps() {
	step "8. Apps"
	if [ "$SKIP_APPS" = "1" ]; then
		info "SKIP_APPS=1: skipped"
		return 0
	fi

	# Brave: official key and repository file.
	if [ ! -f /etc/apt/sources.list.d/brave-browser-release.sources ]; then
		sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
			https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
		sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources \
			https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
	fi
	# Claude Desktop: official key and repository (code.claude.com/docs/en/desktop-linux).
	if [ ! -f /etc/apt/sources.list.d/claude-desktop.list ]; then
		sudo curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc \
			https://downloads.claude.ai/claude-desktop/key.asc
		echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
			| sudo tee /etc/apt/sources.list.d/claude-desktop.list > /dev/null
	fi
	sudo apt-get update -q
	apt_install brave-browser gnome-shell-extension-manager
	# --no-install-recommends skips QEMU for Cowork: it needs virtualization,
	# which is off on the Legion, and 8 GB is too little for its VM.
	sudo apt-get install -y -q --no-install-recommends claude-desktop

	# ChatGPT and Discord ship as .deb files. The ChatGPT package adds its
	# own apt repository, so later updates come with "apt upgrade".
	if ! is_installed chatgpt; then
		curl -fsSLo "$TMP_DIR/chatgpt_amd64.deb" \
			https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb
		apt_install "$TMP_DIR/chatgpt_amd64.deb"
	fi
	if ! is_installed discord; then
		curl -fsSLo "$TMP_DIR/discord.deb" \
			"https://discord.com/api/download?platform=linux&format=deb"
		apt_install "$TMP_DIR/discord.deb"
	fi

	# Everything else (apt, snap, Flathub) is listed in apps.txt.
	"$REPO_DIR/apps.sh"
}

# ------------------------------------------------------- 9. GNOME desktop ---

install_ego_extension() {
	# Download an extension from extensions.gnome.org for this GNOME version.
	local uuid="$1" shell_major url
	if [ -d "$HOME/.local/share/gnome-shell/extensions/$uuid" ]; then
		info "ok      $uuid"
		return 0
	fi
	shell_major="$(gnome-shell --version | grep -oE '[0-9]+' | head -n 1)"
	url="$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell_major}" \
		| jq -r '.download_url // empty')"
	if [ -z "$url" ]; then
		warn "$uuid: no version for GNOME $shell_major on extensions.gnome.org"
		return 0
	fi
	curl -fsSLo "$TMP_DIR/$uuid.zip" "https://extensions.gnome.org${url}"
	gnome-extensions install --force "$TMP_DIR/$uuid.zip"
	info "installed $uuid"
}

setup_desktop() {
	step "9. GNOME: extensions, keys, layouts, theme, Windows icon"
	if [ "$SKIP_DESKTOP" = "1" ]; then
		info "SKIP_DESKTOP=1: skipped"
		return 0
	fi
	if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] || ! command -v gnome-shell > /dev/null; then
		warn "No GNOME session here (over SSH?). Run the script in a terminal on the desktop."
		return 0
	fi

	install_ego_extension hidetopbar@mathieu.bidon.ca
	install_ego_extension hide-cursor@elcste.com
	install_ego_extension soft-brightness-plus@joelkitching.com
	local ext_dir="$HOME/.local/share/gnome-shell/extensions"
	mkdir -p "$ext_dir"
	cp -r "$REPO_DIR/gnome/extensions/dock-keyboard-autohide@boris" "$ext_dir/"
	info "installed dock-keyboard-autohide@boris (my own)"

	# Only chosen sections, never a whole "dconf dump": that would carry
	# E16-only things (screen scale, recent folders) to this machine.
	dconf load / < "$REPO_DIR/gnome/settings.ini"
	info "GNOME settings loaded"

	# Russian phonetic: ч on the ` key, ю on = (stock layout is the other way).
	# An xkb-data update undoes this: run the script again.
	local ru=/usr/share/X11/xkb/symbols/ru
	if sed -n '/xkb_symbols "phonetic"/,/^};/p' "$ru" | grep -q 'key <TLDE>.*Cyrillic_che'; then
		info "ok      ru(phonetic) ч/ю"
	else
		sudo cp "$ru" "$ru.bak-$STAMP"
		sudo sed -i '/xkb_symbols "phonetic"/,/^};/{
s/\(key <TLDE>.*\)Cyrillic_yu,\s*Cyrillic_YU/\1Cyrillic_che, Cyrillic_CHE/
s/\(key <AE12>.*\)Cyrillic_che,\s*Cyrillic_CHE/\1Cyrillic_yu, Cyrillic_YU/
}' "$ru"
		info "swapped ч/ю in ru(phonetic), original kept as $ru.bak-$STAMP"
	fi

	setup_dualboot
}

setup_dualboot() {
	# One-click "Windows" icon, only on machines that also boot Windows.
	if ! sudo efibootmgr 2>/dev/null | grep -q "Windows Boot Manager"; then
		info "no Windows on this machine: no Windows icon"
		return 0
	fi
	# Root-owned and outside my home: pkexec runs it as root, so a file I can
	# edit without a password must never be what it runs.
	sudo install -m 755 -o root -g root "$REPO_DIR/dualboot/to-windows" /usr/local/sbin/to-windows
	install -D -m 644 "$REPO_DIR/dualboot/to-windows.desktop" \
		"$HOME/.local/share/applications/to-windows.desktop"
	info "installed the Windows icon (/usr/local/sbin/to-windows)"
}

# ----------------------------------------------------------- 10. self-check ---

self_check() {
	step "10. Self-check"

	echo "--- TCP ports open to the network (expect only 22):"
	local exposed
	exposed="$(sudo ss -Htln | awk '{print $4}' \
		| grep -vE '^(127\.|\[::1\]|\[::ffff:127\.)' \
		| sed 's/.*://' | sort -un | tr '\n' ' ')"
	if [ "$exposed" = "22 " ]; then
		info "PASS  only 22/tcp listens outside localhost"
	else
		warn "CHECK listening outside localhost: ${exposed:-none}"
	fi

	echo "--- All listening ports:"
	sudo ss -tuln

	echo "--- Firewall:"
	sudo ufw status verbose

	echo "--- SSH settings in force:"
	sudo sshd -T | grep -Ei '^(pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|permitrootlogin) '

	echo "--- n8n:"
	sudo docker port n8n
	local code
	code="$(curl -s -o /dev/null -w '%{http_code}' --retry 10 --retry-delay 3 --retry-all-errors http://127.0.0.1:5678 || true)"
	info "http://127.0.0.1:5678 -> HTTP $code"

	echo "--- Ollama:"
	info "version $(curl -fs http://127.0.0.1:11434/api/version | jq -r .version)"
	ollama list
}

# ------------------------------------------------------------------- main ---

main() {
	exec > >(tee -a "$LOG") 2>&1
	echo "linux-workstation install, $(date), log: $LOG"
	preflight
	setup_packages   # first: git and vim must exist before step 2 uses them
	setup_terminal
	setup_firewall
	setup_ssh
	setup_docker
	setup_n8n
	setup_ollama
	setup_apps
	setup_desktop
	self_check
	step "Done"
	info "Log out and back in once, so GNOME turns on the extensions."
	info "Then: gh auth login, gh auth setup-git (git uses gh, no token in a plain file)."
}

main "$@"
