# linux-workstation

One Bash script that turns a fresh **Ubuntu 26.04 LTS** desktop into my workstation,
the same as my main laptop, and safe on a home network.
Part of my TUMO Labs Guided Self-Learning, cybersecurity track, cycle 1 (KPI 1).

**Test results:** [docs/TESTS.md](docs/TESTS.md) – 11 tests, all passed.

## Run it

On the machine you want to set up, as your normal user (not root):

```bash
cd ~ && wget -qO- https://github.com/BHarutyunyan/linux-workstation/archive/main.tar.gz | tar xz && ~/linux-workstation-main/install.sh
```

- `wget` and `tar` come with Ubuntu; `git` and `curl` do not, so the script installs them first.
- It first asks `Set up THIS machine, "<hostname>"? Type yes`, so it cannot run on the wrong laptop by accident.
- It asks for the sudo password once.
- It is **safe to run again**: every step checks before it changes anything.

## What it does

| Step | What | Security point |
|---|---|---|
| 1 | System update, basic tools | Updates first |
| 2 | My `bashrc`, `.bash_aliases`, Vim, git | Linked from this repo; old files kept as `.bak-<date>`, never deleted |
| 3 | ufw firewall | Deny all incoming, allow only 22/tcp |
| 4 | SSH | Keys from `github.com/BHarutyunyan.keys`; passwords and root login off; `sshd -t` checks the config before restart; if no key is found, passwords stay on (no lockout) |
| 5 | Docker | I am not in the `docker` group: membership equals root |
| 6 | n8n in Docker | Published on `127.0.0.1:5678` only. Docker writes its own firewall rules and bypasses ufw, so the address is what keeps it private |
| 7 | Ollama + `qwen2.5:1.5b` | `OLLAMA_HOST=127.0.0.1:11434`; manual install, so no NVIDIA driver changes |
| 8 | Apps | Brave, Claude, ChatGPT, Discord from the vendors' own repositories; the rest from `apps.txt` through `apps.sh` |
| 9 | GNOME + dual-boot | My keys, layouts (us, ru, am), theme, extensions; a "Windows" icon if Windows is installed |
| 10 | Daily updates | A systemd timer runs `apt upgrade` and `flatpak update` at the first start of each day (no password, no new packages removed, waits if apt is busy, retries without network) |
| 11 | Self-check | Lists open ports and fails loudly if anything but 22 listens outside localhost |

After it finishes: log out and in (extensions), then `gh auth login` and `gh auth setup-git`.

## Same apps and dock on both laptops

`apps.txt` is one list (`apt`, `snap` or `flatpak` lines); the dock order is `favorite-apps`
in `gnome/settings.ini`. `apps.sh` never removes anything.

```bash
./apps.sh save     # laptop I changed: pick new apps for the list, save the dock, commit, push
./apps.sh          # other laptop: git pull, install what is missing, same dock order
```

A line in `apps.txt` can end with `host=<part of hostname>` to keep an app on one machine only.
Sign-ins inside apps are never synced: they stay on each machine.

## Dual-boot switch

| From | Click | What happens |
|---|---|---|
| Ubuntu | **Windows** icon in the dock | `pkexec /usr/local/sbin/to-windows` sets UEFI `BootNext` to Windows Boot Manager and reboots |
| Windows | **To Ubuntu** on the desktop | A SYSTEM task runs `bcdedit /set {fwbootmgr} bootsequence {ubuntu}` and reboots |

Both switch **once**; the default boot entry does not change.
Windows side, once, in PowerShell as administrator: [windows/to-ubuntu-setup.ps1](windows/to-ubuntu-setup.ps1).

Security rule used on both sides: a script that runs as root or SYSTEM lives where only an
administrator can write (`/usr/local/sbin`, `C:\Program Files`), never in a user's folder.

## Files

```text
install.sh                     the one command
apps.sh, apps.txt              extra apps: one list for all my machines
dotfiles/                      bashrc, .bash_aliases, .vimrc, .vim/
gnome/settings.ini             chosen GNOME settings (not a whole dconf dump)
gnome/extensions/              my own GNOME extension
dualboot/                      to-windows script and its icon
windows/to-ubuntu-setup.ps1    Windows side of the switch
docs/TESTS.md                  test results and screenshots
```

## Options

`ASSUME_YES=1` (no question), `SKIP_APPS=1`, `SKIP_DESKTOP=1`, `OLLAMA_MODEL=name`,
`GITHUB_USER=name`, `GIT_EMAIL=address`.

## No secrets here

No passwords, tokens or private keys are in this repository. SSH trusts only the public keys
GitHub already shows for my account. Sign-ins (GitHub, apps) are done by hand after the install.
