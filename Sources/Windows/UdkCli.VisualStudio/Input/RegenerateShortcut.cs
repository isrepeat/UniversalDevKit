using System;
using System.Threading.Tasks;
using System.Runtime.InteropServices;

using Microsoft.VisualStudio;
using Microsoft.VisualStudio.OLE.Interop;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace UniversalDevKit.UdkCli.VisualStudio.Input {
    internal sealed class RegenerateShortcut : IDisposable {
        private const int GetMessageHook = 3;
        private const int RemoveMessage = 1;
        private const int NullMessage = 0;
        private const int KeyDown = 0x0100;
        private const int SystemKeyDown = 0x0104;
        private const int RScanCode = 0x13;
        private const int ExtendedKey = 1 << 24;
        private const int PreviousKeyState = 1 << 30;
        private const int Control = 0x11;
        private const int RightControl = 0xA3;
        private const int LeftAlt = 0xA4;
        private const int RightAlt = 0xA5;
        private const int Shift = 0x10;
        private const int LeftWindows = 0x5B;
        private const int RightWindows = 0x5C;
        private const uint RootOwner = 3;
        private static readonly Guid SolutionExists = new Guid(VSConstants.UICONTEXT.SolutionExists_string);
        private static readonly int MessageIdOffset = Marshal.OffsetOf<MSG>(nameof(MSG.message)).ToInt32();

        private readonly AsyncPackage package;
        private readonly OleMenuCommand command;
        private readonly IVsFilterKeys2 filterKeys;
        private readonly IVsUIShell uiShell;
        private readonly HookProcedure hookProcedure;
        private IntPtr hook;

        public RegenerateShortcut(AsyncPackage package, OleMenuCommand command, IVsFilterKeys2 filterKeys, IVsUIShell uiShell) {
            ThreadHelper.ThrowIfNotOnUIThread();
            this.package = package;
            this.command = command;
            this.filterKeys = filterKeys;
            this.uiShell = uiShell;
            this.hookProcedure = this.OnMessage;
            this.hook = SetWindowsHookEx(GetMessageHook, this.hookProcedure, IntPtr.Zero, GetCurrentThreadId());
            if (this.hook == IntPtr.Zero) {
                var message = $"Could not attach the shortcut handler: {Marshal.GetLastWin32Error()}.";
                if (VsShell.VsixLog.IsInitialized) {
                    Diagnostic.Log.Write(Diagnostic.Level.Warning, VsShell.VsixLog.Category, message);
                } else {
                    ActivityLog.LogWarning(VsShell.VsixLog.Category, message);
                }
            }
        }

        public void Dispose() {
            if (this.hook != IntPtr.Zero && UnhookWindowsHookEx(this.hook)) {
                this.hook = IntPtr.Zero;
            }
        }

        private IntPtr OnMessage(int code, IntPtr operation, IntPtr address) {
            var result = CallNextHookEx(IntPtr.Zero, code, operation, address);
            if (code < 0 || operation.ToInt64() != RemoveMessage || this.package.DisposalToken.IsCancellationRequested) {
                return result;
            }

            var message = Marshal.PtrToStructure<MSG>(address);
            var keyData = message.lParam.ToInt64();
            var scanCode = (keyData >> 16) & 0xFF;
            // Синтетические нажатия могут приходить без скан-кода.
            if ((message.message != KeyDown && message.message != SystemKeyDown) ||
                (scanCode != RScanCode && (scanCode != 0 || message.wParam != ShortcutBindings.VirtualKeyR)) ||
                (keyData & ExtendedKey) != 0 ||
                !IsControlAltDown() ||
                IsDown(Shift) || IsDown(LeftWindows) || IsDown(RightWindows)) {
                return result;
            }

            try {
                ThreadHelper.ThrowIfNotOnUIThread();
                if (!UIContext.FromUIContextGuid(SolutionExists).IsActive || ErrorHandler.Failed(this.uiShell.GetDialogOwnerHwnd(out var owner)) ||
                    owner == IntPtr.Zero || GetAncestor(message.hwnd, RootOwner) != owner ||
                    ShortcutBindings.IsReserved(this.filterKeys, message)) {
                    return result;
                }
                if ((keyData & PreviousKeyState) == 0) {
                    this.package.JoinableTaskFactory.RunAsync(this.InvokeAsync).FileAndForget("UniversalDevKit/RegenerateShortcut");
                }
                Marshal.WriteInt32(address, MessageIdOffset, NullMessage);
            } catch (COMException) {
                // Если Visual Studio не смогла проверить назначение, оставляем сообщение в её очереди.
            }
            return result;
        }

        private async Task InvokeAsync() {
            await this.package.JoinableTaskFactory.SwitchToMainThreadAsync(alwaysYield: true);
            if (!this.package.DisposalToken.IsCancellationRequested && UIContext.FromUIContextGuid(SolutionExists).IsActive) {
                this.command.Invoke();
            }
        }

        // AltGr может добавлять синтетический левый Ctrl.
        private static bool IsControlAltDown() => IsDown(Control) && (IsDown(LeftAlt) || (IsDown(RightAlt) && IsDown(RightControl)));

        private static bool IsDown(int key) => GetKeyState(key) < 0;

        private delegate IntPtr HookProcedure(int code, IntPtr operation, IntPtr address);

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int type, HookProcedure procedure, IntPtr module, uint threadId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnhookWindowsHookEx(IntPtr hook);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr operation, IntPtr address);

        [DllImport("user32.dll")]
        private static extern short GetKeyState(int key);

        [DllImport("user32.dll")]
        private static extern IntPtr GetAncestor(IntPtr window, uint flags);
    }
}