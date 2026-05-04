using System;
using System.Linq;
using System.Collections.Generic;
using System.Threading.Tasks;
using PgwizCmdTools.Setup;
using Spectre.Console;

namespace PgwizCmdTools
{
    class Program
    {
        static async Task Main(string[] args)
        {
            try
            {
                // If no args, show interactive wizard
                if (args.Length == 0)
                {
                    await RunInteractiveWizard();
                }
                else if (args[0] == "setup")
                {
                    await RunInteractiveWizard();
                }
                else if (args[0] == "--help" || args[0] == "-h")
                {
                    ShowHelp();
                }
                else if (args[0] == "--version" || args[0] == "-v")
                {
                    ShowVersion();
                }
                else
                {
                    AnsiConsole.MarkupLine("[red]Unknown command:[/] {0}", args[0]);
                    AnsiConsole.MarkupLine("[dim]Run 'pgwiz setup' to configure aliases[/]");
                    Environment.Exit(1);
                }
            }
            catch (Exception ex)
            {
                AnsiConsole.WriteException(ex, ExceptionFormats.ShortenEverything);
                Environment.Exit(1);
            }
        }

        static async Task RunInteractiveWizard()
        {
            AnsiConsole.Clear();
            
            AnsiConsole.MarkupLine("[bold green]╔══════════════════════════════════════════════════════════════╗[/]");
            AnsiConsole.MarkupLine("[bold green]║  pgwiz Windows CMD Extensions Setup Wizard                   ║[/]");
            AnsiConsole.MarkupLine("[bold green]╚══════════════════════════════════════════════════════════════╝[/]");
            AnsiConsole.MarkupLine("");
            
            AnsiConsole.MarkupLine("[cyan]Welcome![/] This wizard will help you install Windows CMD aliases and extensions.");
            AnsiConsole.MarkupLine("");
            
            // Let wizard handle the rest
            var wizard = new SetupWizard();
            await wizard.RunAsync();
        }

        static void ShowHelp()
        {
            AnsiConsole.MarkupLine("[bold]pgwiz[/] — Windows CMD Extensions Manager");
            AnsiConsole.MarkupLine("");
            AnsiConsole.MarkupLine("[yellow]USAGE[/]");
            AnsiConsole.MarkupLine("  pgwiz [command]");
            AnsiConsole.MarkupLine("");
            AnsiConsole.MarkupLine("[yellow]COMMANDS[/]");
            AnsiConsole.MarkupLine("  setup       Run interactive setup wizard");
            AnsiConsole.MarkupLine("  --help      Show this help message");
            AnsiConsole.MarkupLine("  --version   Show version information");
            AnsiConsole.MarkupLine("");
            AnsiConsole.MarkupLine("[dim]Documentation: https://github.com/pgwiz/windows_aliases[/]");
        }

        static void ShowVersion()
        {
            var version = typeof(Program).Assembly.GetName().Version;
            AnsiConsole.MarkupLine("[bold]pgwiz[/] version {0}", version ?? new Version(1, 0, 0));
        }
    }
}
