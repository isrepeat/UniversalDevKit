using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Threading;
using System.Reflection;
using System.Diagnostics;

using ICSharpCode.AvalonEdit;
using ICSharpCode.AvalonEdit.Search;
using ICSharpCode.AvalonEdit.Highlighting;

using PreviewRenderer = AndroidAppPreviewer.PreviewBrushes;

namespace AndroidAppPreviewer {
    /// <summary>
    /// Координирует UI превьювера: режимы AvalonEdit, сохранённое состояние сессии,
    /// наблюдение за внешними файлами и жизненный цикл нативной сессии рендеринга.
    /// WPF редактирует файлы и показывает кадры; дерево, ввод и отрисовка принадлежат native ApplicationSession.
    /// </summary>
    public partial class MainWindow : Window {
        private sealed class MarkupNavigationTarget {
            public required string Name { get; init; }
            public required string Path { get; init; }

            public override string ToString() {
                return this.Name;
            }
        }

        private const string NoScenarioName = "Storage";
        private const double SearchPanelOverlayHeight = 84.0;
        private readonly WorkspaceController workspaceController;
        private readonly EditorScrollController editorScrollController;
        private readonly PreviewStatusPresenter statusPresenter;
        private readonly MarkupEditorController markupEditorController;
        private readonly DocumentEditorController documentEditorController;
        private readonly ScenarioController scenarioController;
        private readonly SettingsController settingsController;
        private readonly SearchPanel markupSearchPanel;
        private readonly XamlCompletionController xamlCompletionController;
        private readonly FolderPickerController folderPickerController;
        private readonly PreviewViewportController previewViewportController;
        private readonly NavigationGraphController navigationGraphController;
        private readonly PluginSessionController pluginSessionController;
        private readonly PreviewController previewController;
        private readonly PreviewDeviceController previewDeviceController;
        private readonly WindowLayoutController windowLayoutController;
        private readonly DispatcherTimer windowSizePersistenceTimer;
        private readonly Grid previewLayer = new();
        private bool updatingPreviewControls;
        private bool updatingScenarioPicker;
        private bool updatingControlPicker;
        private bool selectingPageFromNative;
        private bool settingsPersistenceReady;
        private IReadOnlyList<string>? pendingPreviewRoute;
        private string? deferredNavigationEditorPage;
        private bool isClosing;
        private PreviewerSettings settings => this.settingsController.Value;
        private bool isSettingsDirty;
        private bool isScenarioDirty => this.scenarioController.IsDirty;
        private bool updatingElementSelection;
        private bool updatingEditors;
        private bool suppressFoldingStatePersistence;
        private EditorMode editorMode;
        private string? scenarioPath => this.scenarioController.Path;
        private string? scenarioFileText => this.scenarioController.PersistedText;
        private string? activeScenarioPath;
        private string? activeScenarioName;

        private bool IsNativePluginAvailable => this.pluginSessionController.IsAvailable;
        private bool IsPluginSelectionLocked => Array.Exists(
            Environment.GetCommandLineArgs(),
            argument => string.Equals(argument, "--plugin", StringComparison.OrdinalIgnoreCase));
        private NativePreviewSession? nativeApplicationSession => this.previewController.Session;
        private bool isMarkupDirty => this.documentEditorController.IsDirty;
        private string? markupPath => this.documentEditorController.Path;

        private enum EditorMode {
            Xaml,
            Scenario,
            Settings,
        }

        private sealed class AnimationSpeed {
            public required string Name { get; init; }
            public required double Rate { get; init; }

            public override string ToString() {
                return this.Name;
            }
        }

        public MainWindow() {
            InitializeComponent();
            this.statusPresenter = new PreviewStatusPresenter(this.StatusText);
            this.navigationGraphController = new NavigationGraphController(
                this.NavigationGraphControl,
                this.statusPresenter.Information);
            this.pluginSessionController = new PluginSessionController();
            this.previewController = new PreviewController(this.Dispatcher, this.pluginSessionController);
            this.previewDeviceController = new PreviewDeviceController();
            this.windowSizePersistenceTimer = new DispatcherTimer {
                Interval = TimeSpan.FromMilliseconds(300),
            };
            this.windowSizePersistenceTimer.Tick += this.WindowSizePersistenceTimerTick;
            this.windowLayoutController = new WindowLayoutController(this.EditorColumn, this.WorkspaceColumn);
            this.previewController.RenderRequested += () => this.ShowNativeApplicationPreview();
            this.previewController.FrameUpdated += this.PreviewFrameUpdated;
            this.previewController.Failed += this.ShowPreviewError;
            this.navigationGraphController.ActivePageChanged += this.NavigationGraphActivePageChanged;
            this.navigationGraphController.RouteConfirmed += this.NavigationGraphRouteConfirmed;
            this.DeviceSurface.Child = this.previewLayer;
            WindowTheme.EnableDarkTitleBar(this);
            this.markupSearchPanel = MainWindow.ConfigureEditor(this.MarkupEditor, MarkupSyntaxHighlighter.Create());
            MainWindow.ConfigureEditor(this.SettingsEditor, MarkupSyntaxHighlighter.CreateJson());
            MainWindow.ConfigureEditor(this.ScenarioEditor, MarkupSyntaxHighlighter.CreateJson());
            this.markupSearchPanel.IsVisibleChanged += this.MarkupSearchPanelLayoutChanged;
            this.markupEditorController = new MarkupEditorController(this.MarkupEditor);
            this.documentEditorController = new DocumentEditorController();
            this.scenarioController = new ScenarioController();
            this.settingsController = new SettingsController();
            this.markupEditorController.FoldingStateChanged += this.MarkupEditorFoldingStateChanged;
            this.MarkupEditor.TextArea.Caret.PositionChanged += this.MarkupEditorCaretPositionChanged;
            this.xamlCompletionController = new XamlCompletionController(this.MarkupEditor);
            this.folderPickerController = new FolderPickerController(
                this.FolderPickerPanel,
                this.FolderPickerPathText,
                this.FolderPickerErrorText,
                this.FolderPickerEntries,
                this.SelectFolderButton,
                this.FolderPickerBackButton,
                this.FolderPickerForwardButton,
                this.ShowFolderPickerPreview,
                this.ClearFolderPickerPreview,
                this.ReportFolderPickerStatus);
            this.previewViewportController = new PreviewViewportController(
                this.PreviewViewport,
                this.GetPreviewScale,
                this.SetPreviewScale,
                () => { this.SyncSettingsEditor(); this.PersistSettings(); });
            this.workspaceController = new WorkspaceController(this.Dispatcher, this.ExternalRefresh);
            this.editorScrollController = new EditorScrollController(
                () => this.settings,
                steps => this.SetEditorScale(this.GetEditorScale() + 0.1 * steps));
            this.Loaded += this.WindowLoaded;
            this.Closing += this.WindowClosing;
            this.SizeChanged += this.WindowSizeChanged;
            this.StateChanged += this.WindowStateChanged;
            this.PreviewKeyDown += this.WindowPreviewKeyDown;
            this.PreviewKeyUp += this.WindowPreviewKeyUp;
            this.Deactivated += (_, _) => this.UpdateElementInspection();
            this.Activated += (_, _) => this.UpdateElementInspection();
        }

        private void WindowLoaded(object sender, RoutedEventArgs eventArgs) {
            this.LoadSettings();
            // Дожидаемся первого отрисованного кадра: системный FilePicker открывается
            // модально и иначе показывает ещё не заполненную белую поверхность окна.
            this.Dispatcher.BeginInvoke(
                new Action(this.InitializeLoadedWindow),
                DispatcherPriority.ContextIdle);
        }

        private void InitializeLoadedWindow() {
            this.UpdatePluginSelectionAvailability();
            var pluginPath = this.GetConfiguredPluginPath();
            if (pluginPath is null) {
                pluginPath = this.pluginSessionController.PickPlugin(this);
                if (pluginPath is not null) {
                    this.settings.PreviewPluginPath = pluginPath;
                    this.settingsController.Save();
                }
            }
            var pluginInitializationError = this.pluginSessionController.Initialize(pluginPath);
            if (pluginInitializationError is not null) {
                if (!this.IsPluginSelectionLocked) {
                    this.settings.PreviewPluginPath = string.Empty;
                    this.settingsController.Save();
                }
                this.statusPresenter.Error(
                    $"Preview-plugin не загружен: {pluginInitializationError.Message} Выберите DLL, совместимую с текущей версией Previewer-а.");
            }
            if (this.IsNativePluginAvailable) {
                this.ApplyPluginSourceMarkupDirectory();
            }
            this.UpdateNativePluginTitle();
            this.ConfigureMouseWheelScrolling();
            this.ApplyEditorScale();
            this.InitializePreviewControls();
            this.RestoreWindowState();
            this.ConfigureWatchers();
            this.RefreshPageNames();
            var lastMarkupPath = this.settings.LastMarkupPath;
            if (lastMarkupPath is not null && File.Exists(lastMarkupPath)) {
                var lastPageName = this.GetPagePickerPath(lastMarkupPath);
                if (this.IsNativePluginAvailable) {
                    this.pluginSessionController.LogInfo(
                        $"Preview restore: saved markup='{lastMarkupPath}', matched page='{lastPageName ?? "<none>"}'");
                }
                if (lastPageName is not null) {
                    this.PagePicker.SelectedItem = lastPageName;
                } else {
                    this.LoadMarkup(lastMarkupPath);
                }
            }

            this.updatingEditors = true;
            this.SettingsEditor.Text = this.settings.ToJson();
            this.updatingEditors = false;
            this.isSettingsDirty = false;
            this.UpdateEditorMode();
            this.settingsPersistenceReady = true;
            this.PersistSettings();
            this.UpdateDocumentState();
            this.ScheduleRender();
            if (this.settings.PreviewScale <= 0.0) {
                this.Dispatcher.BeginInvoke(new Action(this.FitPreview));
            }
        }

        private string? GetConfiguredPluginPath() {
            var arguments = Environment.GetCommandLineArgs();
            var pluginArgumentIndex = Array.FindIndex(arguments, argument => string.Equals(argument, "--plugin", StringComparison.OrdinalIgnoreCase));
            if (pluginArgumentIndex >= 0 && pluginArgumentIndex + 1 < arguments.Length) {
                return arguments[pluginArgumentIndex + 1];
            }
            if (!string.IsNullOrWhiteSpace(this.settings.PreviewPluginPath)) {
                return this.settings.PreviewPluginPath;
            }
            return null;
        }

        private void UpdatePluginSelectionAvailability() {
            this.SelectPreviewPluginButton.IsEnabled = !this.IsPluginSelectionLocked;
            this.SelectPreviewPluginButton.ToolTip = this.IsPluginSelectionLocked
                ? "Приложение закреплено параметром --plugin для текущего сеанса отладки."
                : null;
        }

        private void UpdateNativePluginTitle() {
            var configuredPluginPath = this.pluginSessionController.PluginPath ?? this.GetConfiguredPluginPath();
            if (configuredPluginPath is null) {
                this.Title = "Android App Previewer (preview-plugin не выбран)";
                WindowTheme.SetTitleBarWarning(this, true);
                return;
            }
            var loadedLibraryPath = Path.GetFullPath(configuredPluginPath);
            var loadedLibrary = new FileInfo(loadedLibraryPath);
            if (!loadedLibrary.Exists) {
                this.Title = "Android App Previewer (preview-plugin не найден)";
                WindowTheme.SetTitleBarWarning(this, true);
                return;
            }
            this.Title = $"Android App Previewer ({loadedLibrary.Name}: {loadedLibrary.LastWriteTime:yyyy-MM-dd HH:mm:ss})";
            WindowTheme.SetTitleBarWarning(this, false);
        }

        private void ApplyPluginSourceMarkupDirectory() {
            var pluginInfo = this.pluginSessionController.Info
                ?? throw new InvalidOperationException("Preview-plugin не передал описание исходников XAML.");
            this.settings.XamlDirectory = pluginInfo.SourceMarkupDirectory;
            this.settings.ResourcesDirectory = this.workspaceController.ResolveResourcesDirectory(pluginInfo.SourceMarkupDirectory);
            this.settings.ControlsDirectory = pluginInfo.SourceControlsDirectory;
            this.settings.LastMarkupPath = pluginInfo.SourceEntryMarkupPath;
        }

        private void OpenButtonClick(object sender, RoutedEventArgs eventArgs) {
            // Legacy custom workspace explorer is temporarily disabled.
            // Application packages are selected through the native DLL file picker.
        }

        private void ShowFolderPicker() {
            this.folderPickerController.Open(this.GetFolderPickerInitialDirectory());
            this.MarkupEditor.Visibility = Visibility.Collapsed;
            this.SettingsPanel.Visibility = Visibility.Collapsed;
            this.OpenButton.IsEnabled = false;
            this.statusPresenter.Information("Выберите папку, содержащую XAML-файлы.");
        }

        private string GetFolderPickerInitialDirectory() {
            if (Directory.Exists(this.settings.XamlDirectory)) {
                return this.settings.XamlDirectory;
            }

            var documentsDirectory = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            return Directory.Exists(documentsDirectory)
                ? documentsDirectory
                : Environment.CurrentDirectory;
        }

        private void FolderPickerUpButtonClick(object sender, RoutedEventArgs eventArgs) {
            this.folderPickerController.Up();
        }

        private void FolderPickerBackButtonClick(object sender, RoutedEventArgs eventArgs) {
            this.folderPickerController.Back();
        }

        private void FolderPickerForwardButtonClick(object sender, RoutedEventArgs eventArgs) {
            this.folderPickerController.Forward();
        }

        private void FolderPickerPathTextKeyDown(object sender, KeyEventArgs eventArgs) {
            if (eventArgs.Key != Key.Enter) {
                return;
            }
            this.folderPickerController.SubmitPath();
            eventArgs.Handled = true;
        }

        private void FolderPickerEntriesPreviewKeyDown(object sender, KeyEventArgs eventArgs) {
            this.folderPickerController.HandleListKey(eventArgs);
        }

        private void FolderPickerEntriesPreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs eventArgs) {
            this.folderPickerController.HandleListBackgroundMouseDown(eventArgs.OriginalSource as DependencyObject);
        }

        private void FolderPickerEntriesMouseDoubleClick(object sender, MouseButtonEventArgs eventArgs) {
            this.folderPickerController.HandleListDoubleClick();
        }

        private void FolderPickerEntriesSelectionChanged(object sender, SelectionChangedEventArgs eventArgs) {
            this.folderPickerController.HandleSelectionChanged();
        }

        private void CancelFolderPickerButtonClick(object sender, RoutedEventArgs eventArgs) {
            this.HideFolderPicker();
        }

        private void SelectFolderButtonClick(object sender, RoutedEventArgs eventArgs) {
            if (!this.folderPickerController.TrySelectDirectory(out var selectedDirectory)) {
                return;
            }
            this.settings.XamlDirectory = selectedDirectory;
            this.settings.ResourcesDirectory = this.workspaceController.ResolveResourcesDirectory(selectedDirectory);
            this.ConfigureWatchers();
            this.RefreshPageNames();
            this.HideFolderPicker();
            this.PersistSettings();
            this.statusPresenter.Success($"Выбрана папка XAML: {this.settings.XamlDirectory}");
        }

        private void ShowFolderPickerPreview(string path) {
            this.ShowNativeApplicationPreview();
        }

        private void ClearFolderPickerPreview() {
            this.previewController.StopAnimation();
            this.deferredNavigationEditorPage = null;
            this.previewController.Reset();
            this.previewLayer.Children.Clear();
            this.navigationGraphController.Clear();
        }

        private void ShowPreviewError(Exception exception) {
            if (this.nativeApplicationSession is not null) {
                this.statusPresenter.Error(exception.Message);
                this.previewController.StartAnimation();
                return;
            }
            this.ClearFolderPickerPreview();
            this.previewLayer.Children.Add(new Border {
                Background = PreviewBrushes.Parse("#1F1717"),
                BorderBrush = PreviewBrushes.Parse("#A75B5B"),
                BorderThickness = new Thickness(1),
                Child = new TextBlock {
                    Margin = new Thickness(32),
                    Foreground = PreviewBrushes.Parse("#FFB4AB"),
                    FontSize = 18,
                    Text = $"Ошибка предпросмотра\n\n{exception.Message}",
                    TextWrapping = TextWrapping.Wrap,
                    VerticalAlignment = VerticalAlignment.Center,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    TextAlignment = TextAlignment.Center,
                },
            });
            this.statusPresenter.Error(exception.Message);
        }

        private void HideFolderPicker() {
            this.folderPickerController.Close();
            this.UpdateEditorMode();
            this.ScheduleRender();
        }

        private void ReportFolderPickerStatus(string message, bool isSuccess) {
            if (isSuccess) {
                this.statusPresenter.Success(message);
            } else {
                this.statusPresenter.Information(message);
            }
        }

        private void SaveButtonClick(object sender, RoutedEventArgs eventArgs) {
            if (this.editorMode == EditorMode.Settings) {
                this.settingsController.Replace(this.SettingsEditor.Text);
                this.ApplyElementInspectionHighlightSettings();
                this.ConfigureMouseWheelScrolling();
                this.ApplyEditorScale();
                this.ApplySettingsToPreviewControls();
                this.SaveSettings();
                this.RefreshPageNames();
                this.updatingEditors = true;
                this.SettingsEditor.Text = this.settings.ToJson();
                this.updatingEditors = false;
                this.isSettingsDirty = false;
                this.UpdateDocumentState();
                this.statusPresenter.Success($"Настройки сохранены: {this.settings.FilePath}");
                return;
            }
            if (this.editorMode == EditorMode.Scenario) {
                if (this.scenarioPath is null) {
                    return;
                }
                try {
                    this.scenarioController.Save(this.ScenarioEditor.Text.TrimEnd());
                    this.RefreshScenarioNames();
                    if (this.scenarioPath is not null) {
                        this.editorMode = EditorMode.Scenario;
                        this.ScenarioButton.IsChecked = true;
                        this.UpdateEditorMode();
                    }
                    this.ShowNativeApplicationPreview();
                    this.statusPresenter.Success($"Сценарии сохранены: {this.scenarioPath}");
                }
                catch (JsonException exception) {
                    this.statusPresenter.Error($"Сценарии не сохранены: {exception.Message}");
                }
                this.UpdateDocumentState();
                return;
            }
            if (this.markupPath is null) {
                return;
            }

            var markup = this.markupEditorController.Text.TrimEnd();
            if (!this.documentEditorController.Save(markup, this.ConfirmMarkupOverwrite)) {
                this.statusPresenter.Information("Сохранение отменено: исходный XAML был изменён извне.");
                return;
            }
            this.RefreshScenarioNames();
            this.UpdateDocumentState();
            // Собственное сохранение не изменяет текст редактора, поэтому
            // FileSystemWatcher его намеренно игнорирует. Перезагружаем XAML
            // напрямую, не ожидая внешнего изменения файла.
            this.ScheduleRender();
            this.statusPresenter.Success($"Сохранено: {this.markupPath}");
        }

        private bool ConfirmMarkupOverwrite() {
            var dialog = new ExternalMarkupConflictDialog(this.markupPath!) {
                Owner = this,
            };
            return dialog.ShowDialog() == true;
        }

        private void DevicePresetPickerSelectionChanged(object sender, SelectionChangedEventArgs eventArgs) {
            if (this.updatingPreviewControls || this.DevicePresetPicker.SelectedItem is not DevicePreset preset) {
                return;
            }

            this.settings.PreviewWidth = preset.Width;
            this.settings.PreviewHeight = preset.Height;
            this.ApplyPreviewLayout();
            this.SyncSettingsEditor();
            this.PersistSettings();
            this.ScheduleRender();
        }

        private void ResetSessionButtonClick(object sender, RoutedEventArgs eventArgs) {
            this.ResetNativeApplicationSession();
            this.ShowNativeApplicationPreview();
        }

        private void ResetNativeApplicationSession() {
            this.previewController.StopAnimation();
            this.previewController.Reset();
            this.previewLayer.Children.Clear();
        }

        private void SelectPreviewPluginButtonClick(object sender, RoutedEventArgs eventArgs) {
            if (this.IsPluginSelectionLocked) {
                return;
            }
            var pluginPath = this.pluginSessionController.PickPlugin(this);
            if (pluginPath is null) {
                return;
            }
            this.settings.PreviewPluginPath = pluginPath;
            this.PersistSettings();
            Process.Start(new ProcessStartInfo {
                FileName = Environment.ProcessPath!,
                WorkingDirectory = AppContext.BaseDirectory,
                UseShellExecute = true,
            });
            this.Close();
        }

        private void NavigationGraphToggleButtonClick(object sender, RoutedEventArgs eventArgs) {
            if (this.updatingPreviewControls) {
                return;
            }

            this.settings.IsNavigationGraphVisible = this.NavigationGraphToggleButton.IsChecked == true;
            this.UpdateNavigationGraphVisibility();
            this.SyncSettingsEditor();
            this.PersistSettings();
        }

        private void ElementSelectionButtonClick(object sender, RoutedEventArgs eventArgs) {
            this.UpdateElementInspection();
            this.SelectElementFromMarkupEditor();
        }

        private void ElementSelectionWireframeOptionClick(object sender, RoutedEventArgs eventArgs) {
            this.ApplyElementInspectionHighlightSettings();
        }

        private void AnimationSpeedPickerSelectionChanged(object sender, SelectionChangedEventArgs eventArgs) {
            if (this.updatingPreviewControls || this.AnimationSpeedPicker.SelectedItem is not AnimationSpeed speed) {
                return;
            }

            this.settings.AnimationPlaybackRate = speed.Rate;
            this.nativeApplicationSession?.SetAnimationPlaybackRate(speed.Rate);
            this.SyncSettingsEditor();
            this.PersistSettings();
        }

        private void PreviewOrientationToggleClick(object sender, RoutedEventArgs eventArgs) {
            if (this.updatingPreviewControls) {
                return;
            }

            this.settings.IsPreviewLandscape = this.PreviewOrientationToggle.IsChecked == true;
            this.UpdatePreviewOrientationToggle();
            this.ApplyPreviewLayout();
            this.SyncSettingsEditor();
            this.PersistSettings();
            this.ScheduleRender();
        }

        private void ZoomOutButtonClick(object sender, RoutedEventArgs eventArgs) {
            this.SetPreviewScale(this.GetPreviewScale() - 0.1);
        }

        private void ZoomInButtonClick(object sender, RoutedEventArgs eventArgs) {
            this.SetPreviewScale(this.GetPreviewScale() + 0.1);
        }

        private void PreviewViewportPreviewMouseWheel(object sender, MouseWheelEventArgs eventArgs) {
            this.previewViewportController.HandleMouseWheel(eventArgs);
        }

        private void PreviewViewportPreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs eventArgs) {
            this.previewViewportController.HandleMouseDown(eventArgs);
        }

        private void PreviewViewportPreviewMouseMove(object sender, MouseEventArgs eventArgs) {
            this.previewViewportController.HandleMouseMove(eventArgs);
        }

        private void PreviewViewportPreviewMouseLeftButtonUp(object sender, MouseButtonEventArgs eventArgs) {
            this.previewViewportController.HandleMouseUp(eventArgs);
        }

        private void PreviewViewportLostMouseCapture(object sender, MouseEventArgs eventArgs) {
            this.previewViewportController.HandleLostMouseCapture();
        }

        private void WindowPreviewKeyDown(object sender, KeyEventArgs eventArgs) {
            if (this.ElementSelectionButton.IsChecked == true) {
                return;
            }
            var key = eventArgs.Key == Key.System ? eventArgs.SystemKey : eventArgs.Key;
            if (key is Key.LeftAlt or Key.RightAlt) {
                this.UpdateElementInspection();
            }
        }

        private void WindowPreviewKeyUp(object sender, KeyEventArgs eventArgs) {
            if (this.ElementSelectionButton.IsChecked != true) {
                var key = eventArgs.Key == Key.System ? eventArgs.SystemKey : eventArgs.Key;
                if (key is Key.LeftAlt or Key.RightAlt) {
                    this.UpdateElementInspection();
                }
            }
            this.previewViewportController.HandleKeyUp(eventArgs);
        }

        private void UpdateElementInspection() {
            var isElementSelectionEnabled = this.ElementSelectionButton.IsChecked == true;
            var isEnabled = this.IsElementSelectionActive();
            this.nativeApplicationSession?.SetElementInspectionEnabled(isEnabled, isElementSelectionEnabled && isEnabled);
        }

        private bool IsElementSelectionActive() {
            return this.editorMode == EditorMode.Xaml
                && (this.ElementSelectionButton.IsChecked == true
                    || (this.IsActive
                        && (Keyboard.IsKeyDown(Key.LeftAlt)
                            || Keyboard.IsKeyDown(Key.RightAlt))));
        }

        private void PreviewElementSelected(AndroidAppPreviewerPluginSDK.NativeInspectionResult inspection) {
            if (string.IsNullOrWhiteSpace(inspection.SourcePath) || !File.Exists(inspection.SourcePath)) {
                return;
            }
            // Клик в preview уже закрепил конкретный визуальный экземпляр. Перемещение
            // caret нужно только для навигации; оно не должно выбирать первый экземпляр
            // того же тега в повторяющемся ItemTemplate.
            this.updatingElementSelection = true;
            try {
                this.SelectControlMarkup(inspection.SourcePath);
                if (inspection.Line < 1 || inspection.Line > this.MarkupEditor.Document.LineCount) {
                    return;
                }
                var line = this.MarkupEditor.Document.GetLineByNumber(inspection.Line);
                var column = Math.Clamp(inspection.Column - 1, 0, line.Length);
                this.MarkupEditor.CaretOffset = line.Offset + column;
                this.MarkupEditor.Select(this.MarkupEditor.CaretOffset, 0);
                this.MarkupEditor.ScrollTo(inspection.Line, inspection.Column);
                this.MarkupEditor.Focus();
            } finally {
                this.updatingElementSelection = false;
            }
        }

        private void ApplyElementInspectionHighlightSettings() {
            this.nativeApplicationSession?.SetElementInspectionWireframes(
                this.settings.HoveredElementInspectionWireframe,
                this.settings.ActiveElementInspectionWireframe,
                this.ElementSelectionMarginCheckBox.IsChecked == true,
                this.ElementSelectionPaddingCheckBox.IsChecked == true);
        }

        private void ExpandAllFoldingsButtonClick(object sender, RoutedEventArgs eventArgs) {
            this.markupEditorController.ExpandAll();
        }

        private void MarkupEditorFoldingStateChanged(object? sender, EventArgs eventArgs) {
            this.UpdateExpandAllFoldingsButtonLayout();
            this.ExpandAllFoldingsButton.Visibility = this.markupEditorController.HasFoldedSections
                ? Visibility.Visible
                : Visibility.Collapsed;
            if (!this.suppressFoldingStatePersistence) {
                this.StoreCollapsedMarkupFoldings();
                this.PersistSettings();
            }
        }

        private void MarkupSearchPanelLayoutChanged(
            object sender,
            DependencyPropertyChangedEventArgs eventArgs) {
            this.UpdateExpandAllFoldingsButtonLayout();
        }

        private void UpdateExpandAllFoldingsButtonLayout() {
            var searchPanelHeight = this.markupSearchPanel.IsVisible
                ? MainWindow.SearchPanelOverlayHeight
                : 0.0;
            this.ExpandAllFoldingsButton.Margin = new Thickness(0.0, 16.0 + searchPanelHeight, 38.0, 0.0);
        }

        private void FitPreviewButtonClick(object sender, RoutedEventArgs eventArgs) {
            this.FitPreview();
        }

        private void EditorZoomOutButtonClick(object sender, RoutedEventArgs eventArgs) {
            this.SetEditorScale(this.GetEditorScale() - 0.1);
        }

        private void EditorZoomInButtonClick(object sender, RoutedEventArgs eventArgs) {
            this.SetEditorScale(this.GetEditorScale() + 0.1);
        }

        private void SettingsButtonClick(object sender, RoutedEventArgs eventArgs) {
            if (this.SettingsButton.IsChecked == true) {
                this.ScenarioButton.IsChecked = false;
                this.editorMode = EditorMode.Settings;
                if (!this.isSettingsDirty) {
                    this.SyncSettingsEditor();
                }
            } else {
                this.editorMode = EditorMode.Xaml;
            }
            this.UpdateEditorMode();
        }

        private void ScenarioButtonClick(object sender, RoutedEventArgs eventArgs) {
            if (this.ScenarioButton.IsChecked == true && this.scenarioPath is not null) {
                this.SettingsButton.IsChecked = false;
                this.editorMode = EditorMode.Scenario;
                if (!this.isScenarioDirty) {
                    this.updatingEditors = true;
                    this.ScenarioEditor.Text = this.scenarioFileText!;
                    this.updatingEditors = false;
                }
            } else {
                this.editorMode = EditorMode.Xaml;
            }
            this.UpdateEditorMode();
        }

        private void PagePickerSelectionChanged(object sender, SelectionChangedEventArgs eventArgs) {
            var shouldLoadSelectedPage = !this.selectingPageFromNative;
            if (this.PagePicker.SelectedItem is string pageName) {
                this.RefreshControlNames();
                this.LoadMarkup(Path.Combine(this.settings.XamlDirectory, pageName));
            }

            this.ShowNativeApplicationPreview(shouldLoadSelectedPage);
        }

        private void NavigationGraphRouteConfirmed(IReadOnlyList<string> route) {
            this.pendingPreviewRoute = route;
            this.ShowNativeApplicationPreview();
        }

        private void NavigationGraphActivePageChanged(string page) {
            this.PersistNavigationPage(page);
            if (this.nativeApplicationSession?.IsTransitioning == true) {
                this.deferredNavigationEditorPage = page;
                return;
            }
            this.SelectNavigationPageInEditor(page);
        }

        private void SelectNavigationPageInEditor(string page) {
            var pagePath = this.GetMarkupPathForNativePage(page);
            if (pagePath is not null) {
                this.selectingPageFromNative = true;
                try {
                    this.PagePicker.SelectedItem = pagePath;
                }
                finally {
                    this.selectingPageFromNative = false;
                }
            }
        }

        private void ControlPickerSelectionChanged(object sender, SelectionChangedEventArgs eventArgs) {
            if (this.updatingControlPicker || this.ControlPicker.SelectedItem is not MarkupNavigationTarget target) {
                return;
            }
            this.SelectControlMarkup(target.Path);
        }

        private void ScenarioPickerSelectionChanged(object sender, SelectionChangedEventArgs eventArgs) {
            if (this.updatingScenarioPicker) {
                return;
            }
            if (this.ScenarioPicker.SelectedItem is not string name || name == MainWindow.NoScenarioName) {
                this.activeScenarioPath = null;
                this.activeScenarioName = null;
                this.ResetNativeApplicationSession();
            }
            else {
                this.activeScenarioPath = this.scenarioPath;
                this.activeScenarioName = name;
            }

            this.ShowNativeApplicationPreview();
            this.UpdateSaveScenarioToStorageButtonState();
        }

        private void SaveScenarioToStorageButtonClick(object sender, RoutedEventArgs eventArgs) {
            if (this.nativeApplicationSession is null
                || this.scenarioPath is null
                || this.ScenarioPicker.SelectedItem is not string name
                || name == MainWindow.NoScenarioName) {
                return;
            }

            this.nativeApplicationSession.SavePreviewState();
            this.settings.SavedScenarioPath = null;
            this.settings.SavedScenarioName = null;
            this.activeScenarioPath = null;
            this.activeScenarioName = null;
            this.SyncSettingsEditor();
            this.PersistSettings();
            this.ScenarioPicker.SelectedItem = MainWindow.NoScenarioName;
        }

        private void EditorTextChanged(object sender, EventArgs eventArgs) {
            if (ReferenceEquals(sender, this.MarkupEditor)) {
                if (this.markupEditorController.HandleTextChanged()) {
                    this.documentEditorController.MarkDirty();
                    this.UpdateDocumentState();
                }

                return;
            }

            if (!this.updatingEditors) {
                if (ReferenceEquals(sender, this.SettingsEditor)) {
                    this.isSettingsDirty = true;
                }
                if (ReferenceEquals(sender, this.ScenarioEditor)) {
                    this.scenarioController.MarkDirty();
                }

                this.UpdateDocumentState();
            }
        }

        private void SelectElementFromMarkupEditor() {
            if (!this.IsElementSelectionActive()) {
                return;
            }
            var tagOffset = this.FindNearestOpeningTagOffset(this.MarkupEditor.CaretOffset);
            if (tagOffset is null) {
                return;
            }
            if (this.markupPath is null) {
                return;
            }
            var position = this.MarkupEditor.Document.GetLocation(tagOffset.Value);
            this.nativeApplicationSession?.SelectElementInspection(
                Path.GetFullPath(this.markupPath).Replace('\\', '/'),
                position.Line,
                position.Column);
        }

        private int? FindNearestOpeningTagOffset(int offset) {
            var text = this.MarkupEditor.Document.Text;
            for (var tagOffset = Math.Min(offset, text.Length - 1); tagOffset >= 0;) {
                tagOffset = text.LastIndexOf('<', tagOffset);
                if (tagOffset < 0) {
                    return null;
                }
                if (tagOffset + 1 < text.Length
                    && text[tagOffset + 1] is not '/' and not '?' and not '!') {
                    return tagOffset;
                }
                --tagOffset;
            }
            return null;
        }

        private void MarkupEditorCaretPositionChanged(object? sender, EventArgs eventArgs) {
            if (this.updatingElementSelection) {
                return;
            }
            this.SelectElementFromMarkupEditor();
        }

        private void EditorPreviewKeyDown(object sender, KeyEventArgs eventArgs) {
            if (ReferenceEquals(sender, this.SettingsEditor)
                && MainWindow.IsPasteGesture(eventArgs)
                && Clipboard.ContainsText()) {
                var pastedText = Clipboard.GetText();
                var jsonText = MainWindow.EscapeWindowsPathForJson(pastedText);
                if (!string.Equals(pastedText, jsonText, StringComparison.Ordinal)) {
                    this.SettingsEditor.SelectedText = jsonText;
                    eventArgs.Handled = true;
                    return;
                }
            }

            if (eventArgs.Key == Key.S && Keyboard.Modifiers == ModifierKeys.Control) {
                this.SaveButtonClick(this, eventArgs);
                eventArgs.Handled = true;
                return;
            }

            if (!ReferenceEquals(sender, this.MarkupEditor)) {
                return;
            }

            if (this.xamlCompletionController.HandlePreviewKeyDown(eventArgs)) {
                return;
            }
            this.markupEditorController.HandlePreviewKeyDown(eventArgs);
        }

        private static bool IsPasteGesture(KeyEventArgs eventArgs) {
            return eventArgs.Key == Key.V && Keyboard.Modifiers == ModifierKeys.Control
                || eventArgs.Key == Key.Insert && Keyboard.Modifiers == ModifierKeys.Shift;
        }

        private static string EscapeWindowsPathForJson(string value) {
            var candidate = value.Trim();
            if (candidate.Length >= 2 && candidate[0] == '"' && candidate[^1] == '"') {
                candidate = candidate[1..^1];
            }
            if (!MainWindow.IsWindowsPath(candidate)) {
                return value;
            }

            var result = new StringBuilder(value.Length * 2);
            for (var index = 0; index < value.Length; index++) {
                var character = value[index];
                if (character != '\\') {
                    result.Append(character);
                    continue;
                }

                result.Append("\\\\");
                if (index + 1 < value.Length && value[index + 1] == '\\') {
                    index++;
                }
            }
            return result.ToString();
        }

        private static bool IsWindowsPath(string value) {
            return value.Length >= 3
                && char.IsAsciiLetter(value[0])
                && value[1] == ':'
                && value[2] == '\\'
                || value.StartsWith("\\\\", StringComparison.Ordinal);
        }

        private void SynchronizeNavigationGraph(NativePreviewSession session) {
            if (!string.Equals(this.navigationGraphController.CurrentPage, session.CurrentPage, StringComparison.Ordinal)) {
                // Native graph разрешает previousPage по своей истории. Поэтому после смены
                // страницы нельзя ограничиться подсветкой узла: нужно получить новый граф.
                this.navigationGraphController.SetGraph(session.NavigationGraph);
            }
        }

        private void PreviewFrameUpdated(NativePreviewSession session) {
            if (this.isClosing) {
                return;
            }
            this.SynchronizeNavigationGraph(session);
            if (!session.IsTransitioning && this.deferredNavigationEditorPage is not null) {
                this.SelectNavigationPageInEditor(this.deferredNavigationEditorPage);
                this.deferredNavigationEditorPage = null;
            }
        }

        private void NativeApplicationInteractionCompleted() {
            if (this.nativeApplicationSession is null) {
                return;
            }
            this.SynchronizeNavigationGraph(this.nativeApplicationSession);
            this.pluginSessionController.LogInfo(
                $"Preview interaction completed: native='{this.nativeApplicationSession.CurrentPage}', graph='{this.navigationGraphController.CurrentPage}'.");
            this.UpdateSaveScenarioToStorageButtonState();
        }
        private void UpdateSaveScenarioToStorageButtonState() {
            this.SaveScenarioToStorageButton.IsEnabled = this.scenarioPath is not null
                && this.ScenarioPicker.SelectedItem is string name
                && name != MainWindow.NoScenarioName
                && this.nativeApplicationSession?.CanSavePreviewState() == true;
        }

        private void LoadMarkup(string path) {
            this.StoreCollapsedMarkupFoldings();
            var markup = this.documentEditorController.Load(path);
            this.ConfigureWatchers();
            this.FilePathText.Text = this.markupPath;
            this.suppressFoldingStatePersistence = true;
            this.updatingEditors = true;
            try {
                this.markupEditorController.SetText(markup);
                this.markupEditorController.SetFoldedOffsets(this.GetCollapsedMarkupFoldings());
            }
            finally {
                this.updatingEditors = false;
                this.suppressFoldingStatePersistence = false;
            }
            this.SelectControlPicker(path);
            this.RefreshScenarioNames();
            this.ConfigureWatchers();
            this.UpdateDocumentState();
            // PersistSettings записывает previewer.settings.json. Его изменение
            // асинхронно придёт обратно через settingsWatcher, поэтому refresh ниже
            // не должен самовольно менять текущую страницу.
            this.PersistSettings();
            this.ScheduleRender();
        }

        private void RefreshPageNames() {
            // RefreshPageNames вызывается и из settingsWatcher после PersistSettings.
            // Сохраняем выбор, чтобы такой внутренний refresh не отменял навигацию
            // на другую страницу через несколько сотен миллисекунд после tap.
            var previous = this.PagePicker.SelectedItem as string;
            var pages = this.workspaceController.DiscoverPages(this.settings.XamlDirectory);
            if (this.PagePicker.Items.Cast<string>().SequenceEqual(pages)) {
                this.RefreshControlNames();
                return;
            }
            this.PagePicker.ItemsSource = pages;
            var savedPage = this.settings.LastMarkupPath is null
                ? null
                : pages.FirstOrDefault(candidate => string.Equals(
                    Path.GetFullPath(Path.Combine(this.settings.XamlDirectory, candidate)),
                    this.settings.LastMarkupPath,
                    StringComparison.OrdinalIgnoreCase));
            this.PagePicker.SelectedItem = pages.Contains(previous)
                ? previous
                : savedPage is not null
                    ? savedPage
                    : pages.FirstOrDefault();
            this.RefreshControlNames();
        }

        private string? GetSelectedPageMarkupPath() {
            return this.workspaceController.GetPagePath(this.settings.XamlDirectory, this.PagePicker.SelectedItem as string);
        }

        private void RefreshControlNames() {
            var pagePath = this.GetSelectedPageMarkupPath();
            if (pagePath is null || !File.Exists(pagePath)) {
                this.ControlPicker.ItemsSource = null;
                return;
            }
            var discoveredControls = this.workspaceController.DiscoverControls(pagePath, this.settings.ControlsDirectory);
            var controls = new List<MarkupNavigationTarget> {
                new() { Name = "Page", Path = pagePath },
            };
            foreach (var group in discoveredControls.GroupBy(control => control.Name, StringComparer.Ordinal)
                .OrderBy(group => group.Key, StringComparer.Ordinal)) {
                var unnamedIndex = 0;
                var groupCount = group.Count();
                foreach (var control in group.OrderBy(control => string.IsNullOrEmpty(control.Id) ? 1 : 0)) {
                    var label = control.Name;
                    if (groupCount > 1) {
                        label += string.IsNullOrEmpty(control.Id)
                            ? $" [{++unnamedIndex}]"
                            : $" [{control.Id}]";
                    }
                    controls.Add(new() { Name = label, Path = control.Path });
                }
            }
            this.updatingControlPicker = true;
            try {
                this.ControlPicker.ItemsSource = controls;
                this.SelectControlPicker(this.markupPath ?? pagePath);
            }
            finally {
                this.updatingControlPicker = false;
            }
        }

        private void SelectControlMarkup(string path) {
            this.SelectControlPicker(path);
            if (this.markupPath is null || !MainWindow.PathsAreEqual(this.markupPath, path)) {
                this.LoadMarkup(path);
            }
        }

        private void SelectControlPicker(string path) {
            if (this.ControlPicker.ItemsSource is not IEnumerable<MarkupNavigationTarget> targets) {
                return;
            }
            var target = targets.FirstOrDefault(item => MainWindow.PathsAreEqual(item.Path, path));
            if (target is null || ReferenceEquals(this.ControlPicker.SelectedItem, target)) {
                return;
            }
            this.updatingControlPicker = true;
            try {
                this.ControlPicker.SelectedItem = target;
            }
            finally {
                this.updatingControlPicker = false;
            }
        }

        private static bool PathsAreEqual(string first, string second) {
            return string.Equals(
                Path.GetFullPath(first),
                Path.GetFullPath(second),
                StringComparison.OrdinalIgnoreCase);
        }

        private void LoadSettings() {
            this.settingsController.Load();
            var resourcesDirectory = this.workspaceController.ResolveResourcesDirectory(this.settings.XamlDirectory);
            if (!string.Equals(this.settings.ResourcesDirectory, resourcesDirectory, StringComparison.OrdinalIgnoreCase)) {
                this.settings.ResourcesDirectory = resourcesDirectory;
                this.settingsController.Save();
            }

            this.ApplyElementInspectionHighlightSettings();
        }

        private void ConfigureWatchers() {
            this.workspaceController.ConfigureWatchers(this.markupPath, this.scenarioPath, this.settings);
        }

        private void ExternalRefresh() {
            if (this.isClosing) {
                return;
            }
            try {
                bool previewChanged = false;
                this.RefreshPageNames();
                if (this.markupPath is not null && File.Exists(this.markupPath)) {
                    var markup = File.ReadAllText(this.markupPath);
                    if (!this.isMarkupDirty
                        && !string.Equals(markup, this.markupEditorController.Text, StringComparison.Ordinal)) {
                        this.updatingEditors = true;
                        this.markupEditorController.SetText(markup);
                        this.updatingEditors = false;
                        this.documentEditorController.AcceptPersistedText(markup);
                        this.RefreshScenarioNames();
                        this.ConfigureWatchers();
                        this.UpdateDocumentState();
                        previewChanged = true;
                    }
                }
                if (this.scenarioPath is not null
                    && (!File.Exists(this.scenarioPath)
                        || !string.Equals(File.ReadAllText(this.scenarioPath), this.scenarioFileText, StringComparison.Ordinal))) {
                    this.RefreshScenarioNames();
                    this.ConfigureWatchers();
                    previewChanged = true;
                }
                if (File.Exists(this.settings.FilePath)) {
                    var settingsJson = File.ReadAllText(this.settings.FilePath);
                    if (!this.isSettingsDirty
                        && !string.Equals(settingsJson, this.SettingsEditor.Text, StringComparison.Ordinal)) {
                        this.settingsController.Replace(settingsJson);
                        this.ApplyElementInspectionHighlightSettings();
                        this.updatingEditors = true;
                        this.SettingsEditor.Text = settingsJson;
                        this.updatingEditors = false;
                        this.isSettingsDirty = false;
                        this.UpdateDocumentState();
                        this.ConfigureWatchers();
                        // Не сбрасывает PagePicker на MainPage: RefreshPageNames
                        // восстанавливает страницу, выбранную обработчиком navigation.
                        this.RefreshPageNames();
                        this.ConfigureMouseWheelScrolling();
                        this.ApplyEditorScale();
                        this.ApplySettingsToPreviewControls();
                        previewChanged = true;
                    }
                }
                if (previewChanged) {
                    this.ScheduleRender();
                }
            }
            catch (Exception exception) {
                this.statusPresenter.Error(exception.Message);
            }
        }

        private void SaveSettings() {
            this.StoreCollapsedMarkupFoldings();
            var nativePagePath = this.nativeApplicationSession is null
                ? null
                : this.GetMarkupPathForNativePage(this.nativeApplicationSession.CurrentPage);
            this.settings.LastMarkupPath = nativePagePath is null
                ? this.markupPath
                : Path.GetFullPath(Path.Combine(this.settings.XamlDirectory, nativePagePath));
            if (this.WindowState == WindowState.Normal) {
                this.settings.WindowWidth = this.Width;
                this.settings.WindowHeight = this.Height;
            }
            this.settings.IsMaximized = this.WindowState == WindowState.Maximized;
            this.settings.EditorPaneRatio = this.GetEditorPaneRatio();
            this.settingsController.Save();
            // Синхронизируем отображаемый JSON после собственного сохранения.
            // Тогда settingsWatcher не принимает нашу же запись за внешнее
            // изменение и не запускает повторный рендер native-сессии.
            if (!this.isSettingsDirty) {
                this.updatingEditors = true;
                this.SettingsEditor.Text = this.settings.ToJson();
                this.updatingEditors = false;
            }
        }

        private void PersistSettings() {
            if (this.settingsPersistenceReady) {
                this.SaveSettings();
            }
        }

        private string? GetMarkupPathForNativePage(string page) {
            return this.PagePicker.Items.Cast<string>().FirstOrDefault(candidate =>
                string.Equals(Path.GetFileNameWithoutExtension(candidate), page, StringComparison.Ordinal));
        }

        private string? GetPagePickerPath(string markupPath) {
            return this.PagePicker.Items.Cast<string>().FirstOrDefault(candidate => string.Equals(
                Path.GetFullPath(Path.Combine(this.settings.XamlDirectory, candidate)),
                markupPath,
                StringComparison.OrdinalIgnoreCase));
        }

        private void PersistNavigationPage(string page) {
            var pagePath = this.GetMarkupPathForNativePage(page);
            if (pagePath is null) {
                this.pluginSessionController.LogInfo($"Preview navigation: could not map native page='{page}' to a markup file");
                return;
            }

            var markupPath = Path.GetFullPath(Path.Combine(this.settings.XamlDirectory, pagePath));
            if (string.Equals(this.settings.LastMarkupPath, markupPath, StringComparison.Ordinal)) {
                return;
            }

            this.settings.LastMarkupPath = markupPath;
            if (this.settingsPersistenceReady) {
                this.settingsController.Save();
                if (!this.isSettingsDirty) {
                    this.updatingEditors = true;
                    this.SettingsEditor.Text = this.settings.ToJson();
                    this.updatingEditors = false;
                }
                this.pluginSessionController.LogInfo(
                    $"Preview navigation: saved native page='{page}', markup='{this.settings.LastMarkupPath}'");
            }
        }

        private int[] GetCollapsedMarkupFoldings() {
            if (this.markupPath is null
                || !this.settings.CollapsedMarkupFoldingOffsets.TryGetValue(this.markupPath, out var offsets)) {
                return [];
            }
            return offsets;
        }

        private void StoreCollapsedMarkupFoldings() {
            if (this.markupPath is null) {
                return;
            }
            var offsets = this.markupEditorController.GetFoldedOffsets();
            if (offsets.Length == 0) {
                this.settings.CollapsedMarkupFoldingOffsets.Remove(this.markupPath);
                return;
            }
            this.settings.CollapsedMarkupFoldingOffsets[this.markupPath] = offsets;
        }

        private void RestoreWindowState() {
            if (this.settings.WindowWidth >= this.MinWidth) {
                this.Width = this.settings.WindowWidth;
            }
            if (this.settings.WindowHeight >= this.MinHeight) {
                this.Height = this.settings.WindowHeight;
            }
            if (this.settings.IsMaximized) {
                this.WindowState = WindowState.Maximized;
            } else {
                // Положение из прошлой сессии не восстанавливаем: окно должно
                // открываться в центре рабочей области текущего экрана.
                var workArea = SystemParameters.WorkArea;
                this.Left = workArea.Left + (workArea.Width - this.Width) / 2.0;
                this.Top = workArea.Top + (workArea.Height - this.Height) / 2.0;
            }
            this.ApplyEditorPreviewSplit();
        }

        private void WindowClosing(object? sender, System.ComponentModel.CancelEventArgs eventArgs) {
            if (this.isClosing) {
                return;
            }
            this.isClosing = true;
            this.settingsPersistenceReady = false;
            this.windowSizePersistenceTimer.Stop();
            this.previewController.Dispose();
            this.workspaceController.Dispose();
            this.editorScrollController.Dispose();
            this.markupEditorController.Dispose();
            this.previewLayer.Children.Clear();
        }

        private void WindowSizeChanged(object sender, SizeChangedEventArgs eventArgs) {
            // SizeChanged приходит на каждый пиксель при перетаскивании границы.
            // Немедленная запись settings будит FileSystemWatcher и запускает
            // лишние native-кадры, из-за чего поверхность визуально мигает.
            this.windowSizePersistenceTimer.Stop();
            this.windowSizePersistenceTimer.Start();
        }

        private void WindowSizePersistenceTimerTick(object? sender, EventArgs eventArgs) {
            this.windowSizePersistenceTimer.Stop();
            this.PersistSettings();
        }

        private void WindowStateChanged(object? sender, EventArgs eventArgs) {
            this.PersistSettings();
        }

        private void EditorSplitterDragCompleted(object sender, DragCompletedEventArgs eventArgs) {
            this.PersistSettings();
        }

        private void UpdateEditorMode() {
            this.MarkupEditor.Visibility = this.editorMode == EditorMode.Xaml ? Visibility.Visible : Visibility.Collapsed;
            this.ScenarioPanel.Visibility = this.editorMode == EditorMode.Scenario ? Visibility.Visible : Visibility.Collapsed;
            this.SettingsPanel.Visibility = this.editorMode == EditorMode.Settings ? Visibility.Visible : Visibility.Collapsed;
            this.OpenButton.IsEnabled = this.editorMode == EditorMode.Xaml;
            this.UpdateScenarioToggle();
            this.UpdateDocumentState();
            this.UpdateNavigationGraphVisibility();
            this.UpdateElementInspection();
        }

        private void UpdateDocumentState() {
            this.XamlModeText.Text = this.isMarkupDirty ? "XAML *" : "XAML";
            this.ScenarioModeText.Text = this.isScenarioDirty ? "Сценарии *" : "Сценарии";
            this.SettingsButton.Content = this.isSettingsDirty ? "Настройки *" : "Настройки";
            this.ScenarioButton.ToolTip = this.isScenarioDirty ? "Сценарии изменены" : null;
            this.SaveButton.IsEnabled = this.editorMode switch {
                EditorMode.Xaml => this.isMarkupDirty,
                EditorMode.Scenario => this.isScenarioDirty,
                EditorMode.Settings => this.isSettingsDirty,
                _ => false,
            };
        }

        private void UpdateScenarioToggle() {
            var isScenarioMode = this.editorMode == EditorMode.Scenario;
            this.XamlModeText.Foreground = PreviewBrushes.Parse(isScenarioMode ? "#E6E6E6" : "#D5BD7D");
            this.ScenarioModeText.Foreground = PreviewBrushes.Parse(isScenarioMode ? "#D5BD7D" : "#E6E6E6");
        }

        private void InitializePreviewControls() {
            this.ApplySettingsToPreviewControls();
            this.ApplyPreviewLayout();
        }

        private void ApplySettingsToPreviewControls() {
            this.updatingPreviewControls = true;
            try {
                this.DevicePresetPicker.ItemsSource = this.settings.PreviewResolutions;
                this.DevicePresetPicker.SelectedItem = this.settings.PreviewResolutions.FirstOrDefault(
                    preset => preset.Width == this.settings.PreviewWidth
                        && preset.Height == this.settings.PreviewHeight);
                this.PreviewOrientationToggle.IsChecked = this.settings.IsPreviewLandscape;
                this.NavigationGraphToggleButton.IsChecked = this.settings.IsNavigationGraphVisible;
                var speeds = this.settings.AnimationPlaybackRates.Select(rate => new AnimationSpeed {
                    Name = rate.ToString("G", System.Globalization.CultureInfo.InvariantCulture) + "×",
                    Rate = rate,
                }).ToArray();
                this.AnimationSpeedPicker.ItemsSource = speeds;
                this.AnimationSpeedPicker.SelectedItem = speeds.FirstOrDefault(
                    speed => speed.Rate == this.GetAnimationPlaybackRate());
            }
            finally {
                this.updatingPreviewControls = false;
            }
            this.UpdatePreviewOrientationToggle();
            this.UpdateNavigationGraphVisibility();
            this.ApplyPreviewLayout();
        }

        private void UpdateNavigationGraphVisibility() {
            var isVisible = this.settings.IsNavigationGraphVisible;
            this.NavigationGraphPanel.Visibility = isVisible ? Visibility.Visible : Visibility.Collapsed;
            // Маршрут занимает ту же рабочую область, что XAML, сценарий и настройки.
            // При закрытии графа восстанавливаем именно ранее выбранный режим редактора.
            this.MarkupEditor.Visibility = !isVisible && this.editorMode == EditorMode.Xaml
                ? Visibility.Visible : Visibility.Collapsed;
            this.ScenarioPanel.Visibility = !isVisible && this.editorMode == EditorMode.Scenario
                ? Visibility.Visible : Visibility.Collapsed;
            this.SettingsPanel.Visibility = !isVisible && this.editorMode == EditorMode.Settings
                ? Visibility.Visible : Visibility.Collapsed;
        }

        private double GetEditorPaneRatio() {
            return this.windowLayoutController.GetEditorPaneRatio(this.settings);
        }

        private void ApplyEditorPreviewSplit() {
            this.windowLayoutController.ApplyEditorPreviewSplit(this.settings);
        }

        private void UpdatePreviewOrientationToggle() {
            this.previewDeviceController.UpdateOrientation(this.settings, this.PortraitOrientationText, this.LandscapeOrientationText);
        }

        private void ApplyPreviewLayout() {
            this.previewDeviceController.Apply(this.settings, this.DeviceSurface, this.PreviewViewbox, this.ZoomText);
        }

        private double GetAnimationPlaybackRate() {
            return this.settings.AnimationPlaybackRate;
        }

        private void FitPreview() {
            if (this.previewDeviceController.Fit(this.settings, this.PreviewViewport, this.DeviceSurface, this.PreviewViewbox, this.ZoomText)) {
                this.SyncSettingsEditor();
                this.PersistSettings();
            }
        }

        private (int Width, int Height) GetPreviewSize() {
            return this.previewDeviceController.GetSize(this.settings);
        }

        private double GetPreviewScale() {
            return this.previewDeviceController.GetScale(this.settings);
        }

        private void SetPreviewScale(double scale) {
            this.previewDeviceController.SetScale(this.settings, scale, this.DeviceSurface, this.PreviewViewbox, this.ZoomText);
            this.SyncSettingsEditor();
            this.PersistSettings();
        }

        private string GetNativeApplicationPageName(string initialPage) {
            var pagePath = this.PagePicker.SelectedItem as string ?? this.markupPath;
            if (string.IsNullOrEmpty(pagePath)) {
                return initialPage;
            }
            return Path.GetFileNameWithoutExtension(pagePath);
        }

        private void RefreshScenarioNames() {
            this.updatingScenarioPicker = true;
            try {
                var previous = this.ScenarioPicker.SelectedItem as string;
                var previousPath = this.scenarioPath;
                var wasScenarioMode = this.editorMode == EditorMode.Scenario;
                this.scenarioController.Clear();
                this.ScenarioPicker.ItemsSource = null;
                this.ScenarioPicker.SelectedItem = null;
                this.ScenarioPicker.Visibility = Visibility.Collapsed;
                this.SaveScenarioToStorageButton.Visibility = Visibility.Collapsed;
                this.ScenarioLabel.Visibility = Visibility.Collapsed;
                var pagePath = this.GetSelectedPageMarkupPath();
                if (pagePath is null || !File.Exists(pagePath)) {
                    this.ClearScenarioMode();
                    return;
                }
                try {
                    var names = this.scenarioController.LoadForMarkup(pagePath);
                    if (names.Count == 0) {
                        this.ClearScenarioMode();
                        return;
                    }
                    var scenarioPath = this.scenarioPath;
                    this.ScenarioPicker.ItemsSource = new[] { MainWindow.NoScenarioName }.Concat(names).ToArray();
                    if (scenarioPath is not null
                        && this.activeScenarioPath is not null
                        && MainWindow.PathsAreEqual(this.activeScenarioPath, scenarioPath)
                        && this.activeScenarioName is not null
                        && names.Contains(this.activeScenarioName)) {
                        this.ScenarioPicker.SelectedItem = this.activeScenarioName;
                    } else if (previousPath is not null
                        && MainWindow.PathsAreEqual(previousPath, this.scenarioPath!)
                        && previous is not null
                        && this.ScenarioPicker.Items.Contains(previous)) {
                        this.ScenarioPicker.SelectedItem = previous;
                    } else if (scenarioPath is not null
                        && this.settings.SavedScenarioPath is not null
                        && MainWindow.PathsAreEqual(this.settings.SavedScenarioPath, scenarioPath)
                        && this.settings.SavedScenarioName is not null
                        && names.Contains(this.settings.SavedScenarioName)) {
                        this.ScenarioPicker.SelectedItem = this.settings.SavedScenarioName;
                    } else {
                        this.ScenarioPicker.SelectedItem = MainWindow.NoScenarioName;
                    }
                    this.ScenarioPicker.Visibility = Visibility.Visible;
                    this.SaveScenarioToStorageButton.Visibility = Visibility.Visible;
                    this.ScenarioLabel.Visibility = Visibility.Visible;
                    this.ScenarioButton.Visibility = Visibility.Visible;
                    this.ScenarioButton.IsChecked = wasScenarioMode;
                }
                catch (Exception exception) when (exception is IOException || exception is JsonException) {
                    this.ClearScenarioMode();
                    this.statusPresenter.Information($"Сценарии не загружены: {exception.Message}");
                }
            }
            finally {
                this.updatingScenarioPicker = false;
            }
        }

        private void ClearScenarioMode() {
            // У страницы может не быть сценариев. Это не причина пересоздавать
            // native-сессию: новая сессия всегда начинает с MainPage и отменяет
            // только что завершённую навигацию.
            this.ScenarioButton.Visibility = Visibility.Visible;
            this.ScenarioButton.IsChecked = false;
            if (this.editorMode == EditorMode.Scenario) {
                this.editorMode = EditorMode.Xaml;
                this.UpdateEditorMode();
            }
        }

        private string? GetSelectedScenarioJson() {
            if (this.scenarioPath is null
                || this.ScenarioPicker.SelectedItem is not string name
                || name == MainWindow.NoScenarioName) {
                return null;
            }
            return this.scenarioController.GetSelectedJson(name);
        }

        private void ShowNativeApplicationPreview(bool shouldLoadSelectedPage = false) {
            if (this.isClosing) {
                return;
            }
            if (!this.IsNativePluginAvailable) {
                this.statusPresenter.Information("Выберите native DLL приложения.");
                return;
            }
            try {
                var previewSize = this.GetPreviewSize();
                var isNewSession = this.nativeApplicationSession is null
                    || this.nativeApplicationSession.Width != previewSize.Width
                    || this.nativeApplicationSession.Height != previewSize.Height;
                if (isNewSession) {
                    this.previewController.StopAnimation();
                    this.deferredNavigationEditorPage = null;
                    var (session, _) = this.previewController.EnsureSession(
                        previewSize.Width,
                        previewSize.Height);
                    session.SetAnimationPlaybackRate(this.GetAnimationPlaybackRate());
                    session.ElementSelected += this.PreviewElementSelected;
                    session.RuntimeMarkupReloaded += this.SelectElementFromMarkupEditor;
                    session.InteractionCompleted += this.NativeApplicationInteractionCompleted;
                    this.previewLayer.Children.Clear();
                    this.previewLayer.Children.Add(session.Surface);
                    this.ApplyElementInspectionHighlightSettings();
                    this.navigationGraphController.SetGraph(session.NavigationGraph);
                }
                var nativeSession = this.nativeApplicationSession ?? throw new InvalidOperationException("Preview session was not created.");
                var targetPage = this.GetNativeApplicationPageName(nativeSession.InitialPage);
                var shouldLoadTargetPage = isNewSession || shouldLoadSelectedPage;
                if (isNewSession) {
                    this.pluginSessionController.LogInfo(
                        $"Preview startup: markup='{this.markupPath}', selected='{this.PagePicker.SelectedItem}', target='{targetPage}', native='{this.nativeApplicationSession.CurrentPage}'");
                }
                this.UpdateElementInspection();
                if (shouldLoadTargetPage) {
                    this.nativeApplicationSession.LoadPage(targetPage);
                    if (isNewSession) {
                        this.pluginSessionController.LogInfo($"Preview startup after initial load: native='{this.nativeApplicationSession.CurrentPage}'");
                    }
                }
                if (this.pendingPreviewRoute is { Count: > 0 } route) {
                    // SetGraph меняет PagePicker и может синхронно вызвать повторный preview.
                    // Маршрут уже должен быть снят с очереди до этого вызова.
                    this.pendingPreviewRoute = null;
                    this.pluginSessionController.LogInfo($"Preview graph dispatches native route: {string.Join('>', route)}");
                    this.nativeApplicationSession.NavigatePreviewRoute(route);
                    targetPage = this.nativeApplicationSession.CurrentPage;
                    shouldLoadTargetPage = false;
                    this.pluginSessionController.LogInfo($"Preview graph native route completed: {targetPage}");
                    this.navigationGraphController.SetGraph(this.nativeApplicationSession.NavigationGraph);
                }
                else {
                    this.pendingPreviewRoute = null;
                }
                var scenario = this.GetSelectedScenarioJson();
                if (scenario is not null) {
                    this.nativeApplicationSession.ApplyPreviewScenario(targetPage, scenario);
                }
                var pagePath = this.GetSelectedPageMarkupPath();
                if (pagePath is not null) {
                    this.nativeApplicationSession.LoadRuntimeMarkup(
                        targetPage, File.ReadAllText(pagePath), pagePath);
                }
                if (this.ControlPicker.ItemsSource is IEnumerable<MarkupNavigationTarget> controls) {
                    foreach (var control in controls.Where(control => control.Name != "Page")) {
                        this.nativeApplicationSession.LoadRuntimeMarkup(
                            targetPage, File.ReadAllText(control.Path), control.Path);
                    }
                }
                if (shouldLoadTargetPage) {
                    if (isNewSession) {
                        this.pluginSessionController.LogInfo($"Preview startup before final load: native='{this.nativeApplicationSession.CurrentPage}'");
                    }
                    this.nativeApplicationSession.LoadPage(targetPage);
                    if (isNewSession) {
                        this.pluginSessionController.LogInfo($"Preview startup after final load: native='{this.nativeApplicationSession.CurrentPage}'");
                    }
                }
                this.nativeApplicationSession.UpdateAndRender();
                this.SynchronizeNavigationGraph(this.nativeApplicationSession);
                this.UpdateSaveScenarioToStorageButtonState();
                this.previewController.StartAnimation();
                this.statusPresenter.Success($"Native app: {this.nativeApplicationSession.CurrentPage}");
            }
            catch (Exception exception) {
                this.ShowPreviewError(exception);
            }
        }

        private void PreviewViewportScrollChanged(object sender, ScrollChangedEventArgs eventArgs) {
            if (eventArgs.HorizontalChange == 0.0 && eventArgs.VerticalChange == 0.0) {
                return;
            }
            this.settings.PreviewHorizontalOffset = this.PreviewViewport.HorizontalOffset;
            this.settings.PreviewVerticalOffset = this.PreviewViewport.VerticalOffset;
            this.PersistSettings();
        }

        private void RestorePreviewPosition() {
            this.PreviewViewport.ScrollToHorizontalOffset(this.settings.PreviewHorizontalOffset);
            this.PreviewViewport.ScrollToVerticalOffset(this.settings.PreviewVerticalOffset);
        }

        private void ApplyEditorScale() {
            const double defaultFontSize = 14.0;
            var scale = this.GetEditorScale();
            foreach (var editor in new[] {
                this.MarkupEditor,
                this.ScenarioEditor,
                this.SettingsEditor,
            }) {
                editor.FontSize = defaultFontSize * scale;
            }
            this.markupEditorController.UpdateFoldingMarkerSize();
            this.EditorZoomText.Text = $"{scale:P0}";
        }

        private double GetEditorScale() {
            return Math.Clamp(
                this.settings.EditorScale > 0.0 ? this.settings.EditorScale : 1.0,
                0.5,
                3.0);
        }

        private void SetEditorScale(double scale) {
            this.settings.EditorScale = Math.Clamp(scale, 0.5, 3.0);
            this.ApplyEditorScale();
            this.SyncSettingsEditor();
            this.PersistSettings();
        }

        private void SyncSettingsEditor() {
            if (this.editorMode != EditorMode.Settings) {
                return;
            }

            this.updatingEditors = true;
            this.SettingsEditor.Text = this.settings.ToJson();
            this.updatingEditors = false;
            this.isSettingsDirty = false;
            this.UpdateDocumentState();
        }

        private static SearchPanel ConfigureEditor(TextEditor editor, IHighlightingDefinition highlighting) {
            editor.SyntaxHighlighting = highlighting;
            editor.Options.EnableHyperlinks = false;
            editor.Options.EnableEmailHyperlinks = false;
            editor.TextArea.Caret.CaretBrush = PreviewBrushes.Parse("#F0D78C");
            editor.TextArea.SelectionBrush = PreviewBrushes.Parse("#5A4D26");
            editor.TextArea.SelectionForeground = PreviewBrushes.Parse("#FFFFFF");
            var searchPanel = SearchPanel.Install(editor);
            searchPanel.Background = PreviewBrushes.Parse("#252525");
            searchPanel.BorderBrush = PreviewBrushes.Parse("#4A4A4A");
            searchPanel.Foreground = PreviewBrushes.Parse("#E6E6E6");
            searchPanel.MarkerBrush = PreviewBrushes.Parse("#665A4D26");
            searchPanel.MarkerPen = new Pen(PreviewBrushes.Parse("#D5BD7D"), 1.0);
            var messageField = typeof(SearchPanel).GetField("messageView", BindingFlags.Instance | BindingFlags.NonPublic);
            if (messageField?.GetValue(searchPanel) is ToolTip message) {
                message.Visibility = Visibility.Collapsed;
            }
            return searchPanel;
        }

        private void ConfigureMouseWheelScrolling() {
            this.editorScrollController.Configure(
                this.MarkupEditor,
                this.SettingsEditor,
                this.ScenarioEditor);
        }

        private void ScheduleRender() {
            if (this.isClosing) {
                return;
            }
            this.previewController.ScheduleRender();
        }
    }
}