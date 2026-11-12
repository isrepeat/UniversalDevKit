using System;
using System.Windows;

namespace UniversalDevKit.UdkCli.Setup {
    internal static class Program {
        [STAThread]
        public static void Main(string[] args) {
            var application = new Application();
            if (args is ["--uninstall"]) {
                Uninstall();
                return;
            }

            application.Run(new SetupWindow());
        }

        private static void Uninstall() {
            var dialog = new UninstallWindow();
            if (dialog.ShowDialog() != true) {
                return;
            }

            try {
                Installation.Uninstall(dialog.RemoveVersionCache);
                MessageBox.Show("UDK CLI was removed.", dialog.Title, MessageBoxButton.OK, MessageBoxImage.Information);
            } catch (Exception exception) {
                MessageBox.Show(exception.Message, dialog.Title, MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }
}