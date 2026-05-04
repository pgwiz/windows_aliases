@echo off
REM refreshsudo.cmd — shim for CMD sessions
REM Hands off to PowerShell refreshsudo function

powershell -NoProfile -ExecutionPolicy Bypass -Command "& { . '%USERPROFILE%\CmdPlugins\ps1\refreshsudo.ps1'; refreshsudo %*; exit $LASTEXITCODE }"
exit /b %errorlevel%
