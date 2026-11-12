using System;
using System.IO;
using System.Diagnostics;

namespace UniversalDevKit.UdkCli.Setup {
    internal sealed class SetupLog : IDisposable {
        public bool IsInitialized { get; }

        private string PathToLog { get; } = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "UdkCli", "Logs", "Setup.log");

        public SetupLog() {
            try {
                var result = Diagnostic.Log.Initialize(new Diagnostic.LoggerOptions { FilePath = this.PathToLog });
                this.IsInitialized = result.Succeeded;
                if (!result.Succeeded) {
                    Trace.TraceError($"Could not initialize Setup logging: {result.Error}: {result.Message}");
                }
            } catch (Exception exception) {
                Trace.TraceError(exception.ToString());
            }
        }

        public string Location => this.IsInitialized ? $"\n\nSetup log: {this.PathToLog}" : "";

        public void Dispose() {
            if (this.IsInitialized) {
                Diagnostic.Log.Shutdown();
            }
        }
    }
}