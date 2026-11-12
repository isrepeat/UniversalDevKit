using System;
using System.Threading.Tasks;

using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace UniversalDevKit.UdkCli.VisualStudio.Commands {
    internal sealed class RegenerateSolutionCommand {
        internal static readonly int Id = 0x0100;

        private readonly AsyncPackage package;

        public bool IsRunning { get; private set; }

        public RegenerateSolutionCommand(AsyncPackage package) {
            this.package = package;
        }

        public void Execute(object sender, EventArgs args) {
            ThreadHelper.ThrowIfNotOnUIThread();
            if (this.IsRunning) {
                return;
            }
            this.IsRunning = true;
            this.package.JoinableTaskFactory.RunAsync(this.RegenerateAsync).FileAndForget("UniversalDevKit/RegenerateSolution");
        }

        private async Task RegenerateAsync() {
            IVsOutputWindowPane pane = null;
            try {
                pane = await VsShell.UdkOutput.GetPaneAsync(this.package);
                await this.package.JoinableTaskFactory.SwitchToMainThreadAsync();
                pane.Activate();

                var root = await VsShell.SolutionRepository.FindAsync(this.package);
                if (root == null) {
                    pane.OutputStringThreadSafe("Open a solution in a repository with Components.json.\r\n");
                    return;
                }
                pane.OutputStringThreadSafe($"Regenerating UDK projects in {root}\r\n");
                var result = await Task.Run(() => Generation.ProjectGenerator.RunAsync(root));
                await this.package.JoinableTaskFactory.SwitchToMainThreadAsync();
                pane.OutputStringThreadSafe(result);
            } catch (Exception exception) {
                await this.package.JoinableTaskFactory.SwitchToMainThreadAsync();
                pane?.OutputStringThreadSafe($"UDK: {exception.Message}\r\n");
                if (pane == null) {
                    throw;
                }
            } finally {
                await this.package.JoinableTaskFactory.SwitchToMainThreadAsync();
                this.IsRunning = false;
            }
        }
    }
}