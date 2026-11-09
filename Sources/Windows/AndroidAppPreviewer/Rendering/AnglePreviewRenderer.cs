using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AndroidAppPreviewer {
    internal sealed class AnglePreviewRenderer : IDisposable {
        private IntPtr surface;

        public int Height { get; }
        public int Width { get; }

        public AnglePreviewRenderer(string markupDirectory, int width, int height) {
            this.Width = width;
            this.Height = height;
            this.surface = AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Rendering.xp_create_angle_surface(
                this.Width,
                this.Height,
                AnglePreviewRenderer.GetPreviewRendererRegularFontPath(),
                markupDirectory);
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(this.surface != IntPtr.Zero);
        }

        public BitmapSource Render(IntPtr root) {
            const int bytesPerPixel = 4;
            var stride = this.Width * bytesPerPixel;
            var pixels = new byte[stride * this.Height];
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Rendering.xp_render_angle_surface(
                this.surface,
                root,
                pixels,
                stride,
                pixels.Length) != 0);
            var bitmap = BitmapSource.Create(
                this.Width,
                this.Height,
                96,
                96,
                PixelFormats.Pbgra32,
                null,
                pixels,
                stride);
            bitmap.Freeze();
            return bitmap;
        }

        public BitmapSource RenderNativeSession(IntPtr session) {
            const int bytesPerPixel = 4;
            var stride = this.Width * bytesPerPixel;
            var pixels = new byte[stride * this.Height];
            AndroidAppPreviewerPluginSDK.NativeRuntime.ThrowIfFalse(AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Session.xp_session_render_angle_surface(
                session,
                this.surface,
                pixels,
                stride,
                pixels.Length) != 0);
            var bitmap = BitmapSource.Create(this.Width, this.Height, 96, 96, PixelFormats.Pbgra32, null, pixels, stride);
            bitmap.Freeze();
            return bitmap;
        }

        public void Dispose() {
            if (this.surface == IntPtr.Zero) {
                return;
            }
            AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Rendering.xp_destroy_angle_surface(this.surface);
            this.surface = IntPtr.Zero;
        }

        private static string GetPreviewRendererRegularFontPath() {
            var fontsDirectory = Path.Combine(AppContext.BaseDirectory, "Fonts");
            var fontNames = new[] {
                "Roboto-Regular.ttf",
                "Roboto-Bold.ttf",
                "Roboto-Black.ttf",
            };
            foreach (var fontName in fontNames) {
                var fontPath = Path.Combine(fontsDirectory, fontName);
                if (!File.Exists(fontPath)) {
                    throw new FileNotFoundException($"Не найден шрифт previewer: {fontPath}");
                }
            }

            return Path.Combine(fontsDirectory, fontNames[0]);
        }
    }
}