using System;
using System.Windows;
using System.Threading.Tasks;
using System.ComponentModel;

namespace UniversalDevKit.UdkCli.Setup {
    public partial class ExtensionWindow : Window {
        private readonly Func<Action<int>, Task<string>> installExtensionAsync;
        private readonly string logLocation;
        private bool installing;

        internal ExtensionWindow(string status, string error, string logLocation, Func<Action<int>, Task<string>> installExtensionAsync) {
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
            if (this.installing) {
                return;
            }
            this.installing = true;
            InstallExtensionButton.IsEnabled = false;
            SkipButton.IsEnabled = false;
            DetailsText.Text = "Installing the Visual Studio extension…";
            ExtensionProgressBar.Value = 0;
            ExtensionProgress.Visibility = Visibility.Visible;
            string result;
            try {
                await System.Windows.Threading.Dispatcher.Yield();
                result = await this.installExtensionAsync(value => ExtensionProgressBar.Value = value);
                await System.Windows.Threading.Dispatcher.Yield();
            } catch (Exception exception) {
                DetailsText.Text = $"Installation failed. {exception.Message}{this.logLocation}";
                ExtensionProgress.Visibility = Visibility.Collapsed;
                this.installing = false;
                InstallExtensionButton.IsEnabled = true;
                SkipButton.IsEnabled = true;
                return;
            }

            MessageBox.Show(this, StatusText.Text + result, Title, MessageBoxButton.OK, MessageBoxImage.Information);
            this.installing = false;
            DialogResult = true;
        }
    }
}