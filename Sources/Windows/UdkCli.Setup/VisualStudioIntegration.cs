using System;
using System.IO;
using System.IO.Compression;
using System.Xml.Linq;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Diagnostics;

namespace UniversalDevKit.UdkCli.Setup {
    internal static class VisualStudioIntegration {
        private const int AlreadyInstalled = 1001;
        private const string ExtensionId = "UniversalDevKit.UdkCli.VisualStudio";
        private static readonly XNamespace ManifestNamespace = "http://schemas.microsoft.com/developer/vsx-schema/2011";

        private sealed record Instance(string Id, string Name, string Installer, string ExtensionsDirectory);

        private static async Task<Instance[]> FindInstancesAsync() {
            var vswhere = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                "Microsoft Visual Studio", "Installer", "vswhere.exe");
            if (!File.Exists(vswhere)) {
                return [];
            }

            using var discovery = Start(vswhere, true, "-products", "*", "-prerelease", "-version", "[18.0,19.0)", "-requires",
                "Microsoft.VisualStudio.Component.CoreEditor", "-format", "json", "-utf8");
            var instances = await discovery.StandardOutput.ReadToEndAsync();
            await discovery.WaitForExitAsync();
            if (discovery.ExitCode != 0) {
                throw new InvalidOperationException($"Visual Studio discovery failed (exit code {discovery.ExitCode}).");
            }
            using var document = JsonDocument.Parse(instances);
            return document.RootElement.EnumerateArray().Select(installation => {
                var id = installation.GetProperty("instanceId").GetString()!;
                var name = installation.GetProperty("displayName").GetString()!;
                var directory = installation.GetProperty("installationPath").GetString()!;
                return new Instance(id, name, Path.Combine(directory, "Common7", "IDE", "VSIXInstaller.exe"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                        "Microsoft", "VisualStudio", $"18.0_{id}", "Extensions"));
            }).ToArray();
        }

        public static async Task<string> InstallAsync(Stream package, Action<int> reportProgress) {
            var installations = await FindInstancesAsync();
            if (installations.Length == 0) {
                reportProgress(100);
                return "";
            }

            var packagePath = Path.Combine(Path.GetTempPath(), $"UdkCli-{Guid.NewGuid():N}.vsix");
            var failures = new List<string>();
            try {
                await using (var file = File.Open(packagePath, FileMode.CreateNew, FileAccess.Write, FileShare.None)) {
                    await package.CopyToAsync(file);
                }
                var expected = ReadPackageVersion(packagePath);
                var completed = 1;
                var total = installations.Length + 2;
                reportProgress(100 * completed / total);
                foreach (var installation in installations) {
                    var log = Path.Combine(Path.GetTempPath(), $"UdkCli-Vsix-{Guid.NewGuid():N}.log");
                    try {
                        var installed = ReadInstalledVersions(installation);
                        if (installed.Length == 1 && installed[0] == expected) {
                            continue;
                        }
                        if (installed.Any(version => version > expected)) {
                            failures.Add($"{installation.Name} ({installation.Id}): installed UDK extension {string.Join(", ", installed.Select(version => version.ToString()))}; this Setup contains {expected}. Use a newer UDK Setup.");
                            continue;
                        }
                        if (IsVisualStudioRunning()) {
                            failures.Add("Close Visual Studio, then click Install extension.");
                            break;
                        }
                        using var process = Start(installation.Installer, false, "/quiet",
                            $"/instanceIds:{installation.Id}", $"/logFile:{log}", packagePath);
                        await process.WaitForExitAsync();
                        installed = ReadInstalledVersions(installation);
                        if ((process.ExitCode != 0 && process.ExitCode != AlreadyInstalled)
                            || installed.Length != 1 || installed[0] != expected) {
                            var actual = installed.Length == 0 ? "missing" : string.Join(", ", installed.Select(version => version.ToString()));
                            failures.Add($"{installation.Name} ({installation.Id}): expected UDK extension {expected}, found {actual} (exit code {process.ExitCode}). Log: {log}");
                        }
                    } catch (Exception exception) {
                        failures.Add($"{installation.Name} ({installation.Id}): {exception.Message}");
                    } finally {
                        reportProgress(100 * ++completed / total);
                    }
                }
            } finally {
                File.Delete(packagePath);
            }
            if (failures.Count != 0) {
                throw new InvalidOperationException(string.Join(Environment.NewLine, failures));
            }
            reportProgress(100);
            return "\n\nIn Visual Studio, select Tools > Regenerate UDK Solution.";
        }

        public static async Task UninstallAsync() {
            var installations = await FindInstancesAsync();
            var failures = new List<string>();
            foreach (var installation in installations) {
                var log = Path.Combine(Path.GetTempPath(), $"UdkCli-Vsix-{Guid.NewGuid():N}.log");
                try {
                    if (ReadInstalledVersions(installation).Length == 0) {
                        continue;
                    }
                    if (IsVisualStudioRunning()) {
                        throw new InvalidOperationException("Close Visual Studio and run UDK Uninstall again.");
                    }
                    using var process = Start(installation.Installer, false, "/quiet",
                        $"/instanceIds:{installation.Id}", $"/logFile:{log}", $"/uninstall:{ExtensionId}");
                    await process.WaitForExitAsync();
                    if (ReadInstalledVersions(installation).Length != 0) {
                        failures.Add($"{installation.Name} ({installation.Id}): UDK extension is still installed (exit code {process.ExitCode}). Log: {log}");
                    }
                } catch (Exception exception) {
                    failures.Add($"{installation.Name} ({installation.Id}): {exception.Message}");
                }
            }
            if (failures.Count != 0) {
                throw new InvalidOperationException(string.Join(Environment.NewLine, failures));
            }
        }

        private static Version ReadPackageVersion(string path) {
            using var archive = ZipFile.OpenRead(path);
            using var manifest = archive.GetEntry("extension.vsixmanifest")?.Open()
                ?? throw new InvalidDataException("The bundled VSIX has no extension manifest.");
            return ReadExtensionVersion(manifest)
                ?? throw new InvalidDataException("The bundled VSIX has an unexpected extension ID.");
        }

        private static Version[] ReadInstalledVersions(Instance installation) {
            if (!Directory.Exists(installation.ExtensionsDirectory)) {
                return [];
            }
            var versions = new List<Version>();
            foreach (var path in Directory.EnumerateFiles(installation.ExtensionsDirectory, "extension.vsixmanifest", SearchOption.AllDirectories)) {
                using var manifest = File.OpenRead(path);
                if (ReadExtensionVersion(manifest) is Version version) {
                    versions.Add(version);
                }
            }
            return versions.ToArray();
        }

        private static Version? ReadExtensionVersion(Stream manifest) {
            var identity = XDocument.Load(manifest).Root?.Element(ManifestNamespace + "Metadata")?.Element(ManifestNamespace + "Identity");
            if (!string.Equals((string?)identity?.Attribute("Id"), ExtensionId, StringComparison.OrdinalIgnoreCase)) {
                return null;
            }
            return Version.Parse((string?)identity?.Attribute("Version")
                ?? throw new InvalidDataException("The UDK extension manifest has no version."));
        }

        private static bool IsVisualStudioRunning() {
            using var current = Process.GetCurrentProcess();
            var sessionId = current.SessionId;
            var processes = Process.GetProcessesByName("devenv");
            try {
                return processes.Any(process => process.SessionId == sessionId);
            } finally {
                foreach (var process in processes) {
                    process.Dispose();
                }
            }
        }

        private static Process Start(string executable, bool captureOutput, params string[] arguments) {
            var start = new ProcessStartInfo {
                FileName = executable,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = captureOutput
            };
            if (captureOutput) {
                start.StandardOutputEncoding = Encoding.UTF8;
            }
            foreach (var argument in arguments) {
                start.ArgumentList.Add(argument);
            }
            return Process.Start(start) ?? throw new InvalidOperationException($"Could not start {executable}.");
        }
    }
}