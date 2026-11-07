# to-ubuntu-setup.ps1  (Windows side of my dual-boot)
#
# Creates a desktop shortcut "To Ubuntu": one click reboots ONCE into Ubuntu.
# Windows stays the default boot entry, so a normal restart comes back here.
#
# Run once in PowerShell as administrator (Win+X -> Terminal (Admin)):
#     powershell -ExecutionPolicy Bypass -File .\to-ubuntu-setup.ps1
#
# Undo:
#     Unregister-ScheduledTask -TaskName ToUbuntu -Confirm:$false
#     Remove-Item -Recurse "$env:ProgramFiles\ToUbuntu"
#     Remove-Item "$([Environment]::GetFolderPath('Desktop'))\To Ubuntu.lnk"

$ErrorActionPreference = 'Stop'
$dir = "$env:ProgramFiles\ToUbuntu"

# 1. The script. It lives in Program Files, where only administrators can
#    write: a SYSTEM task must never run a file that normal users can edit.
New-Item -ItemType Directory -Force -Path $dir | Out-Null
@'
# Reboot ONCE into Ubuntu. Windows stays the default boot entry.
# Works in any Windows language: bcdedit labels are translated
# ("identifier" = "идентификатор"), so it looks for "ubuntu" and takes the {GUID}.
$log    = "$env:ProgramFiles\ToUbuntu\last-run.log"
$blocks = (bcdedit /enum firmware | Out-String) -split "\r?\n\s*\r?\n"
$entry  = $blocks | Where-Object { $_ -match 'ubuntu' } | Select-Object -First 1
$guid   = '\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}'
if ($entry -match $guid) {
    "$(Get-Date)  next boot: Ubuntu $($Matches[0])" | Out-File $log
    bcdedit /set '{fwbootmgr}' bootsequence $Matches[0] | Out-Null
    shutdown /r /t 0
} else {
    "$(Get-Date)  ERROR: Ubuntu entry not found" | Out-File $log
}
'@ | Set-Content -Path "$dir\to-ubuntu.ps1" -Encoding UTF8

# 2. A task that runs the script as SYSTEM, so the click needs no UAC prompt.
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dir\to-ubuntu.ps1`""
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'ToUbuntu' -Action $action -Principal $principal -Force | Out-Null

# 3. Let signed-in users START this one task (read + execute, nothing more).
#    Without it the shortcut fails silently with "Access is denied".
$svc  = New-Object -ComObject Schedule.Service
$svc.Connect()
$task = $svc.GetFolder('\').GetTask('ToUbuntu')
$sd   = $task.GetSecurityDescriptor(0xF)
if ($sd -notmatch [regex]::Escape('(A;;GRGX;;;AU)')) {
    $task.SetSecurityDescriptor($sd + '(A;;GRGX;;;AU)', 0)
}

# 4. The shortcut.
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut(
    "$([Environment]::GetFolderPath('Desktop'))\To Ubuntu.lnk")
$lnk.TargetPath   = "$env:SystemRoot\System32\schtasks.exe"
$lnk.Arguments    = '/run /tn "ToUbuntu"'
$lnk.WindowStyle  = 7
$lnk.IconLocation = "$env:SystemRoot\System32\shell32.dll,27"
$lnk.Save()

"Done: double-click 'To Ubuntu' on the desktop."
