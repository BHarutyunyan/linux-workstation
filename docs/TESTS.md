# Test results

Machine under test: **Lenovo Legion Y520** (i5-7300HQ, 8 GB, GTX 1050), Ubuntu 26.04.1 LTS,
GNOME Shell 50.1, installed in October 2026 with no setup of my own; dual-boot with Windows.
Scanner: **ThinkPad E16**, same home network. Date: 2026-11-07.

| # | Test | How | Result |
|---|---|---|---|
| 1 | Full install with one command | `wget … main.tar.gz \| tar xz && ~/linux-workstation-main/install.sh` | **PASS** – all 10 steps, no errors, about 12 minutes |
| 2 | Safe to run again | Same command a second time | **PASS** – files `ok`, n8n container and model reused, ufw skipped existing rules, no apps reinstalled |
| 3 | Only SSH is reachable from the network | Script self-check | **PASS** – `only 22/tcp listens outside localhost` |
| 4 | Outside view | `sudo nmap -p- 192.168.15.73` from the E16 | **PASS** – only `22/tcp open ssh` ([screenshot](nmap.png)) |
| 5 | SSH accepts my key | `ssh anmahana@192.168.15.73` from the E16 | **PASS** – logged in, no password asked |
| 6 | SSH refuses passwords | `ssh -o PubkeyAuthentication=no anmahana@192.168.15.73` | **PASS** – `Permission denied (publickey)` ([screenshot](ssh-password-denied.png)) |
| 7 | n8n only on localhost | `docker port n8n`, `curl 127.0.0.1:5678` | **PASS** – `127.0.0.1:5678`, HTTP 200 |
| 8 | Ollama only on localhost | `ss -tln`, `curl 127.0.0.1:11434/api/version` | **PASS** – `127.0.0.1:11434`, version 0.40.15, `qwen2.5:1.5b` loaded |
| 9 | Desktop matches my main laptop | Log out and in | **PASS** – 7 extensions on, 3 keyboard layouts, theme, keys |
| 10 | Dual-boot switch both ways | "Windows" icon in Ubuntu, "To Ubuntu" on the Windows desktop | **PASS** on both laptops |
| 11 | Code quality | `shellcheck install.sh dualboot/to-windows` | **PASS** – 0 warnings |

## Self-check output (test 1, end of the run)

```text
==> 10. Self-check
--- TCP ports open to the network (expect only 22):
    PASS  only 22/tcp listens outside localhost
--- All listening ports (TCP):
tcp   LISTEN 0  4096   127.0.0.54:53      0.0.0.0:*
tcp   LISTEN 0  4096    127.0.0.1:5678    0.0.0.0:*      <- n8n
tcp   LISTEN 0  4096 127.0.0.53%lo:53     0.0.0.0:*
tcp   LISTEN 0  4096    127.0.0.1:32867   0.0.0.0:*
tcp   LISTEN 0  4096    127.0.0.1:631     0.0.0.0:*      <- printing
tcp   LISTEN 0  4096    127.0.0.1:11434   0.0.0.0:*      <- Ollama
tcp   LISTEN 0  4096      0.0.0.0:22      0.0.0.0:*      <- SSH, the only open door
tcp   LISTEN 0  4096        [::1]:631        [::]:*
tcp   LISTEN 0  4096         [::]:22         [::]:*
--- Firewall:
Status: active
Default: deny (incoming), allow (outgoing), deny (routed)
22/tcp                     ALLOW IN    Anywhere
22/tcp (v6)                ALLOW IN    Anywhere (v6)
--- SSH settings in force:
permitrootlogin no
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
--- n8n:
5678/tcp -> 127.0.0.1:5678
    http://127.0.0.1:5678 -> HTTP 200
--- Ollama:
    version 0.40.15
NAME            ID              SIZE      MODIFIED
qwen2.5:1.5b    65ec06548149    986 MB    2 minutes ago
```

## Problems found while testing, and fixes

| Problem | Cause | Fix |
|---|---|---|
| Wallpaper kept going back to an old picture | The app **Variety** (wallpaper changer, in autostart) reset it at login | Removed Variety; the script's setting was correct |
| Script was run by mistake on the main laptop | Same command works on any Ubuntu | Script now asks `Set up THIS machine, "<hostname>"? Type yes` first. Rolled back in minutes: originals were kept as `.bak` |
| "To Ubuntu" did nothing on Windows | 1) `bcdedit` labels are translated on Russian Windows; 2) a normal user may not start a SYSTEM task | 1) find the entry by the word `ubuntu` and its `{GUID}`; 2) allow read+execute on that one task (`(A;;GRGX;;;AU)`) |
| Old "Windows" icon ran a file from my home folder as root | `pkexec /home/…/to-windows.sh`: anything running as me could edit it | Script is now root-owned in `/usr/local/sbin` |
| Claude app: "Hardware acceleration disabled" | Intel + NVIDIA laptop after a graphics stack update, before reboot | Reboot; not caused by the script |
| Russian phonetic layout: `ю` and `ч` were on the wrong keys for me | Stock `ru(phonetic)` puts `ю` on the `` ` `` key and `ч` on `=` | Script swaps the two keys with `sed`, only inside the `phonetic` section of `/usr/share/X11/xkb/symbols/ru`; keeps `ru.bak-<date>`; skips if already done. An `xkb-data` update undoes it: run the script again |
| Soft Brightness Plus stopped working after the script ran | Script sets the whole `enabled-extensions` list, so extensions not in it were switched off | Added `soft-brightness-plus@joelkitching.com` to the list |
| Dock flickered over maximized apps (Deezer, Firefox) when the top bar was hidden | GNOME "unredirect": a window covering the whole screen skips the compositor, and the dock kept switching this on and off. Found by turning extensions off one by one: Hide Top Bar was the trigger | My dock extension calls `global.compositor.disable_unredirect()` on enable and `enable_unredirect()` on disable |

## Honest limits

- Tested on a machine with a recent, unconfigured Ubuntu, not on a freshly wiped disk.
- UDP services such as device discovery (5353, 3702) still listen, but ufw blocks all incoming
  traffic except 22/tcp.
- Desktop apps are downloaded from their vendors at install time; their versions are not pinned.
