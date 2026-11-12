using System;
using System.Threading.Tasks;

using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace UniversalDevKit.UdkCli.VisualStudio.VsShell {
    internal static class UdkOutput {
        private static readonly Guid PaneId = new Guid("67224449-43a9-4734-986f-dc8150bc1809");

        public static async Task<IVsOutputWindowPane> GetPaneAsync(AsyncPackage package) {
            await package.JoinableTaskFactory.SwitchToMainThreadAsync(package.DisposalToken);
            var output = await package.GetServiceAsync(typeof(SVsOutputWindow)) as IVsOutputWindow
                ?? throw new InvalidOperationException("Visual Studio Output window is unavailable.");
            var paneId = PaneId;
            ErrorHandler.ThrowOnFailure(output.CreatePane(ref paneId, "UDK CLI", 1, 0));
            ErrorHandler.ThrowOnFailure(output.GetPane(ref paneId, out var pane));
            return pane;
        }
    }
}