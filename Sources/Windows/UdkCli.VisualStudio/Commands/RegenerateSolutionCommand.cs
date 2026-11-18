using System;
using System.Threading.Tasks;

using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace UniversalDevKit.UdkCli.VisualStudio.Commands {
    internal sealed class RegenerateSolutionCommand {
        internal static readonly int Id = 0x0100;
        internal static readonly int CleanId = 0x0101;

        private readonly AsyncPackage package;

        public bool IsRunning { get; private set; }

        public RegenerateSolutionCommand(AsyncPackage package) {
            this.package = package;
        }

        public void Execute(object sender, EventArgs args) {
            ThreadHelper.ThrowIfNotOnUIThread();
            this.Start(false);
        }

        public void ExecuteClean(object sender, EventArgs args) {
            ThreadHelper.ThrowIfNotOnUIThread();
            this.Start(true);
        }

        private void Start(bool clean) {
            ThreadHelper.ThrowIfNotOnUIThread();
            if (this.IsRunning) {
                return;
            }
            this.IsRunning = true;
            this.package.JoinableTaskFactory.RunAsync(() => this.RegenerateAsync(clean)).FileAndForget("UniversalDevKit/RegenerateSolution");
        }

        private async Task RegenerateAsync(bool clean) {
            IVsOutputWindowPane pane = null;
            try {
                pane = await VsShell.UdkOutput.GetPaneAsync(this.package);
                await this.package.JoinableTaskFactory.SwitchToMainThreadAsync();
                pane.Activate();

                var root = await VsShell.SolutionRepository.FindAsync(this.package);
                if (root == null) {
                    pane.OutputStringThreadSafe("Open a solution in a repository with Components.xml.\r\n");
                    return;
                }
                pane.OutputStringThreadSafe($"Running udk project generate{(clean ? " --clean" : "")} in {root}\r\n");
                if (VsShell.VsixLog.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Info, VsShell.VsixLog.Category, $"Running udk project generate{(clean ? " --clean" : "")} in {root}.");
                }
                await this.RunWithClosedSolutionAsync(root, clean, pane);
            } catch (Exception exception) {
                await this.package.JoinableTaskFactory.SwitchToMainThreadAsync();
                if (VsShell.VsixLog.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Error, VsShell.VsixLog.Category, exception.ToString());
                } else {
                    ActivityLog.LogError(VsShell.VsixLog.Category, exception.ToString());
                }
                pane?.OutputStringThreadSafe($"UDK: {exception.Message}\r\n");
                if (pane == null) {
                    throw;
                }
            } finally {
                await this.package.JoinableTaskFactory.SwitchToMainThreadAsync();
                this.IsRunning = false;
            }
        }

        private async Task RunWithClosedSolutionAsync(string root, bool clean, IVsOutputWindowPane pane) {
            await this.package.JoinableTaskFactory.SwitchToMainThreadAsync();
            var solution = await this.package.GetServiceAsync(typeof(SVsSolution)) as IVsSolution
                ?? throw new InvalidOperationException("Visual Studio solution service is unavailable.");
            ErrorHandler.ThrowOnFailure(solution.GetSolutionInfo(out _, out var solutionFile, out _));
            if (string.IsNullOrEmpty(solutionFile)) {
                throw new InvalidOperationException("The current solution has no saved file.");
            }

            // Close before changing generated files so Visual Studio does not prompt to reload them.
            var closeResult = solution.CloseSolutionElement((uint)__VSSLNSAVEOPTIONS.SLNSAVEOPT_PromptSave, null, 0);
            if (closeResult == VSConstants.E_ABORT || closeResult == VSConstants.S_FALSE) {
                pane.OutputStringThreadSafe("UDK operation cancelled while closing the solution.\r\n");
                return;
            }
            ErrorHandler.ThrowOnFailure(closeResult);
            ErrorHandler.ThrowOnFailure(solution.GetProperty((int)__VSPROPID.VSPROPID_IsSolutionOpen, out var isOpen));
            if ((bool)isOpen) {
                pane.OutputStringThreadSafe("UDK operation cancelled because the solution is still open.\r\n");
                return;
            }

            try {
                var result = await Task.Run(() => Generation.ProjectGenerator.RunAsync(root, clean));
                pane.OutputStringThreadSafe(result);
            } finally {
                await this.package.JoinableTaskFactory.SwitchToMainThreadAsync();
                ErrorHandler.ThrowOnFailure(solution.GetProperty((int)__VSPROPID.VSPROPID_IsSolutionOpen, out isOpen));
                if ((bool)isOpen) {
                    pane.OutputStringThreadSafe($"Another solution was opened during the UDK operation. Reopen '{solutionFile}' to see its changes.\r\n");
                } else {
                    pane.OutputStringThreadSafe($"Reopening solution {solutionFile}\r\n");
                    ErrorHandler.ThrowOnFailure(solution.OpenSolutionFile((uint)__VSSLNOPENOPTIONS.SLNOPENOPT_Silent, solutionFile));
                }
            }
        }
    }
}