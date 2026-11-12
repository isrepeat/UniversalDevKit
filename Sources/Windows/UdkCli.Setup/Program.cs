using System;
using System.Windows;

namespace UniversalDevKit.UdkCli.Setup {
    internal static class Program {
        [STAThread]
        public static void Main(string[] args) {
            using var log = new SetupLog();
            var application = new Application();
            if (args is ["--uninstall"]) {
                log.Info($"Started UDK CLI {Installation.Version} uninstall.");
                Uninstall(log);
                return;
            }

            log.Info($"Started UDK CLI {Installation.Version} setup.");
            application.Run(new SetupWindow(log));
        }

        private static void Uninstall(SetupLog log) {
            var dialog = new UninstallWindow();
            if (dialog.ShowDialog() != true) {
                log.Info("Uninstall cancelled.");
                return;
            }

            try {
                log.Info($"Removing the Visual Studio extension and CLI. Remove version cache: {dialog.RemoveVersionCache}.");
                Installation.Uninstall(dialog.RemoveVersionCache);
                log.Info("UDK CLI removed.");
                MessageBox.Show("UDK CLI was removed.", dialog.Title, MessageBoxButton.OK, MessageBoxImage.Information);
            } catch (Exception exception) {
                log.Error(exception);
                MessageBox.Show(exception.Message + log.Location, dialog.Title, MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }
}