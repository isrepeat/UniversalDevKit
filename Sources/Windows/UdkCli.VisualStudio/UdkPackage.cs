using System;
using System.Threading;
using System.Threading.Tasks;

using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace UniversalDevKit.UdkCli.VisualStudio {
    public sealed partial class UdkPackage : AsyncPackage {
        private Input.RegenerateShortcut shortcut;

        protected override async Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress) {
            VsShell.VsixLog.Initialize();
            var command = await Commands.CommandRegistration.RegisterAsync(this, cancellationToken);
            if (command == null) {
                return;
            }
            await this.JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);
            if (await this.GetServiceAsync(typeof(SVsFilterKeys)) is IVsFilterKeys2 filterKeys &&
                await this.GetServiceAsync(typeof(SVsUIShell)) is IVsUIShell uiShell) {
                this.shortcut = new Input.RegenerateShortcut(this, command, filterKeys, uiShell);
            } else {
                if (VsShell.VsixLog.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Warning, VsShell.VsixLog.Category, "Shortcut services unavailable.");
                } else {
                    ActivityLog.LogWarning(VsShell.VsixLog.Category, "Shortcut services unavailable.");
                }
            }
        }

        protected override void Dispose(bool disposing) {
            if (disposing) {
                this.shortcut?.Dispose();
                VsShell.VsixLog.Shutdown();
            }
            base.Dispose(disposing);
        }
    }
}