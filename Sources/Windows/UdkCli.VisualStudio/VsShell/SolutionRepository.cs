using System;
using System.IO;
using System.Threading.Tasks;

using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace UniversalDevKit.UdkCli.VisualStudio.VsShell {
    internal static class SolutionRepository {
        public static async Task<string> FindAsync(AsyncPackage package) {
            await package.JoinableTaskFactory.SwitchToMainThreadAsync(package.DisposalToken);
            var solution = await package.GetServiceAsync(typeof(SVsSolution)) as IVsSolution
                ?? throw new InvalidOperationException("Visual Studio solution service is unavailable.");
            ErrorHandler.ThrowOnFailure(solution.GetSolutionInfo(out var directory, out var solutionFile, out _));
            return string.IsNullOrEmpty(solutionFile) || string.IsNullOrEmpty(directory) ? null : FindRepository(directory);
        }

        private static string FindRepository(string directory) {
            for (var current = new DirectoryInfo(directory); current != null; current = current.Parent) {
                if (File.Exists(Path.Combine(current.FullName, "Components.json")) ||
                    File.Exists(Path.Combine(current.FullName, "Components.xml"))) {
                    return current.FullName;
                }
                var git = Path.Combine(current.FullName, ".git");
                if (Directory.Exists(git) || File.Exists(git)) {
                    break;
                }
            }
            return null;
        }
    }
}