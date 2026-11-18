using System;
using System.Windows;

namespace UniversalDevKit.UdkCli.Setup {
    internal static class Program {
        [STAThread]
        public static void Main(string[] args) {
            using var log = new SetupLog();
            var application = new Application();
            if (args is ["--uninstall"]) {
                if (log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Info, "UdkCli.Setup", $"Started UDK CLI {Installation.Version} uninstall.");
                }
                application.Run(new UninstallWindow(log));
                return;
            }

            if (log.IsInitialized) {
                Diagnostic.Log.Write(Diagnostic.Level.Info, "UdkCli.Setup", $"Started UDK CLI {Installation.Version} setup.");
            }
            application.Run(new SetupWindow(log));
        }
    }
}