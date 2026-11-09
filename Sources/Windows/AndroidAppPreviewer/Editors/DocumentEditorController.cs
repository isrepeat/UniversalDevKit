using System.IO;

namespace AndroidAppPreviewer {
    internal sealed class DocumentEditorController {
        public bool IsDirty { get; private set; }
        public string? Path { get; private set; }
        public string? PersistedText { get; private set; }

        public string Load(string path) {
            this.Path = System.IO.Path.GetFullPath(path);
            var text = File.ReadAllText(this.Path);
            this.AcceptPersistedText(text);
            return text;
        }

        public void MarkDirty() {
            this.IsDirty = true;
        }

        public void AcceptPersistedText(string text) {
            this.PersistedText = text;
            this.IsDirty = false;
        }

        public bool HasExternalChanges() {
            return this.Path is not null
                && this.PersistedText is not null
                && (!File.Exists(this.Path) || !string.Equals(File.ReadAllText(this.Path), this.PersistedText, StringComparison.Ordinal));
        }

        public bool Save(string text, Func<bool> confirmOverwrite) {
            if (this.Path is null) {
                return false;
            }
            if (this.IsDirty && this.HasExternalChanges() && !confirmOverwrite()) {
                return false;
            }
            File.WriteAllText(this.Path, text);
            this.AcceptPersistedText(text);
            return true;
        }
    }
}