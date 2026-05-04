# CmdPlugins\uninstall-sudo.ps1
# Clean removal of sudo and refreshsudo (preserves files, removes integration)

param(
    [switch]$RemoveFiles
)

$ErrorActionPreference = "Stop"

$base = "$env:USERPROFILE\CmdPlugins"

Write-Host "[→] Uninstalling sudo and refreshsudo..."
Write-Host ""

# ──────────────────────────────────────────────────────────────────────
# 1. Remove from PowerShell profile
# ──────────────────────────────────────────────────────────────────────

Write-Host "[→] Removing from PowerShell profile..."

if (Test-Path $PROFILE) {
    $content = Get-Content $PROFILE -Raw
    $original = $content
    
    $content = $content -replace "^\s*\.\s*`"$base\\ps1\\sudo\.ps1`"\s*`r?`n?", ""
    $content = $content -replace "^\s*\.\s*`"$base\\ps1\\refreshsudo\.ps1`"\s*`r?`n?", ""
    
    if ($content -ne $original) {
        $content | Set-Content $PROFILE
        Write-Host "  [+] Removed dot-source entries"
    } else {
        Write-Host "  [~] No entries found to remove"
    }
} else {
    Write-Host "  [~] Profile not found: $PROFILE"
}

# ──────────────────────────────────────────────────────────────────────
# 2. Remove from PATH
# ──────────────────────────────────────────────────────────────────────

Write-Host "`n[→] Removing from PATH..."

$binPath = "$base\bin"
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")

if ($currentPath -match [regex]::Escape($binPath)) {
    $newPath = $currentPath -replace [regex]::Escape($binPath) + ";?", ""
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    Write-Host "  [+] Removed from PATH: $binPath"
} else {
    Write-Host "  [~] Not found in PATH"
}

# ──────────────────────────────────────────────────────────────────────
# 3. Optional: Remove files
# ──────────────────────────────────────────────────────────────────────

if ($RemoveFiles) {
    Write-Host "`n[→] Removing files..."
    
    $filesToRemove = @(
        "$base\ps1\sudo.ps1",
        "$base\ps1\refreshsudo.ps1",
        "$base\bin\sudo.cmd",
        "$base\bin\refreshsudo.cmd"
    )
    
    foreach ($file in $filesToRemove) {
        if (Test-Path $file) {
            Remove-Item $file -Force
            Write-Host "  [+] Removed: $(Split-Path $file -Leaf)"
        }
    }
}

Write-Host "`n" -ForegroundColor Green
Write-Host "[✓] Uninstall complete!" -ForegroundColor Green

if (-not $RemoveFiles) {
    Write-Host "`nFiles preserved in: $base" -ForegroundColor DarkGray
    Write-Host "To remove files, run: uninstall-sudo.ps1 -RemoveFiles" -ForegroundColor DarkGray
}

Write-Host "`nNote: Close and reopen PowerShell/CMD for changes to take effect.`n"
