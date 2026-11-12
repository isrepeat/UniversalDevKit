using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Reflection;
using System.Diagnostics;

namespace UniversalDevKit.UdkCli.Setup {
    internal static class Installation {
        private const string RegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\UniversalDevKit.UdkCli";
        private const string UninstallerName = "Uninstall UDK CLI.exe";
        private static readonly string ShortcutPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Uninstall UDK CLI.lnk");

        public static string DefaultDirectory {
            get;
        } = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "UdkCli");

        public static string Version => Assembly.GetExecutingAssembly()
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()!.InformationalVersion;

        public static string? GetInstalledDirectory() {
            using var registration = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RegistryPath);
            return registration?.GetValue("InstallLocation") as string;
        }

        public static void Install(Stream payload, string selectedDirectory) {
            using var registration = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(RegistryPath);
            var registeredDirectory = registration.GetValue("InstallLocation") as string;
            var directory = ValidateDirectory(registeredDirectory ?? selectedDirectory);
            if (directory.Contains(';')) {
                throw new IOException("Choose an installation folder without semicolons to add it to PATH.");
            }
            if (registeredDirectory is null && Directory.Exists(directory) && Directory.EnumerateFileSystemEntries(directory).Any()) {
                throw new IOException($"Choose an empty folder for the first installation.\n{directory}");
            }

            var staging = directory + ".stage-" + Guid.NewGuid().ToString("N");
            var backup = staging + ".previous";
            try {
                Directory.CreateDirectory(staging);
                using (var archive = new ZipArchive(payload)) {
                    archive.ExtractToDirectory(staging);
                }
                File.Copy(Environment.ProcessPath!, Path.Combine(staging, UninstallerName));

                if (Directory.Exists(directory)) {
                    Directory.Move(directory, backup);
                }
                try {
                    Directory.Move(staging, directory);
                } catch {
                    if (Directory.Exists(backup)) {
                        Directory.Move(backup, directory);
                    }
                    throw;
                }

                registration.SetValue("InstallLocation", directory);
                var uninstaller = Path.Combine(directory, UninstallerName);
                registration.SetValue("DisplayName", "UDK CLI");
                registration.SetValue("DisplayVersion", Version);
                registration.SetValue("Publisher", "UniversalDevKit");
                registration.SetValue("UninstallString", $"\"{uninstaller}\" --uninstall");
                registration.SetValue("DisplayIcon", Path.Combine(directory, "udk.exe"));
                registration.SetValue("NoModify", 1);
                registration.SetValue("NoRepair", 1);
                CreateShortcut(uninstaller);
                UpdatePath(registration, directory, addToPath: true);
                if (Directory.Exists(backup)) {
                    Directory.Delete(backup, recursive: true);
                }
            } finally {
                if (Directory.Exists(staging)) {
                    Directory.Delete(staging, recursive: true);
                }
            }
        }

        public static void Uninstall(bool removeVersionCache) {
            using var registration = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RegistryPath, writable: true);
            if (registration?.GetValue("InstallLocation") is not string registeredDirectory) {
                throw new InvalidOperationException("UDK CLI is not registered for the current user.");
            }

            var directory = ValidateDirectory(registeredDirectory);
            var uninstaller = Path.Combine(directory, UninstallerName);
            if (!string.Equals(Environment.ProcessPath, uninstaller, StringComparison.OrdinalIgnoreCase)) {
                throw new InvalidOperationException("Run the installed uninstaller from the Start menu.");
            }

            Task.Run(VisualStudioIntegration.UninstallAsync).GetAwaiter().GetResult();

            if (removeVersionCache) {
                RemoveVersionCache(directory);
            }

            var tools = Path.Combine(directory, "Tools");
            if (Directory.Exists(tools)) {
                Directory.Delete(tools, recursive: true);
            }
            File.Delete(Path.Combine(directory, "udk.exe"));
            File.Delete(Path.Combine(directory, "LICENSE"));
            File.Delete(ShortcutPath);
            UpdatePath(registration, directory, addToPath: false);

            // Windows releases the executable after this process exits.
            var cleanup = new ProcessStartInfo {
                FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                UseShellExecute = false,
                CreateNoWindow = true
            };
            cleanup.ArgumentList.Add("-NoProfile");
            cleanup.ArgumentList.Add("-Command");
            cleanup.ArgumentList.Add("Wait-Process -Id $env:UDK_SETUP_PID -ErrorAction SilentlyContinue; " +
                "Remove-Item -LiteralPath $env:UDK_SETUP_EXE -ErrorAction Stop; " +
                "if (-not (Get-ChildItem -LiteralPath $env:UDK_SETUP_DIR -Force)) { [IO.Directory]::Delete($env:UDK_SETUP_DIR) }");
            cleanup.Environment["UDK_SETUP_PID"] = Environment.ProcessId.ToString();
            cleanup.Environment["UDK_SETUP_EXE"] = uninstaller;
            cleanup.Environment["UDK_SETUP_DIR"] = directory;
            using var process = Process.Start(cleanup) ?? throw new InvalidOperationException("Could not start uninstall cleanup.");
            Microsoft.Win32.Registry.CurrentUser.DeleteSubKeyTree(RegistryPath);
        }

        public static bool HasPowerShell() => (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';')
            .Where(entry => !string.IsNullOrWhiteSpace(entry))
            .Any(entry => File.Exists(Path.Combine(Environment.ExpandEnvironmentVariables(entry.Trim().Trim('"')), "pwsh.exe")));

        private static void RemoveVersionCache(string installDirectory) {
            var cacheRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "UdkCli");
            var versions = Path.Combine(cacheRoot, "versions");
            if (!Directory.Exists(versions)) {
                return;
            }

            ValidateDirectory(cacheRoot);
            ValidateDirectory(versions);
            if (string.Equals(installDirectory, versions, StringComparison.OrdinalIgnoreCase) ||
                installDirectory.StartsWith(versions + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) {
                throw new IOException("The UDK CLI installation is inside the version cache.");
            }
            Directory.Delete(versions, recursive: true);
        }

        private static string ValidateDirectory(string path) {
            if (!Path.IsPathFullyQualified(path)) {
                throw new IOException("Choose an absolute installation folder.");
            }
            var directory = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
            if (Path.GetDirectoryName(directory) is null ||
                (Directory.Exists(directory) && (File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)) {
                throw new IOException("Choose a regular installation folder below the drive root.");
            }
            return directory;
        }

        private static void CreateShortcut(string uninstaller) {
            var shellType = Type.GetTypeFromProgID("WScript.Shell", throwOnError: true)!;
            dynamic shell = Activator.CreateInstance(shellType)!;
            dynamic shortcut = shell.CreateShortcut(ShortcutPath);
            shortcut.TargetPath = uninstaller;
            shortcut.Arguments = "--uninstall";
            shortcut.Save();
        }

        private static void UpdatePath(Microsoft.Win32.RegistryKey registration, string directory, bool addToPath) {
            using var environment = Microsoft.Win32.Registry.CurrentUser.CreateSubKey("Environment");
            var value = environment.GetValue("Path", null, Microsoft.Win32.RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
            var entries = (value ?? "").Split(';').ToList();
            var owned = registration.GetValue("OwnsPath") is 1;
            var exactIndex = entries.FindLastIndex(entry => string.Equals(entry, directory, StringComparison.OrdinalIgnoreCase));
            if (addToPath) {
                if (entries.Any(entry => string.Equals(
                    Path.TrimEndingDirectorySeparator(Environment.ExpandEnvironmentVariables(entry.Trim().Trim('"'))),
                    directory, StringComparison.OrdinalIgnoreCase))) {
                    return;
                }
                if (entries.Count == 1 && entries[0].Length == 0) {
                    entries.Clear();
                }
                entries.Add(directory);
            } else {
                if (!owned || exactIndex < 0) {
                    return;
                }
                entries.RemoveAt(exactIndex);
            }

            var kind = value is null ? Microsoft.Win32.RegistryValueKind.ExpandString : environment.GetValueKind("Path");
            environment.SetValue("Path", string.Join(';', entries), kind);
            registration.SetValue("OwnsPath", addToPath ? 1 : 0);
            SendMessageTimeout(new IntPtr(0xffff), 0x001a, IntPtr.Zero, "Environment", 2, 3000, out _);
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wParam, string lParam,
            uint flags, uint timeout, out IntPtr result);
    }
}