using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Encodings.Web;

namespace AndroidAppPreviewer {
    internal sealed class DevicePreset {
        public required string Name { get; init; }
        public required int Width { get; init; }
        public required int Height { get; init; }

        public override string ToString() {
            return $"{this.Name} · {this.Width}×{this.Height}";
        }
    }

    internal sealed class ElementInspectionWireframeSettings {
        public string LineColor { get; set; } = "#E05252";
        public double LineThickness { get; set; } = 3.0;
        public string LineStyle { get; set; } = "solid";
        public string MarginColor { get; set; } = "#6F4B72";
        public string PaddingColor { get; set; } = "#5E4289DE";
    }

    internal sealed class PreviewerSettings {
        private static readonly JsonSerializerOptions JsonOptions = new() {
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            WriteIndented = true
        };

        public string XamlDirectory { get; set; } = string.Empty;
        public string ResourcesDirectory { get; set; } = string.Empty;
        public string ControlsDirectory { get; set; } = string.Empty;
        public string PreviewPluginPath { get; set; } = string.Empty;
        public string? SavedScenarioPath { get; set; }
        public string? SavedScenarioName { get; set; }
        public string? LastMarkupPath { get; set; }
        public Dictionary<string, int[]> CollapsedMarkupFoldingOffsets { get; set; } = [];
        public double WindowWidth { get; set; }
        public double WindowHeight { get; set; }
        public bool IsMaximized { get; set; }
        public double EditorPaneRatio { get; set; } = 0.5;
        public double NavigationGraphPaneWidth { get; set; } = 430.0;
        public double EditorScale { get; set; } = 1.0;
        public int MouseWheelLines { get; set; } = 6;
        public double MouseWheelAnimationDurationMilliseconds { get; set; } = 400.0;
        public string MouseWheelSmoothingMode { get; set; } = "Exponential";
        public int PreviewWidth { get; set; } = 720;
        public int PreviewHeight { get; set; } = 1600;
        public double PreviewScale { get; set; }
        public double PreviewHorizontalOffset { get; set; }
        public double PreviewVerticalOffset { get; set; }
        public bool IsNavigationGraphVisible { get; set; }
        public bool IsPreviewLandscape { get; set; }
        public double AnimationPlaybackRate { get; set; } = 1.0;
        public double[] AnimationPlaybackRates { get; set; } = [0.1, 0.25, 0.5, 1.0, 2.0, 4.0];
        public ElementInspectionWireframeSettings HoveredElementInspectionWireframe { get; set; } = new();
        public ElementInspectionWireframeSettings ActiveElementInspectionWireframe { get; set; } = new() {
            LineColor = "#4DA3FF",
        };
        public DevicePreset[] PreviewResolutions { get; set; } = [
            new() { Name = "Redmi 15C", Width = 720, Height = 1600 },
            new() { Name = "HD+", Width = 720, Height = 1280 },
            new() { Name = "FHD+", Width = 1080, Height = 2400 },
            new() { Name = "QHD+", Width = 1440, Height = 3200 },
        ];

        [JsonIgnore]
        public string FilePath { get; private set; } = string.Empty;

        [JsonIgnore]
        public bool IsFirstLaunch { get; private set; }

        public static PreviewerSettings LoadDebug() {
            var settingsPath = Path.Combine(AppContext.BaseDirectory, "previewer.settings.json");
            PreviewerSettings settings;
            if (File.Exists(settingsPath)) {
                settings = JsonSerializer.Deserialize<PreviewerSettings>(File.ReadAllText(settingsPath))
                    ?? CreateDefaults(settingsPath);
                settings.FilePath = settingsPath;
            } else {
                settings = CreateDefaults(settingsPath);
                settings.IsFirstLaunch = true;
                settings.Save();
            }
            settings.CollapsedMarkupFoldingOffsets ??= [];
            settings.ValidateAnimationSpeeds();
            settings.ValidateResolutions();
            settings.ValidateElementInspectionHighlight();
            return settings;
        }

        public static PreviewerSettings Parse(string json, string filePath) {
            var settings = JsonSerializer.Deserialize<PreviewerSettings>(json)
                ?? throw new InvalidDataException("Настройки не содержат объект.");
            settings.FilePath = filePath;
            settings.CollapsedMarkupFoldingOffsets ??= [];
            settings.ValidateAnimationSpeeds();
            settings.ValidateResolutions();
            settings.ValidateElementInspectionHighlight();
            return settings;
        }

        private void ValidateResolutions() {
            if (this.PreviewResolutions is null || this.PreviewResolutions.Length == 0
                || this.PreviewResolutions.Any(preset => preset is null || string.IsNullOrWhiteSpace(preset.Name)
                    || preset.Width <= 0 || preset.Height <= 0)) {
                throw new InvalidDataException("PreviewResolutions должен содержать названия и положительные размеры экранов.");
            }
        }

        private void ValidateAnimationSpeeds() {
            if (this.AnimationPlaybackRates is null || this.AnimationPlaybackRates.Length == 0
                || this.AnimationPlaybackRates.Any(rate => !float.IsFinite((float)rate) || (float)rate <= 0)) {
                throw new InvalidDataException("AnimationPlaybackRates должен содержать положительные конечные скорости.");
            }
            this.AnimationPlaybackRates = this.AnimationPlaybackRates.Distinct().ToArray();
            if (!this.AnimationPlaybackRates.Contains(this.AnimationPlaybackRate)) {
                this.AnimationPlaybackRate = this.AnimationPlaybackRates[0];
            }
        }

        private void ValidateElementInspectionHighlight() {
            ValidateElementInspectionWireframe(
                this.HoveredElementInspectionWireframe,
                nameof(this.HoveredElementInspectionWireframe));
            ValidateElementInspectionWireframe(
                this.ActiveElementInspectionWireframe,
                nameof(this.ActiveElementInspectionWireframe));
        }

        private static void ValidateElementInspectionWireframe(ElementInspectionWireframeSettings? wireframe, string name) {
            if (wireframe is null) {
                throw new InvalidDataException($"{name} должен содержать объект настроек.");
            }
            ValidateColor(wireframe.LineColor, $"{name}.LineColor");
            ValidateColor(wireframe.MarginColor, $"{name}.MarginColor");
            ValidateColor(wireframe.PaddingColor, $"{name}.PaddingColor");
            if (!double.IsFinite(wireframe.LineThickness) || wireframe.LineThickness <= 0.0) {
                throw new InvalidDataException($"{name}.LineThickness должен быть положительным конечным числом.");
            }
            if (wireframe.LineStyle is not "solid" and not "dashed") {
                throw new InvalidDataException($"{name}.LineStyle должен быть solid или dashed.");
            }
        }

        private static void ValidateColor(string? color, string name) {
            if (string.IsNullOrWhiteSpace(color)) {
                throw new InvalidDataException($"{name} должен содержать цвет.");
            }
            try {
                _ = PreviewBrushes.Parse(color);
            }
            catch (Exception exception) {
                throw new InvalidDataException($"{name} содержит некорректный цвет.", exception);
            }
        }

        public void Save() {
            File.WriteAllText(this.FilePath, this.ToJson());
        }

        public string ToJson() {
            return JsonSerializer.Serialize(this, JsonOptions).TrimEnd();
        }

        private static PreviewerSettings CreateDefaults(string settingsPath) {
            return new PreviewerSettings {
                FilePath = settingsPath,
            };
        }
    }
}