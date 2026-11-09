using System.Windows;

namespace AndroidAppPreviewer {
    public partial class ExternalMarkupConflictDialog : Window {
        public ExternalMarkupConflictDialog(string markupPath) {
            InitializeComponent();
            WindowTheme.EnableDarkTitleBar(this);
            this.MarkupPathText.Text = markupPath;
            this.Loaded += this.DialogLoaded;
        }

        private void DialogLoaded(object sender, RoutedEventArgs eventArgs) {
            this.CancelButton.Focus();
        }

        private void OverwriteButtonClick(object sender, RoutedEventArgs eventArgs) {
            this.DialogResult = true;
        }
    }
}