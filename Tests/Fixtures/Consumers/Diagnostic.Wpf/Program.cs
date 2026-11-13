using System;
using System.IO;
using System.Windows;
using System.Runtime.CompilerServices;

using UniversalDevKit.Diagnostic;

internal static class Program {
    [STAThread]
    private static int Main() {
        var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        application.Startup += (_, _) => {
            try {
                VerifyPackage();
                Console.WriteLine("DIAGNOSTIC_WPF_PASS");
                application.Shutdown(0);
            }
            catch (Exception exception) {
                Console.Error.WriteLine(exception);
                application.Shutdown(1);
            }
        };
        return application.Run();
    }

    private static void VerifyPackage() {
        const uint loggerId = 42;
        const string message = "\u0421\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u0435 {WPF} 日本語";
        string directory = Path.Combine(Path.GetTempPath(), $"udk-wpf-{Guid.NewGuid():N}");
        string filePath = Path.Combine(directory, "\u0436\u0443\u0440\u043d\u0430\u043b.log");
        Directory.CreateDirectory(directory);
        try {
            var options = new LoggerOptions { FilePath = filePath };
            var initialized = Log.Initialize(options, loggerId);
            Require(initialized.Succeeded && initialized.SystemError == 0 && initialized.Message.Length == 0, initialized.ToString());

            var duplicate = Log.Initialize(options, loggerId);
            Require(duplicate.Error == LoggerInitError.AlreadyInitialized && duplicate.Message.Length > 0, duplicate.ToString());

            var invalidPath = Log.Initialize(new LoggerOptions { FilePath = Path.Combine(filePath, "nested.log") }, loggerId + 1);
            Require(invalidPath.Error == LoggerInitError.DirectoryUnavailable && invalidPath.SystemError != 0 &&
                invalidPath.Message.Length > 0, invalidPath.ToString());

            int line = CurrentLine() + 1;
            Log.Write(Level.Info, "WPF", message, loggerId);
            Log.Flush(loggerId);
            using var stream = new FileStream(filePath, System.IO.FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            using var reader = new StreamReader(stream);
            string contents = reader.ReadToEnd();
            Require(contents.Contains($"{{Program.cs:{line} VerifyPackage}} [WPF] {message}", StringComparison.Ordinal), contents);
        }
        finally {
            Log.Shutdown();
            Directory.Delete(directory, recursive: true);
        }
    }

    private static int CurrentLine([CallerLineNumber] int line = 0) => line;

    private static void Require(bool condition, string details) {
        if (!condition) {
            throw new InvalidOperationException(details);
        }
    }
}