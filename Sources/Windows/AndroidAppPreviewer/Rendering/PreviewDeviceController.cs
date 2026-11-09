using System.Windows;
using System.Windows.Controls;

namespace AndroidAppPreviewer {
    internal sealed class PreviewDeviceController {
        public (int Width, int Height) GetSize(PreviewerSettings settings) {
            var width = Math.Max(1, settings.PreviewWidth);
            var height = Math.Max(1, settings.PreviewHeight);
            return settings.IsPreviewLandscape ? (height, width) : (width, height);
        }

        public double GetScale(PreviewerSettings settings) {
            return Math.Clamp(settings.PreviewScale > 0.0 ? settings.PreviewScale : 0.5, 0.1, 3.0);
        }

        public void Apply(PreviewerSettings settings, FrameworkElement deviceSurface, FrameworkElement previewViewbox, TextBlock zoomText) {
            var size = this.GetSize(settings);
            var scale = this.GetScale(settings);
            deviceSurface.Width = size.Width;
            deviceSurface.Height = size.Height;
            previewViewbox.Width = size.Width * scale;
            previewViewbox.Height = size.Height * scale;
            zoomText.Text = $"{scale:P0}";
        }

        public void SetScale(PreviewerSettings settings, double scale, FrameworkElement deviceSurface, FrameworkElement previewViewbox, TextBlock zoomText) {
            settings.PreviewScale = Math.Clamp(scale, 0.1, 3.0);
            this.Apply(settings, deviceSurface, previewViewbox, zoomText);
        }

        public bool Fit(PreviewerSettings settings, ScrollViewer viewport, FrameworkElement deviceSurface, FrameworkElement previewViewbox, TextBlock zoomText) {
            var size = this.GetSize(settings);
            if (viewport.ViewportWidth > 0.0 && viewport.ViewportHeight > 0.0) {
                this.SetScale(settings, Math.Min(viewport.ViewportWidth / size.Width, viewport.ViewportHeight / size.Height), deviceSurface, previewViewbox, zoomText);
                return true;
            }
            return false;
        }

        public void UpdateOrientation(PreviewerSettings settings, TextBlock portraitText, TextBlock landscapeText) {
            portraitText.Foreground = PreviewBrushes.Parse(settings.IsPreviewLandscape ? "#E6E6E6" : "#D5BD7D");
            landscapeText.Foreground = PreviewBrushes.Parse(settings.IsPreviewLandscape ? "#D5BD7D" : "#E6E6E6");
        }
    }
}