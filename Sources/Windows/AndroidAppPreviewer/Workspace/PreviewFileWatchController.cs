using System.IO;
using System.Windows.Threading;

namespace AndroidAppPreviewer {
    internal sealed class PreviewFileWatchController : IDisposable {
        private readonly Dispatcher dispatcher;
        private readonly DispatcherTimer refreshTimer;
        private readonly Action refresh;
        private FileSystemWatcher? markupWatcher;
        private FileSystemWatcher? scenarioWatcher;
        private FileSystemWatcher? xamlDirectoryWatcher;
        private FileSystemWatcher? settingsWatcher;
        private FileSystemWatcher? controlsWatcher;
        private bool isDisposed;

        public PreviewFileWatchController(Dispatcher dispatcher, Action refresh) {
            this.dispatcher = dispatcher;
            this.refresh = refresh;
            this.refreshTimer = new DispatcherTimer {
                Interval = TimeSpan.FromMilliseconds(200)
            };
            this.refreshTimer.Tick += this.RefreshTimerTick;
        }

        public void Configure(string? markupPath, string? scenarioPath, string settingsPath, string xamlDirectory, string controlsDirectory) {
            this.ReplaceWatcher(ref this.markupWatcher, this.CreateFileWatcher(markupPath));
            this.ReplaceWatcher(ref this.scenarioWatcher, this.CreateFileWatcher(scenarioPath));
            this.ReplaceWatcher(ref this.settingsWatcher, this.CreateFileWatcher(settingsPath));
            this.ReplaceWatcher(ref this.xamlDirectoryWatcher, this.CreateDirectoryWatcher(xamlDirectory));
            this.ReplaceWatcher(ref this.controlsWatcher, this.CreateDirectoryWatcher(controlsDirectory));
        }

        public void Dispose() {
            if (this.isDisposed) {
                return;
            }
            this.isDisposed = true;
            this.refreshTimer.Stop();
            this.DisposeWatcher(ref this.markupWatcher);
            this.DisposeWatcher(ref this.scenarioWatcher);
            this.DisposeWatcher(ref this.xamlDirectoryWatcher);
            this.DisposeWatcher(ref this.settingsWatcher);
            this.DisposeWatcher(ref this.controlsWatcher);
        }

        private void ReplaceWatcher(ref FileSystemWatcher? target, FileSystemWatcher? replacement) {
            this.DisposeWatcher(ref target);
            target = replacement;
        }

        private void DisposeWatcher(ref FileSystemWatcher? watcher) {
            watcher?.Dispose();
            watcher = null;
        }

        private FileSystemWatcher? CreateFileWatcher(string? path) {
            if (string.IsNullOrEmpty(path)) {
                return null;
            }
            var directory = Path.GetDirectoryName(path);
            var fileName = Path.GetFileName(path);
            if (string.IsNullOrEmpty(directory) || string.IsNullOrEmpty(fileName) || !Directory.Exists(directory)) {
                return null;
            }
            var watcher = new FileSystemWatcher(directory, fileName) {
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName,
                EnableRaisingEvents = true,
            };
            watcher.Changed += this.FileChanged;
            watcher.Created += this.FileChanged;
            watcher.Renamed += this.FileRenamed;
            return watcher;
        }

        private FileSystemWatcher? CreateDirectoryWatcher(string directory) {
            if (!Directory.Exists(directory)) {
                return null;
            }
            var watcher = new FileSystemWatcher(directory, "*.xaml") {
                IncludeSubdirectories = true,
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite,
                EnableRaisingEvents = true,
            };
            watcher.Created += this.FileChanged;
            watcher.Changed += this.FileChanged;
            watcher.Deleted += this.FileChanged;
            watcher.Renamed += this.FileRenamed;
            return watcher;
        }

        private void FileChanged(object sender, FileSystemEventArgs eventArgs) {
            this.dispatcher.BeginInvoke(this.QueueRefresh);
        }

        private void FileRenamed(object sender, RenamedEventArgs eventArgs) {
            this.dispatcher.BeginInvoke(this.QueueRefresh);
        }

        private void QueueRefresh() {
            if (this.isDisposed) {
                return;
            }
            this.refreshTimer.Stop();
            this.refreshTimer.Start();
        }

        private void RefreshTimerTick(object? sender, EventArgs eventArgs) {
            this.refreshTimer.Stop();
            if (!this.isDisposed) {
                this.refresh();
            }
        }
    }
}