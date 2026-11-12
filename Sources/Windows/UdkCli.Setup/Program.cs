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
                Uninstall(log);
                return;
            }

            if (log.IsInitialized) {
                Diagnostic.Log.Write(Diagnostic.Level.Info, "UdkCli.Setup", $"Started UDK CLI {Installation.Version} setup.");
            }
            application.Run(new SetupWindow(log));
        }

        private static void Uninstall(SetupLog log) {
            var dialog = new UninstallWindow();
            if (dialog.ShowDialog() != true) {
                if (log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Info, "UdkCli.Setup", "Uninstall cancelled.");
                }
                return;
            }

            try {
                if (log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Info, "UdkCli.Setup", $"Removing the Visual Studio extension and CLI. Remove version cache: {dialog.RemoveVersionCache}.");
                }
                Installation.Uninstall(dialog.RemoveVersionCache);
                if (log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Info, "UdkCli.Setup", "UDK CLI removed.");
                }
                MessageBox.Show("UDK CLI was removed.", dialog.Title, MessageBoxButton.OK, MessageBoxImage.Information);
            } catch (Exception exception) {
                if (log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Error, "UdkCli.Setup", exception.ToString());
                }
                MessageBox.Show(exception.Message + log.Location, dialog.Title, MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }
}