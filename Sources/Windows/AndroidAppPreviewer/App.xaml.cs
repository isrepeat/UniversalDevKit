using System;
using System.IO;
using System.Windows;
using System.Windows.Threading;
using System.Threading.Tasks;

namespace AndroidAppPreviewer {
    public partial class App : Application {
        private static readonly object UnhandledExceptionLogLock = new();

        public App() {
            this.DispatcherUnhandledException += this.HandleDispatcherUnhandledException;
            AppDomain.CurrentDomain.UnhandledException += AppDomainUnhandledException;
            TaskScheduler.UnobservedTaskException += TaskSchedulerUnobservedTaskException;
        }

        internal static void LogNativeOperation(string operation) {
            AppendLog("Native", operation);
        }

        private void HandleDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs eventArgs) {
            AppendLog("WPF dispatcher", eventArgs.Exception.ToString());
        }

        private static void AppDomainUnhandledException(object sender, UnhandledExceptionEventArgs eventArgs) {
            AppendLog("AppDomain", eventArgs.ExceptionObject.ToString() ?? "Unknown exception");
        }

        private static void TaskSchedulerUnobservedTaskException(object? sender, UnobservedTaskExceptionEventArgs eventArgs) {
            AppendLog("TaskScheduler", eventArgs.Exception.ToString());
        }

        private static void AppendLog(string source, string message) {
            try {
                var path = Path.Combine(AppContext.BaseDirectory, "android-app-previewer.wpf.log");
                var value = $"{DateTimeOffset.Now:O} [{source}] {message}{Environment.NewLine}";
                lock (UnhandledExceptionLogLock) {
                    File.AppendAllText(path, value);
                }
            } catch {
                // Ошибка записи лога не должна мешать штатному завершению процесса.
            }
        }
    }
}