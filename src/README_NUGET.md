# pgwiz.cmdtools — NuGet Global Tool

Windows CMD aliases and extensions as a **dotnet global tool** with interactive setup wizard.

```
dotnet tool install -g pgwiz.cmdtools
pgwiz
```

## Features

✅ **sudo** — Run commands with elevation (inline, no new window)  
✅ **refreshsudo** — Refresh stale elevation tokens  
✅ **Interactive setup wizard** — Choose which aliases to install  
✅ **Auto-deployment** — Aliases copied to %USERPROFILE%\CmdPlugins\  
✅ **PATH integration** — Automatic PATH configuration  
✅ **Cross-shell** — Works in PowerShell and CMD.exe  
✅ **Extensible** — Architecture ready for additional aliases  

## Installation

### Prerequisites

- Windows 10 or 11
- .NET 8.0 or later
- UAC enabled

### Quick Install

```powershell
dotnet tool install -g pgwiz.cmdtools
```

Then run the setup wizard:

```powershell
pgwiz setup
```

Or just:

```powershell
pgwiz
```

### What Gets Installed

- `~/.dotnet/tools/pgwiz.exe` — Entry point (added to PATH)
- `%USERPROFILE%\CmdPlugins\` — Alias files and infrastructure
  - `ps1/sudo.ps1`
  - `ps1/refreshsudo.ps1`
  - `bin/sudo.cmd`
  - `bin/refreshsudo.cmd`
  - Supporting infrastructure scripts

## Usage

### Interactive Setup

```powershell
$ pgwiz
╔══════════════════════════════════════════════════════════════╗
║  pgwiz Windows CMD Extensions Setup Wizard                   ║
╚══════════════════════════════════════════════════════════════╝

Welcome! This wizard will help you install Windows CMD aliases and extensions.

STEP 1: Select Aliases to Install
Use ↑/↓ to navigate, Space to toggle, Enter to confirm

✓ sudo — Execute commands with elevation (inline, no new window)
✓ refreshsudo — Refresh stale elevation tokens

Ready to install? [Y/n]: Y

STEP 2: Installing...
Creating directories...
Installing gsudo via winget...
Installing sudo...
Installing refreshsudo...
Updating PowerShell profile...
Adding to PATH...

✓ Installation complete!
```

### Using sudo

```powershell
# Check elevation status
refreshsudo --status

# Run elevated commands
sudo whoami                         # Returns DOMAIN\Administrator
sudo net stop "Print Spooler"       # Stop services
sudo reg add HKLM\... /v ...        # Modify registry
sudo choco install ffmpeg           # Install packages
```

### Refresh Token

```powershell
# If your sudo stops working mid-session
refreshsudo
# UAC prompt → token refreshed → ready to go
```

## Architecture

**Pattern A: Global Tool** (chosen for pgwiz.cmdtools)

```
dotnet tool install -g pgwiz.cmdtools
    ↓
Installs to: %USERPROFILE%\.dotnet\tools\pgwiz.exe
    ↓
Auto-added to PATH
    ↓
Runs interactive setup wizard
    ↓
Deploys aliases to %USERPROFILE%\CmdPlugins\
```

### Project Structure

```
windows_aliases/
├── src/
│   └── PgwizCmdTools/
│       ├── Program.cs               ← Entry point, CLI handler
│       ├── PgwizCmdTools.csproj    ← Package metadata
│       └── Setup/
│           ├── SetupWizard.cs       ← TUI interactive menu
│           └── PluginInstaller.cs   ← Deployment logic
├── tools/
│   ├── init.ps1                     ← Post-install hook
│   └── uninstall.ps1                ← Uninstall hook
├── global.json                      ← .NET 8.0 SDK version
└── .gitignore
```

## Building from Source

### Prerequisites

- .NET 8.0 SDK
- Git

### Build

```powershell
cd windows_aliases
dotnet build src/PgwizCmdTools/PgwizCmdTools.csproj -c Release
```

### Pack Locally

```powershell
dotnet pack src/PgwizCmdTools/PgwizCmdTools.csproj -c Release -o ./nupkg/
```

### Test Local Install

```powershell
sudo dotnet tool install -g --add-source ./nupkg pgwiz.cmdtools
pgwiz setup
```

## Troubleshooting

### "pgwiz command not found"

After installing, PATH isn't updated in current shell. Close and reopen PowerShell/CMD.

### sudo opens new window instead of running inline

Install gsudo manually:

```powershell
winget install gerardog.gsudo
```

### "Not elevated" when running refreshsudo

This is expected. Run `refreshsudo` to establish elevation:

```powershell
$ refreshsudo
[sudo] Refreshing elevation token...
[sudo] Re-establishing elevation — UAC prompt incoming...
(UAC prompt appears)
[sudo] Token refreshed.
```

## Publishing to NuGet.org

### Prerequisites

- NuGet.org account
- API key from https://www.nuget.org/account/apikeys

### Publish

```powershell
$apiKey = "your-nuget-api-key"
dotnet nuget push .\nupkg\pgwiz.cmdtools.1.0.0.nupkg `
  --api-key $apiKey `
  --source https://api.nuget.org/v3/index.json
```

### Verify

Visit: https://www.nuget.org/packages/pgwiz.cmdtools

## Development & Contributing

Repository: https://github.com/pgwiz/windows_aliases

### Documentation

- [sensesudo.md](../sensesudo.md) — Philosophy & motivation
- [WINDOWS_CMD_EXTENSIONS_GUIDE.md](../WINDOWS_CMD_EXTENSIONS_GUIDE.md) — Technical architecture
- [NUT.md](../NUT.md) — NuGet publishing patterns

### Adding New Aliases

1. Create `/sudo/<newname>/` directory
2. Add `ps1/<newname>.ps1` and `bin/<newname>.cmd`
3. Update `AliasOption` list in `SetupWizard.cs`
4. Add help file: `Assets/help/<newname>.txt`
5. Update `PluginInstaller.cs` deploy logic
6. Test locally
7. Bump version in `.csproj`
8. Publish to NuGet

## License

MIT

## Support

Issues: https://github.com/pgwiz/windows_aliases/issues  
Documentation: https://github.com/pgwiz/windows_aliases
