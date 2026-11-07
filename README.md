# linux-workstation

One Bash script that turns a fresh **Ubuntu 26.04 LTS** desktop into my workstation.
Part of my TUMO Labs Guided Self-Learning, cybersecurity track, cycle 1 (KPI 1).

## Run it

On a fresh machine, as your normal user (not root), from the home folder:

```bash
cd ~ && wget -qO- https://github.com/BHarutyunyan/linux-workstation/archive/main.tar.gz | tar xz && ~/linux-workstation-main/install.sh
```

`wget` and `tar` come with Ubuntu; `git` and `curl` do not, so the script starts with them.
It asks for the sudo password once and is safe to run again.

## What it does

| Step | What | Security point |
|---|---|---|
| 1 | System update, basic tools | Updates first |
| 2 | My `.bashrc`, `.bash_aliases`, Vim, git | Linked from this repo, old files kept as `.bak-<date>` |
| 3 | ufw firewall | Deny all incoming, allow only 22/tcp |
| 4 | SSH | Keys from `github.com/BHarutyunyan.keys`; passwords and root login off; `sshd -t` before restart; passwords stay on if no key is found |
| 5 | Docker | I am not in the `docker` group (that equals root) |
| 6 | n8n in Docker | Published on `127.0.0.1:5678` only: Docker bypasses ufw, so the address matters |
| 7 | Ollama + `qwen2.5:1.5b` | `OLLAMA_HOST=127.0.0.1:11434`; manual install, no NVIDIA driver changes |
| 8 | Apps | Official repositories: Brave, Claude, ChatGPT, Discord, Obsidian, Slack, Telegram |
| 9 | GNOME | My keys, layouts (us, ru, am), theme, extensions |
| 10 | Self-check | Fails loudly if anything but 22 listens outside localhost |

After it finishes: log out and in (extensions), then `gh auth login` and `gh auth setup-git`.

## Options

`SKIP_APPS=1`, `SKIP_DESKTOP=1`, `OLLAMA_MODEL=name`, `GITHUB_USER=name`, `GIT_EMAIL=address`.

## No secrets here

No passwords, tokens or private keys are in this repository. SSH trusts only the public keys
GitHub already shows for my account. Sign-ins (GitHub, apps) are done by hand after the install.
