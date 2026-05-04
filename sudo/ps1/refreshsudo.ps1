# CmdPlugins\ps1\refreshsudo.ps1
# Philosophy: stale elevation shouldn't kill your session flow.

function refreshsudo {
    param(
        [switch]$Status,    # just report current token state, don't refresh
        [switch]$Force      # force refresh even if token looks valid
    )

    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # ── Status only ──────────────────────────────────────────────────
    if ($Status) {
        if ($isAdmin) {
            Write-Host "[sudo] " -NoNewline -ForegroundColor DarkGray
            Write-Host "Elevated" -ForegroundColor Green -NoNewline
            Write-Host " — token is active." -ForegroundColor DarkGray
        } else {
            Write-Host "[sudo] " -NoNewline -ForegroundColor DarkGray
            Write-Host "Not elevated" -ForegroundColor Yellow -NoNewline
            Write-Host " — run refreshsudo to re-establish." -ForegroundColor DarkGray
        }
        return
    }

    # ── Already elevated and not forcing ─────────────────────────────
    if ($isAdmin -and -not $Force) {
        Write-Host "[sudo] Token is current. Use -Force to refresh anyway." -ForegroundColor Green
        return
    }

    Write-Host "[sudo] Refreshing elevation token..." -ForegroundColor Cyan

    # Step 1: Clear cached credentials that may be stale
    $credTargets = cmdkey /list 2>$null |
        Select-String "Target:" |
        ForEach-Object { ($_ -split "Target:\s*")[1].Trim() } |
        Where-Object { $_ -match "elevation|admin|runas|sudo" }

    foreach ($target in $credTargets) {
        cmdkey /delete:$target 2>$null | Out-Null
    }

    # Step 2: If gsudo is present, reset its cache
    if (Get-Command gsudo -ErrorAction SilentlyContinue) {
        gsudo cache off 2>$null
        Write-Host "[sudo] gsudo cache cleared." -ForegroundColor DarkGray
    }

    # Step 3: Re-trigger elevation handshake (one UAC prompt)
    Write-Host "[sudo] Re-establishing elevation — UAC prompt incoming..." -ForegroundColor Yellow

    $result = Start-Process powershell -ArgumentList "-NoProfile -Command exit 0" `
        -Verb RunAs -Wait -PassThru 2>$null

    if ($result.ExitCode -eq 0) {
        # Step 4: Warm-start gsudo broker so next sudo is instant
        if (Get-Command gsudo -ErrorAction SilentlyContinue) {
            gsudo cache on 2>$null
            Write-Host "[sudo] gsudo broker warm-started." -ForegroundColor DarkGray
        }

        Write-Host "[sudo] " -NoNewline -ForegroundColor DarkGray
        Write-Host "Token refreshed." -ForegroundColor Green
        Write-Host "[sudo] Next sudo call is ready." -ForegroundColor DarkGray
    } else {
        Write-Host "[sudo] " -NoNewline -ForegroundColor DarkGray
        Write-Host "Refresh failed or was cancelled." -ForegroundColor Red
        Write-Host "[sudo] UAC was denied or timed out." -ForegroundColor DarkGray
    }
}
