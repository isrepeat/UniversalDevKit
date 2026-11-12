using System.Windows;

namespace UniversalDevKit.UdkCli.Setup {
    public partial class UninstallWindow : Window {
        public UninstallWindow() {
            InitializeComponent();
        }

        public bool RemoveVersionCache => RemoveVersionCacheCheckBox.IsChecked == true;

        private void OnUninstallClick(object sender, RoutedEventArgs args) {
            DialogResult = true;
        }
    }
}