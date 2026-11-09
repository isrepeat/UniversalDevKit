using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Input;
using System.Windows.Interop;

using Microsoft.Win32.SafeHandles;

namespace AndroidAppPreviewer {
    internal sealed class PreviewCursorSet : IDisposable {
        private readonly List<CursorHandle> handles = [];

        public PreviewCursorSet() {
            var directory = Path.Combine(AppContext.BaseDirectory, "Resources", "Cursors");
            this.Tap = this.Create(Path.Combine(directory, "tap.png"), 26, new Point(13, 4));
            this.TapPressed = this.Create(Path.Combine(directory, "tap_pressed.png"), 26, new Point(13, 4));
            this.Grab = this.Create(Path.Combine(directory, "grab.png"), 24, new Point(11, 11));
            this.Grabbing = this.Create(Path.Combine(directory, "grabbing.png"), 24, new Point(11, 11));
        }

        public Cursor Tap { get; }
        public Cursor TapPressed { get; }
        public Cursor Grab { get; }
        public Cursor Grabbing { get; }

        public void Dispose() {
            foreach (var handle in this.handles) {
                handle.Dispose();
            }
            this.handles.Clear();
        }

        private Cursor Create(string path, int size, Point hotspot) {
            using var source = new Bitmap(path);
            using var image = new Bitmap(size, size, PixelFormat.Format32bppArgb);
            using var graphics = Graphics.FromImage(image);
            graphics.Clear(Color.Transparent);
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.DrawImage(source, new Rectangle(Point.Empty, image.Size));
            var icon = image.GetHicon();
            try {
                if (!GetIconInfo(icon, out var iconInfo)) {
                    throw new InvalidOperationException("Не удалось прочитать изображение курсора.");
                }
                try {
                    iconInfo.IsIcon = false;
                    iconInfo.HotspotX = (uint)hotspot.X;
                    iconInfo.HotspotY = (uint)hotspot.Y;
                    var cursor = CreateIconIndirect(ref iconInfo);
                    if (cursor == IntPtr.Zero) {
                        throw new InvalidOperationException("Не удалось создать курсор.");
                    }
                    var handle = new CursorHandle(cursor);
                    this.handles.Add(handle);
                    return CursorInteropHelper.Create(handle);
                } finally {
                    DeleteObject(iconInfo.MaskBitmap);
                    DeleteObject(iconInfo.ColorBitmap);
                }
            } finally {
                DestroyIcon(icon);
            }
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr CreateIconIndirect(ref IconInfo iconInfo);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetIconInfo(IntPtr icon, out IconInfo iconInfo);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DestroyIcon(IntPtr icon);

        [DllImport("gdi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DeleteObject(IntPtr handle);

        [StructLayout(LayoutKind.Sequential)]
        private struct IconInfo {
            [MarshalAs(UnmanagedType.Bool)]
            public bool IsIcon;
            public uint HotspotX;
            public uint HotspotY;
            public IntPtr MaskBitmap;
            public IntPtr ColorBitmap;
        }

        private sealed class CursorHandle : SafeHandleZeroOrMinusOneIsInvalid {
            public CursorHandle(IntPtr handle) : base(true) {
                this.SetHandle(handle);
            }

            protected override bool ReleaseHandle() {
                return DestroyIcon(this.handle);
            }
        }
    }
}