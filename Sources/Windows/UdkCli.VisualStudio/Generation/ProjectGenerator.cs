using System.IO;
using System.Text;
using System.Threading.Tasks;
using System.Diagnostics;
using System.ComponentModel;

using Microsoft.Win32;
using Microsoft.VisualStudio.Shell;

namespace UniversalDevKit.UdkCli.VisualStudio.Generation {
    internal static class ProjectGenerator {
        private const string Registration = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\UniversalDevKit.UdkCli";

        public static async Task<string> RunAsync(string root) {
            var script = Path.Combine(root, "Sources", "Windows", "UdkCli", "Tools", "ProjectTools", "Generate.ps1");
            var local = File.Exists(script);
            var start = new ProcessStartInfo {
                FileName = local ? "pwsh.exe" : FindUdk(),
                Arguments = local ? $"-NoProfile -File \"{script}\" -ManifestPath Components.json" : "project generate",
                WorkingDirectory = root,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };
            using var process = new Process { StartInfo = start };
            try {
                process.Start();
            } catch (Win32Exception exception) when (!local && (exception.NativeErrorCode == 2 || exception.NativeErrorCode == 3)) {
                if (VsShell.VsixLog.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Warning, VsShell.VsixLog.Category, exception.Message);
                } else {
                    ActivityLog.LogWarning(VsShell.VsixLog.Category, exception.Message);
                }
                return "UDK CLI was not found. Install UDK CLI and reopen Visual Studio, then run Tools > Regenerate UDK Solution again.\r\n";
            }
            var stdout = process.StandardOutput.ReadToEndAsync();
            var stderr = process.StandardError.ReadToEndAsync();
            await Task.WhenAll(stdout, stderr);
            process.WaitForExit();
            if (process.ExitCode != 0) {
                var message = $"Generation exited with code {process.ExitCode}. {await stderr}";
                if (VsShell.VsixLog.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Error, VsShell.VsixLog.Category, message);
                } else {
                    ActivityLog.LogError(VsShell.VsixLog.Category, message);
                }
            }
            return $"{await stdout}{await stderr}UDK exited with code {process.ExitCode}.\r\n";
        }

        private static string FindUdk() {
            using var registration = Registry.CurrentUser.OpenSubKey(Registration);
            if (registration?.GetValue("InstallLocation") is string directory) {
                var executable = Path.Combine(directory, "udk.exe");
                if (File.Exists(executable)) {
                    return executable;
                }
            }
            return "udk.exe";
        }
    }
}