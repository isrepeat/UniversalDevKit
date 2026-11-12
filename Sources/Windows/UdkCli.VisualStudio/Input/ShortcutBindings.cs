using System;

using Microsoft.VisualStudio;
using Microsoft.VisualStudio.OLE.Interop;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace UniversalDevKit.UdkCli.VisualStudio.Input {
    internal static class ShortcutBindings {
        internal static readonly IntPtr VirtualKeyR = new IntPtr(0x52);

        public static bool IsReserved(IVsFilterKeys2 filterKeys, MSG message) {
            ThreadHelper.ThrowIfNotOnUIThread();
            if (IsMapped(filterKeys, message)) {
                return true;
            }
            if (message.wParam == VirtualKeyR) {
                return false;
            }
            message.wParam = VirtualKeyR;
            return IsMapped(filterKeys, message);
        }

        private static bool IsMapped(IVsFilterKeys2 filterKeys, MSG message) {
            ThreadHelper.ThrowIfNotOnUIThread();
            var result = filterKeys.TranslateAcceleratorEx(
                new[] { message },
                (uint)__VSTRANSACCELEXFLAGS.VSTAEXF_NoFireCommand,
                0,
                Array.Empty<Guid>(),
                out _,
                out _,
                out var translated,
                out var startsChord
            );
            return result != VSConstants.S_FALSE || translated != 0 || startsChord != 0;
        }
    }
}