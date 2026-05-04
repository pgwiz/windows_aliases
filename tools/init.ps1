# NuGet post-install script for pgwiz.cmdtools
# This runs after: dotnet tool install -g pgwiz.cmdtools

param($toolsPath)

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  pgwiz Windows CMD Extensions installed                   ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Close and reopen PowerShell/CMD" -ForegroundColor DarkGray
Write-Host "  2. Run: pgwiz setup" -ForegroundColor DarkGray
Write-Host "  3. Follow the interactive wizard" -ForegroundColor DarkGray
Write-Host ""

Write-Host "Alternatively, run directly:" -ForegroundColor Cyan
Write-Host "  pgwiz" -ForegroundColor DarkGray
Write-Host ""
