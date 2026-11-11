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
            const string title = "Uninstall UDK CLI";
            if (MessageBox.Show("Remove UDK CLI for the current user?", title, MessageBoxButton.YesNo,
                MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) {
                return;
            }

            try {
                Installation.Uninstall();
                MessageBox.Show("UDK CLI was removed.", title, MessageBoxButton.OK, MessageBoxImage.Information);
            } catch (Exception exception) {
                MessageBox.Show(exception.Message, title, MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }
}