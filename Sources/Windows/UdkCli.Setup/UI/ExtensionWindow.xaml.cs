using System;
using System.Windows;
using System.Threading.Tasks;
using System.ComponentModel;

namespace UniversalDevKit.UdkCli.Setup {
    public partial class ExtensionWindow : Window {
        private readonly Func<Task<string>> installExtensionAsync;
        private readonly string logLocation;
        private bool installing;

        internal ExtensionWindow(string status, string error, string logLocation, Func<Task<string>> installExtensionAsync) {
            this.installExtensionAsync = installExtensionAsync;
            this.logLocation = logLocation;
            InitializeComponent();
            StatusText.Text = status;
            DetailsText.Text = $"Installation failed. {error}{this.logLocation}";
        }

        protected override void OnClosing(CancelEventArgs args) {
            base.OnClosing(args);
            if (this.installing) {
                args.Cancel = true;
            }
        }

        private async void OnInstallExtensionClick(object sender, RoutedEventArgs args) {
            this.installing = true;
            InstallExtensionButton.IsEnabled = false;
            SkipButton.IsEnabled = false;
            DetailsText.Text = "Installing the Visual Studio extension…";
            string result;
            try {
                result = await this.installExtensionAsync();
            } catch (Exception exception) {
                DetailsText.Text = $"Installation failed. {exception.Message}{this.logLocation}";
                return;
            } finally {
                this.installing = false;
                InstallExtensionButton.IsEnabled = true;
                SkipButton.IsEnabled = true;
            }

            MessageBox.Show(this, StatusText.Text + result, Title, MessageBoxButton.OK, MessageBoxImage.Information);
            DialogResult = true;
        }
    }
}