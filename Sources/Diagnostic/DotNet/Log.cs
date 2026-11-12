#nullable enable
using System;
#if NETFRAMEWORK
using System.Text;
#endif
using System.Runtime.InteropServices;
using System.Runtime.CompilerServices;

#if NETFRAMEWORK
[assembly: DefaultDllImportSearchPaths(DllImportSearchPath.AssemblyDirectory | DllImportSearchPath.System32)]
#endif

namespace UniversalDevKit.Diagnostic;

public enum Level {
    Trace = 0,
    Debug = 1,
    Info = 2,
    Warning = 3,
    Error = 4,
    Critical = 5,
    Off = 6
}

public enum LogFolder {
    CurrentDirectory = 0,
    Application = 1,
    Package = 2,
    ApplicationOrPackage = 3
}

public enum FileMode {
    Append = 0,
    Truncate = 1
}

public enum LoggerInitError {
    None = 0,
    AlreadyInitialized = 1,
    FileAlreadyUsed = 2,
    InvalidOptions = 3,
    DirectoryUnavailable = 4,
    FileOpenFailed = 5,
    PackageUnavailable = 6,
    UnsupportedPlatform = 7,
    ShutdownRegistrationFailed = 8,
    InitializationFailed = 9,
    ShutdownInProgress = 10
}

public sealed class LoggerOptions {
    public Level MinimumLevel { get; init; } = Level.Info;
    public string? FilePath { get; init; }
    public LogFolder LogFolder { get; init; }
    public FileMode FileMode { get; init; }
    public ulong MaxFileSize { get; init; } = 10 * 1024 * 1024;
    public ulong MaxFiles { get; init; } = 1;
    public bool AppendNewSession { get; init; } = true;
    public bool EnableConsole { get; init; }
    public bool EnableDebugger { get; init; }
    public bool ColorConsole { get; init; } = true;
}

public readonly record struct LoggerInitResult(LoggerInitError Error, int SystemError, string Message) {
    public bool Succeeded => Error == LoggerInitError.None;
}

public static partial class Log {
    public static LoggerInitResult Initialize(LoggerOptions? loggerOptions = null, uint loggerId = 0) {
        loggerOptions ??= new LoggerOptions();
        var nativeOptions = new NativeMethods.Options {
            MaxFileSize = loggerOptions.MaxFileSize,
            MaxFiles = loggerOptions.MaxFiles,
            MinimumLevel = loggerOptions.MinimumLevel,
            LogFolder = loggerOptions.LogFolder,
            FileMode = loggerOptions.FileMode,
            Flags = (loggerOptions.AppendNewSession ? NativeMethods.Flags.AppendNewSession : 0)
                | (loggerOptions.EnableConsole ? NativeMethods.Flags.EnableConsole : 0)
                | (loggerOptions.EnableDebugger ? NativeMethods.Flags.EnableDebugger : 0)
                | (loggerOptions.ColorConsole ? NativeMethods.Flags.ColorConsole : 0)
        };
        var error = NativeMethods.UdkDiagnosticInitialize(
            loggerId,
            in nativeOptions,
            loggerOptions.FilePath,
            out var systemError,
            out var message
        );
        try {
            return new LoggerInitResult(error, systemError, ReadMessage(message));
        }
        finally {
            NativeMethods.UdkDiagnosticFreeMessage(message);
        }
    }

    public static void Write(
        Level level,
        string category,
        string message,
        uint loggerId = 0,
        [CallerFilePath] string file = "",
        [CallerMemberName] string member = "",
        [CallerLineNumber] int line = 0
    ) {
        NativeMethods.UdkDiagnosticWriteRecord(loggerId, level, category, message, file, member, line);
    }

    public static void Flush(uint loggerId = 0) => NativeMethods.UdkDiagnosticFlush(loggerId);

    public static void Shutdown() => NativeMethods.UdkDiagnosticShutdownLoggers();

    private static string ReadMessage(IntPtr message) {
#if NETFRAMEWORK
        if (message == IntPtr.Zero) {
            return string.Empty;
        }
        var length = 0;
        while (Marshal.ReadByte(message, length) != 0) {
            length++;
        }
        var bytes = new byte[length];
        Marshal.Copy(message, bytes, 0, length);
        return Encoding.UTF8.GetString(bytes);
#else
        return Marshal.PtrToStringUTF8(message) ?? string.Empty;
#endif
    }

    private static partial class NativeMethods {
        private const string Library = "universaldevkit_diagnostic_dynamic";

        [Flags]
        internal enum Flags : uint {
            AppendNewSession = 1,
            EnableConsole = 2,
            EnableDebugger = 4,
            ColorConsole = 8
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct Options {
            internal ulong MaxFileSize;
            internal ulong MaxFiles;
            internal Level MinimumLevel;
            internal LogFolder LogFolder;
            internal FileMode FileMode;
            internal Flags Flags;
        }

#if NETFRAMEWORK
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        internal static extern LoggerInitError UdkDiagnosticInitialize(
            uint loggerId, in Options options, [MarshalAs(UnmanagedType.LPUTF8Str)] string? filePath,
            out int systemError, out IntPtr message
        );

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void UdkDiagnosticFreeMessage(IntPtr message);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void UdkDiagnosticWriteRecord(
            uint loggerId, Level level, [MarshalAs(UnmanagedType.LPUTF8Str)] string category,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string message, [MarshalAs(UnmanagedType.LPUTF8Str)] string file,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string member, int line
        );

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void UdkDiagnosticFlush(uint loggerId);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void UdkDiagnosticShutdownLoggers();
#else
        [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)]
        internal static partial LoggerInitError UdkDiagnosticInitialize(
            uint loggerId,
            in Options options,
            string? filePath,
            out int systemError,
            out nint message
        );

        [LibraryImport(Library)]
        internal static partial void UdkDiagnosticFreeMessage(nint message);

        [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)]
        internal static partial void UdkDiagnosticWriteRecord(
            uint loggerId, Level level, string category, string message, string file, string member, int line
        );

        [LibraryImport(Library)]
        internal static partial void UdkDiagnosticFlush(uint loggerId);

        [LibraryImport(Library)]
        internal static partial void UdkDiagnosticShutdownLoggers();
#endif
    }
}