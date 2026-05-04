using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Spectre.Console;

namespace PgwizCmdTools.Setup
{
    public class PluginInstaller
    {
        private readonly string cmdPluginsDir;
        private readonly string profilePath;

        public PluginInstaller()
        {
            cmdPluginsDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                "CmdPlugins"
            );
            profilePath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                "PowerShell",
                "Microsoft.PowerShell_profile.ps1"
            );
        }

        public async Task InstallAsync(List<string> selectedAliases)
        {
            try
            {
                // Step 1: Create directory structure
                CreateDirectories();

                // Step 2: Install gsudo
                await InstallGsudo();

                // Step 3: Deploy alias files
                foreach (var alias in selectedAliases)
                {
                    AnsiConsole.MarkupLine($"[dim]Installing {alias}...[/]");
                    await DeployAliasAsync(alias);
                }

                // Step 4: Update PowerShell profile
                UpdatePowerShellProfile(selectedAliases);

                // Step 5: Add to PATH
                AddToPath();

                AnsiConsole.MarkupLine("[green]✓ All components installed[/]");
            }
            catch (Exception ex)
            {
                AnsiConsole.MarkupLine($"[red]Installation failed:[/] {ex.Message}");
                throw;
            }
        }

        private void CreateDirectories()
        {
            AnsiConsole.MarkupLine("[dim]Creating directories...[/]");

            var dirs = new[] { "ps1", "bin", "lib", "help", "macros", "registry" };
            foreach (var dir in dirs)
            {
                var path = Path.Combine(cmdPluginsDir, dir);
                Directory.CreateDirectory(path);
            }

            AnsiConsole.MarkupLine("[green]✓ Directories created[/]");
        }

        private async Task InstallGsudo()
        {
            AnsiConsole.MarkupLine("[dim]Checking gsudo...[/]");

            try
            {
                // Check if gsudo already installed
                var processInfo = new ProcessStartInfo
                {
                    FileName = "gsudo",
                    Arguments = "--version",
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using (var process = Process.Start(processInfo))
                {
                    if (process != null && process.WaitForExit(5000))
                    {
                        AnsiConsole.MarkupLine("[green]✓ gsudo already installed[/]");
                        return;
                    }
                }
            }
            catch
            {
                // Not installed, continue
            }

            // Install gsudo via winget
            AnsiConsole.MarkupLine("[dim]Installing gsudo via winget...[/]");

            try
            {
                var processInfo = new ProcessStartInfo
                {
                    FileName = "winget",
                    Arguments = "install gerardog.gsudo --silent",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true
                };

                using (var process = Process.Start(processInfo))
                {
                    if (process != null && process.WaitForExit(60000))
                    {
                        AnsiConsole.MarkupLine("[green]✓ gsudo installed[/]");
                    }
                }
            }
            catch (Exception ex)
            {
                AnsiConsole.MarkupLine($"[yellow]Warning: Could not install gsudo - {ex.Message}[/]");
                AnsiConsole.MarkupLine("[yellow]You can install manually: winget install gerardog.gsudo[/]");
            }
        }

        private async Task DeployAliasAsync(string aliasName)
        {
            // Extract embedded resources for this alias and deploy to CmdPlugins
            // For now, we'll copy from the repository structure
            
            var aliasDir = Path.Combine(
                Path.GetDirectoryName(typeof(PluginInstaller).Assembly.Location) ?? "",
                "..",
                "..",
                "sudo"  // This references the repo structure
            );

            if (aliasName == "sudo" || aliasName == "refreshsudo")
            {
                // These come from the same sudo/ directory
                var sourcePs1 = Path.Combine(aliasDir, "ps1", $"{aliasName}.ps1");
                var sourceCmd = Path.Combine(aliasDir, "bin", $"{aliasName}.cmd");

                var destPs1 = Path.Combine(cmdPluginsDir, "ps1", $"{aliasName}.ps1");
                var destCmd = Path.Combine(cmdPluginsDir, "bin", $"{aliasName}.cmd");

                if (File.Exists(sourcePs1))
                {
                    File.Copy(sourcePs1, destPs1, true);
                }

                if (File.Exists(sourceCmd))
                {
                    File.Copy(sourceCmd, destCmd, true);
                }
            }

            await Task.Delay(100); // Brief delay for file system
        }

        private void UpdatePowerShellProfile(List<string> selectedAliases)
        {
            AnsiConsole.MarkupLine("[dim]Updating PowerShell profile...[/]");

            // Ensure profile directory exists
            var profileDir = Path.GetDirectoryName(profilePath);
            Directory.CreateDirectory(profileDir ?? "");

            var profileContent = File.Exists(profilePath) ? File.ReadAllText(profilePath) : "";

            // Add dot-source entries for selected aliases
            foreach (var alias in selectedAliases)
            {
                var dotSource = $". \"$env:USERPROFILE\\CmdPlugins\\ps1\\{alias}.ps1\"";
                if (!profileContent.Contains(dotSource))
                {
                    profileContent += Environment.NewLine + dotSource;
                }
            }

            File.WriteAllText(profilePath, profileContent);
            AnsiConsole.MarkupLine("[green]✓ Profile updated[/]");
        }

        private void AddToPath()
        {
            AnsiConsole.MarkupLine("[dim]Adding to PATH...[/]");

            var binPath = Path.Combine(cmdPluginsDir, "bin");
            var currentPath = Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User) ?? "";

            if (!currentPath.Contains(binPath))
            {
                var newPath = $"{binPath};{currentPath}";
                Environment.SetEnvironmentVariable("PATH", newPath, EnvironmentVariableTarget.User);
                AnsiConsole.MarkupLine("[green]✓ PATH updated[/]");
            }
            else
            {
                AnsiConsole.MarkupLine("[dim]Already in PATH[/]");
            }
        }
    }
}
