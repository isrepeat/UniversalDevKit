using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Controls;

namespace AndroidAppPreviewer {
    internal sealed record PreviewRoute(
        string Id,
        string Source,
        string Target,
        string Title,
        bool IsDefault,
        string TargetKind,
        string BackwardOfTransitionId,
        string DataType,
        JsonElement HasPreviewDefaultNavigationState);

    internal sealed record PreviewNavigationGraph(
        string CurrentPageId,
        string LayoutRootPageId,
        IReadOnlyDictionary<string, string> PageTitles,
        IReadOnlyList<PreviewRoute> Routes);

    // Native application mode. It is intentionally separate from editable-XAML mode:
    // WPF hosts the image and input only; the loaded plugin owns the runtime tree.
    internal sealed class NativePreviewSession : IDisposable {
        private readonly AnglePreviewRenderer renderer;
        private readonly PreviewCursorSet cursorSet;
        private readonly Image image;
        private IntPtr session;
        private string? loadedPage;
        private readonly Dictionary<string, string> scenarios = [];
        private readonly Dictionary<string, string> markups = [];
        private bool hasPointerCapture;
        private bool isElementInspectionEnabled;
        private bool useDefaultCursorForElementInspection;

        public event Action<AndroidAppPreviewerPluginSDK.NativeInspectionResult>? ElementSelected;
        public event Action? RuntimeMarkupReloaded;
        public event Action? InteractionCompleted;

        public NativePreviewSession(string resourcesDirectory, int width, int height) {
            this.renderer = new AnglePreviewRenderer(resourcesDirectory, width, height);
            this.cursorSet = new PreviewCursorSet();
            this.session = AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Interaction.xp_create_session(width, height);
            try {
                AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(this.session != IntPtr.Zero);
                this.image = new Image {
                    Width = width,
                    Height = height,
                    Stretch = Stretch.Fill
                };
                this.image.MouseLeftButtonDown += this.ImageMouseLeftButtonDown;
                this.image.MouseLeftButtonUp += this.ImageMouseLeftButtonUp;
                this.image.MouseMove += this.ImageMouseMove;
                this.image.MouseLeave += this.ImageMouseLeave;
            }
            catch {
                if (this.session != IntPtr.Zero) {
                    AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Interaction.xp_destroy_session(this.session);
                    this.session = IntPtr.Zero;
                }
                this.renderer.Dispose();
                throw;
            }
        }

        public int Height => this.renderer.Height;
        public string InitialPage => this.GetInitialPage();
        public FrameworkElement Surface => this.image;
        public int Width => this.renderer.Width;

        public void LoadPage(string page) {
            if (this.loadedPage == page
                && string.Equals(this.GetCurrentPage(), page, StringComparison.Ordinal)) {
                return;
            }
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_load_page(this.session, page) != 0);
            this.loadedPage = page;

            this.Render();
        }

        public string CurrentPage => this.GetCurrentPage();

        public bool IsTransitioning => AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_is_transitioning(this.session) != 0;

        public PreviewNavigationGraph NavigationGraph => this.GetNavigationGraph();

        public void NavigatePreviewRoute(string target) {
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_navigate_preview_route(this.session, target) != 0);
            this.loadedPage = this.GetCurrentPage();
            this.Render();
        }

        public void NavigatePreviewRoute(IReadOnlyList<string> path) {
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(path.Count > 0);
            var request = JsonSerializer.Serialize(new { transitionIds = path });
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Metadata.xp_navigate(this.session, request) != 0);
            this.loadedPage = this.GetCurrentPage();
            this.Render();
        }

        public void LoadRuntimeMarkup(string page, string markup, string sourcePath) {
            if (this.markups.TryGetValue(sourcePath, out var previous) && previous == markup) {
                return;
            }
            App.LogNativeOperation($"Reload markup begins: page='{page}', source='{sourcePath}'.");
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_reload_markup(this.session, page, markup, sourcePath) != 0);
            App.LogNativeOperation($"Reload markup completed: page='{page}', source='{sourcePath}'.");
            if (Path.GetFileNameWithoutExtension(sourcePath) == page) {
                this.markups.Clear();
            }
            this.markups[sourcePath] = markup;
            this.Render();
            this.RuntimeMarkupReloaded?.Invoke();
        }

        public void SetAnimationPlaybackRate(double value) {
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_set_animation_playback_rate(this.session, (float)value) != 0);
        }

        public void SetElementInspectionEnabled(bool value, bool useDefaultCursor) {
            this.isElementInspectionEnabled = value;
            this.useDefaultCursorForElementInspection = value && useDefaultCursor;
            this.image.Cursor = this.useDefaultCursorForElementInspection ? Cursors.Arrow : null;
            if (!value) {
                AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_clear_inspection_wireframe(this.session) != 0);
                // Закреплённая голубая рамка принадлежит режиму выбора так же, как
                // временная рамка наведения, поэтому при выходе очищаем обе.
                AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_clear_selected_inspection_element(this.session) != 0);
                this.Render();
            }
        }

        public void SetElementInspectionWireframes(
            ElementInspectionWireframeSettings hovered,
            ElementInspectionWireframeSettings active,
            bool renderMargin,
            bool renderPadding) {
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_set_inspection_wireframe(
                this.session,
                (float)hovered.LineThickness,
                hovered.LineStyle == "solid" ? 0 : 1,
                ParseColor(hovered.LineColor),
                renderMargin ? ParseColor(hovered.MarginColor) : default,
                renderPadding ? ParseColor(hovered.PaddingColor) : default) != 0);
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_set_selected_wireframe(
                this.session,
                (float)active.LineThickness,
                active.LineStyle == "solid" ? 0 : 1,
                ParseColor(active.LineColor),
                renderMargin ? ParseColor(active.MarginColor) : default,
                renderPadding ? ParseColor(active.PaddingColor) : default) != 0);
            this.Render();
        }

        public bool SelectElementInspection(string sourcePath, int line, int column) {
            var isSelected = AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_select_inspection_element(this.session, sourcePath, line, column) != 0;
            if (isSelected) {
                this.Render();
            }
            return isSelected;
        }

        public void ApplyPreviewScenario(string page, string json) {
            if (this.scenarios.TryGetValue(page, out var previous) && previous == json) {
                return;
            }
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_apply_preview_scenario(this.session, page, json) != 0);
            this.scenarios[page] = json;
            this.Render();
        }
        public bool CanSavePreviewState() {
            return AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_can_save_preview_state(this.session) != 0;
        }

        public void SavePreviewState() {
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_export_preview_state(this.session) != 0);
        }

        public void UpdateAndRender() {
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_update(this.session) != 0);
            this.loadedPage = this.GetCurrentPage();
            this.Render();
        }

        public void Dispose() {
            this.image.MouseLeftButtonDown -= this.ImageMouseLeftButtonDown;
            this.image.MouseLeftButtonUp -= this.ImageMouseLeftButtonUp;
            this.image.MouseMove -= this.ImageMouseMove;
            this.image.MouseLeave -= this.ImageMouseLeave;
            if (this.hasPointerCapture) {
                this.image.ReleaseMouseCapture();
                this.hasPointerCapture = false;
            }
            if (this.session != IntPtr.Zero) {
                AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Interaction.xp_destroy_session(this.session);
                this.session = IntPtr.Zero;
            }

            this.cursorSet.Dispose();
            this.renderer.Dispose();
        }

        private void ImageMouseLeftButtonDown(object sender, MouseButtonEventArgs eventArgs) {
            var point = eventArgs.GetPosition(this.image);
            if (this.isElementInspectionEnabled) {
                if (this.TryInspect(point, out var inspection)) {
                    AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_pin_inspection_element(this.session) != 0);
                    this.Render();
                    this.ElementSelected?.Invoke(inspection);
                }
                eventArgs.Handled = true;
                return;
            }
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_pointer_down(
                this.session,
                this.ScaleX(point.X),
                this.ScaleY(point.Y)) != 0);
            this.hasPointerCapture = this.image.CaptureMouse();
            this.SetCursor(this.CursorKind(point) switch {
                PreviewCursorKind.Tap => this.cursorSet.TapPressed,
                PreviewCursorKind.Grab => this.cursorSet.Grabbing,
                _ => null,
            });
            this.UpdateAndRender();
            eventArgs.Handled = true;
        }

        private void ImageMouseLeftButtonUp(object sender, MouseButtonEventArgs eventArgs) {
            if (!this.hasPointerCapture) {
                return;
            }
            var point = eventArgs.GetPosition(this.image);
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_pointer_up(
                this.session,
                this.ScaleX(point.X),
                this.ScaleY(point.Y)) != 0);
            this.image.ReleaseMouseCapture();
            this.hasPointerCapture = false;
            this.SetCursor(this.CursorKind(point));
            this.UpdateAndRender();
            this.InteractionCompleted?.Invoke();
            eventArgs.Handled = true;
        }

        private void ImageMouseMove(object sender, MouseEventArgs eventArgs) {
            var point = eventArgs.GetPosition(this.image);
            if (this.isElementInspectionEnabled) {
                if (this.useDefaultCursorForElementInspection) {
                    this.image.Cursor = Cursors.Arrow;
                }
                this.TryInspect(point, out _);
                return;
            }
            if (!this.hasPointerCapture) {
                this.SetCursor(this.CursorKind(point));
                return;
            }
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_pointer_move(
                this.session,
                this.ScaleX(point.X),
                this.ScaleY(point.Y)) != 0);
            this.UpdateAndRender();
        }

        private void ImageMouseLeave(object sender, MouseEventArgs eventArgs) {
            this.image.Cursor = null;
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_clear_inspection_wireframe(this.session) != 0);
            this.Render();
        }

        private bool TryInspect(Point point, out AndroidAppPreviewerPluginSDK.NativeInspectionResult result) {
            if (this.image.ActualWidth <= 0.0 || this.image.ActualHeight <= 0.0) {
                result = default;
                return false;
            }
            var isInspected = AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_inspect(this.session, this.ScaleX(point.X), this.ScaleY(point.Y), out result) != 0;
            this.Render();
            return isInspected;
        }

        private string GetCurrentPage() {
            return AndroidAppPreviewerPluginSDK.NativeRuntime.Session.GetSessionCurrentPage(this.session);
        }

        private string GetInitialPage() {
            return AndroidAppPreviewerPluginSDK.NativeRuntime.Metadata.GetInitialPageId(this.session);
        }

        private PreviewNavigationGraph GetNavigationGraph() {
            using var document = JsonDocument.Parse(AndroidAppPreviewerPluginSDK.NativeRuntime.Metadata.GetNavigationGraph(this.session));
            var root = document.RootElement;
            var titles = root.GetProperty("pages")
                .EnumerateArray()
                .ToDictionary(
                    page => page.GetProperty("id").GetString() ?? throw new InvalidDataException("Page id is required."),
                    page => page.GetProperty("title").GetString() ?? throw new InvalidDataException("Page title is required."),
                    StringComparer.Ordinal);
            var routes = root.GetProperty("transitions")
                .EnumerateArray()
                .Select(transition => new PreviewRoute(
                    transition.GetProperty("id").GetString() ?? throw new InvalidDataException("Transition id is required."),
                    transition.GetProperty("sourcePageId").GetString() ?? throw new InvalidDataException("Transition sourcePageId is required."),
                    transition.GetProperty("targetPageId").GetString() ?? throw new InvalidDataException("Transition targetPageId is required."),
                    transition.GetProperty("title").GetString() ?? throw new InvalidDataException("Transition title is required."),
                    transition.GetProperty("isDefault").GetBoolean(),
                    transition.GetProperty("targetKind").GetString() ?? "page",
                    transition.TryGetProperty("backwardOfTransitionId", out var backwardOfTransitionId)
                        ? backwardOfTransitionId.GetString() ?? ""
                        : "",
                    transition.GetProperty("dataType").GetString() ?? "",
                    transition.GetProperty("hasPreviewDefaultNavigationState").Clone()))
                .ToArray();
            return new PreviewNavigationGraph(
                root.GetProperty("currentPageId").GetString() ?? throw new InvalidDataException("Current page is required."),
                root.GetProperty("layoutRootPageId").GetString() ?? throw new InvalidDataException("Layout root is required."),
                titles,
                routes);
        }

        private void Render() {
            this.image.Source = this.renderer.RenderNativeSession(this.session);
        }

        private static AndroidAppPreviewerPluginSDK.NativeColor ParseColor(string color) {
            if (ColorConverter.ConvertFromString(color) is not Color parsedColor) {
                throw new InvalidOperationException("Не удалось разобрать цвет подсветки элемента.");
            }
            return new AndroidAppPreviewerPluginSDK.NativeColor {
                Red = parsedColor.R / 255.0f,
                Green = parsedColor.G / 255.0f,
                Blue = parsedColor.B / 255.0f,
                Alpha = parsedColor.A / 255.0f,
            };
        }

        private float ScaleX(double value) {
            return (float)(value / this.image.ActualWidth * this.renderer.Width);
        }

        private float ScaleY(double value) {
            return (float)(value / this.image.ActualHeight * this.renderer.Height);
        }

        private PreviewCursorKind CursorKind(Point point) {
            if (this.image.ActualWidth <= 0.0 || this.image.ActualHeight <= 0.0) {
                return PreviewCursorKind.None;
            }
            return (PreviewCursorKind)AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_cursor_kind(
                this.session,
                this.ScaleX(point.X),
                this.ScaleY(point.Y));
        }

        private void SetCursor(PreviewCursorKind kind) {
            this.SetCursor(kind switch {
                PreviewCursorKind.Tap => this.cursorSet.Tap,
                PreviewCursorKind.Grab => this.cursorSet.Grab,
                _ => null,
            });
        }

        private void SetCursor(Cursor? cursor) {
            this.image.Cursor = cursor;
        }

        private enum PreviewCursorKind {
            None,
            Tap,
            Grab,
        }
    }
}