# CmdPlugins Deployment Manifest
# Generated: 2026-05-04
# Version: 1.0

## DEPLOYED FILES

### PowerShell Functions (ps1\)
- sudo.ps1
  Purpose: Elevation broker for single elevated commands
  Type: PowerShell function
  Exported: Yes

- refreshsudo.ps1
  Purpose: Refresh stale elevation tokens
  Type: PowerShell function
  Exported: Yes

### CMD Shims (bin\)
- sudo.cmd
  Purpose: CMD-layer wrapper for sudo PS1 function
  Type: Batch script
  Exported: Yes

- refreshsudo.cmd
  Purpose: CMD-layer wrapper for refreshsudo PS1 function
  Type: Batch script
  Exported: Yes

### Dependencies
- gsudo (winget: gerardog.gsudo)
  Purpose: Broker process for inline elevation
  Type: External executable
  Status: Required for optimal operation (fallback to RunAs if missing)

## REGISTRY MODIFICATIONS

Key: HKCU\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell
Property: $PROFILE (user's PowerShell profile file)
Action: Dot-source sudo.ps1 and refreshsudo.ps1 on profile load

## ENVIRONMENT MODIFICATIONS

- PATH: Ensure %USERPROFILE%\CmdPlugins\bin\ is included for .cmd shim discovery

## BACKUP & RESTORE

Registry backups stored in: %USERPROFILE%\CmdPlugins\registry\
Use backup-registry.ps1 to export current registry state
Use restore-registry.ps1 to restore from backup

## CLEAN UNINSTALL

Run: uninstall-sudo.ps1
This will:
1. Remove dot-source entries from $PROFILE
2. Remove PATH entry for CmdPlugins\bin
3. Preserve all files in CmdPlugins\ (manual delete if desired)
4. Restore backed-up registry keys
