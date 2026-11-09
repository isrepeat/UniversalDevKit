using System.Windows.Media;

namespace AndroidAppPreviewer {
    internal static class PreviewBrushes {
        public static Brush Parse(string value) {
            return PreviewBrushes.ParseBrush(value);
        }

        public static Brush ParseBrush(string value) {
            return new BrushConverter().ConvertFromInvariantString(value) as Brush
                ?? throw new InvalidOperationException($"Не удалось разобрать цвет: {value}");
        }
    }
}