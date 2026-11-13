using System;
using System.IO;
using System.Windows;
using System.Threading.Tasks;
using System.Reflection;
using System.ComponentModel;

namespace UniversalDevKit.UdkCli.Setup {
    public partial class SetupWindow : Window {
        private readonly SetupLog log;

        protected override void OnClosing(CancelEventArgs args) {
            base.OnClosing(args);
            if (ExtensionProgress.Visibility == Visibility.Visible) {
                args.Cancel = true;
            }
        }

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
                if (this.log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Info, "UdkCli.Setup", $"Installing CLI to {InstallDirectoryText.Text}.");
                }
                var assembly = Assembly.GetExecutingAssembly();
                using var payload = assembly.GetManifestResourceStream("UdkPayload.zip")
                    ?? throw new InvalidDataException("The installer does not contain the UDK CLI files.");
                Installation.Install(payload, InstallDirectoryText.Text);
                if (this.log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Info, "UdkCli.Setup", "CLI files installed. Checking the Visual Studio extension.");
                }
                var message = "UDK CLI is installed. Open a new terminal and run udk --help.";
                if (!Installation.HasPowerShell()) {
                    message += "\n\nUDK CLI commands require Windows PowerShell 5.1.";
                }
                try {
                    message += await this.InstallExtensionWithProgressAsync();
                } catch (Exception exception) {
                    var extensionWindow = new ExtensionWindow(message, exception.Message, this.log.Location, this.InstallExtensionAsync) {
                        Owner = this
                    };
                    var installed = extensionWindow.ShowDialog() == true;
                    if (this.log.IsInitialized) {
                        Diagnostic.Log.Write(Diagnostic.Level.Info, "UdkCli.Setup",
                            installed ? "Setup completed." : "Setup completed without finishing Visual Studio integration.");
                    }
                    Close();
                    return;
                }
                if (this.log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Info, "UdkCli.Setup", "Setup completed.");
                }
                MessageBox.Show(this, message, Title, MessageBoxButton.OK, MessageBoxImage.Information);
                Close();
            } catch (Exception exception) {
                if (this.log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Error, "UdkCli.Setup", exception.ToString());
                }
                MessageBox.Show(this, exception.Message + this.log.Location, Title, MessageBoxButton.OK, MessageBoxImage.Error);
            } finally {
                InstallButton.IsEnabled = true;
                BrowseButton.IsEnabled = true;
            }
        }

        private async Task<string> InstallExtensionWithProgressAsync() {
            ExtensionProgressBar.Value = 0;
            ExtensionProgress.Visibility = Visibility.Visible;
            CancelButton.IsEnabled = false;
            try {
                await System.Windows.Threading.Dispatcher.Yield();
                var result = await this.InstallExtensionAsync(value => ExtensionProgressBar.Value = value);
                await System.Windows.Threading.Dispatcher.Yield();
                return result;
            } finally {
                ExtensionProgress.Visibility = Visibility.Collapsed;
                CancelButton.IsEnabled = true;
            }
        }

        private async Task<string> InstallExtensionAsync(Action<int> reportProgress) {
            try {
                using var extension = Assembly.GetExecutingAssembly().GetManifestResourceStream("UdkCli.VisualStudio.vsix")
                    ?? throw new InvalidDataException("The installer does not contain the UDK CLI extension.");
                var result = await VisualStudioIntegration.InstallAsync(extension, reportProgress);
                if (this.log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Info, "UdkCli.Setup", $"Visual Studio integration completed. {result.Trim()}");
                }
                return result;
            } catch (Exception exception) {
                if (this.log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Error, "UdkCli.Setup", exception.ToString());
                }
                throw;
            }
        }

        private void OnCancelClick(object sender, RoutedEventArgs args) {
            Close();
        }
    }
}