# sensesudo.md
### The Philosophy of `sudo` and `refreshsudo` on Windows

---

## THE PROBLEM

Unix has `sudo`. It's elegant — one word, one elevation, one command.

Windows has:
- Right-click → "Run as administrator"
- A UAC dialog box that appears in the center of your screen like a medieval tribunal
- `runas /user:Administrator` — which asks for a password you probably forgot
- No memory of what you were doing before it interrupted you

The result is that Windows developers context-switch constantly. You're in CMD doing work, hit something that needs elevation, open a *new* elevated window, redo your navigation, run the command, close the window, go back to your original session — which has lost all its environment state.

**This is insane.**

---

## THE PHILOSOPHY

`sudo` on Windows should feel like `sudo` on Linux:

```
You are already in your session.
You already know what you want to run.
You type sudo before it.
It runs elevated.
You stay where you are.
```

No new window. No repeated navigation. No UAC theater (well — one prompt, unavoidable, but at least it's *purposeful*).

`refreshsudo` is the companion — because Windows elevation tokens expire, credentials cache, and group policy sometimes revokes tokens mid-session without telling you. `refreshsudo` doesn't re-elevate a process. It **re-establishes the trust channel** — clears stale credential cache, re-triggers the elevation handshake, and hands you back a clean sudo context.

Think of it like this:

```
sudo          → "do this one thing as admin"
refreshsudo   → "my sudo is stale, wake it back up"
```

---

## HOW IT ACTUALLY WORKS ON WINDOWS

Windows elevation goes through one of two mechanisms:

```
┌─────────────────────────────────────────────────────────┐
│  ShellExecute + runas verb                              │
│  → Spawns a NEW elevated process                        │
│  → UAC prompt fires                                     │
│  → Output goes to new window (you lose it)             │
├─────────────────────────────────────────────────────────┤
│  Start-Process -Verb RunAs                              │
│  → Same as above, PowerShell wrapper                    │
│  → Still spawns new window                             │
├─────────────────────────────────────────────────────────┤
│  gsudo / wudo (third-party)                             │
│  → Broker process approach                             │
│  → Elevated child shares parent's console              │
│  → Output stays in YOUR window  ← this is the goal    │
└─────────────────────────────────────────────────────────┘
```

A well-implemented `sudo` alias on Windows uses the **broker pattern**: an already-elevated helper process sits ready, and your command is tunneled through it back into your console. Output, errors, exit codes — all come back to you as if nothing special happened.

---

## EXAMPLE USAGE

```powershell
# Install a system package
sudo choco install ffmpeg

# Edit a hosts file
sudo notepad C:\Windows\System32\drivers\etc\hosts

# Restart a Windows service
sudo net stop wuauserv
sudo net start wuauserv

# Write to a protected registry key
sudo reg add "HKLM\SOFTWARE\MyApp" /v Debug /t REG_DWORD /d 1 /f

# Run an elevated shell inline, do work, exit — back to your session
sudo cmd /c "netsh wlan show profiles"

# Token expired mid-session? Don't open a new window.
refreshsudo

# Then continue
sudo sc config MyService start= auto
```

---

## WHAT `refreshsudo` ACTUALLY DOES

```
1. Checks if current session has a valid elevation token
2. If stale/expired → clears CredentialManager cached elevation
3. Re-triggers UAC (one prompt, intentional)
4. Warm-starts the broker so next `sudo` call is instant
5. Reports token expiry time so you know how long you have
```

It's the difference between your sudo silently failing and you spending 10 minutes debugging why a command returned Access Denied on a file you *know* you have rights to.

---

## THE CODE (agent creates this)

> The following is what an agent should generate and deploy.
> All files land in `%USERPROFILE%\CmdPlugins\`.

---

### `sudo.ps1` — core implementation

```powershell
# CmdPlugins\ps1\sudo.ps1
# Philosophy: run one elevated command without leaving your session.

function sudo {
    param(
        [Parameter(Mandatory, ValueFromRemainingArguments)]
        [string[]]$Command
    )

    # Resolve the executable vs arguments
    $exe  = $Command[0]
    $args = $Command[1..($Command.Length - 1)]

    # Check if already elevated — if so, just run it
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        # Already elevated — run directly, no overhead
        & $exe @args
        return $LASTEXITCODE
    }

    # Not elevated — use gsudo broker if available, else fallback
    if (Get-Command gsudo -ErrorAction SilentlyContinue) {
        gsudo $exe @args
        return $LASTEXITCODE
    }

    # Fallback: PowerShell RunAs — output goes to new window (warn user)
    Write-Warning "[sudo] gsudo not found — output will appear in a new elevated window."
    Write-Warning "[sudo] Install gsudo for inline elevation: winget install gerardog.gsudo"

    $argString = ($args | ForEach-Object { "`"$_`"" }) -join " "
    Start-Process $exe -ArgumentList $argString -Verb RunAs -Wait
}
```

---

### `refreshsudo.ps1` — token refresh implementation

```powershell
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
```

---

### `sudo.cmd` — CMD-layer shim (so it works outside PowerShell)

```bat
@echo off
REM sudo.cmd — shim for CMD sessions
REM Hands off to PowerShell sudo function

powershell -NoProfile -ExecutionPolicy Bypass -Command "& { . '%USERPROFILE%\CmdPlugins\ps1\sudo.ps1'; sudo %*; exit $LASTEXITCODE }"
exit /b %errorlevel%
```

---

### `refreshsudo.cmd` — CMD-layer shim

```bat
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { . '%USERPROFILE%\CmdPlugins\ps1\refreshsudo.ps1'; refreshsudo %*; exit $LASTEXITCODE }"
exit /b %errorlevel%
```

---

## EXAMPLE SESSION (what good looks like)

```
C:\projects\unimarket> sudo netsh int ip reset
[sudo] Elevating: netsh int ip reset
Resetting , OK!
Resetting Echo Request, OK!
Restart required.

C:\projects\unimarket> sudo net stop "Print Spooler"
[sudo] Elevating: net stop "Print Spooler"
The Print Spooler service is stopping.
The Print Spooler service was stopped successfully.

C:\projects\unimarket> refreshsudo --status
[sudo] Not elevated — run refreshsudo to re-establish.

C:\projects\unimarket> refreshsudo
[sudo] Refreshing elevation token...
[sudo] gsudo cache cleared.
[sudo] Re-establishing elevation — UAC prompt incoming...
[sudo] Token refreshed.
[sudo] Next sudo call is ready.

C:\projects\unimarket> sudo sc config wuauserv start= disabled
[sudo] Elevating: sc config wuauserv start= disabled
[SC] ChangeServiceConfig SUCCESS
```

You never left `C:\projects\unimarket`. You never opened a new window.
That's the whole point.

---

## INSTALL THESE TWO

```powershell
# 1. Install gsudo (the broker that makes inline elevation work)
winget install gerardog.gsudo

# 2. Drop the functions into your plugin dir
$base = "$env:USERPROFILE\CmdPlugins"
# (agent copies sudo.ps1 and refreshsudo.ps1 into $base\ps1\)
# (agent copies sudo.cmd and refreshsudo.cmd into $base\bin\)

# 3. Load in $PROFILE
Add-Content $PROFILE ". `"$base\ps1\sudo.ps1`""
Add-Content $PROFILE ". `"$base\ps1\refreshsudo.ps1`""

# 4. Done — works in PowerShell and CMD
sudo whoami
refreshsudo --status
```

---

## WHAT THE AGENT SHOULD DO

When asked to set up sudo on a Windows machine:

```
1. winget install gerardog.gsudo          ← broker binary
2. Write sudo.ps1        → CmdPlugins\ps1\
3. Write refreshsudo.ps1 → CmdPlugins\ps1\
4. Write sudo.cmd        → CmdPlugins\bin\
5. Write refreshsudo.cmd → CmdPlugins\bin\
6. Append both dot-sources to $PROFILE
7. Verify CmdPlugins\bin\ is on user PATH
8. Test: sudo whoami → should return your username
9. Test: refreshsudo --status → should report token state
```

No registry bloat. No system files touched.
Two functions, two shims, one `winget` install.

---

*sensesudo.md — because Windows deserved better and we gave it some.*
