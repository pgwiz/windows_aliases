# WINDOWS CMD EXTENSIONS — AGENT GUIDE
### Pluggable Aliases, DLL Command Libraries, Help Integration & Clean Uninstall

---

## TABLE OF CONTENTS

1. [Architecture Overview](#1-architecture-overview)
2. [Layer 1 — Simple Aliases (doskey)](#2-layer-1--simple-aliases-doskey)
3. [Layer 2 — PowerShell Function Aliases](#3-layer-2--powershell-function-aliases)
4. [Layer 3 — Batch Script Commands (PATH injection)](#4-layer-3--batch-script-commands-path-injection)
5. [Layer 4 — DLL-backed Commands (C# / .NET)](#5-layer-4--dll-backed-commands-c--net)
6. [Layer 5 — Native C++ CMD Extension DLL](#6-layer-5--native-c-cmd-extension-dll)
7. [Registering Commands in Windows Help (HELP command)](#7-registering-commands-in-windows-help-help-command)
8. [Custom HELP Tab / Help System](#8-custom-help-tab--help-system)
9. [Plugin Registry — Centralized Manifest](#9-plugin-registry--centralized-manifest)
10. [Agent Workflow — Full Deployment Script](#10-agent-workflow--full-deployment-script)
11. [Clean Uninstall — Full Removal](#11-clean-uninstall--full-removal)
12. [Security Considerations](#12-security-considerations)
13. [Quick Reference Card](#13-quick-reference-card)

---

## 1. ARCHITECTURE OVERVIEW

Windows CMD extensions operate across **five layers** of increasing power and integration depth:

```
┌─────────────────────────────────────────────────────────┐
│  LAYER 5 │ Native C++ DLL  (HKCU\Software\Microsoft\    │
│          │ Command Processor\AutoRun hooks)              │
├─────────────────────────────────────────────────────────┤
│  LAYER 4 │ .NET / C# EXE backed by a registered DLL     │
│          │ (GAC or local, callable from PATH)            │
├─────────────────────────────────────────────────────────┤
│  LAYER 3 │ .bat / .cmd scripts injected into PATH       │
│          │ via per-user Environment variable             │
├─────────────────────────────────────────────────────────┤
│  LAYER 2 │ PowerShell $PROFILE functions / aliases      │
│          │ (survives sessions, cross-shell capable)      │
├─────────────────────────────────────────────────────────┤
│  LAYER 1 │ DOSKEY macros loaded via AutoRun registry    │
│          │ (lightweight, CMD-session scoped)             │
└─────────────────────────────────────────────────────────┘
```

**Key Principle**: All layers write to **HKCU** (current user) or user-space directories — no `HKLM`, no UAC elevation required. Everything is reversible.

**Plugin root directory convention:**
```
%USERPROFILE%\CmdPlugins\
  ├── bin\          ← .bat/.cmd/.exe commands live here (added to PATH)
  ├── lib\          ← .dll files
  ├── help\         ← .txt help files per command
  ├── macros\       ← doskey macro definition files (.mac)
  └── registry\     ← backup of registry keys for clean uninstall
```

---

## 2. LAYER 1 — SIMPLE ALIASES (DOSKEY)

### What it is
`DOSKEY` macros are CMD-session aliases. By hooking the `AutoRun` registry key they load automatically in every new CMD window.

### 2.1 — Create a macro file

```bat
REM %USERPROFILE%\CmdPlugins\macros\aliases.mac

cls=cls & echo [Cleared]
ll=dir /a /w $*
gs=git status $*
gp=git push $*
gc=git commit -m $*
up=cd ..
back=cd -
myip=curl -s https://api.ipify.org & echo.
```

> `$*` passes all arguments through. `$1`–`$9` for positional args.

### 2.2 — Load macros via AutoRun registry key

```bat
REM install_doskey.bat
@echo off
set MACRO_FILE=%USERPROFILE%\CmdPlugins\macros\aliases.mac
set AUTORUN_CMD=doskey /macrofile="%MACRO_FILE%"

reg add "HKCU\Software\Microsoft\Command Processor" ^
    /v AutoRun /t REG_SZ /d "%AUTORUN_CMD%" /f

echo [OK] DOSKEY macros will load in every new CMD session.
```

### 2.3 — If AutoRun already has a value (chain it)

```bat
REM Read existing value first
for /f "tokens=3 delims= " %%A in ('reg query "HKCU\Software\Microsoft\Command Processor" /v AutoRun 2^>nul') do set EXISTING=%%A

if defined EXISTING (
    reg add "HKCU\Software\Microsoft\Command Processor" /v AutoRun /t REG_SZ ^
        /d "%EXISTING% & doskey /macrofile=\"%MACRO_FILE%\"" /f
) else (
    reg add "HKCU\Software\Microsoft\Command Processor" /v AutoRun /t REG_SZ ^
        /d "doskey /macrofile=\"%MACRO_FILE%\"" /f
)
```

### 2.4 — Add a new macro at runtime

```bat
doskey myalias=echo hello $*
REM Persists only for current session unless added to .mac file
```

---

## 3. LAYER 2 — POWERSHELL FUNCTION ALIASES

### 3.1 — Profile location

```powershell
# Check your profile path
$PROFILE
# Typically: C:\Users\<you>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
```

### 3.2 — Define a function (true alias with logic)

```powershell
# In $PROFILE or a dot-sourced file:

function which($name) {
    Get-Command $name -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

function touch($file) {
    if (!(Test-Path $file)) { New-Item $file -ItemType File | Out-Null }
    else { (Get-Item $file).LastWriteTime = Get-Date }
}

function mkcd($dir) {
    New-Item -ItemType Directory -Force $dir | Set-Location
}

# Simple alias
Set-Alias -Name ll -Value Get-ChildItem
```

### 3.3 — Modular plugin loading

```powershell
# In $PROFILE — load all plugin .ps1 files from plugin dir
$pluginDir = "$env:USERPROFILE\CmdPlugins\ps1"
if (Test-Path $pluginDir) {
    Get-ChildItem "$pluginDir\*.ps1" | ForEach-Object { . $_.FullName }
}
```

Each plugin is a standalone `.ps1` file:

```powershell
# CmdPlugins\ps1\git-helpers.ps1

function glog {
    git log --oneline --graph --decorate --all @args
}

function gclean {
    git fetch --prune
    git branch --merged | Where-Object { $_ -notmatch '\*|main|master|develop' } |
        ForEach-Object { git branch -d $_.Trim() }
}
```

---

## 4. LAYER 3 — BATCH SCRIPT COMMANDS (PATH INJECTION)

Any `.bat` or `.cmd` file in a directory on `%PATH%` becomes a callable command.

### 4.1 — Add plugin bin dir to user PATH (no elevation)

```bat
REM add_to_path.bat
@echo off
set PLUGIN_BIN=%USERPROFILE%\CmdPlugins\bin

REM Read current user PATH
for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v PATH 2^>nul') do set CURRENT_PATH=%%B

REM Check if already in PATH
echo %CURRENT_PATH% | find /i "%PLUGIN_BIN%" >nul
if %errorlevel%==0 (
    echo [SKIP] Already in PATH.
    exit /b 0
)

REM Append
setx PATH "%CURRENT_PATH%;%PLUGIN_BIN%"
echo [OK] Added %PLUGIN_BIN% to user PATH. Restart CMD to apply.
```

### 4.2 — A well-structured command script with built-in help

```bat
REM %USERPROFILE%\CmdPlugins\bin\mygrep.cmd
@echo off
setlocal

if "%~1"=="" goto :usage
if "%~1"=="/?" goto :usage
if /i "%~1"=="--help" goto :usage

REM Main logic
findstr /i /s %* 2>nul
goto :eof

:usage
echo.
echo MYGREP — Case-insensitive recursive string search
echo.
echo Usage:  mygrep [options] "pattern" [path]
echo.
echo Options:
echo   /?  --help    Show this help
echo   /n            Print line numbers
echo   /c            Count matching lines only
echo.
echo Examples:
echo   mygrep "TODO" .
echo   mygrep /n "function" src\
echo.
exit /b 0
```

### 4.3 — Versioned command with metadata header

```bat
REM ===================================================
REM Command : mygrep
REM Version : 1.0.0
REM Author  : pgwiz
REM Plugin  : search-tools
REM Requires: findstr (built-in)
REM ===================================================
```

---

## 5. LAYER 4 — DLL-BACKED COMMANDS (C# / .NET)

A C# project compiles to either:
- A standalone `.exe` (callable directly from PATH)
- A `.dll` referenced by a thin launcher `.exe`

### 5.1 — Project structure

```
CmdPlugins\
  src\
    MyCmdTools\
      MyCmdTools.csproj
      Commands\
        HelloCommand.cs
        GreetCommand.cs
      EntryPoint.cs
      PluginManifest.cs
```

### 5.2 — The project file

```xml
<!-- MyCmdTools.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <AssemblyName>mycmd</AssemblyName>
    <RootNamespace>MyCmdTools</RootNamespace>
    <PublishSingleFile>true</PublishSingleFile>
    <SelfContained>false</SelfContained>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  </PropertyGroup>
</Project>
```

### 5.3 — Command router pattern

```csharp
// EntryPoint.cs
using System;
using System.Collections.Generic;

namespace MyCmdTools
{
    class Program
    {
        static readonly Dictionary<string, Func<string[], int>> Commands = new()
        {
            ["hello"]  = HelloCommand.Run,
            ["greet"]  = GreetCommand.Run,
            ["help"]   = HelpCommand.Run,
        };

        static int Main(string[] args)
        {
            if (args.Length == 0 || args[0] is "/?" or "--help" or "help")
                return HelpCommand.Run(args);

            var cmd = args[0].ToLower();
            if (Commands.TryGetValue(cmd, out var handler))
                return handler(args[1..]);

            Console.ForegroundColor = ConsoleColor.Red;
            Console.Error.WriteLine($"Unknown command: {cmd}");
            Console.ResetColor();
            Console.WriteLine("Run 'mycmd help' for usage.");
            return 1;
        }
    }
}
```

### 5.4 — A command implementation

```csharp
// Commands/GreetCommand.cs
namespace MyCmdTools
{
    public static class GreetCommand
    {
        public const string Name        = "greet";
        public const string Synopsis    = "Print a personalised greeting";
        public const string Usage       = "mycmd greet <name> [--shout]";
        public const string Description = """
            Greets a person by name.
            Use --shout to print in uppercase.
            """;

        public static int Run(string[] args)
        {
            if (args.Length == 0 || args[0] is "/?" or "--help")
            {
                PrintHelp();
                return 0;
            }

            var name  = args[0];
            var shout = Array.Exists(args, a => a == "--shout");
            var msg   = $"Hello, {name}!";

            Console.WriteLine(shout ? msg.ToUpper() : msg);
            return 0;
        }

        public static void PrintHelp()
        {
            Console.WriteLine($"""
            NAME
                {Name} — {Synopsis}

            SYNOPSIS
                {Usage}

            DESCRIPTION
                {Description}

            OPTIONS
                --shout     Print greeting in uppercase

            EXAMPLES
                mycmd greet Alice
                mycmd greet Bob --shout
            """);
        }
    }
}
```

### 5.5 — Help command that lists all sub-commands

```csharp
// Commands/HelpCommand.cs
namespace MyCmdTools
{
    public static class HelpCommand
    {
        public static int Run(string[] args)
        {
            if (args.Length > 0)
            {
                // Delegate to subcommand's help
                return args[0].ToLower() switch
                {
                    "greet" => { GreetCommand.PrintHelp(); return 0; },
                    "hello" => { HelloCommand.PrintHelp(); return 0; },
                    _       => { Console.WriteLine($"No help for '{args[0]}'"); return 1; }
                };
            }

            Console.WriteLine("""
            mycmd — Custom CMD Plugin v1.0.0

            USAGE
                mycmd <command> [options]

            COMMANDS
                hello    Say hello to the world
                greet    Personalised greeting
                help     Show this help (mycmd help <command> for details)

            EXAMPLES
                mycmd hello
                mycmd greet Alice --shout
                mycmd help greet
            """);
            return 0;
        }
    }
}
```

### 5.6 — Build and deploy

```powershell
# build_and_deploy.ps1
$src     = "$env:USERPROFILE\CmdPlugins\src\MyCmdTools"
$out     = "$env:USERPROFILE\CmdPlugins\bin"

Push-Location $src
dotnet publish -c Release -r win-x64 --self-contained false -o $out
Pop-Location

Write-Host "[OK] mycmd.exe deployed to $out" -ForegroundColor Green
```

---

## 6. LAYER 5 — NATIVE C++ CMD EXTENSION DLL

Windows CMD supports `CMDEXTVERSION` and can load an AutoRun that calls a compiled shim. For true CMD-level extension (tab completion, hook into `cmd.exe` parsing), use a **AutoRun launcher EXE** that loads your DLL.

### 6.1 — The DLL project (C++/CLI or pure C++)

```cpp
// MyCmdExt.cpp  (compile: cl /LD MyCmdExt.cpp /o MyCmdExt.dll)
#include <windows.h>
#include <cstdio>

extern "C" __declspec(dllexport)
int RunCommand(int argc, wchar_t* argv[]) {
    if (argc < 1) return 1;
    wprintf(L"[MyCmdExt] Called with: %s\n", argv[0]);
    return 0;
}

BOOL APIENTRY DllMain(HMODULE hMod, DWORD reason, LPVOID) {
    return TRUE;
}
```

### 6.2 — Register the DLL path in registry

```bat
REM register_dll.bat
set DLL_PATH=%USERPROFILE%\CmdPlugins\lib\MyCmdExt.dll

REM Backup first
reg export "HKCU\Software\MyCmdPlugins" "%USERPROFILE%\CmdPlugins\registry\backup.reg" /y 2>nul

reg add "HKCU\Software\MyCmdPlugins\Extensions" ^
    /v MyCmdExt /t REG_SZ /d "%DLL_PATH%" /f

echo [OK] DLL registered at HKCU\Software\MyCmdPlugins\Extensions\MyCmdExt
```

### 6.3 — COM-free DLL loading shim (C#)

For .NET-to-DLL bridging without COM registration:

```csharp
// DllLoader.cs — loads a native DLL and calls an exported function
using System.Runtime.InteropServices;

[DllImport("kernel32.dll", SetLastError = true)]
static extern IntPtr LoadLibrary(string lpFileName);

[DllImport("kernel32.dll", SetLastError = true)]
static extern IntPtr GetProcAddress(IntPtr hModule, string procName);

var dll   = LoadLibrary(@"C:\Users\you\CmdPlugins\lib\MyCmdExt.dll");
var proc  = GetProcAddress(dll, "RunCommand");
// Marshal and invoke...
```

---

## 7. REGISTERING COMMANDS IN WINDOWS HELP (`HELP` COMMAND)

The built-in `HELP` command in CMD reads from `cmd.exe`'s internal list — **it cannot be extended natively** without patching the binary. However, there are two practical approaches:

### 7.1 — Override `HELP` with a wrapper (recommended)

Create `%USERPROFILE%\CmdPlugins\bin\help.cmd` (takes precedence over system `help` via PATH ordering):

```bat
@echo off
setlocal enabledelayedexpansion

REM If no args or explicit /all — show system help THEN plugin help
if "%~1"=="" goto :show_all
if /i "%~1"=="/all" goto :show_all

REM Check if it's a plugin command
set HELP_FILE=%USERPROFILE%\CmdPlugins\help\%~1.txt
if exist "!HELP_FILE!" (
    type "!HELP_FILE!"
    exit /b 0
)

REM Fall through to system help
help %*
exit /b %errorlevel%

:show_all
REM Show system commands first
help

echo.
echo ═══════════════════════════════════════════════════
echo   PLUGIN COMMANDS  (installed via CmdPlugins)
echo ═══════════════════════════════════════════════════
echo.

REM Read plugin manifest
set MANIFEST=%USERPROFILE%\CmdPlugins\registry\manifest.txt
if exist "!MANIFEST!" (
    type "!MANIFEST!"
) else (
    echo   No plugins installed.
)
echo.
exit /b 0
```

### 7.2 — Per-command help files

Each installed command drops a `.txt` file in `CmdPlugins\help\`:

```
CmdPlugins\help\
  mygrep.txt
  mycmd.txt
  glog.txt
```

Format follows Windows `HELP` output style:

```
MYGREP — Case-insensitive recursive string search

Syntax:  MYGREP [/N] [/C] "pattern" [path]

  pattern   String to search for (use quotes for phrases)
  path      Directory to search (default: current directory)

  /N        Display line numbers with output
  /C        Display only count of matching lines

Notes:
  Wraps FINDSTR with sensible defaults.
  Recursive by default (/S flag applied automatically).

Examples:
  mygrep "TODO" .
  mygrep /N "return" src\
```

### 7.3 — Manifest file format

`%USERPROFILE%\CmdPlugins\registry\manifest.txt`:

```
  mygrep      Case-insensitive recursive string search
  mycmd       Multi-command plugin toolkit (run: mycmd help)
  glog        Pretty git log graph
  gclean      Prune merged git branches
  touch       Create file or update timestamp
  mkcd        Create directory and cd into it
```

---

## 8. CUSTOM HELP TAB / HELP SYSTEM

For a richer experience — a `helpme` command with categories, search, and paged output:

### 8.1 — helpme.cmd

```bat
@echo off
setlocal enabledelayedexpansion
set HELP_DIR=%USERPROFILE%\CmdPlugins\help

if "%~1"=="" goto :index
if /i "%~1"=="search" goto :search
if /i "%~1"=="list" goto :list

REM Direct lookup
if exist "%HELP_DIR%\%~1.txt" (
    REM Page output with MORE
    type "%HELP_DIR%\%~1.txt" | more
    exit /b 0
)

echo No help found for '%~1'. Try: helpme list
exit /b 1

:index
echo.
echo  ┌─────────────────────────────────────────────┐
echo  │           CMDPLUGINS HELP SYSTEM            │
echo  │                                             │
echo  │  helpme ^<command^>     Show help for command │
echo  │  helpme list          List all commands     │
echo  │  helpme search ^<str^>  Search help text      │
echo  └─────────────────────────────────────────────┘
echo.
goto :eof

:list
echo.
echo Installed plugin commands:
echo.
for %%F in ("%HELP_DIR%\*.txt") do (
    set "fname=%%~nF"
    echo   !fname!
)
echo.
exit /b 0

:search
if "%~2"=="" (echo Usage: helpme search ^<term^> & exit /b 1)
echo Searching for '%~2' in help files...
echo.
findstr /i /l "%~2" "%HELP_DIR%\*.txt"
exit /b 0
```

### 8.2 — PowerShell rich help viewer (optional, opens in new window)

```powershell
# CmdPlugins\ps1\helpme-gui.ps1
function Show-PluginHelp {
    param([string]$Command = "")

    $helpDir = "$env:USERPROFILE\CmdPlugins\help"
    $files   = Get-ChildItem "$helpDir\*.txt"

    if ($Command) {
        $file = Join-Path $helpDir "$Command.txt"
        if (Test-Path $file) {
            Get-Content $file | Out-Host -Paging
        } else {
            Write-Warning "No help for '$Command'"
        }
        return
    }

    # Interactive selector using Out-GridView
    $selected = $files |
        Select-Object @{N='Command';E={$_.BaseName}},
                      @{N='File';E={$_.FullName}} |
        Out-GridView -Title "Plugin Commands — Select to view help" -PassThru

    if ($selected) {
        Get-Content $selected.File | Out-Host -Paging
    }
}

Set-Alias -Name helpme -Value Show-PluginHelp
```

---

## 9. PLUGIN REGISTRY — CENTRALIZED MANIFEST

### 9.1 — Plugin manifest JSON

`%USERPROFILE%\CmdPlugins\registry\plugins.json`:

```json
{
  "schema": "1.0",
  "plugins": [
    {
      "id": "search-tools",
      "version": "1.0.0",
      "commands": ["mygrep"],
      "layer": "batch",
      "bin": "bin\\mygrep.cmd",
      "help": "help\\mygrep.txt",
      "installed": "2025-05-04"
    },
    {
      "id": "mycmd-toolkit",
      "version": "1.0.0",
      "commands": ["mycmd"],
      "layer": "dotnet",
      "bin": "bin\\mycmd.exe",
      "dll": "lib\\MyCmdTools.dll",
      "help": "help\\mycmd.txt",
      "installed": "2025-05-04"
    },
    {
      "id": "doskey-aliases",
      "version": "1.0.0",
      "commands": ["ll", "gs", "gp", "gc", "up"],
      "layer": "doskey",
      "macro_file": "macros\\aliases.mac",
      "help": "help\\aliases.txt",
      "installed": "2025-05-04"
    }
  ]
}
```

### 9.2 — Plugin installer helper (PowerShell)

```powershell
# CmdPlugins\ps1\plugin-manager.ps1

$PluginRoot = "$env:USERPROFILE\CmdPlugins"
$ManifestPath = "$PluginRoot\registry\plugins.json"

function Install-CmdPlugin {
    param(
        [string]$PluginDir,   # Path to the plugin source folder
        [string]$PluginId
    )

    # Copy files
    Copy-Item "$PluginDir\bin\*"  "$PluginRoot\bin\"  -Force -ErrorAction SilentlyContinue
    Copy-Item "$PluginDir\lib\*"  "$PluginRoot\lib\"  -Force -ErrorAction SilentlyContinue
    Copy-Item "$PluginDir\help\*" "$PluginRoot\help\" -Force -ErrorAction SilentlyContinue

    # Update manifest
    $manifest = Get-Content $ManifestPath | ConvertFrom-Json
    $meta = Get-Content "$PluginDir\plugin.json" | ConvertFrom-Json
    $meta.installed = (Get-Date -Format "yyyy-MM-dd")
    $manifest.plugins += $meta
    $manifest | ConvertTo-Json -Depth 5 | Set-Content $ManifestPath

    Write-Host "[OK] Plugin '$PluginId' installed." -ForegroundColor Green
}

function Remove-CmdPlugin {
    param([string]$PluginId)

    $manifest = Get-Content $ManifestPath | ConvertFrom-Json
    $plugin   = $manifest.plugins | Where-Object { $_.id -eq $PluginId }

    if (-not $plugin) { Write-Warning "Plugin '$PluginId' not found."; return }

    # Remove files
    foreach ($cmd in $plugin.commands) {
        Remove-Item "$PluginRoot\bin\$cmd.*"  -Force -ErrorAction SilentlyContinue
        Remove-Item "$PluginRoot\help\$cmd.txt" -Force -ErrorAction SilentlyContinue
    }
    if ($plugin.dll) {
        Remove-Item "$PluginRoot\$($plugin.dll)" -Force -ErrorAction SilentlyContinue
    }

    # Update manifest
    $manifest.plugins = $manifest.plugins | Where-Object { $_.id -ne $PluginId }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content $ManifestPath

    Write-Host "[OK] Plugin '$PluginId' removed." -ForegroundColor Yellow
}

function Get-CmdPlugins {
    $manifest = Get-Content $ManifestPath | ConvertFrom-Json
    $manifest.plugins | Format-Table id, version, layer, commands, installed -AutoSize
}
```

---

## 10. AGENT WORKFLOW — FULL DEPLOYMENT SCRIPT

An agent can run this end-to-end to scaffold and install a new command plugin:

```powershell
# deploy_plugin.ps1
# Usage: .\deploy_plugin.ps1 -Name "mygrep" -Layer "batch"

param(
    [string]$Name,
    [string]$Layer = "batch",   # batch | dotnet | doskey | ps1
    [string]$Synopsis = "Custom command"
)

$Root = "$env:USERPROFILE\CmdPlugins"

# 1. Ensure directory structure
@("bin","lib","help","macros","registry","src") | ForEach-Object {
    New-Item -ItemType Directory -Force "$Root\$_" | Out-Null
}

# 2. Initialize manifest if missing
$ManifestPath = "$Root\registry\plugins.json"
if (-not (Test-Path $ManifestPath)) {
    '{"schema":"1.0","plugins":[]}' | Set-Content $ManifestPath
}

# 3. Add plugin bin dir to user PATH
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$Root\bin*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$Root\bin", "User")
    Write-Host "[PATH] Added $Root\bin" -ForegroundColor Cyan
}

# 4. Create stub command file based on layer
switch ($Layer) {
    "batch" {
        $stub = @"
@echo off
if "%~1"=="/?" goto :help
if /i "%~1"=="--help" goto :help

REM ── COMMAND LOGIC HERE ──
echo Running $Name with args: %*
goto :eof

:help
echo $Name — $Synopsis
echo.
echo Usage: $Name [args]
exit /b 0
"@
        $stub | Set-Content "$Root\bin\$Name.cmd"
    }

    "ps1" {
        $stub = @"
function global:$Name {
    param([Parameter(ValueFromRemainingArguments)][string[]]`$Args)
    # Command logic here
    Write-Host '$Name called with: ' `$Args
}
"@
        $stub | Set-Content "$Root\ps1\$Name.ps1"

        # Ensure $PROFILE dot-sources plugin ps1 dir
        $profileContent = Get-Content $PROFILE -ErrorAction SilentlyContinue
        $loadLine = ". `"$Root\ps1\$Name.ps1`""
        if ($profileContent -notcontains $loadLine) {
            Add-Content $PROFILE "`n$loadLine"
        }
    }

    "doskey" {
        Add-Content "$Root\macros\aliases.mac" "`n$Name=echo $Name alias `$*"
    }
}

# 5. Create help file
@"
$($Name.ToUpper()) — $Synopsis

Usage:  $Name [options] [args]

Options:
    /?  --help    Show this help

Examples:
    $Name --help
"@ | Set-Content "$Root\help\$Name.txt"

# 6. Register in manifest
$manifest = Get-Content $ManifestPath | ConvertFrom-Json
$entry = [PSCustomObject]@{
    id        = $Name
    version   = "1.0.0"
    commands  = @($Name)
    layer     = $Layer
    synopsis  = $Synopsis
    installed = (Get-Date -Format "yyyy-MM-dd")
}
$manifest.plugins += $entry
$manifest | ConvertTo-Json -Depth 5 | Set-Content $ManifestPath

# 7. Update manifest.txt (for HELP wrapper)
$manifest.plugins |
    ForEach-Object { "  {0,-16} {1}" -f $_.id, $_.synopsis } |
    Set-Content "$Root\registry\manifest.txt"

Write-Host "[DONE] Plugin '$Name' ($Layer) deployed." -ForegroundColor Green
Write-Host "  Command file : $Root\bin\$Name.cmd"
Write-Host "  Help file    : $Root\help\$Name.txt"
Write-Host "  Run: $Name --help"
```

---

## 11. CLEAN UNINSTALL — FULL REMOVAL

```bat
REM uninstall_all.bat — removes everything, no trace

@echo off
echo Removing CmdPlugins...

REM 1. Remove AutoRun registry key
reg delete "HKCU\Software\Microsoft\Command Processor" /v AutoRun /f 2>nul

REM 2. Remove plugin registry keys
reg delete "HKCU\Software\MyCmdPlugins" /f 2>nul

REM 3. Remove bin dir from PATH
powershell -Command ^
    "$p = [Environment]::GetEnvironmentVariable('PATH','User');" ^
    "$p = ($p -split ';' | Where-Object { $_ -notlike '*CmdPlugins*' }) -join ';';" ^
    "[Environment]::SetEnvironmentVariable('PATH', $p, 'User')"

REM 4. Remove help wrapper
del /f "%USERPROFILE%\CmdPlugins\bin\help.cmd" 2>nul

REM 5. Remove plugin root directory
rmdir /s /q "%USERPROFILE%\CmdPlugins" 2>nul

REM 6. Clean $PROFILE (PowerShell)
powershell -Command ^
    "$content = Get-Content $PROFILE -ErrorAction SilentlyContinue;" ^
    "$content = $content | Where-Object { $_ -notlike '*CmdPlugins*' };" ^
    "Set-Content $PROFILE $content"

echo [DONE] CmdPlugins fully removed. Restart CMD/PowerShell.
```

---

## 12. SECURITY CONSIDERATIONS

| Concern | Mitigation |
|---|---|
| PATH hijacking via plugin bin | Use full paths in scripts; audit `%PATH%` order |
| DLL hijacking | Store DLLs in user-owned dir, not system dirs |
| AutoRun abuse | Only write to `HKCU`, not `HKLM`; agents must not touch HKLM AutoRun |
| Script injection via alias args | Always quote `%*` and `$*` in batch; use `[Parameter(...)]` in PS |
| Persistent registry keys | All writes go to `HKCU\Software\MyCmdPlugins` — one `reg delete` cleans it |
| Leaving help.cmd shadow | Uninstaller explicitly removes the PATH override |

**Agent rule**: Never write to `HKLM`. Never modify `%WINDIR%\System32`. Always back up registry keys before modifying.

---

## 13. QUICK REFERENCE CARD

```
LAYER       │ PERSIST  │ SCOPE      │ BEST FOR
────────────┼──────────┼────────────┼─────────────────────────────────
DOSKEY      │ AutoRun  │ CMD only   │ Simple text substitution aliases
PowerShell  │ $PROFILE │ PS + tools │ Complex logic, pipelines
Batch (bin) │ PATH     │ CMD + PS   │ Reusable scripts, wrappers
.NET EXE    │ PATH     │ Universal  │ Complex tools, sub-commands
Native DLL  │ Registry │ Low-level  │ CMD hooks, performance-critical
────────────┴──────────┴────────────┴─────────────────────────────────

KEY REGISTRY KEYS (all HKCU — no UAC needed)
  HKCU\Software\Microsoft\Command Processor\AutoRun    ← CMD on-launch hook
  HKCU\Environment\PATH                                ← User PATH
  HKCU\Software\MyCmdPlugins\Extensions\*              ← DLL registry

KEY DIRECTORIES
  %USERPROFILE%\CmdPlugins\bin\       ← commands (on PATH)
  %USERPROFILE%\CmdPlugins\lib\       ← DLLs
  %USERPROFILE%\CmdPlugins\help\      ← *.txt help files
  %USERPROFILE%\CmdPlugins\macros\    ← doskey .mac files
  %USERPROFILE%\CmdPlugins\registry\  ← manifest + reg backups

AGENT CHECKLIST FOR NEW COMMAND
  [x] Create bin\<name>.cmd or compile bin\<name>.exe
  [x] Write help\<name>.txt
  [x] Register in registry\plugins.json
  [x] Regenerate registry\manifest.txt
  [x] Ensure bin\ is on user PATH
  [x] For doskey: append to macros\aliases.mac, reload AutoRun
  [x] For DLL: reg add HKCU\Software\MyCmdPlugins\Extensions\<name>
  [x] Test: <name> --help
  [x] Test: help <name>   (via help.cmd wrapper)
```

---

*Generated for pgwiz / CmdPlugins agent workflow — all operations HKCU-scoped, UAC-free, reversible.*
