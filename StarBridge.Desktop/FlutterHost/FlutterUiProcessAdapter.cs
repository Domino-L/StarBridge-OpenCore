namespace StarBridge.Desktop.FlutterHost;

using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

internal sealed record FlutterUiExecutableResolution(
    string? ExecutablePath,
    string? FailureCode)
{
    internal bool Found => ExecutablePath is not null;
}

internal static class FlutterUiExecutableLocator
{
    internal static FlutterUiExecutableResolution Resolve(
        string? explicitPath,
        string applicationBaseDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(applicationBaseDirectory);
        if (!string.IsNullOrWhiteSpace(explicitPath))
        {
            var resolved = TryResolveFile(explicitPath);
            return resolved is null
                ? new FlutterUiExecutableResolution(null, "ui_owner.flutter_not_found")
                : new FlutterUiExecutableResolution(resolved, null);
        }

        var candidates = new[]
        {
            Path.Combine(applicationBaseDirectory, "flutter", "starbridge_flutter.exe"),
            Path.Combine(applicationBaseDirectory, "starbridge_flutter.exe")
        };
        foreach (var candidate in candidates)
        {
            var resolved = TryResolveFile(candidate);
            if (resolved is not null)
            {
                return new FlutterUiExecutableResolution(resolved, null);
            }
        }

        return new FlutterUiExecutableResolution(null, "ui_owner.flutter_not_found");
    }

    private static string? TryResolveFile(string path)
    {
        try
        {
            var fullPath = Path.GetFullPath(path.Trim());
            return File.Exists(fullPath) ? fullPath : null;
        }
        catch (Exception exception) when (
            exception is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return null;
        }
    }
}

internal sealed class FlutterUiProcessAdapter : IFlutterUiProcess
{
    private const int ShowWindowRestore = 9;
    private static readonly TimeSpan DefaultStartupTimeout = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan DefaultStopTimeout = TimeSpan.FromSeconds(3);

    private readonly FlutterUiExecutableResolution _executable;
    private readonly int _hostProcessId;
    private readonly TimeSpan _startupTimeout;
    private readonly object _gate = new();
    private Process? _process;
    private bool _disposed;

    internal FlutterUiProcessAdapter(
        FlutterUiExecutableResolution executable,
        int hostProcessId,
        TimeSpan? startupTimeout = null)
    {
        _executable = executable ?? throw new ArgumentNullException(nameof(executable));
        _hostProcessId = hostProcessId > 0
            ? hostProcessId
            : throw new ArgumentOutOfRangeException(nameof(hostProcessId));
        _startupTimeout = startupTimeout ?? DefaultStartupTimeout;
    }

    public bool IsRunning
    {
        get
        {
            lock (_gate)
            {
                return IsProcessRunning(_process);
            }
        }
    }

    public event EventHandler<FlutterUiProcessExitedEventArgs>? Exited;

    public async ValueTask<FlutterUiStartResult> StartAsync(
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (!_executable.Found)
        {
            return FlutterUiStartResult.Failed(
                _executable.FailureCode ?? "ui_owner.flutter_not_found");
        }

        lock (_gate)
        {
            if (IsProcessRunning(_process))
            {
                return FlutterUiStartResult.Started(_process!.Id);
            }
        }

        Process? process = null;
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = _executable.ExecutablePath!,
                WorkingDirectory = Path.GetDirectoryName(_executable.ExecutablePath!)!,
                UseShellExecute = false
            };
            startInfo.ArgumentList.Add("--starbridge-managed-ui");
            startInfo.Environment["STARBRIDGE_MANAGED_UI"] = "1";
            startInfo.Environment["STARBRIDGE_HOST_PROCESS_ID"] =
                _hostProcessId.ToString(System.Globalization.CultureInfo.InvariantCulture);

            process = Process.Start(startInfo);
            if (process is null)
            {
                return FlutterUiStartResult.Failed("ui_owner.flutter_start_failed");
            }

            process.EnableRaisingEvents = true;
            process.Exited += Process_Exited;
            lock (_gate)
            {
                _process = process;
            }

            var ready = await WaitForMainWindowAsync(
                process,
                _startupTimeout,
                cancellationToken);
            if (!ready)
            {
                await StopAsync(CancellationToken.None);
                return FlutterUiStartResult.Failed(
                    process.HasExited
                        ? "ui_owner.flutter_exited_before_ready"
                        : "ui_owner.flutter_start_timeout");
            }

            return FlutterUiStartResult.Started(process.Id);
        }
        catch (OperationCanceledException)
        {
            if (process is not null)
            {
                await StopAsync(CancellationToken.None);
            }

            throw;
        }
        catch (Exception)
        {
            if (process is not null)
            {
                await StopAsync(CancellationToken.None);
            }

            return FlutterUiStartResult.Failed("ui_owner.flutter_start_failed");
        }
    }

    public async ValueTask StopAsync(CancellationToken cancellationToken = default)
    {
        Process? process;
        lock (_gate)
        {
            process = _process;
        }

        if (process is null)
        {
            return;
        }

        try
        {
            if (!process.HasExited)
            {
                _ = process.CloseMainWindow();
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
                    cancellationToken);
                timeout.CancelAfter(DefaultStopTimeout);
                try
                {
                    await process.WaitForExitAsync(timeout.Token);
                }
                catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
                {
                    process.Kill(entireProcessTree: true);
                    await process.WaitForExitAsync(CancellationToken.None);
                }
            }
        }
        finally
        {
            process.Exited -= Process_Exited;
            lock (_gate)
            {
                if (ReferenceEquals(_process, process))
                {
                    _process = null;
                }
            }

            process.Dispose();
        }
    }

    public ValueTask ActivateAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Process? process;
        lock (_gate)
        {
            process = _process;
        }

        if (!IsProcessRunning(process))
        {
            return ValueTask.CompletedTask;
        }

        process!.Refresh();
        var handle = process.MainWindowHandle;
        if (handle != IntPtr.Zero)
        {
            ShowWindow(handle, ShowWindowRestore);
            SetForegroundWindow(handle);
        }

        return ValueTask.CompletedTask;
    }

    private void Process_Exited(object? sender, EventArgs eventArgs)
    {
        if (sender is not Process process)
        {
            return;
        }

        var exitCode = -1;
        try
        {
            exitCode = process.ExitCode;
        }
        catch (InvalidOperationException)
        {
            // The process state changed before the exit code was available.
        }

        Exited?.Invoke(
            this,
            new FlutterUiProcessExitedEventArgs(process.Id, exitCode));
    }

    private static async Task<bool> WaitForMainWindowAsync(
        Process process,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (process.HasExited)
            {
                return false;
            }

            process.Refresh();
            if (process.MainWindowHandle != IntPtr.Zero)
            {
                return true;
            }

            await Task.Delay(TimeSpan.FromMilliseconds(50), cancellationToken);
        }

        return false;
    }

    private static bool IsProcessRunning(Process? process)
    {
        if (process is null)
        {
            return false;
        }

        try
        {
            return !process.HasExited;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        await StopAsync();
    }

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr handle, int command);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr handle);
}
