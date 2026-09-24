namespace StarBridge.Desktop.FlutterHost;

internal enum DesktopUiOwner
{
    Wpf,
    Flutter
}

internal enum DesktopUiOwnerTransitionState
{
    WpfActive,
    StartingFlutter,
    FlutterActive,
    ReturningToWpf,
    Disposed
}

internal sealed record DesktopUiOwnerSnapshot(
    DesktopUiOwner Owner,
    DesktopUiOwnerTransitionState State,
    string? FailureCode = null);

internal sealed record DesktopUiOwnerTransitionResult(
    bool Succeeded,
    DesktopUiOwnerSnapshot Snapshot);

internal sealed record FlutterUiStartResult(
    bool Succeeded,
    int? ProcessId,
    string? FailureCode)
{
    internal static FlutterUiStartResult Started(int processId) =>
        new(true, processId, null);

    internal static FlutterUiStartResult Failed(string failureCode) =>
        new(false, null, failureCode);
}

internal sealed class FlutterUiProcessExitedEventArgs(
    int processId,
    int exitCode) : EventArgs
{
    internal int ProcessId { get; } = processId;

    internal int ExitCode { get; } = exitCode;
}

internal interface IDesktopUiSurface
{
    ValueTask HideAsync(CancellationToken cancellationToken = default);

    ValueTask ShowAsync(CancellationToken cancellationToken = default);

    ValueTask ActivateAsync(CancellationToken cancellationToken = default);
}

internal interface IFlutterUiProcess : IAsyncDisposable
{
    bool IsRunning { get; }

    event EventHandler<FlutterUiProcessExitedEventArgs>? Exited;

    ValueTask<FlutterUiStartResult> StartAsync(
        CancellationToken cancellationToken = default);

    ValueTask StopAsync(CancellationToken cancellationToken = default);

    ValueTask ActivateAsync(CancellationToken cancellationToken = default);
}

internal sealed record DesktopUiOwnerStartupOptions(
    DesktopUiOwner PreferredOwner,
    string? FlutterExecutablePath,
    string? FailureCode)
{
    private const string OwnerPrefix = "--ui-owner=";
    private const string FlutterExecutablePrefix = "--flutter-exe=";

    internal static DesktopUiOwnerStartupOptions Parse(
        IReadOnlyList<string> arguments)
    {
        ArgumentNullException.ThrowIfNull(arguments);
        DesktopUiOwner? requestedOwner = null;
        string? flutterExecutablePath = null;
        var invalid = false;

        foreach (var rawArgument in arguments)
        {
            var argument = rawArgument?.Trim() ?? string.Empty;
            if (argument.StartsWith(OwnerPrefix, StringComparison.OrdinalIgnoreCase))
            {
                var value = argument[OwnerPrefix.Length..];
                var parsed = value.ToLowerInvariant() switch
                {
                    "wpf" => DesktopUiOwner.Wpf,
                    "flutter" => DesktopUiOwner.Flutter,
                    _ => (DesktopUiOwner?)null
                };
                if (parsed is null ||
                    (requestedOwner is not null && requestedOwner != parsed))
                {
                    invalid = true;
                    continue;
                }

                requestedOwner = parsed;
                continue;
            }

            if (argument.StartsWith(
                    FlutterExecutablePrefix,
                    StringComparison.OrdinalIgnoreCase))
            {
                var value = argument[FlutterExecutablePrefix.Length..].Trim();
                if (string.IsNullOrWhiteSpace(value) || flutterExecutablePath is not null)
                {
                    invalid = true;
                    continue;
                }

                flutterExecutablePath = value;
            }
        }

        if (invalid)
        {
            return new DesktopUiOwnerStartupOptions(
                DesktopUiOwner.Wpf,
                null,
                "ui_owner.invalid_arguments");
        }

        return new DesktopUiOwnerStartupOptions(
            requestedOwner ?? DesktopUiOwner.Wpf,
            flutterExecutablePath,
            null);
    }
}

/// <summary>
/// Owns the only UI-ownership state machine. Business capabilities remain in
/// the WPF/Native Host process; this module only leases visibility to Flutter.
/// Every transition removes the old visible owner before exposing the new one.
/// </summary>
internal sealed class DesktopUiOwnerCoordinator : IDisposable, IAsyncDisposable
{
    private readonly IDesktopUiSurface _wpf;
    private readonly IFlutterUiProcess _flutter;
    private readonly Action<string>? _diagnostic;
    private readonly SemaphoreSlim _transitionGate = new(1, 1);
    private DesktopUiOwnerSnapshot _current = new(
        DesktopUiOwner.Wpf,
        DesktopUiOwnerTransitionState.WpfActive);
    private bool _expectedFlutterExit;
    private bool _disposed;

    internal DesktopUiOwnerCoordinator(
        IDesktopUiSurface wpf,
        IFlutterUiProcess flutter,
        Action<string>? diagnostic = null)
    {
        _wpf = wpf ?? throw new ArgumentNullException(nameof(wpf));
        _flutter = flutter ?? throw new ArgumentNullException(nameof(flutter));
        _diagnostic = diagnostic;
        _flutter.Exited += Flutter_Exited;
    }

    internal DesktopUiOwnerSnapshot Current => Volatile.Read(ref _current);

    internal async Task<DesktopUiOwnerTransitionResult> SwitchAsync(
        DesktopUiOwner target,
        CancellationToken cancellationToken = default)
    {
        await _transitionGate.WaitAsync(cancellationToken);
        try
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (Current.Owner == target &&
                Current.State is DesktopUiOwnerTransitionState.WpfActive or
                    DesktopUiOwnerTransitionState.FlutterActive)
            {
                return new DesktopUiOwnerTransitionResult(true, Current);
            }

            return target == DesktopUiOwner.Flutter
                ? await SwitchToFlutterAsync(cancellationToken)
                : await SwitchToWpfAsync(cancellationToken);
        }
        finally
        {
            _transitionGate.Release();
        }
    }

    internal async ValueTask ActivateAsync(
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (Current.Owner == DesktopUiOwner.Flutter && _flutter.IsRunning)
        {
            await _flutter.ActivateAsync(cancellationToken);
            return;
        }

        await _wpf.ActivateAsync(cancellationToken);
    }

    private async Task<DesktopUiOwnerTransitionResult> SwitchToFlutterAsync(
        CancellationToken cancellationToken)
    {
        SetCurrent(new DesktopUiOwnerSnapshot(
            DesktopUiOwner.Wpf,
            DesktopUiOwnerTransitionState.StartingFlutter));
        await _wpf.HideAsync(cancellationToken);

        FlutterUiStartResult start;
        try
        {
            start = await _flutter.StartAsync(cancellationToken);
        }
        catch (OperationCanceledException)
        {
            await _wpf.ShowAsync(CancellationToken.None);
            SetCurrent(new DesktopUiOwnerSnapshot(
                DesktopUiOwner.Wpf,
                DesktopUiOwnerTransitionState.WpfActive,
                "ui_owner.cancelled"));
            throw;
        }
        catch (Exception exception)
        {
            Report($"Flutter UI start failed: {exception.GetType().Name}");
            start = FlutterUiStartResult.Failed("ui_owner.flutter_start_failed");
        }

        if (!start.Succeeded || !_flutter.IsRunning)
        {
            var failure = start.FailureCode ?? "ui_owner.flutter_start_failed";
            await _wpf.ShowAsync(CancellationToken.None);
            SetCurrent(new DesktopUiOwnerSnapshot(
                DesktopUiOwner.Wpf,
                DesktopUiOwnerTransitionState.WpfActive,
                failure));
            return new DesktopUiOwnerTransitionResult(false, Current);
        }

        SetCurrent(new DesktopUiOwnerSnapshot(
            DesktopUiOwner.Flutter,
            DesktopUiOwnerTransitionState.FlutterActive));
        return new DesktopUiOwnerTransitionResult(true, Current);
    }

    private async Task<DesktopUiOwnerTransitionResult> SwitchToWpfAsync(
        CancellationToken cancellationToken)
    {
        SetCurrent(new DesktopUiOwnerSnapshot(
            DesktopUiOwner.Flutter,
            DesktopUiOwnerTransitionState.ReturningToWpf));
        _expectedFlutterExit = true;
        try
        {
            await _flutter.StopAsync(cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Report($"Flutter UI stop failed: {exception.GetType().Name}");
        }
        finally
        {
            _expectedFlutterExit = false;
        }

        if (_flutter.IsRunning)
        {
            SetCurrent(new DesktopUiOwnerSnapshot(
                DesktopUiOwner.Flutter,
                DesktopUiOwnerTransitionState.FlutterActive,
                "ui_owner.flutter_stop_failed"));
            return new DesktopUiOwnerTransitionResult(false, Current);
        }

        await _wpf.ShowAsync(cancellationToken);
        SetCurrent(new DesktopUiOwnerSnapshot(
            DesktopUiOwner.Wpf,
            DesktopUiOwnerTransitionState.WpfActive));
        return new DesktopUiOwnerTransitionResult(true, Current);
    }

    private void Flutter_Exited(
        object? sender,
        FlutterUiProcessExitedEventArgs eventArgs)
    {
        _ = RecoverFromUnexpectedFlutterExitAsync(eventArgs);
    }

    private async Task RecoverFromUnexpectedFlutterExitAsync(
        FlutterUiProcessExitedEventArgs eventArgs)
    {
        await _transitionGate.WaitAsync();
        try
        {
            if (_disposed || _expectedFlutterExit ||
                Current.State is DesktopUiOwnerTransitionState.WpfActive or
                    DesktopUiOwnerTransitionState.Disposed)
            {
                return;
            }

            Report(
                $"Flutter UI process {eventArgs.ProcessId} exited with code {eventArgs.ExitCode}.");
            await _wpf.ShowAsync();
            SetCurrent(new DesktopUiOwnerSnapshot(
                DesktopUiOwner.Wpf,
                DesktopUiOwnerTransitionState.WpfActive,
                "ui_owner.flutter_exited"));
        }
        catch (Exception exception)
        {
            Report($"WPF UI recovery failed: {exception.GetType().Name}");
        }
        finally
        {
            _transitionGate.Release();
        }
    }

    private void SetCurrent(DesktopUiOwnerSnapshot snapshot) =>
        Volatile.Write(ref _current, snapshot);

    private void Report(string message) => _diagnostic?.Invoke(message);

    public void Dispose() => DisposeAsync().AsTask().GetAwaiter().GetResult();

    public async ValueTask DisposeAsync()
    {
        await _transitionGate.WaitAsync();
        try
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _flutter.Exited -= Flutter_Exited;
            _expectedFlutterExit = true;
            try
            {
                await _flutter.StopAsync();
            }
            finally
            {
                await _flutter.DisposeAsync();
                SetCurrent(new DesktopUiOwnerSnapshot(
                    DesktopUiOwner.Wpf,
                    DesktopUiOwnerTransitionState.Disposed));
            }
        }
        finally
        {
            _transitionGate.Release();
            _transitionGate.Dispose();
        }
    }
}
