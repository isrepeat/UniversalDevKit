using System;
using System.IO;
using System.Windows;
using System.Reflection;

namespace UniversalDevKit.UdkCli.Setup {
    public partial class SetupWindow : Window {
        public SetupWindow() {
            InitializeComponent();
            VersionText.Text = $"UDK CLI {Installation.Version}";
            var installedDirectory = Installation.GetInstalledDirectory();
            InstallDirectoryText.Text = installedDirectory ?? Installation.DefaultDirectory;
            if (installedDirectory is not null) {
                InstallLocationLabel.Text = "Update the existing installation in";
                InstallButton.Content = "Update";
                BrowseButton.Visibility = Visibility.Collapsed;
            }
        }

        private void OnBrowseClick(object sender, RoutedEventArgs args) {
            var dialog = new Microsoft.Win32.OpenFolderDialog {
                Title = "Choose an empty folder for UDK CLI"
            };
            if (Directory.Exists(InstallDirectoryText.Text)) {
                dialog.InitialDirectory = InstallDirectoryText.Text;
            }
            if (dialog.ShowDialog(this) == true) {
                InstallDirectoryText.Text = dialog.FolderName;
            }
        }

        private void OnInstallClick(object sender, RoutedEventArgs args) {
            try {
                using var payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("UdkPayload.zip")
                    ?? throw new InvalidDataException("The installer does not contain the UDK CLI files.");
                Installation.Install(payload, InstallDirectoryText.Text);
                var message = "UDK CLI is installed. Open a new terminal and run udk --help.";
                if (!Installation.HasPowerShell()) {
                    message += "\n\nPowerShell 7 (pwsh.exe) must be on PATH to run UDK CLI commands.";
                }
                MessageBox.Show(this, message, Title, MessageBoxButton.OK, MessageBoxImage.Information);
                Close();
            } catch (Exception exception) {
                MessageBox.Show(this, exception.Message, Title, MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void OnCancelClick(object sender, RoutedEventArgs args) {
            Close();
        }
    }
}