# Sudo on Windows: Complete Setup & Deployment Guide

Your `sudo` and `refreshsudo` commands are now installed and ready for use.

---

## 📋 Quick Start

### In PowerShell:
```powershell
# Check elevation status
refreshsudo --status

# Run a command with elevation
sudo whoami

# Refresh stale elevation token (if needed)
refreshsudo
```

### In CMD.exe:
```cmd
REM Same commands work in CMD
sudo whoami
refreshsudo --status
refreshsudo
```

---

## 📁 Installation Structure

All files are located in: `%USERPROFILE%\CmdPlugins\`

```
CmdPlugins\
├── ps1\
│   ├── sudo.ps1          ← Main sudo function
│   └── refreshsudo.ps1   ← Token refresh function
├── bin\
│   ├── sudo.cmd          ← CMD shim for sudo
│   └── refreshsudo.cmd   ← CMD shim for refreshsudo
├── lib\                  ← (Reserved for DLLs)
├── help\                 ← (Reserved for help files)
├── macros\               ← (Reserved for DOSKEY macros)
├── registry\             ← Backup of registry keys
├── DEPLOYMENT_MANIFEST.md ← This deployment record
├── setup-sudo.ps1        ← Installation script
├── backup-registry.ps1   ← Backup your registry state
└── uninstall-sudo.ps1    ← Clean uninstall script
```

---

## 🔧 How It Works

### `sudo` Command

Runs a single command with administrator elevation:

```powershell
# These work seamlessly:
sudo whoami                    # Shows: DOMAIN\Administrator
sudo net stop "Print Spooler"
sudo reg add HKLM\... /v ... /t REG_DWORD
```

**Implementation:**
- If already elevated → runs directly (no overhead)
- If not elevated + `gsudo` available → uses broker (inline, no new window)
- If not elevated + `gsudo` missing → fallback to PowerShell RunAs (opens new window)

### `refreshsudo` Command

Refreshes a stale elevation token:

```powershell
refreshsudo --status          # Check token state
refreshsudo                   # Refresh with UAC prompt
refreshsudo --force           # Force refresh anyway
```

**What it does:**
1. Clears cached credentials that may be stale
2. Resets gsudo broker cache (if available)
3. Re-triggers UAC prompt to establish fresh elevation
4. Warm-starts gsudo for next `sudo` call

---

## 🚀 Deployment & Backup

### First Time Setup

If you run this manually:
```powershell
& "$env:USERPROFILE\CmdPlugins\setup-sudo.ps1"
```

Or with options:
```powershell
# Skip gsudo installation (already installed)
& "$env:USERPROFILE\CmdPlugins\setup-sudo.ps1" -SkipGsudo

# Skip PATH update (already in PATH)
& "$env:USERPROFILE\CmdPlugins\setup-sudo.ps1" -SkipPathUpdate
```

### Backup Your Setup

Export current state for safe restore:
```powershell
& "$env:USERPROFILE\CmdPlugins\backup-registry.ps1"
```

This creates timestamped backups in: `CmdPlugins\registry\`

### Clean Uninstall

Remove integration (preserves files):
```powershell
& "$env:USERPROFILE\CmdPlugins\uninstall-sudo.ps1"
```

Remove integration + delete files:
```powershell
& "$env:USERPROFILE\CmdPlugins\uninstall-sudo.ps1" -RemoveFiles
```

---

## 📤 Making It Exportable (Team Deployment)

### Option 1: Copy the Entire Folder

```powershell
# On source machine:
Copy-Item "$env:USERPROFILE\CmdPlugins" -Destination "D:\backup" -Recurse

# On target machine:
Copy-Item "D:\backup\CmdPlugins" -Destination "$env:USERPROFILE\" -Recurse
& "$env:USERPROFILE\CmdPlugins\setup-sudo.ps1"
```

### Option 2: Create a Deployment Package

```powershell
# Create a .zip with everything
Compress-Archive -Path "$env:USERPROFILE\CmdPlugins" `
  -DestinationPath "sudo-windows-deployment.zip"

# On target machine: Extract and run setup
Expand-Archive -Path "sudo-windows-deployment.zip" -DestinationPath "$env:USERPROFILE"
& "$env:USERPROFILE\CmdPlugins\setup-sudo.ps1"
```

### Option 3: Version Control (Git)

```powershell
# Add to your team's repo
git add CmdPlugins/
git commit -m "Add sudo/refreshsudo commands"

# On other machines
git clone <repo>
& "CmdPlugins\setup-sudo.ps1"
```

---

## 🔒 Security Notes

- ✅ All scripts use user-space directories (no system files touched)
- ✅ Elevation is broker-based (not raw `runas`)
- ✅ Everything stored in `%USERPROFILE%\CmdPlugins\` (reversible)
- ✅ Credentials cleared on `refreshsudo` to prevent token reuse attacks
- ✅ No registry HKLM modifications (current user only)

---

## 📝 Registry Changes

Files modified:
- **`$PROFILE`** (PowerShell profile)
  - Added dot-source for `sudo.ps1`
  - Added dot-source for `refreshsudo.ps1`
  
- **User PATH environment variable**
  - Added `%USERPROFILE%\CmdPlugins\bin\`

Registry backups saved to: `CmdPlugins\registry\` for restore if needed.

---

## 🆘 Troubleshooting

### `sudo` opens a new window instead of running inline

**Cause:** `gsudo` broker not installed or not found in PATH

**Fix:**
```powershell
winget install gerardog.gsudo
# OR
choco install gsudo
```

### Functions not found after opening new PowerShell

**Cause:** $PROFILE not loaded in the new session

**Fix:** Close all PowerShell windows and reopen. The profile auto-loads on startup.

Or manually reload:
```powershell
. $PROFILE
```

### `refreshsudo` says "Not elevated"

**Expected behavior** — you're not in an elevated session. Run `refreshsudo` to establish elevation.

After running `refreshsudo`, next `sudo` command will work inline without new window.

---

## 📊 Deployment Manifest

See: `DEPLOYMENT_MANIFEST.md` for full record of what was deployed.

---

**Setup Date:** 2026-05-04  
**Version:** 1.0  
**Status:** ✅ Ready for export and team deployment
