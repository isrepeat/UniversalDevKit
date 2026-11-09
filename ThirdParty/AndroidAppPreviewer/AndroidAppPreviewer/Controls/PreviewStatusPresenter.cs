using System.Windows.Controls;

using PreviewRenderer = AndroidAppPreviewer.PreviewBrushes;

namespace AndroidAppPreviewer {
    internal sealed class PreviewStatusPresenter {
        private readonly TextBlock statusText;

        public PreviewStatusPresenter(TextBlock statusText) {
            this.statusText = statusText;
        }

        public void Information(string message) => this.Set(message, "#D5BD7D");

        public void Success(string message) => this.Set(message, "#8FD18B");

        public void Error(string message) => this.Set(message, "#FF8A80");

        private void Set(string message, string color) {
            this.statusText.Foreground = PreviewRenderer.ParseBrush(color);
            this.statusText.Text = message;
        }
    }
}