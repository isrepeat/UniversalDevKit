using System.Windows;
using System.Windows.Input;
using System.Windows.Controls;
using System.Windows.Threading;

namespace AndroidAppPreviewer {
    internal sealed class PreviewViewportController {
        private readonly ScrollViewer viewport;
        private readonly Func<double> getScale;
        private readonly Action<double> setScale;
        private readonly Action completed;
        private readonly DispatcherTimer zoomTimer;
        private bool isPanning;
        private Point panStart;
        private double panHorizontalOffset;
        private double panVerticalOffset;
        private DateTime zoomStartedAt;
        private double zoomStartScale;
        private double zoomTargetScale;
        private double zoomAnchorX;
        private double zoomAnchorY;
        private Point zoomViewportPoint;

        public PreviewViewportController(ScrollViewer viewport, Func<double> getScale, Action<double> setScale, Action completed) {
            this.viewport = viewport;
            this.getScale = getScale;
            this.setScale = setScale;
            this.completed = completed;
            this.zoomTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
            this.zoomTimer.Tick += this.ZoomTimerTick;
        }

        public void HandleMouseWheel(MouseWheelEventArgs eventArgs) {
            if (!Keyboard.IsKeyDown(Key.LeftCtrl) && !Keyboard.IsKeyDown(Key.RightCtrl)) { return; }
            var point = eventArgs.GetPosition(this.viewport);
            this.zoomStartScale = this.getScale();
            var steps = Math.Max(1, Math.Abs(eventArgs.Delta) / Mouse.MouseWheelDeltaForOneLine);
            var factor = Math.Pow(1.25, steps);
            this.zoomTargetScale = Math.Clamp(this.zoomStartScale * (eventArgs.Delta > 0 ? factor : 1.0 / factor), 0.1, 3.0);
            this.zoomAnchorX = (this.viewport.HorizontalOffset + point.X) / this.zoomStartScale;
            this.zoomAnchorY = (this.viewport.VerticalOffset + point.Y) / this.zoomStartScale;
            this.zoomViewportPoint = point;
            this.zoomStartedAt = DateTime.UtcNow;
            this.zoomTimer.Start();
            eventArgs.Handled = true;
        }

        public void HandleMouseDown(MouseButtonEventArgs eventArgs) {
            if ((Keyboard.Modifiers & ModifierKeys.Control) == 0) { return; }
            this.isPanning = true;
            this.panStart = eventArgs.GetPosition(this.viewport);
            this.panHorizontalOffset = this.viewport.HorizontalOffset;
            this.panVerticalOffset = this.viewport.VerticalOffset;
            this.viewport.Cursor = Cursors.Cross;
            this.viewport.CaptureMouse();
            eventArgs.Handled = true;
        }

        public void HandleMouseMove(MouseEventArgs eventArgs) {
            if (!this.isPanning) { return; }
            var point = eventArgs.GetPosition(this.viewport);
            this.viewport.ScrollToHorizontalOffset(this.panHorizontalOffset - point.X + this.panStart.X);
            this.viewport.ScrollToVerticalOffset(this.panVerticalOffset - point.Y + this.panStart.Y);
            eventArgs.Handled = true;
        }

        public void HandleMouseUp(MouseButtonEventArgs eventArgs) { if (this.isPanning) { this.StopPanning(); eventArgs.Handled = true; } }
        public void HandleLostMouseCapture() => this.StopPanning();
        public void HandleKeyUp(KeyEventArgs eventArgs) { if (eventArgs.Key is Key.LeftCtrl or Key.RightCtrl) { this.StopPanning(); } }

        private void ZoomTimerTick(object? sender, EventArgs eventArgs) {
            var progress = Math.Clamp((DateTime.UtcNow - this.zoomStartedAt).TotalMilliseconds / 120.0, 0.0, 1.0);
            var scale = this.zoomStartScale + (this.zoomTargetScale - this.zoomStartScale) * progress;
            this.setScale(scale);
            this.viewport.ScrollToHorizontalOffset(this.zoomAnchorX * scale - this.zoomViewportPoint.X);
            this.viewport.ScrollToVerticalOffset(this.zoomAnchorY * scale - this.zoomViewportPoint.Y);
            if (progress >= 1.0) { this.zoomTimer.Stop(); this.completed(); }
        }

        private void StopPanning() {
            if (!this.isPanning) { return; }
            this.isPanning = false;
            this.viewport.Cursor = null;
            this.viewport.ReleaseMouseCapture();
        }
    }
}