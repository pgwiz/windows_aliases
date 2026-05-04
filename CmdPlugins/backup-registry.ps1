# CmdPlugins\backup-registry.ps1
# Export current registry state and PowerShell profile

param(
    [string]$BackupDir = "$env:USERPROFILE\CmdPlugins\registry"
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = Join-Path $BackupDir "registry_backup_$timestamp.reg"

Write-Host "[→] Backing up registry state..."

# Backup PowerShell registry key (if it exists)
$regPath = "HKCU:\Software\Microsoft\PowerShell"
if (Test-Path $regPath) {
    Write-Host "  [+] Exporting: $regPath"
    reg export "HKEY_CURRENT_USER\Software\Microsoft\PowerShell" $backupFile /y | Out-Null
    Write-Host "  [✓] Saved to: $backupFile"
} else {
    Write-Host "  [~] No PowerShell registry keys to backup"
}

# Also backup the $PROFILE content
$profileBackup = Join-Path $BackupDir "profile_backup_$timestamp.ps1"
if (Test-Path $PROFILE) {
    Write-Host "  [+] Backing up PowerShell profile"
    Copy-Item $PROFILE $profileBackup
    Write-Host "  [✓] Saved to: $profileBackup"
}

Write-Host "`n[✓] Backup complete!" -ForegroundColor Green
