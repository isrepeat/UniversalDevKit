using System;
using System.IO;

using Microsoft.VisualStudio.Shell;

namespace UniversalDevKit.UdkCli.VisualStudio.VsShell {
    internal static class VsixLog {
        internal const string Category = "UdkCli.VisualStudio";

        public static bool IsInitialized { get; private set; }

        public static void Initialize() {
            try {
                var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "UdkCli", "Logs", "VisualStudio.log");
                var result = Diagnostic.Log.Initialize(new Diagnostic.LoggerOptions { FilePath = path });
                IsInitialized = result.Succeeded;
                if (!IsInitialized) {
                    ActivityLog.LogWarning(Category, $"Could not initialize Diagnostic: {result.Error}: {result.Message}");
                }
            } catch (Exception exception) {
                ActivityLog.LogWarning(Category, exception.ToString());
            }
        }

        public static void Shutdown() {
            if (IsInitialized) {
                IsInitialized = false;
                Diagnostic.Log.Shutdown();
            }
        }
    }
}