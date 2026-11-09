using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Controls;
using System.Windows.Threading;

namespace AndroidAppPreviewer {
    internal sealed class FolderPickerController {
        private readonly Grid panel;
        private readonly TextBox pathText;
        private readonly TextBlock errorText;
        private readonly ListBox entriesList;
        private readonly Button selectButton;
        private readonly Button backButton;
        private readonly Button forwardButton;
        private readonly Action<string> previewFile;
        private readonly Action clearPreview;
        private readonly Action<string, bool> report;
        private readonly List<HistoryEntry> history = [];
        private string? directory;
        private int historyIndex = -1;

        private sealed class Entry {
            public required string FullPath { get; init; }
            public required string Name { get; init; }
            public required bool IsDirectory { get; init; }

            public override string ToString() => this.IsDirectory ? $"📁  {this.Name}" : $"     {this.Name}";
        }

        private sealed class HistoryEntry {
            public required string DirectoryPath { get; init; }
            public string? SelectedEntryPath { get; set; }
        }

        public FolderPickerController(
            Grid panel,
            TextBox pathText,
            TextBlock errorText,
            ListBox entriesList,
            Button selectButton,
            Button backButton,
            Button forwardButton,
            Action<string> previewFile,
            Action clearPreview,
            Action<string, bool> report) {
            this.panel = panel;
            this.pathText = pathText;
            this.errorText = errorText;
            this.entriesList = entriesList;
            this.selectButton = selectButton;
            this.backButton = backButton;
            this.forwardButton = forwardButton;
            this.previewFile = previewFile;
            this.clearPreview = clearPreview;
            this.report = report;
        }

        public void Open(string initialDirectory) {
            this.history.Clear();
            this.historyIndex = -1;
            this.clearPreview();
            this.Navigate(initialDirectory, true);
            this.panel.Visibility = Visibility.Visible;
            this.entriesList.Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() => Keyboard.Focus(this.entriesList)));
        }

        public void Close() {
            this.panel.Visibility = Visibility.Collapsed;
            this.directory = null;
            this.history.Clear();
            this.historyIndex = -1;
        }

        public void Up() {
            if (this.directory is not null && Directory.GetParent(this.directory) is { } parent) {
                this.Navigate(parent.FullName, true, this.directory);
            }
        }

        public void Back() {
            if (this.historyIndex > 0) {
                --this.historyIndex;
                this.Navigate(this.history[this.historyIndex].DirectoryPath, false);
            }
        }

        public void Forward() {
            if (this.historyIndex < this.history.Count - 1) {
                ++this.historyIndex;
                this.Navigate(this.history[this.historyIndex].DirectoryPath, false);
            }
        }

        public void SubmitPath() => this.Navigate(this.pathText.Text, true);

        public void HandleListKey(KeyEventArgs eventArgs) {
            if (eventArgs.Key == Key.Escape) {
                this.entriesList.UnselectAll();
                this.clearPreview();
                eventArgs.Handled = true;
            } else if (eventArgs.Key == Key.Left || eventArgs.Key == Key.Back) {
                this.Up();
                eventArgs.Handled = true;
            } else if ((eventArgs.Key == Key.Right || eventArgs.Key == Key.Enter)
                && this.entriesList.SelectedItem is Entry { IsDirectory: true } entry) {
                this.Navigate(entry.FullPath, true);
                eventArgs.Handled = true;
            }
        }

        public void HandleListBackgroundMouseDown(DependencyObject? source) {
            if (ItemsControl.ContainerFromElement(this.entriesList, source) is null) {
                this.entriesList.UnselectAll();
                this.clearPreview();
            }
        }

        public void HandleListDoubleClick() {
            if (this.entriesList.SelectedItem is not Entry { IsDirectory: true } entry) {
                this.report("Для выбора доступны только папки.", false);
                return;
            }
            this.Navigate(entry.FullPath, true);
        }

        public void HandleSelectionChanged() {
            this.selectButton.IsEnabled = this.entriesList.SelectedItem is not Entry entry || entry.IsDirectory;
            if (this.entriesList.SelectedItem is Entry { IsDirectory: false } file) {
                this.previewFile(file.FullPath);
            } else {
                this.clearPreview();
            }
        }

        public bool TrySelectDirectory(out string selectedDirectory) {
            selectedDirectory = string.Empty;
            var selectedEntry = this.entriesList.SelectedItem as Entry;
            var candidate = selectedEntry?.IsDirectory == true ? selectedEntry.FullPath
                : this.entriesList.SelectedItem is null ? this.pathText.Text : null;
            if (candidate is null || !this.Navigate(candidate, false)) {
                return false;
            }
            selectedDirectory = this.directory!;
            return true;
        }

        private bool Navigate(string candidate, bool addToHistory, string? selectedEntryPath = null) {
            string path;
            try { path = Path.GetFullPath(candidate); }
            catch (Exception exception) when (exception is ArgumentException or NotSupportedException or PathTooLongException) {
                this.ShowError("Указан некорректный путь.");
                return false;
            }
            if (!Directory.Exists(path)) {
                this.ShowError("Папка не существует или недоступна.");
                return false;
            }
            if (addToHistory) { this.SaveSelection(); }
            this.directory = path;
            if (addToHistory) {
                if (this.historyIndex < this.history.Count - 1) { this.history.RemoveRange(this.historyIndex + 1, this.history.Count - this.historyIndex - 1); }
                this.history.Add(new HistoryEntry { DirectoryPath = path });
                this.historyIndex = this.history.Count - 1;
            }
            selectedEntryPath ??= this.historyIndex >= 0 ? this.history[this.historyIndex].SelectedEntryPath : null;
            this.RefreshEntries(selectedEntryPath);
            this.backButton.IsEnabled = this.historyIndex > 0;
            this.forwardButton.IsEnabled = this.historyIndex < this.history.Count - 1;
            return true;
        }

        private void RefreshEntries(string? selectedEntryPath) {
            this.pathText.Text = this.directory!;
            this.errorText.Text = string.Empty;
            var entries = Directory.EnumerateDirectories(this.directory!).Order().Select(path => new Entry { FullPath = path, Name = Path.GetFileName(path), IsDirectory = true })
                .Concat(Directory.EnumerateFiles(this.directory!, "*.xaml").Order().Select(path => new Entry { FullPath = path, Name = Path.GetFileName(path), IsDirectory = false })).ToArray();
            this.entriesList.ItemsSource = entries;
            this.entriesList.SelectedItem = selectedEntryPath is null ? null : entries.FirstOrDefault(entry => string.Equals(entry.FullPath, selectedEntryPath, StringComparison.OrdinalIgnoreCase));
            if (this.entriesList.SelectedItem is Entry entry) {
                this.entriesList.Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() => {
                    this.entriesList.ScrollIntoView(entry);
                    if (this.entriesList.ItemContainerGenerator.ContainerFromItem(entry) is ListBoxItem item) {
                        Keyboard.Focus(item);
                    } else {
                        Keyboard.Focus(this.entriesList);
                    }
                }));
            }
            this.HandleSelectionChanged();
        }

        private void SaveSelection() {
            if (this.historyIndex >= 0 && this.historyIndex < this.history.Count) {
                this.history[this.historyIndex].SelectedEntryPath = (this.entriesList.SelectedItem as Entry)?.FullPath;
            }
        }

        private void ShowError(string message) {
            this.errorText.Text = message;
            this.report(message, false);
        }
    }
}