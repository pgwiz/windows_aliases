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
