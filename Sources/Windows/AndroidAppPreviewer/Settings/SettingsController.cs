namespace AndroidAppPreviewer {
    internal sealed class SettingsController {
        private PreviewerSettings settings = null!;

        public PreviewerSettings Value => this.settings;

        public void Load() {
            this.settings = PreviewerSettings.LoadDebug();
        }

        public void Replace(string json) {
            this.settings = PreviewerSettings.Parse(json, this.settings.FilePath);
        }

        public void Save() {
            this.settings.Save();
        }
    }
}