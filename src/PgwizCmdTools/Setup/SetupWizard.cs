using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Spectre.Console;

namespace PgwizCmdTools.Setup
{
    public class SetupWizard
    {
        private List<AliasOption> availableAliases = new()
        {
            new AliasOption("sudo", "Execute commands with elevation (inline, no new window)", true),
            new AliasOption("refreshsudo", "Refresh stale elevation tokens", true),
        };

        public async Task RunAsync()
        {
            try
            {
                // Check prerequisites
                CheckPrerequisites();
                
                AnsiConsole.MarkupLine("");
                AnsiConsole.MarkupLine("[yellow]STEP 1: Select Aliases to Install[/]");
                AnsiConsole.MarkupLine("");
                
                var selectedAliases = ShowCheckboxMenu();
                
                if (!selectedAliases.Any())
                {
                    AnsiConsole.MarkupLine("[yellow]No aliases selected. Exiting.[/]");
                    return;
                }

                AnsiConsole.MarkupLine("");
                AnsiConsole.MarkupLine("[yellow]STEP 2: Configure Installation[/]");
                AnsiConsole.MarkupLine("");
                
                // Show configuration summary
                var cmdPluginsDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "CmdPlugins");
                AnsiConsole.MarkupLine($"[dim]CmdPlugins Directory:[/] {cmdPluginsDir}");
                AnsiConsole.MarkupLine($"[dim]PowerShell Profile:[/] {GetProfilePath()}");
                AnsiConsole.MarkupLine("");

                var confirm = AnsiConsole.Confirm("[cyan]Ready to install?[/]", true);
                
                if (!confirm)
                {
                    AnsiConsole.MarkupLine("[yellow]Installation cancelled.[/]");
                    return;
                }

                AnsiConsole.MarkupLine("");
                AnsiConsole.MarkupLine("[yellow]STEP 3: Installing...[/]");
                AnsiConsole.MarkupLine("");

                // Run installer
                var installer = new PluginInstaller();
                await installer.InstallAsync(selectedAliases);

                AnsiConsole.MarkupLine("");
                AnsiConsole.MarkupLine("[bold green]✓ Installation complete![/]");
                AnsiConsole.MarkupLine("");
                AnsiConsole.MarkupLine("[cyan]Next steps:[/]");
                AnsiConsole.MarkupLine("  1. Close and reopen PowerShell/CMD for PATH changes");
                AnsiConsole.MarkupLine("  2. Try: [yellow]refreshsudo --status[/]");
                AnsiConsole.MarkupLine("  3. Try: [yellow]sudo whoami[/]");
                AnsiConsole.MarkupLine("");
            }
            catch (Exception ex)
            {
                AnsiConsole.MarkupLine($"[red]Error during setup:[/] {ex.Message}");
                throw;
            }
        }

        private void CheckPrerequisites()
        {
            AnsiConsole.MarkupLine("[yellow]Checking prerequisites...[/]");
            
            // Check if running on Windows
            if (!System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(
                System.Runtime.InteropServices.OSPlatform.Windows))
            {
                throw new PlatformNotSupportedException("This tool only works on Windows.");
            }

            AnsiConsole.MarkupLine("[green]✓ Windows detected[/]");
            
            // Note: gsudo check is done during install
            AnsiConsole.MarkupLine("[dim]gsudo will be installed if not present[/]");
            AnsiConsole.MarkupLine("");
        }

        private List<string> ShowCheckboxMenu()
        {
            var selected = new List<string>();
            
            AnsiConsole.MarkupLine("[dim]Use [green]↑/↓[/] to navigate, [cyan]Space[/] to toggle, [green]Enter[/] to confirm[/]");
            AnsiConsole.MarkupLine("");

            foreach (var alias in availableAliases)
            {
                var prompt = alias.Selected ? "[green]✓[/]" : "[dim]☐[/]";
                var description = $"{prompt} [cyan]{alias.Name}[/] — {alias.Description}";
                
                var selected_this = AnsiConsole.Confirm(description, alias.Selected);
                if (selected_this)
                {
                    selected.Add(alias.Name);
                }
            }

            return selected;
        }

        private string GetProfilePath()
        {
            var psVersion = "Core"; // Assume PowerShell Core 7+
            var profileDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                "PowerShell"
            );
            return Path.Combine(profileDir, "Microsoft.PowerShell_profile.ps1");
        }
    }

    public class AliasOption
    {
        public string Name { get; }
        public string Description { get; }
        public bool Selected { get; set; }

        public AliasOption(string name, string description, bool selected = false)
        {
            Name = name;
            Description = description;
            Selected = selected;
        }
    }
}
