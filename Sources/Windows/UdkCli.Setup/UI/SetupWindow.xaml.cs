using System;
using System.IO;
using System.Windows;
using System.Reflection;

namespace UniversalDevKit.UdkCli.Setup {
    public partial class SetupWindow : Window {
        private readonly SetupLog log;

        internal SetupWindow(SetupLog log) {
            this.log = log;
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

        private async void OnInstallClick(object sender, RoutedEventArgs args) {
            InstallButton.IsEnabled = false;
            BrowseButton.IsEnabled = false;
            try {
                this.log.Info($"Installing CLI to {InstallDirectoryText.Text}.");
                var assembly = Assembly.GetExecutingAssembly();
                using var payload = assembly.GetManifestResourceStream("UdkPayload.zip")
                    ?? throw new InvalidDataException("The installer does not contain the UDK CLI files.");
                Installation.Install(payload, InstallDirectoryText.Text);
                this.log.Info("CLI files installed. Checking the Visual Studio extension.");
                var message = "UDK CLI is installed. Open a new terminal and run udk --help.";
                if (!Installation.HasPowerShell()) {
                    message += "\n\nPowerShell 7 (pwsh.exe) must be on PATH to run UDK CLI commands.";
                }
                try {
                    using var extension = assembly.GetManifestResourceStream("UdkCli.VisualStudio.vsix")
                        ?? throw new InvalidDataException("The installer does not contain the Visual Studio extension.");
                    var result = await VisualStudioIntegration.InstallAsync(extension);
                    this.log.Info($"Visual Studio integration completed. {result.Trim()}");
                    message += result;
                } catch (Exception exception) {
                    this.log.Error(exception);
                    MessageBox.Show(this, message + "\n\nVisual Studio extension: " + exception.Message + this.log.Location,
                        Title, MessageBoxButton.OK, MessageBoxImage.Warning);
                    InstallLocationLabel.Text = "Update the existing installation in";
                    InstallButton.Content = "Update";
                    BrowseButton.Visibility = Visibility.Collapsed;
                    return;
                }
                this.log.Info("Setup completed.");
                MessageBox.Show(this, message, Title, MessageBoxButton.OK, MessageBoxImage.Information);
                Close();
            } catch (Exception exception) {
                this.log.Error(exception);
                MessageBox.Show(this, exception.Message + this.log.Location, Title, MessageBoxButton.OK, MessageBoxImage.Error);
            } finally {
                InstallButton.IsEnabled = true;
                BrowseButton.IsEnabled = true;
            }
        }

        private void OnCancelClick(object sender, RoutedEventArgs args) {
            Close();
        }
    }
}