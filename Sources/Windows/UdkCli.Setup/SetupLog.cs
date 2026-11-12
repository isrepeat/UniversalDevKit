using System;
using System.IO;
using System.Reflection;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace UniversalDevKit.UdkCli.Setup {
    internal sealed class SetupLog : IDisposable {
        [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        private delegate int InitializeFile(string path);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        private delegate void WriteMessage(int isError, string message);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void Shutdown();

        private readonly string nativeDirectory = Path.Combine(Path.GetTempPath(), $"UdkSetup-{Guid.NewGuid():N}");
        private IntPtr library;
        private WriteMessage? write;
        private Shutdown? shutdown;

        public string PathToLog { get; } = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "UdkCli", "Logs", "Setup.log");

        public SetupLog() {
            try {
                using var payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("UdkDiagnostic.dll")
                    ?? throw new InvalidDataException("The installer does not contain Diagnostic.");
                Directory.CreateDirectory(this.nativeDirectory);
                var libraryPath = Path.Combine(this.nativeDirectory, "UdkDiagnostic.dll");
                using (var file = File.Open(libraryPath, FileMode.CreateNew)) {
                    payload.CopyTo(file);
                }
                this.library = NativeLibrary.Load(libraryPath);
                var initialize = this.GetExport<InitializeFile>("UdkDiagnosticInitializeFile");
                var write = this.GetExport<WriteMessage>("UdkDiagnosticWrite");
                var shutdown = this.GetExport<Shutdown>("UdkDiagnosticShutdown");
                if (initialize(this.PathToLog) == 0) {
                    throw new IOException($"Could not open the Setup log at {this.PathToLog}.");
                }
                this.write = write;
                this.shutdown = shutdown;
            } catch (Exception exception) {
                Trace.TraceError(exception.ToString());
                this.Dispose();
            }
        }

        public void Info(string message) => this.write?.Invoke(0, message);

        public void Error(Exception exception) => this.write?.Invoke(1, exception.ToString());

        public string Location => this.write is null ? "" : $"\n\nSetup log: {this.PathToLog}";

        public void Dispose() {
            this.shutdown?.Invoke();
            this.shutdown = null;
            this.write = null;
            if (this.library != IntPtr.Zero) {
                NativeLibrary.Free(this.library);
                this.library = IntPtr.Zero;
            }
            try {
                if (Directory.Exists(this.nativeDirectory)) {
                    File.Delete(Path.Combine(this.nativeDirectory, "UdkDiagnostic.dll"));
                    Directory.Delete(this.nativeDirectory);
                }
            } catch (IOException exception) {
                Trace.TraceError(exception.ToString());
            } catch (UnauthorizedAccessException exception) {
                Trace.TraceError(exception.ToString());
            }
        }

        private T GetExport<T>(string name) where T : Delegate =>
            Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(this.library, name));
    }
}