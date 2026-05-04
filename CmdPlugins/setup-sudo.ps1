# CmdPlugins\setup-sudo.ps1
# Deployment script: Install sudo and refreshsudo

param(
    [switch]$SkipGsudo,
    [switch]$SkipPathUpdate
)

$ErrorActionPreference = "Stop"

# ──────────────────────────────────────────────────────────────────────
# 1. Verify CmdPlugins structure
# ──────────────────────────────────────────────────────────────────────

$base = "$env:USERPROFILE\CmdPlugins"
$requiredDirs = @("ps1", "bin", "lib", "help", "macros", "registry")

Write-Host "[→] Verifying CmdPlugins structure..."
foreach ($dir in $requiredDirs) {
    $path = Join-Path $base $dir
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Host "  [+] Created: $dir\"
    } else {
        Write-Host "  [✓] Exists: $dir\"
    }
}

# ──────────────────────────────────────────────────────────────────────
# 2. Install gsudo (if not skipped)
# ──────────────────────────────────────────────────────────────────────

if (-not $SkipGsudo) {
    Write-Host "`n[→] Installing gsudo broker..."
    $gsudoCheck = Get-Command gsudo -ErrorAction SilentlyContinue
    if ($gsudoCheck) {
        Write-Host "  [✓] gsudo already installed: $($gsudoCheck.Source)"
    } else {
        Write-Host "  [+] Running: winget install gerardog.gsudo"
        winget install gerardog.gsudo --silent
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [✓] gsudo installed successfully"
        } else {
            Write-Warning "  [!] gsudo installation may require manual intervention"
        }
    }
}

# ──────────────────────────────────────────────────────────────────────
# 3. Add to PowerShell profile
# ──────────────────────────────────────────────────────────────────────

Write-Host "`n[→] Updating PowerShell profile..."

if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    Write-Host "  [+] Created profile: $PROFILE"
}

$sudoSource = ". `"$base\ps1\sudo.ps1`""
$refreshsudoSource = ". `"$base\ps1\refreshsudo.ps1`""

$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($profileContent -notmatch [regex]::Escape($sudoSource)) {
    Add-Content $PROFILE "`n$sudoSource"
    Write-Host "  [+] Added sudo.ps1 to profile"
} else {
    Write-Host "  [✓] sudo.ps1 already in profile"
}

if ($profileContent -notmatch [regex]::Escape($refreshsudoSource)) {
    Add-Content $PROFILE "`n$refreshsudoSource"
    Write-Host "  [+] Added refreshsudo.ps1 to profile"
} else {
    Write-Host "  [✓] refreshsudo.ps1 already in profile"
}

# ──────────────────────────────────────────────────────────────────────
# 4. Add to PATH (if not skipped)
# ──────────────────────────────────────────────────────────────────────

if (-not $SkipPathUpdate) {
    Write-Host "`n[→] Updating PATH environment variable..."
    
    $binPath = "$base\bin"
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    
    if ($currentPath -notmatch [regex]::Escape($binPath)) {
        $newPath = "$binPath;$currentPath"
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Host "  [+] Added to PATH: $binPath"
    } else {
        Write-Host "  [✓] Already in PATH: $binPath"
    }
}

# ──────────────────────────────────────────────────────────────────────
# 5. Test sudo function (in current PowerShell session)
# ──────────────────────────────────────────────────────────────────────

Write-Host "`n[→] Loading and testing functions..."

. "$base\ps1\sudo.ps1"
. "$base\ps1\refreshsudo.ps1"

if (Get-Command sudo -ErrorAction SilentlyContinue) {
    Write-Host "  [✓] sudo function loaded"
} else {
    Write-Host "  [✗] sudo function load failed"
}

if (Get-Command refreshsudo -ErrorAction SilentlyContinue) {
    Write-Host "  [✓] refreshsudo function loaded"
} else {
    Write-Host "  [✗] refreshsudo function load failed"
}

# ──────────────────────────────────────────────────────────────────────
# 6. Summary
# ──────────────────────────────────────────────────────────────────────

Write-Host "`n" -ForegroundColor Green
Write-Host "[✓] Setup complete!" -ForegroundColor Green
Write-Host "`nYour sudo and refreshsudo commands are ready.`n"
Write-Host "Quick test:" -ForegroundColor Cyan
Write-Host "  powershell> refreshsudo --status" -ForegroundColor DarkGray
Write-Host "  powershell> sudo whoami" -ForegroundColor DarkGray
Write-Host "`nNote: Close and reopen PowerShell/CMD for PATH changes to take effect.`n"
