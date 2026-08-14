using System.IO;

namespace StarBridge.Desktop;

public enum StartupDataGateState
{
    Initial,
    Loading,
    Live,
    OfflineCache,
    Error
}

public enum StartupSyncOutcome
{
    Succeeded,
    Failed,
    TimedOut
}

public readonly record struct StartupDataGateAttempt(
    long Revision,
    AccountSessionLease AccountSession,
    bool HasCachedState,
    DateTimeOffset? CacheWrittenAtUtc);

public readonly record struct StartupDataVisibility(
    bool ServerDataVisible,
    bool OnlineCountVisible,
    bool BlockingStateVisible,
    bool OfflineCacheNoticeVisible,
    bool LocalPreferencesVisible,
    bool PersonalProfileVisible);

public readonly record struct StartupDataGateSnapshot(
    StartupDataGateState State,
    DateTimeOffset? CacheWrittenAtUtc)
{
    public StartupDataVisibility Visibility => StartupDataVisibilityPolicy.Resolve(State);
    public bool ServerDataVisible => Visibility.ServerDataVisible;
}

public readonly record struct StartupCacheNotice(
    string Title,
    string Description,
    bool HasTimestamp)
{
    public static StartupCacheNotice Resolve(
        DateTimeOffset? cacheWrittenAtUtc,
        DateTimeOffset now,
        bool useChinese)
    {
        var title = useChinese
            ? "当前离线，显示的是本地缓存"
            : "Offline · showing local cache";
        if (cacheWrittenAtUtc is null)
        {
            return new StartupCacheNotice(
                title,
                useChinese
                    ? "恢复连接后可手动重试同步。"
                    : "Retry after the connection is restored.",
                HasTimestamp: false);
        }

        var localTime = cacheWrittenAtUtc.Value.ToLocalTime();
        return new StartupCacheNotice(
            title,
            useChinese
                ? $"缓存写入于 {localTime:yyyy-MM-dd HH:mm} · 恢复连接后可手动重试同步。"
                : $"Cache written {localTime:yyyy-MM-dd HH:mm} · retry after reconnecting.",
            HasTimestamp: true);
    }
}

public static class StartupDataGate
{
    public static StartupDataGateState Resolve(
        bool hasCachedState,
        bool syncSucceeded,
        bool syncFailed,
        bool timedOut)
    {
        if (syncSucceeded)
        {
            return StartupDataGateState.Live;
        }

        if (syncFailed || timedOut)
        {
            return hasCachedState
                ? StartupDataGateState.OfflineCache
                : StartupDataGateState.Error;
        }

        return StartupDataGateState.Loading;
    }
}

public static class StartupDataVisibilityPolicy
{
    public static StartupDataVisibility Resolve(StartupDataGateState state)
    {
        var serverDataVisible = state is StartupDataGateState.Live or StartupDataGateState.OfflineCache;
        return new StartupDataVisibility(
            ServerDataVisible: serverDataVisible,
            OnlineCountVisible: state == StartupDataGateState.Live,
            BlockingStateVisible: state is StartupDataGateState.Loading or StartupDataGateState.Error,
            OfflineCacheNoticeVisible: state == StartupDataGateState.OfflineCache,
            LocalPreferencesVisible: true,
            PersonalProfileVisible: true);
    }
}

public static class StartupRetryPolicy
{
    public static bool ShouldArmPeriodicSynchronization(StartupSyncOutcome outcome) =>
        outcome == StartupSyncOutcome.Succeeded;

    public static bool OffersManualRetry(StartupSyncOutcome outcome) =>
        outcome is StartupSyncOutcome.Failed or StartupSyncOutcome.TimedOut;
}

public sealed class StartupDataGateController
{
    private long _revision;

    public StartupDataGateSnapshot Current { get; private set; } =
        new(StartupDataGateState.Initial, null);

    public StartupDataGateAttempt Begin(
        AccountSessionLease accountSession,
        bool hasCachedState,
        DateTimeOffset? cacheWrittenAtUtc)
    {
        var attempt = new StartupDataGateAttempt(
            ++_revision,
            accountSession,
            hasCachedState,
            cacheWrittenAtUtc);
        Current = new StartupDataGateSnapshot(StartupDataGateState.Loading, cacheWrittenAtUtc);
        return attempt;
    }

    public bool IsCurrent(StartupDataGateAttempt attempt) => attempt.Revision == _revision;

    public bool TryComplete(
        StartupDataGateAttempt attempt,
        bool sessionIsCurrent,
        StartupSyncOutcome outcome)
    {
        if (!sessionIsCurrent || !IsCurrent(attempt))
        {
            return false;
        }

        // Completing an attempt also retires its mutation lease. Any network
        // task that ignores cancellation and returns after timeout can no
        // longer apply server data beneath the terminal cache/error surface.
        _revision++;
        Current = new StartupDataGateSnapshot(
            StartupDataGate.Resolve(
                attempt.HasCachedState,
                syncSucceeded: outcome == StartupSyncOutcome.Succeeded,
                syncFailed: outcome == StartupSyncOutcome.Failed,
                timedOut: outcome == StartupSyncOutcome.TimedOut),
            attempt.CacheWrittenAtUtc);
        return true;
    }

    public void Reset()
    {
        _revision++;
        Current = new StartupDataGateSnapshot(StartupDataGateState.Initial, null);
    }
}

public static class StartupSyncTimeoutPolicy
{
    public static async Task<StartupSyncOutcome> WaitAsync(
        Func<CancellationToken, Task<bool>> operation,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(operation);
        if (timeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }

        using var linkedCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        Task<bool> operationTask;
        try
        {
            operationTask = operation(linkedCancellation.Token);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return StartupSyncOutcome.Failed;
        }

        var timeoutTask = Task.Delay(timeout, cancellationToken);
        var completed = await Task.WhenAny(operationTask, timeoutTask).ConfigureAwait(false);
        if (completed == timeoutTask)
        {
            cancellationToken.ThrowIfCancellationRequested();
            linkedCancellation.Cancel();
            _ = ObserveLateCompletionAsync(operationTask);
            return StartupSyncOutcome.TimedOut;
        }

        linkedCancellation.Cancel();
        try
        {
            return await operationTask.ConfigureAwait(false)
                ? StartupSyncOutcome.Succeeded
                : StartupSyncOutcome.Failed;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return StartupSyncOutcome.Failed;
        }
    }

    private static async Task ObserveLateCompletionAsync(Task operationTask)
    {
        try
        {
            await operationTask.ConfigureAwait(false);
        }
        catch
        {
            // The terminal state is already TimedOut. Observing the late task
            // prevents an unobserved exception without changing that decision.
        }
    }
}

internal sealed class StartupSyncTimingHistory
{
    private const int MaxSamples = 20;
    private static readonly TimeSpan ExistingSlowNoticeMargin = TimeSpan.FromSeconds(4);
    private readonly string _path;
    private readonly List<double> _milliseconds;

    internal StartupSyncTimingHistory(string? path = null)
    {
        _path = string.IsNullOrWhiteSpace(path)
            ? Path.Combine(DesktopAppConfig.ConfigDirectory, "startup-sync-timings.json")
            : path;
        _milliseconds = Load(_path);
    }

    internal TimeSpan ResolveTimeout(TimeSpan upstreamRequestTimeout)
    {
        if (_milliseconds.Count < 5)
        {
            return upstreamRequestTimeout;
        }

        var ordered = _milliseconds.OrderBy(value => value).ToArray();
        var upperTailIndex = Math.Clamp(
            (int)Math.Ceiling(ordered.Length * 0.95) - 1,
            0,
            ordered.Length - 1);
        var measuredUpperTail = TimeSpan.FromMilliseconds(ordered[upperTailIndex]);
        return measuredUpperTail + ExistingSlowNoticeMargin > upstreamRequestTimeout
            ? measuredUpperTail + ExistingSlowNoticeMargin
            : upstreamRequestTimeout;
    }

    internal void RecordSuccessful(TimeSpan elapsed)
    {
        if (elapsed <= TimeSpan.Zero || !double.IsFinite(elapsed.TotalMilliseconds))
        {
            return;
        }

        _milliseconds.Add(elapsed.TotalMilliseconds);
        if (_milliseconds.Count > MaxSamples)
        {
            _milliseconds.RemoveRange(0, _milliseconds.Count - MaxSamples);
        }

        try
        {
            var directory = Path.GetDirectoryName(_path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }
            File.WriteAllText(_path, System.Text.Json.JsonSerializer.Serialize(_milliseconds));
        }
        catch
        {
            // Timing telemetry is local, nonessential, and never allowed to
            // turn a successful synchronization into a failure.
        }
    }

    internal string Describe()
    {
        if (_milliseconds.Count == 0)
        {
            return "no successful startup samples";
        }

        var ordered = _milliseconds.OrderBy(value => value).ToArray();
        var upperTailIndex = Math.Clamp(
            (int)Math.Ceiling(ordered.Length * 0.95) - 1,
            0,
            ordered.Length - 1);
        return $"samples={ordered.Length}, p95={ordered[upperTailIndex]:0}ms, max={ordered[^1]:0}ms";
    }

    private static List<double> Load(string path)
    {
        try
        {
            return (System.Text.Json.JsonSerializer.Deserialize<double[]>(File.ReadAllText(path)) ?? [])
                .Where(value => value > 0 && double.IsFinite(value))
                .TakeLast(MaxSamples)
                .ToList();
        }
        catch
        {
            return [];
        }
    }
}
