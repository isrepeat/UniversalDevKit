using System;
using System.Windows;
using System.Threading.Tasks;
using System.ComponentModel;

namespace UniversalDevKit.UdkCli.Setup {
    public partial class UninstallWindow : Window {
        private readonly SetupLog log;
        private bool isUninstalling;

        internal UninstallWindow(SetupLog log) {
            this.log = log;
            InitializeComponent();
        }

        public bool RemoveVersionCache => RemoveVersionCacheCheckBox.IsChecked == true;

        protected override void OnClosing(CancelEventArgs args) {
            base.OnClosing(args);
            if (this.isUninstalling) {
                args.Cancel = true;
            }
        }

        private async void OnUninstallClick(object sender, RoutedEventArgs args) {
            if (this.isUninstalling) {
                return;
            }
            var removeVersionCache = this.RemoveVersionCache;
            this.isUninstalling = true;
            UninstallButton.IsEnabled = false;
            CancelButton.IsEnabled = false;
            RemoveVersionCacheCheckBox.IsEnabled = false;
            StatusText.Text = "Preparing to remove UDK CLI…";
            StatusText.Visibility = Visibility.Visible;
            UninstallProgress.Visibility = Visibility.Visible;
            var progress = new Progress<string>(status => {
                StatusText.Text = status;
                if (this.log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Info, "UdkCli.Setup", status);
                }
            });
            try {
                await Task.Run(() => Installation.Uninstall(removeVersionCache, progress));
                StatusText.Text = "UDK CLI was removed.";
                UninstallProgress.Visibility = Visibility.Collapsed;
                if (this.log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Info, "UdkCli.Setup", "UDK CLI removed.");
                }
                MessageBox.Show(this, StatusText.Text, Title, MessageBoxButton.OK, MessageBoxImage.Information);
                this.isUninstalling = false;
                Close();
            } catch (Exception exception) {
                StatusText.Text = "Uninstall failed. You can retry after resolving the error.";
                if (this.log.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Error, "UdkCli.Setup", exception.ToString());
                }
                MessageBox.Show(this, exception.Message + this.log.Location, Title, MessageBoxButton.OK, MessageBoxImage.Error);
            } finally {
                this.isUninstalling = false;
                UninstallProgress.Visibility = Visibility.Collapsed;
                UninstallButton.IsEnabled = true;
                CancelButton.IsEnabled = true;
                RemoveVersionCacheCheckBox.IsEnabled = true;
            }
        }
    }
}