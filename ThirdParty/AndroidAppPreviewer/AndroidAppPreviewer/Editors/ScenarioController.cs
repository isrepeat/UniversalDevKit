using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace AndroidAppPreviewer {
    internal sealed class ScenarioController {
        private const string ScenarioReferencePattern = "<\\?xaml-preview-scenario\\s+path=\\\"(?<path>[^\\\"]+)\\\"\\s*\\?>";

        public bool IsDirty { get; private set; }
        public string? Path { get; private set; }
        public string? PersistedText { get; private set; }

        public void Clear() {
            this.Path = null;
            this.PersistedText = null;
            this.IsDirty = false;
        }

        public IReadOnlyList<string> LoadForMarkup(string markupPath) {
            var match = Regex.Match(File.ReadAllText(markupPath), ScenarioReferencePattern, RegexOptions.CultureInvariant);
            if (!match.Success) {
                this.Clear();
                return [];
            }
            var path = System.IO.Path.GetFullPath(System.IO.Path.Combine(System.IO.Path.GetDirectoryName(markupPath)!, match.Groups["path"].Value));
            var text = File.ReadAllText(path);
            using var document = JsonDocument.Parse(text);
            if (document.RootElement.ValueKind != JsonValueKind.Object) {
                throw new JsonException("Корневой элемент должен быть объектом.");
            }
            this.Path = path;
            this.PersistedText = text;
            this.IsDirty = false;
            return document.RootElement.EnumerateObject().Select(property => property.Name).ToArray();
        }

        public void MarkDirty() {
            this.IsDirty = true;
        }

        public void Save(string text) {
            if (this.Path is null) {
                throw new InvalidOperationException("Scenario path is not selected.");
            }
            using var document = JsonDocument.Parse(text);
            if (document.RootElement.ValueKind != JsonValueKind.Object) {
                throw new JsonException("Корневой элемент должен быть объектом.");
            }
            File.WriteAllText(this.Path, text);
            this.PersistedText = text;
            this.IsDirty = false;
        }

        public bool HasExternalChanges() {
            return this.Path is not null
                && (!File.Exists(this.Path) || !string.Equals(File.ReadAllText(this.Path), this.PersistedText, StringComparison.Ordinal));
        }

        public string? GetSelectedJson(string? name) {
            if (this.Path is null || string.IsNullOrEmpty(name)) {
                return null;
            }
            using var document = JsonDocument.Parse(File.ReadAllText(this.Path));
            return document.RootElement.TryGetProperty(name, out var scenario) ? scenario.GetRawText() : null;
        }
    }
}