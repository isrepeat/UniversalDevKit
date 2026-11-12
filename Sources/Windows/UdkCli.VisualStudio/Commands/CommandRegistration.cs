using System;
using System.Threading;
using System.Threading.Tasks;
using System.ComponentModel.Design;

using Microsoft.VisualStudio.Shell;

namespace UniversalDevKit.UdkCli.VisualStudio.Commands {
    internal static class CommandRegistration {
        private static readonly Guid CommandSet = new Guid("93e681d4-1b92-46a3-9400-a1a8c947417a");

        public static async Task RegisterAsync(AsyncPackage package, CancellationToken cancellationToken) {
            await package.JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);
            if (await package.GetServiceAsync(typeof(IMenuCommandService)) is OleMenuCommandService commandService) {
                var handler = new RegenerateSolutionCommand(package);
                var command = new OleMenuCommand(handler.Execute, new CommandID(CommandSet, RegenerateSolutionCommand.Id));
                command.BeforeQueryStatus += (_, _) => command.Enabled = !handler.IsRunning;
                commandService.AddCommand(command);
            }
        }
    }
}