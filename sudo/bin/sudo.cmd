@echo off
REM sudo.cmd — shim for CMD sessions
REM Hands off to PowerShell sudo function

powershell -NoProfile -ExecutionPolicy Bypass -Command "& { . '%USERPROFILE%\CmdPlugins\ps1\sudo.ps1'; sudo %*; exit $LASTEXITCODE }"
exit /b %errorlevel%
