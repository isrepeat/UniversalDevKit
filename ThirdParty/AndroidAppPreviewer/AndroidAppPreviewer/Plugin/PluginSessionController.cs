using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows;

namespace AndroidAppPreviewer {
    internal sealed record PreviewPluginInfo(
        string ApplicationId,
        string DisplayName,
        string ResourcesDirectory,
        string SourceMarkupDirectory,
        string SourceEntryMarkupPath,
        string SourceControlsDirectory);

    internal sealed class PluginSessionController : IDisposable {
        private NativePreviewSession? session;
        private string? pluginPath;

        public bool IsAvailable => this.pluginPath is not null;
        public PreviewPluginInfo? Info { get; private set; }
        public string? PluginPath => this.pluginPath;
        public NativePreviewSession? Session => this.session;

        public Exception? Initialize(string? path) {
            if (string.IsNullOrWhiteSpace(path)) {
                return null;
            }
            try {
                AndroidAppPreviewerPluginSDK.NativeRuntime.ConfigurePlugin(path);
                AndroidAppPreviewerPluginSDK.NativeRuntime.Abi.EnsurePluginCompatibility();
                this.pluginPath = Path.GetFullPath(path);
                this.Info = this.ReadPluginInfo();
                AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Logging.xp_configure_logging(Path.Combine(AppContext.BaseDirectory, "android-app-previewer.log"));
                return null;
            } catch (Exception exception) {
                this.Reset();
                this.pluginPath = null;
                this.Info = null;
                return exception;
            }
        }

        public NativePreviewSession CreateSession(int width, int height) {
            if (!this.IsAvailable || this.Info is null) {
                throw new InvalidOperationException("Native plugin is not loaded.");
            }
            this.Reset();
            this.session = new NativePreviewSession(this.Info.ResourcesDirectory, width, height);
            return this.session;
        }

        public string? PickPlugin(Window owner) {
            var dialog = new Microsoft.Win32.OpenFileDialog {
                Filter = "Android App Previewer plugin (*.dll)|*.dll|Dynamic libraries (*.dll)|*.dll",
                Title = "Выберите native DLL приложения",
            };
            return dialog.ShowDialog(owner) == true ? dialog.FileName : null;
        }

        public void LogInfo(string message) {
            if (this.IsAvailable) {
                AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Logging.xp_log_info(message);
            }
        }

        public void Reset() {
            this.session?.Dispose();
            this.session = null;
        }

        public void Dispose() {
            this.Reset();
        }

        private PreviewPluginInfo ReadPluginInfo() {
            using var document = JsonDocument.Parse(AndroidAppPreviewerPluginSDK.NativeRuntime.Metadata.GetPluginInfo());
            var root = document.RootElement;
            var applicationId = root.GetProperty("applicationId").GetString();
            var displayName = root.GetProperty("displayName").GetString();
            var relativeResourcesDirectory = root.GetProperty("resourceRootRelativePath").GetString();
            var sourceMarkupDirectory = root.GetProperty("sourceMarkupDirectory").GetString();
            var sourceEntryMarkupPath = root.GetProperty("sourceEntryMarkupPath").GetString();
            var sourceControlsDirectory = root.GetProperty("sourceControlsDirectory").GetString();
            if (string.IsNullOrWhiteSpace(applicationId)
                || string.IsNullOrWhiteSpace(displayName)
                || string.IsNullOrWhiteSpace(relativeResourcesDirectory)
                || Path.IsPathRooted(relativeResourcesDirectory)
                || string.IsNullOrWhiteSpace(sourceMarkupDirectory)
                || string.IsNullOrWhiteSpace(sourceEntryMarkupPath)
                || string.IsNullOrWhiteSpace(sourceControlsDirectory)
                || !Path.IsPathRooted(sourceMarkupDirectory)
                || !Path.IsPathRooted(sourceEntryMarkupPath)
                || !Path.IsPathRooted(sourceControlsDirectory)) {
                throw new InvalidDataException("Preview-plugin вернул некорректное описание пакета.");
            }
            var pluginDirectory = Path.GetDirectoryName(this.pluginPath)
                ?? throw new InvalidOperationException("Не удалось определить каталог preview-plugin.");
            var resourcesDirectory = Path.GetFullPath(Path.Combine(pluginDirectory, relativeResourcesDirectory));
            var pluginDirectoryWithSeparator = Path.EndsInDirectorySeparator(pluginDirectory)
                ? pluginDirectory
                : pluginDirectory + Path.DirectorySeparatorChar;
            if (!resourcesDirectory.StartsWith(pluginDirectoryWithSeparator, StringComparison.OrdinalIgnoreCase)
                || !Directory.Exists(resourcesDirectory)) {
                throw new DirectoryNotFoundException(
                    $"Preview-plugin требует каталог ресурсов '{relativeResourcesDirectory}' рядом с DLL.");
            }
            var fullSourceMarkupDirectory = Path.GetFullPath(sourceMarkupDirectory);
            var fullSourceEntryMarkupPath = Path.GetFullPath(sourceEntryMarkupPath);
            var fullSourceControlsDirectory = Path.GetFullPath(sourceControlsDirectory);
            var sourceMarkupDirectoryWithSeparator = Path.EndsInDirectorySeparator(fullSourceMarkupDirectory)
                ? fullSourceMarkupDirectory
                : fullSourceMarkupDirectory + Path.DirectorySeparatorChar;
            if (!Directory.Exists(fullSourceMarkupDirectory)
                || !File.Exists(fullSourceEntryMarkupPath)
                || !Directory.Exists(fullSourceControlsDirectory)
                || !fullSourceEntryMarkupPath.StartsWith(sourceMarkupDirectoryWithSeparator, StringComparison.OrdinalIgnoreCase)) {
                throw new DirectoryNotFoundException(
                    "Preview-plugin требует доступные исходники XAML, стартовую страницу и каталог контролов.");
            }
            return new PreviewPluginInfo(
                applicationId,
                displayName,
                resourcesDirectory,
                fullSourceMarkupDirectory,
                fullSourceEntryMarkupPath,
                fullSourceControlsDirectory);
        }
    }
}