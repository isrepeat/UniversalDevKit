using System.Windows.Threading;

namespace AndroidAppPreviewer {
    internal sealed class PreviewController : IDisposable {
        private readonly PluginSessionController pluginSessionController;
        private readonly DispatcherTimer renderTimer;
        private readonly DispatcherTimer animationTimer;
        private bool isDisposed;

        public event Action? RenderRequested;
        public event Action<NativePreviewSession>? FrameUpdated;
        public event Action<Exception>? Failed;

        public PreviewController(Dispatcher dispatcher, PluginSessionController pluginSessionController) {
            this.pluginSessionController = pluginSessionController;
            this.renderTimer = new DispatcherTimer(DispatcherPriority.Normal, dispatcher) {
                Interval = TimeSpan.FromMilliseconds(250),
            };
            this.renderTimer.Tick += this.RenderTimerTick;
            this.animationTimer = new DispatcherTimer(DispatcherPriority.Normal, dispatcher) {
                Interval = TimeSpan.FromMilliseconds(16),
            };
            this.animationTimer.Tick += this.AnimationTimerTick;
        }

        public NativePreviewSession? Session => this.pluginSessionController.Session;

        public (NativePreviewSession Session, bool IsNew) EnsureSession(
            int width,
            int height) {
            var session = this.Session;
            if (session is not null && session.Width == width && session.Height == height) {
                return (session, false);
            }
            this.StopAnimation();
            return (this.pluginSessionController.CreateSession(width, height), true);
        }

        public void ScheduleRender() {
            if (this.isDisposed) {
                return;
            }
            this.renderTimer.Stop();
            this.renderTimer.Start();
        }

        public void StartAnimation() {
            if (!this.isDisposed) {
                this.animationTimer.Start();
            }
        }

        public void StopAnimation() {
            this.animationTimer.Stop();
        }

        public void Reset() {
            this.StopAnimation();
            this.pluginSessionController.Reset();
        }

        public void Dispose() {
            if (this.isDisposed) {
                return;
            }
            this.isDisposed = true;
            this.renderTimer.Stop();
            this.animationTimer.Stop();
            this.pluginSessionController.Dispose();
        }

        private void RenderTimerTick(object? sender, EventArgs eventArgs) {
            this.renderTimer.Stop();
            this.RenderRequested?.Invoke();
        }

        private void AnimationTimerTick(object? sender, EventArgs eventArgs) {
            try {
                var session = this.Session;
                if (session is null) {
                    return;
                }
                session.UpdateAndRender();
                this.FrameUpdated?.Invoke(session);
            } catch (Exception exception) {
                this.Failed?.Invoke(exception);
            }
        }
    }
}