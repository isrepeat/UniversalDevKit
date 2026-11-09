using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Controls;
using System.Windows.Threading;
using System.Diagnostics;

using ICSharpCode.AvalonEdit;

namespace AndroidAppPreviewer {
    internal sealed class EditorScrollController : IDisposable {
        private readonly DispatcherTimer timer;
        private readonly Func<PreviewerSettings> getSettings;
        private readonly Action<int> zoomEditor;
        private readonly Dictionary<TextEditor, SmoothScrollState> states = [];

        private enum SmoothingMode { None, Linear, Smoothstep, Smootherstep, EaseOutCubic, Exponential }

        private sealed class SmoothScrollState {
            public required ScrollViewer ScrollViewer { get; init; }
            public double StartVerticalOffset { get; set; }
            public double TargetVerticalOffset { get; set; }
            public double LastAppliedVerticalOffset { get; set; }
            public long AnimationStartedAt { get; set; }
            public TimeSpan AnimationDuration { get; set; }
            public SmoothingMode SmoothingMode { get; set; }
            public bool IsAnimating { get; set; }
        }

        public EditorScrollController(Func<PreviewerSettings> getSettings, Action<int> zoomEditor) {
            this.getSettings = getSettings;
            this.zoomEditor = zoomEditor;
            this.timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
            this.timer.Tick += this.TimerTick;
        }

        public void Configure(params TextEditor[] editors) {
            this.states.Clear();
            foreach (var editor in editors) {
                editor.PreviewMouseWheel -= this.EditorPreviewMouseWheel;
                editor.PreviewMouseWheel += this.EditorPreviewMouseWheel;
            }
        }

        public void Dispose() => this.timer.Stop();

        private void EditorPreviewMouseWheel(object sender, MouseWheelEventArgs eventArgs) {
            if (sender is not TextEditor editor || FindVisualChild<ScrollViewer>(editor) is not { } scrollViewer) {
                return;
            }
            var steps = Math.Max(1, Math.Abs(eventArgs.Delta) / Mouse.MouseWheelDeltaForOneLine);
            if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) {
                this.zoomEditor(eventArgs.Delta > 0 ? steps : -steps);
                eventArgs.Handled = true;
                return;
            }
            var settings = this.getSettings();
            if (settings.MouseWheelLines <= 0) {
                return;
            }
            if (!this.states.TryGetValue(editor, out var state)) {
                state = new SmoothScrollState { ScrollViewer = scrollViewer };
                this.states.Add(editor, state);
            }
            // WPF применяет ScrollToVerticalOffset не синхронно с mouse-wheel
            // событием. Пока анимация идёт, берём собственную последнюю позицию,
            // иначе очередной wheel может прочитать старый VerticalOffset и
            // случайно сбросить накопленную цель прокрутки.
            var currentOffset = state.IsAnimating
                ? state.LastAppliedVerticalOffset
                : scrollViewer.VerticalOffset;
            if (!state.IsAnimating && Math.Abs(currentOffset - state.LastAppliedVerticalOffset) > 0.5) {
                state.TargetVerticalOffset = currentOffset;
            }
            var offset = steps * settings.MouseWheelLines * editor.TextArea.TextView.DefaultLineHeight;
            state.StartVerticalOffset = currentOffset;
            var targetOffset = state.IsAnimating ? state.TargetVerticalOffset : currentOffset;
            state.TargetVerticalOffset = Math.Clamp(targetOffset + (eventArgs.Delta > 0 ? -offset : offset), 0, scrollViewer.ScrollableHeight);
            state.LastAppliedVerticalOffset = currentOffset;
            state.AnimationStartedAt = Stopwatch.GetTimestamp();
            state.AnimationDuration = TimeSpan.FromMilliseconds(Math.Clamp(settings.MouseWheelAnimationDurationMilliseconds, 50.0, 5000.0));
            state.SmoothingMode = GetSmoothingMode(settings.MouseWheelSmoothingMode);
            if (state.SmoothingMode == SmoothingMode.None) {
                scrollViewer.ScrollToVerticalOffset(state.TargetVerticalOffset);
                state.LastAppliedVerticalOffset = state.TargetVerticalOffset;
                state.IsAnimating = false;
                eventArgs.Handled = true;
                return;
            }
            state.IsAnimating = Math.Abs(state.TargetVerticalOffset - currentOffset) > 0.5;
            this.timer.Start();
            eventArgs.Handled = true;
        }

        private void TimerTick(object? sender, EventArgs eventArgs) {
            var hasAnimations = false;
            foreach (var state in this.states.Values) {
                if (!state.IsAnimating) {
                    continue;
                }
                var elapsed = TimeSpan.FromSeconds((Stopwatch.GetTimestamp() - state.AnimationStartedAt) / (double)Stopwatch.Frequency);
                var progress = Math.Clamp(elapsed.TotalMilliseconds / state.AnimationDuration.TotalMilliseconds, 0, 1);
                state.LastAppliedVerticalOffset = state.StartVerticalOffset + (state.TargetVerticalOffset - state.StartVerticalOffset) * Interpolate(state.SmoothingMode, progress);
                state.ScrollViewer.ScrollToVerticalOffset(state.LastAppliedVerticalOffset);
                state.IsAnimating = progress < 1;
                if (!state.IsAnimating) {
                    state.ScrollViewer.ScrollToVerticalOffset(state.TargetVerticalOffset);
                    state.LastAppliedVerticalOffset = state.TargetVerticalOffset;
                }
                hasAnimations |= state.IsAnimating;
            }
            if (!hasAnimations) {
                this.timer.Stop();
            }
        }

        private static SmoothingMode GetSmoothingMode(string value) => Enum.TryParse<SmoothingMode>(value, true, out var result) ? result : SmoothingMode.Exponential;

        private static double Interpolate(SmoothingMode mode, double progress) => mode switch {
            SmoothingMode.Linear => progress,
            SmoothingMode.Smootherstep => progress * progress * progress * (progress * (progress * 6 - 15) + 10),
            SmoothingMode.EaseOutCubic => 1 - Math.Pow(1 - progress, 3),
            SmoothingMode.Exponential => (1 - Math.Exp(-6 * progress)) / (1 - Math.Exp(-6)),
            _ => progress * progress * (3 - 2 * progress),
        };

        private static T? FindVisualChild<T>(DependencyObject element) where T : DependencyObject {
            for (var index = 0; index < VisualTreeHelper.GetChildrenCount(element); ++index) {
                var child = VisualTreeHelper.GetChild(element, index);
                if (child is T result) {
                    return result;
                }
                if (FindVisualChild<T>(child) is { } nestedResult) {
                    return nestedResult;
                }
            }
            return null;
        }
    }
}