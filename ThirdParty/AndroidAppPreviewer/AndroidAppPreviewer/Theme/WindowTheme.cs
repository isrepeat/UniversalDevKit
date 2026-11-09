using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace AndroidAppPreviewer {
    internal static class WindowTheme {
        private const int UseImmersiveDarkMode = 20;
        private const int UseImmersiveDarkModeBeforeWindows10Version2004 = 19;
        private const int CaptionColor = 35;
        private const int TextColor = 36;
        private const int DefaultColor = -1;
        private const int WarningCaptionColor = 0x002A2AAA;
        private const int WhiteColor = 0x00FFFFFF;

        public static void EnableDarkTitleBar(Window window) {
            window.SourceInitialized += (_, _) => {
                var value = 1;
                var windowHandle = new WindowInteropHelper(window).Handle;
                if (WindowTheme.DwmSetWindowAttribute(
                    windowHandle,
                    UseImmersiveDarkMode,
                    ref value,
                    sizeof(int)) != 0) {
                    WindowTheme.DwmSetWindowAttribute(
                        windowHandle,
                        UseImmersiveDarkModeBeforeWindows10Version2004,
                        ref value,
                        sizeof(int));
                }
            };
        }

        public static void SetTitleBarWarning(Window window, bool isWarning) {
            var windowHandle = new WindowInteropHelper(window).Handle;
            var captionColor = isWarning ? WarningCaptionColor : DefaultColor;
            var textColor = isWarning ? WhiteColor : DefaultColor;
            WindowTheme.DwmSetWindowAttribute(
                windowHandle,
                CaptionColor,
                ref captionColor,
                sizeof(int));
            WindowTheme.DwmSetWindowAttribute(
                windowHandle,
                TextColor,
                ref textColor,
                sizeof(int));
        }

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(
            IntPtr windowHandle,
            int attribute,
            ref int value,
            int valueSize);
    }
}