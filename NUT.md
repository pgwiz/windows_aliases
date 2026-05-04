# NUT.md — Publishing CMD Extensions to NuGet
### Package, Publish & Interactive Terminal Setup Wizard

> "It's called NuGet. You install nuts. We don't talk about it."

---

## TABLE OF CONTENTS

1. [NuGet Package Architecture for CMD Tools](#1-nuget-package-architecture-for-cmd-tools)
2. [Project Structure](#2-project-structure)
3. [The .nuspec / .csproj Package Manifest](#3-the-nuspec--csproj-package-manifest)
4. [MSBuild Targets — Auto-install on `dotnet tool install`](#4-msbuild-targets--auto-install-on-dotnet-tool-install)
5. [Publishing to NuGet.org](#5-publishing-to-nugetorg)
6. [Dotnet Global Tool Pattern (Recommended)](#6-dotnet-global-tool-pattern-recommended)
7. [The Interactive Terminal Setup Wizard](#7-the-interactive-terminal-setup-wizard)
8. [Multi-select Checkbox Menu (Spectre.Console)](#8-multi-select-checkbox-menu-spectreconsole)
9. [Post-install Hook — Auto-registers to PATH & Help](#9-post-install-hook--auto-registers-to-path--help)
10. [Private NuGet Feed (Self-hosted)](#10-private-nuget-feed-self-hosted)
11. [Full Agent Workflow](#11-full-agent-workflow)
12. [Quick Reference](#12-quick-reference)

---

## 1. NUGET PACKAGE ARCHITECTURE FOR CMD TOOLS

Two patterns exist. Pick based on what you're distributing:

```
┌──────────────────────────────────────────────────────────────────┐
│  PATTERN A — dotnet global tool                                  │
│                                                                  │
│  dotnet tool install -g pgwiz.cmdtools                           │
│  → installs mycmd.exe to %USERPROFILE%\.dotnet\tools\           │
│  → auto-added to PATH by .NET tooling                           │
│  → RECOMMENDED for CLI tools                                     │
├──────────────────────────────────────────────────────────────────┤
│  PATTERN B — NuGet library package + MSBuild targets            │
│                                                                  │
│  Install-Package pgwiz.cmdtools                                  │
│  → drops .bat/.cmd/.mac files via MSBuild .targets file         │
│  → runs a PowerShell post-install script                        │
│  → for distributing scripts/aliases as installable packages     │
└──────────────────────────────────────────────────────────────────┘
```

**For CMD aliases + scripts → Pattern B or Global Tool wrapping a setup wizard.**
**For .NET CLI commands → Pattern A (global tool) is canonical.**

---

## 2. PROJECT STRUCTURE

```
pgwiz.cmdtools/
├── src/
│   └── PgwizCmdTools/
│       ├── PgwizCmdTools.csproj          ← global tool OR library
│       ├── Program.cs                    ← entry point / setup wizard
│       ├── Setup/
│       │   ├── SetupWizard.cs            ← interactive TUI wizard
│       │   ├── PluginInstaller.cs        ← installs aliases/scripts
│       │   └── CheckboxMenu.cs           ← multi-select UI
│       ├── Commands/
│       │   ├── HelloCommand.cs
│       │   └── GrepCommand.cs
│       └── Assets/
│           ├── aliases.mac               ← embedded DOSKEY macros
│           ├── help/
│           │   ├── hello.txt
│           │   └── grep.txt
│           └── scripts/
│               └── mygrep.cmd
├── build/
│   └── pgwiz.cmdtools.targets            ← MSBuild post-install hook
├── tools/
│   └── init.ps1                          ← legacy PackageReference hook
│   └── uninstall.ps1
├── pgwiz.cmdtools.nuspec                 ← explicit NuGet manifest
└── README.md
```

---

## 3. THE .nuspec / .csproj PACKAGE MANIFEST

### Option A — Modern SDK-style `.csproj` (preferred)

```xml
<!-- src/PgwizCmdTools/PgwizCmdTools.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <!-- Global Tool settings -->
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <AssemblyName>pgwiz</AssemblyName>
    <RootNamespace>PgwizCmdTools</RootNamespace>

    <!-- NuGet package identity -->
    <PackageId>pgwiz.cmdtools</PackageId>
    <Version>1.0.0</Version>
    <Authors>pgwiz</Authors>
    <Company>pgwiz</Company>
    <Description>Pluggable Windows CMD extensions, aliases, and tools by pgwiz</Description>
    <PackageTags>cli;cmd;windows;aliases;tools;terminal;pgwiz</PackageTags>
    <PackageProjectUrl>https://github.com/pgwiz/cmdtools</PackageProjectUrl>
    <RepositoryUrl>https://github.com/pgwiz/cmdtools</RepositoryUrl>
    <RepositoryType>git</RepositoryType>
    <PackageLicenseExpression>MIT</PackageLicenseExpression>
    <PackageReadmeFile>README.md</PackageReadmeFile>
    <PackageIcon>icon.png</PackageIcon>

    <!-- Global tool marker — THIS is what makes it a dotnet tool -->
    <PackAsTool>true</PackAsTool>
    <ToolCommandName>pgwiz</ToolCommandName>

    <!-- Embed assets -->
    <GenerateEmbeddedFilesManifest>true</GenerateEmbeddedFilesManifest>
  </PropertyGroup>

  <ItemGroup>
    <!-- Embed all asset files into the binary -->
    <EmbeddedResource Include="Assets\**\*" />

    <!-- Include README and icon in package -->
    <None Include="..\..\README.md" Pack="true" PackagePath="\" />
    <None Include="..\..\icon.png"  Pack="true" PackagePath="\" />
  </ItemGroup>

  <ItemGroup>
    <!-- The TUI library — makes terminal menus beautiful -->
    <PackageReference Include="Spectre.Console" Version="0.49.*" />
    <PackageReference Include="Spectre.Console.Cli" Version="0.49.*" />
  </ItemGroup>
</Project>
```

### Option B — `.nuspec` (for script/alias-only packages, no EXE)

```xml
<?xml version="1.0"?>
<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
  <metadata>
    <id>pgwiz.cmdtools</id>
    <version>1.0.0</version>
    <authors>pgwiz</authors>
    <license type="expression">MIT</license>
    <projectUrl>https://github.com/pgwiz/cmdtools</projectUrl>
    <description>Pluggable Windows CMD aliases and script extensions</description>
    <tags>cli cmd windows aliases terminal pgwiz</tags>
    <readme>README.md</readme>

    <!-- Minimum NuGet client -->
    <minClientVersion>5.0</minClientVersion>
  </metadata>

  <files>
    <!-- MSBuild .targets file — runs on install -->
    <file src="build\pgwiz.cmdtools.targets"
          target="build\pgwiz.cmdtools.targets" />

    <!-- PowerShell install/uninstall hooks (legacy packages) -->
    <file src="tools\init.ps1"        target="tools\init.ps1" />
    <file src="tools\uninstall.ps1"   target="tools\uninstall.ps1" />

    <!-- Actual script assets to deploy -->
    <file src="assets\bin\*"    target="content\CmdPlugins\bin" />
    <file src="assets\help\*"   target="content\CmdPlugins\help" />
    <file src="assets\macros\*" target="content\CmdPlugins\macros" />

    <file src="README.md" target="" />
  </files>
</package>
```

---

## 4. MSBUILD TARGETS — AUTO-INSTALL ON `dotnet tool install`

For the library/script package pattern, a `.targets` file fires after install:

```xml
<!-- build/pgwiz.cmdtools.targets -->
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">

  <Target Name="PgwizInstallAliases" AfterTargets="Build">
    <Message Text="[pgwiz.cmdtools] Installing CMD aliases..." Importance="high" />

    <Exec Command="powershell -ExecutionPolicy Bypass -File &quot;$(MSBuildThisFileDirectory)..\tools\init.ps1&quot;"
          ContinueOnError="true"
          WorkingDirectory="$(MSBuildThisFileDirectory)" />
  </Target>

</Project>
```

```powershell
# tools/init.ps1 — runs after NuGet package install (PackageReference projects)

$Root    = "$env:USERPROFILE\CmdPlugins"
$PkgBase = Split-Path $PSScriptRoot -Parent

# Create dirs
@("bin","lib","help","macros","registry") | ForEach-Object {
    New-Item -ItemType Directory -Force "$Root\$_" | Out-Null
}

# Copy assets
Copy-Item "$PkgBase\content\CmdPlugins\bin\*"    "$Root\bin\"    -Force
Copy-Item "$PkgBase\content\CmdPlugins\help\*"   "$Root\help\"   -Force
Copy-Item "$PkgBase\content\CmdPlugins\macros\*" "$Root\macros\" -Force

# Add to PATH
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$Root\bin*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$Root\bin", "User")
}

# Register AutoRun
$macroFile  = "$Root\macros\aliases.mac"
$autoRunCmd = "doskey /macrofile=`"$macroFile`""
$existing   = (Get-ItemProperty "HKCU:\Software\Microsoft\Command Processor" -Name AutoRun -ErrorAction SilentlyContinue).AutoRun

if ($existing -and $existing -notlike "*$macroFile*") {
    Set-ItemProperty "HKCU:\Software\Microsoft\Command Processor" AutoRun "$existing & $autoRunCmd"
} elseif (-not $existing) {
    Set-ItemProperty "HKCU:\Software\Microsoft\Command Processor" AutoRun $autoRunCmd
}

Write-Host "[pgwiz.cmdtools] Installed. Restart CMD to activate aliases." -ForegroundColor Green
```

---

## 5. PUBLISHING TO NUGET.ORG

### 5.1 — One-time account setup

```
1. Register at https://www.nuget.org/
2. Go to Account → API Keys → Create
   - Key name : pgwiz-publish
   - Scopes   : Push new packages and package versions
   - Glob     : pgwiz.*        ← locks key to your prefix only
3. Copy the key (shown once)
```

### 5.2 — Store API key locally

```powershell
# Store in NuGet credential store (encrypted, per-user)
dotnet nuget add source https://api.nuget.org/v3/index.json `
    --name nuget.org `
    --username pgwiz `
    --password "YOUR_API_KEY_HERE" `
    --store-password-in-clear-text   # omit on Windows (DPAPI encrypts it)
```

### 5.3 — Build → Pack → Push

```powershell
# build_publish.ps1

$project = "src\PgwizCmdTools\PgwizCmdTools.csproj"
$output  = ".\nupkg"

# 1. Build release
dotnet build $project -c Release

# 2. Pack into .nupkg
dotnet pack $project -c Release --no-build -o $output

# 3. Show what we're about to push
$pkg = Get-ChildItem "$output\*.nupkg" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "Pushing: $($pkg.Name)" -ForegroundColor Cyan

# 4. Push to NuGet.org
dotnet nuget push $pkg.FullName `
    --source https://api.nuget.org/v3/index.json `
    --api-key $env:NUGET_API_KEY `
    --skip-duplicate    # don't fail if version already exists

Write-Host "[DONE] Package live at: https://www.nuget.org/packages/pgwiz.cmdtools" -ForegroundColor Green
```

### 5.4 — Install from NuGet (end user)

```powershell
# Global tool install — single command, works everywhere
dotnet tool install -g pgwiz.cmdtools

# Verify
pgwiz --version
pgwiz help

# Update later
dotnet tool update -g pgwiz.cmdtools

# Uninstall
dotnet tool uninstall -g pgwiz.cmdtools
```

### 5.5 — Package versioning strategy

```
1.0.0   → initial release
1.0.1   → patch (bug fix, help text update)
1.1.0   → minor (new alias set added)
2.0.0   → major (breaking change, new install path)

Automate with:
  dotnet pack /p:Version=$(git describe --tags --abbrev=0)
```

---

## 6. DOTNET GLOBAL TOOL PATTERN (RECOMMENDED)

When `PackAsTool=true`, the installed binary lands at:
```
%USERPROFILE%\.dotnet\tools\pgwiz.exe
```
And `.dotnet\tools` is auto-added to PATH by the .NET installer — zero PATH manipulation needed on your side.

The entry point becomes your setup wizard:

```csharp
// Program.cs
using PgwizCmdTools.Setup;
using Spectre.Console.Cli;

var app = new CommandApp();
app.Configure(config =>
{
    config.SetApplicationName("pgwiz");
    config.AddCommand<SetupCommand>("setup")
          .WithDescription("Interactive setup wizard — install/manage aliases");
    config.AddCommand<InstallCommand>("install")
          .WithDescription("Install a specific plugin");
    config.AddCommand<ListCommand>("list")
          .WithDescription("List installed plugins");
    config.AddCommand<UninstallCommand>("uninstall")
          .WithDescription("Remove a plugin");
});

return app.Run(args);
```

User runs:
```
pgwiz setup         ← interactive wizard
pgwiz install grep  ← direct install
pgwiz list          ← show what's installed
pgwiz uninstall ll  ← remove alias
```

---

## 7. THE INTERACTIVE TERMINAL SETUP WIZARD

Full `SetupWizard.cs` using **Spectre.Console** for rich TUI:

```csharp
// Setup/SetupWizard.cs
using Spectre.Console;
using System.Collections.Generic;
using System.Linq;

namespace PgwizCmdTools.Setup
{
    public static class SetupWizard
    {
        public static void Run()
        {
            Console.Clear();

            // ── Header ──────────────────────────────────────────────
            AnsiConsole.Write(
                new FigletText("pgwiz tools")
                    .Centered()
                    .Color(Color.Gold1));

            AnsiConsole.MarkupLine("[grey]Windows CMD Extensions — Setup Wizard[/]\n");
            AnsiConsole.MarkupLine("[dim]All changes are user-scoped. No admin required.[/]\n");

            // ── Step 1: Install mode ─────────────────────────────────
            var mode = AnsiConsole.Prompt(
                new SelectionPrompt<string>()
                    .Title("[bold yellow]How would you like to install?[/]")
                    .PageSize(5)
                    .AddChoices(new[]
                    {
                        "Install everything (recommended)",
                        "Pick individual plugins",
                        "Minimal install (aliases only)",
                        "Show what would be installed (dry run)",
                        "Uninstall all",
                    }));

            switch (mode)
            {
                case "Install everything (recommended)":
                    InstallAll();
                    break;
                case "Pick individual plugins":
                    InstallSelected();
                    break;
                case "Minimal install (aliases only)":
                    InstallMinimal();
                    break;
                case "Show what would be installed (dry run)":
                    DryRun();
                    break;
                case "Uninstall all":
                    UninstallAll();
                    break;
            }
        }

        // ── INSTALL ALL ──────────────────────────────────────────────
        static void InstallAll()
        {
            var plugins = PluginRegistry.All;

            AnsiConsole.MarkupLine($"\n[bold]Installing [green]{plugins.Count}[/] plugins...[/]\n");

            AnsiConsole.Progress()
                .AutoClear(false)
                .Columns(new ProgressColumn[]
                {
                    new TaskDescriptionColumn(),
                    new ProgressBarColumn(),
                    new PercentageColumn(),
                    new SpinnerColumn(),
                })
                .Start(ctx =>
                {
                    var task = ctx.AddTask("[green]Installing plugins[/]", maxValue: plugins.Count);

                    foreach (var plugin in plugins)
                    {
                        task.Description = $"[cyan]Installing[/] [bold]{plugin.Name}[/]";
                        PluginInstaller.Install(plugin);
                        task.Increment(1);
                        Thread.Sleep(80); // let the user see progress
                    }
                });

            PrintSuccess(plugins);
        }

        // ── PICK INDIVIDUAL ──────────────────────────────────────────
        static void InstallSelected()
        {
            var choices = AnsiConsole.Prompt(
                new MultiSelectionPrompt<PluginDef>()
                    .Title("[bold yellow]Select plugins to install:[/]")
                    .PageSize(12)
                    .MoreChoicesText("[grey](Move up/down, [blue]SPACE[/] to select, [green]ENTER[/] to confirm)[/]")
                    .InstructionsText(
                        "[grey]([blue]<space>[/] to toggle, " +
                        "[green]<enter>[/] to accept)[/]")
                    .UseConverter(p => $"[bold]{p.Name,-20}[/] [dim]{p.Description}[/]  [grey]{p.Layer}[/]")
                    .AddChoiceGroup("── Aliases (DOSKEY)", PluginRegistry.Aliases)
                    .AddChoiceGroup("── Shell Scripts",    PluginRegistry.Scripts)
                    .AddChoiceGroup("── .NET Commands",    PluginRegistry.DotnetTools)
                    .AddChoiceGroup("── Help System",      PluginRegistry.HelpTools));

            if (!choices.Any())
            {
                AnsiConsole.MarkupLine("[yellow]Nothing selected. Exiting.[/]");
                return;
            }

            AnsiConsole.MarkupLine($"\n[bold]Installing [green]{choices.Count}[/] selected plugin(s)...[/]\n");

            foreach (var plugin in choices)
            {
                AnsiConsole.MarkupLine($"  [cyan]→[/] {plugin.Name}");
                PluginInstaller.Install(plugin);
            }

            PrintSuccess(choices);
        }

        // ── MINIMAL (aliases only) ───────────────────────────────────
        static void InstallMinimal()
        {
            var minimal = PluginRegistry.Aliases;
            AnsiConsole.MarkupLine($"[bold]Installing [green]{minimal.Count}[/] aliases only...[/]");
            foreach (var p in minimal) PluginInstaller.Install(p);
            PrintSuccess(minimal);
        }

        // ── DRY RUN ──────────────────────────────────────────────────
        static void DryRun()
        {
            var table = new Table()
                .Border(TableBorder.Rounded)
                .BorderColor(Color.Grey)
                .AddColumn("[bold]Plugin[/]")
                .AddColumn("[bold]Layer[/]")
                .AddColumn("[bold]Commands[/]")
                .AddColumn("[bold]Description[/]");

            foreach (var p in PluginRegistry.All)
            {
                table.AddRow(
                    $"[cyan]{p.Name}[/]",
                    $"[grey]{p.Layer}[/]",
                    string.Join(", ", p.Commands),
                    p.Description);
            }

            AnsiConsole.Write(table);
            AnsiConsole.MarkupLine("\n[dim]Dry run complete. Nothing was installed.[/]");
        }

        // ── UNINSTALL ALL ────────────────────────────────────────────
        static void UninstallAll()
        {
            var confirm = AnsiConsole.Confirm(
                "[red bold]Remove all pgwiz.cmdtools plugins and registry entries?[/]");

            if (!confirm) { AnsiConsole.MarkupLine("[yellow]Aborted.[/]"); return; }

            AnsiConsole.Status()
                .Spinner(Spinner.Known.Dots2)
                .SpinnerStyle(Style.Parse("red"))
                .Start("[red]Uninstalling...[/]", _ =>
                {
                    PluginInstaller.UninstallAll();
                    Thread.Sleep(500);
                });

            AnsiConsole.MarkupLine("[green]Done.[/] All plugins removed. Restart CMD/PowerShell.");
        }

        // ── SHARED SUCCESS OUTPUT ────────────────────────────────────
        static void PrintSuccess(IEnumerable<PluginDef> installed)
        {
            AnsiConsole.MarkupLine("\n[bold green]✓ Installation complete![/]\n");

            var panel = new Panel(
                "[bold]Restart CMD or PowerShell to activate changes.[/]\n\n" +
                "  [cyan]pgwiz list[/]         → list installed plugins\n" +
                "  [cyan]help[/]               → see commands in help\n" +
                "  [cyan]helpme search foo[/]  → search plugin help\n" +
                "  [cyan]pgwiz uninstall[/]    → remove anytime")
                .Header("[bold yellow] Next Steps [/]")
                .BorderColor(Color.Gold1)
                .Expand();

            AnsiConsole.Write(panel);
        }
    }
}
```

---

## 8. MULTI-SELECT CHECKBOX MENU (SPECTRE.CONSOLE)

The plugin definition model backing the wizard:

```csharp
// Setup/PluginRegistry.cs
namespace PgwizCmdTools.Setup
{
    public record PluginDef(
        string   Name,
        string   Description,
        string   Layer,          // doskey | batch | ps1 | dotnet
        string[] Commands,
        string?  MacroFile  = null,
        string?  ScriptFile = null,
        bool     IsDefault  = false
    );

    public static class PluginRegistry
    {
        public static readonly List<PluginDef> All = new()
        {
            // ── Aliases ──────────────────────────────────────────────
            new("core-aliases",  "ll, up, back, cls shortcuts",     "doskey",  ["ll","up","back"],   MacroFile: "aliases.mac",      IsDefault: true),
            new("git-aliases",   "gs, gp, gc, glog shortcuts",      "doskey",  ["gs","gp","gc","glog"], MacroFile: "git.mac",        IsDefault: true),
            new("docker-aliases","dps, dcu, dcd shortcuts",         "doskey",  ["dps","dcu","dcd"],  MacroFile: "docker.mac"),

            // ── Scripts ──────────────────────────────────────────────
            new("mygrep",       "Recursive case-insensitive search", "batch",  ["mygrep"],  ScriptFile: "mygrep.cmd",  IsDefault: true),
            new("mkcd",         "mkdir + cd in one command",         "batch",  ["mkcd"],    ScriptFile: "mkcd.cmd"),
            new("touch",        "Create file or update timestamp",   "batch",  ["touch"],   ScriptFile: "touch.cmd"),

            // ── .NET commands ─────────────────────────────────────────
            new("mycmd",        "Full toolkit: hello, greet, etc",  "dotnet",  ["mycmd"]),

            // ── Help System ───────────────────────────────────────────
            new("help-wrapper", "Extends HELP with plugin commands", "batch",  ["help"],   ScriptFile: "help.cmd",    IsDefault: true),
            new("helpme",       "Searchable interactive help",       "batch",  ["helpme"], ScriptFile: "helpme.cmd"),
        };

        public static List<PluginDef> Aliases    => All.Where(p => p.Layer == "doskey").ToList();
        public static List<PluginDef> Scripts     => All.Where(p => p.Layer == "batch").ToList();
        public static List<PluginDef> DotnetTools => All.Where(p => p.Layer == "dotnet").ToList();
        public static List<PluginDef> HelpTools   => All.Where(p => p.Commands.Any(c => c.Contains("help"))).ToList();
        public static List<PluginDef> Defaults    => All.Where(p => p.IsDefault).ToList();
    }
}
```

### What it looks like in terminal

```
 How would you like to install?

  ▶ Install everything (recommended)
    Pick individual plugins
    Minimal install (aliases only)
    Show what would be installed (dry run)
    Uninstall all


── When "Pick individual plugins" is chosen ──

  Select plugins to install:
  (Use <space> to toggle, <enter> to accept)

  ── Aliases (DOSKEY)
  > [x] core-aliases          ll, up, back, cls shortcuts        doskey
    [x] git-aliases           gs, gp, gc, glog shortcuts         doskey
    [ ] docker-aliases        dps, dcu, dcd shortcuts            doskey

  ── Shell Scripts
    [x] mygrep                Recursive case-insensitive search  batch
    [ ] mkcd                  mkdir + cd in one command          batch
    [ ] touch                 Create file or update timestamp    batch

  ── .NET Commands
    [ ] mycmd                 Full toolkit: hello, greet, etc    dotnet

  ── Help System
    [x] help-wrapper          Extends HELP with plugin commands  batch
    [ ] helpme                Searchable interactive help        batch
```

---

## 9. POST-INSTALL HOOK — AUTO-REGISTERS TO PATH & HELP

```csharp
// Setup/PluginInstaller.cs
using System.Runtime.InteropServices;

namespace PgwizCmdTools.Setup
{
    public static class PluginInstaller
    {
        private static readonly string PluginRoot =
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "CmdPlugins");

        public static void Install(PluginDef plugin)
        {
            EnsureDirectories();

            switch (plugin.Layer)
            {
                case "doskey":
                    InstallDoskey(plugin);
                    break;
                case "batch":
                    InstallScript(plugin);
                    break;
                case "dotnet":
                    // Already installed via dotnet tool install — just register help
                    RegisterHelp(plugin);
                    break;
            }

            UpdateManifest(plugin);
        }

        static void InstallDoskey(PluginDef plugin)
        {
            if (plugin.MacroFile == null) return;

            // Extract embedded resource to macros dir
            var dest = Path.Combine(PluginRoot, "macros", plugin.MacroFile);
            ExtractEmbedded($"Assets.{plugin.MacroFile}", dest);

            // Ensure AutoRun loads this .mac file
            RegisterAutoRun(dest);
        }

        static void InstallScript(PluginDef plugin)
        {
            if (plugin.ScriptFile == null) return;

            var dest = Path.Combine(PluginRoot, "bin", plugin.ScriptFile);
            ExtractEmbedded($"Assets.scripts.{plugin.ScriptFile}", dest);
            EnsureOnPath(Path.Combine(PluginRoot, "bin"));

            // Extract help file
            foreach (var cmd in plugin.Commands)
            {
                var helpDest = Path.Combine(PluginRoot, "help", $"{cmd}.txt");
                ExtractEmbedded($"Assets.help.{cmd}.txt", helpDest, optional: true);
            }
        }

        static void RegisterAutoRun(string macroFile)
        {
            const string key     = @"Software\Microsoft\Command Processor";
            const string val     = "AutoRun";
            var          newCmd  = $"doskey /macrofile=\"{macroFile}\"";

            using var regKey = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(key, writable: true)
                            ?? Microsoft.Win32.Registry.CurrentUser.CreateSubKey(key);

            var existing = regKey.GetValue(val) as string ?? "";

            if (!existing.Contains(macroFile))
            {
                var updated = string.IsNullOrEmpty(existing) ? newCmd : $"{existing} & {newCmd}";
                regKey.SetValue(val, updated);
            }
        }

        static void EnsureOnPath(string dir)
        {
            var current = Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User) ?? "";
            if (!current.Contains(dir, StringComparison.OrdinalIgnoreCase))
            {
                Environment.SetEnvironmentVariable("PATH", $"{current};{dir}", EnvironmentVariableTarget.User);
            }
        }

        static void RegisterHelp(PluginDef plugin)
        {
            foreach (var cmd in plugin.Commands)
            {
                var helpDest = Path.Combine(PluginRoot, "help", $"{cmd}.txt");
                ExtractEmbedded($"Assets.help.{cmd}.txt", helpDest, optional: true);
            }
        }

        static void UpdateManifest(PluginDef plugin)
        {
            var manifestTxt = Path.Combine(PluginRoot, "registry", "manifest.txt");
            var line        = $"  {plugin.Name,-20} {plugin.Description}";
            var lines       = File.Exists(manifestTxt)
                ? File.ReadAllLines(manifestTxt).ToList()
                : new List<string>();

            if (!lines.Any(l => l.Contains(plugin.Name)))
            {
                lines.Add(line);
                File.WriteAllLines(manifestTxt, lines);
            }
        }

        static void ExtractEmbedded(string resourceName, string dest, bool optional = false)
        {
            var asm    = System.Reflection.Assembly.GetExecutingAssembly();
            var fullName = asm.GetManifestResourceNames()
                             .FirstOrDefault(n => n.EndsWith(resourceName.Replace('/', '.')));

            if (fullName == null)
            {
                if (!optional) throw new FileNotFoundException($"Embedded resource not found: {resourceName}");
                return;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
            using var stream = asm.GetManifestResourceStream(fullName)!;
            using var file   = File.Create(dest);
            stream.CopyTo(file);
        }

        static void EnsureDirectories()
        {
            foreach (var dir in new[] { "bin", "lib", "help", "macros", "registry" })
                Directory.CreateDirectory(Path.Combine(PluginRoot, dir));
        }

        public static void UninstallAll()
        {
            // Remove AutoRun entries
            using var key = Microsoft.Win32.Registry.CurrentUser
                .OpenSubKey(@"Software\Microsoft\Command Processor", writable: true);
            key?.DeleteValue("AutoRun", throwOnMissingValue: false);

            // Remove custom registry keys
            Microsoft.Win32.Registry.CurrentUser.DeleteSubKeyTree(
                @"Software\MyCmdPlugins", throwOnMissingSubKey: false);

            // Remove from PATH
            var path = Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User) ?? "";
            var cleaned = string.Join(";",
                path.Split(';').Where(p => !p.Contains("CmdPlugins")));
            Environment.SetEnvironmentVariable("PATH", cleaned, EnvironmentVariableTarget.User);

            // Remove files
            var root = Path.Combine(Environment.GetFolderPath(
                Environment.SpecialFolder.UserProfile), "CmdPlugins");
            if (Directory.Exists(root))
                Directory.Delete(root, recursive: true);
        }
    }
}
```

---

## 10. PRIVATE NUGET FEED (SELF-HOSTED)

If you don't want to publish to nuget.org (internal tools, client work):

### Option A — GitHub Packages (free for public repos)

```powershell
# Add GitHub as a NuGet source
dotnet nuget add source "https://nuget.pkg.github.com/pgwiz/index.json" `
    --name github `
    --username pgwiz `
    --password $env:GITHUB_TOKEN

# Push to GitHub Packages
dotnet nuget push ".\nupkg\pgwiz.cmdtools.1.0.0.nupkg" `
    --source github `
    --api-key $env:GITHUB_TOKEN

# End user installs with:
dotnet nuget add source "https://nuget.pkg.github.com/pgwiz/index.json" `
    --name pgwiz-github --username <user> --password <PAT>
dotnet tool install -g pgwiz.cmdtools --add-source https://nuget.pkg.github.com/pgwiz/index.json
```

### Option B — Local/LAN feed (zero infra)

```powershell
# Any folder on disk or network share becomes a feed
$feedPath = "E:\Backup\pwiz\nuget-feed"
New-Item -ItemType Directory -Force $feedPath

# Add as source
dotnet nuget add source $feedPath --name pgwiz-local

# Push = just copy the .nupkg there
Copy-Item ".\nupkg\pgwiz.cmdtools.1.0.0.nupkg" $feedPath

# Install from local
dotnet tool install -g pgwiz.cmdtools --add-source $feedPath
```

### Option C — BaGet (self-hosted NuGet server, Docker)

```yaml
# docker-compose.yml
services:
  baget:
    image: loicsharma/baget
    ports:
      - "5555:80"
    environment:
      ApiKey: "your-secret-key"
      Storage__Type: FileSystem
      Storage__Path: /var/baget/packages
      Database__Type: Sqlite
      Database__ConnectionString: "Data Source=/var/baget/baget.db"
    volumes:
      - ./baget-data:/var/baget
```

```powershell
# Push to self-hosted BaGet
dotnet nuget push ".\nupkg\pgwiz.cmdtools.1.0.0.nupkg" `
    --source http://localhost:5555/v3/index.json `
    --api-key your-secret-key
```

---

## 11. FULL AGENT WORKFLOW

```powershell
# agent_publish.ps1 — full pipeline: build → pack → publish → verify

param(
    [string]$Version     = "1.0.0",
    [string]$Target      = "nuget",   # nuget | github | local
    [switch]$DryRun
)

$proj   = "src\PgwizCmdTools\PgwizCmdTools.csproj"
$outDir = ".\nupkg"

Write-Host "── pgwiz.cmdtools publish pipeline ──" -ForegroundColor Cyan

# 1. Bump version in csproj
(Get-Content $proj) -replace '<Version>.*</Version>', "<Version>$Version</Version>" |
    Set-Content $proj
Write-Host "[1/5] Version set to $Version"

# 2. Clean + build
dotnet build $proj -c Release -v q
Write-Host "[2/5] Build OK"

# 3. Pack
dotnet pack $proj -c Release --no-build -o $outDir /p:Version=$Version
$pkg = Get-ChildItem "$outDir\*.nupkg" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "[3/5] Packed: $($pkg.Name)"

if ($DryRun) { Write-Host "[DRYRUN] Stopping before push."; exit 0 }

# 4. Push
switch ($Target) {
    "nuget" {
        dotnet nuget push $pkg.FullName --source https://api.nuget.org/v3/index.json --api-key $env:NUGET_API_KEY --skip-duplicate
        Write-Host "[4/5] Pushed to nuget.org"
    }
    "github" {
        dotnet nuget push $pkg.FullName --source github --api-key $env:GITHUB_TOKEN --skip-duplicate
        Write-Host "[4/5] Pushed to GitHub Packages"
    }
    "local" {
        Copy-Item $pkg.FullName "E:\Backup\pwiz\nuget-feed\"
        Write-Host "[4/5] Copied to local feed"
    }
}

# 5. Verify install works
Write-Host "[5/5] Verifying install..."
dotnet tool uninstall -g pgwiz.cmdtools 2>$null
dotnet tool install  -g pgwiz.cmdtools
pgwiz --version
Write-Host "[DONE] pgwiz.cmdtools v$Version published and verified." -ForegroundColor Green
```

---

## 12. QUICK REFERENCE

```
PUBLISH TARGETS
  nuget.org       dotnet nuget push --source https://api.nuget.org/v3/index.json
  GitHub Pkgs     dotnet nuget push --source https://nuget.pkg.github.com/<user>/index.json
  Local folder    Copy-Item *.nupkg <folder>   (folder added as dotnet nuget source)
  BaGet (Docker)  dotnet nuget push --source http://localhost:5555/v3/index.json

END-USER INSTALL
  dotnet tool install -g pgwiz.cmdtools              ← from nuget.org
  dotnet tool install -g pgwiz.cmdtools --add-source ← from private feed
  dotnet tool update  -g pgwiz.cmdtools              ← update
  dotnet tool uninstall -g pgwiz.cmdtools            ← clean remove

WIZARD INVOCATION
  pgwiz setup            ← full interactive TUI
  pgwiz setup --all      ← silent install everything
  pgwiz setup --minimal  ← aliases only
  pgwiz list             ← show installed plugins
  pgwiz uninstall <id>   ← remove one plugin

KEY NUGET METADATA (in .csproj)
  <PackAsTool>true</PackAsTool>          ← makes it a global tool
  <ToolCommandName>pgwiz</ToolCommandName> ← the actual command name
  <PackageId>pgwiz.cmdtools</PackageId>  ← what users dotnet tool install

SPECTRE.CONSOLE INSTALL
  dotnet add package Spectre.Console
  dotnet add package Spectre.Console.Cli
```

---

*NUT.md — because someone had to name it that. pgwiz / 2025.*
