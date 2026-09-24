namespace StarBridge.HostRuntime.Auth;

internal readonly record struct ScmRuntimeRecoveryIdentity(
    string Environment,
    string AuthorityId,
    string Subject)
{
    internal ScmRuntimeRecoveryIdentity Normalize() => new(
        Environment.Trim().ToLowerInvariant(),
        AuthorityId.Trim().ToLowerInvariant(),
        Subject.Trim().ToLowerInvariant());

    internal bool IsValid =>
        !string.IsNullOrWhiteSpace(Environment) &&
        !string.IsNullOrWhiteSpace(AuthorityId) &&
        !string.IsNullOrWhiteSpace(Subject);
}

internal readonly record struct ScmRuntimeRecoveryLease(
    long Generation,
    ScmRuntimeRecoveryIdentity Identity);

/// <summary>
/// Owns the single background recovery lane for an SCM account. A newer route or
/// account retires the previous generation, so delayed responses cannot publish
/// state into the next session.
/// </summary>
internal sealed class ScmRuntimeRecoveryCoordinator : IDisposable
{
    private static readonly TimeSpan[] DefaultBackoff =
    [
        TimeSpan.FromSeconds(2),
        TimeSpan.FromSeconds(5),
        TimeSpan.FromSeconds(10),
        TimeSpan.FromSeconds(30)
    ];

    private readonly object _gate = new();
    private readonly Func<int, TimeSpan> _resolveBackoff;
    private readonly Func<TimeSpan, CancellationToken, Task> _delay;
    private CancellationTokenSource? _lifetime;
    private ScmRuntimeRecoveryIdentity? _identity;
    private long _generation;
    private bool _running;

    internal ScmRuntimeRecoveryCoordinator(
        Func<int, TimeSpan>? resolveBackoff = null,
        Func<TimeSpan, CancellationToken, Task>? delay = null)
    {
        _resolveBackoff = resolveBackoff ?? ResolveDefaultBackoff;
        _delay = delay ?? Task.Delay;
    }

    internal Task RequestAsync(
        ScmRuntimeRecoveryIdentity identity,
        Func<ScmRuntimeRecoveryLease, CancellationToken, Task<bool>> recover)
    {
        ArgumentNullException.ThrowIfNull(recover);
        if (!identity.IsValid)
        {
            throw new ArgumentException("SCM runtime recovery requires a complete route identity.", nameof(identity));
        }

        var normalized = identity.Normalize();
        lock (_gate)
        {
            if (_identity is not { } current || current != normalized)
            {
                RetireLocked();
                _identity = normalized;
            }

            if (_running)
            {
                return _activeCompletion?.Task ?? Task.CompletedTask;
            }

            _running = true;
            _lifetime = new CancellationTokenSource();
            var completion = new TaskCompletionSource(
                TaskCreationOptions.RunContinuationsAsynchronously);
            _activeCompletion = completion;
            var lease = new ScmRuntimeRecoveryLease(_generation, normalized);
            _ = RunAsync(lease, _lifetime, completion, recover);
            return completion.Task;
        }
    }

    private TaskCompletionSource? _activeCompletion;

    internal bool IsCurrent(ScmRuntimeRecoveryLease lease)
    {
        lock (_gate)
        {
            return _identity is { } current &&
                   current == lease.Identity &&
                   _generation == lease.Generation;
        }
    }

    internal void Retire()
    {
        lock (_gate)
        {
            RetireLocked();
            _identity = null;
        }
    }

    private async Task RunAsync(
        ScmRuntimeRecoveryLease lease,
        CancellationTokenSource lifetime,
        TaskCompletionSource completion,
        Func<ScmRuntimeRecoveryLease, CancellationToken, Task<bool>> recover)
    {
        await Task.Yield();
        var failureCount = 0;
        try
        {
            while (IsCurrent(lease) && !lifetime.IsCancellationRequested)
            {
                if (await recover(lease, lifetime.Token))
                {
                    return;
                }

                failureCount++;
                await _delay(_resolveBackoff(failureCount), lifetime.Token);
            }
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            completion.TrySetException(exception);
            return;
        }
        finally
        {
            lock (_gate)
            {
                if (_generation == lease.Generation &&
                    _identity is { } current &&
                    current == lease.Identity &&
                    ReferenceEquals(_lifetime, lifetime))
                {
                    _running = false;
                    _lifetime = null;
                    _activeCompletion = null;
                }
            }

            lifetime.Dispose();
            completion.TrySetResult();
        }
    }

    private void RetireLocked()
    {
        _generation++;
        _running = false;
        _lifetime?.Cancel();
        _lifetime = null;
        _activeCompletion = null;
    }

    private static TimeSpan ResolveDefaultBackoff(int failureCount) =>
        DefaultBackoff[Math.Clamp(failureCount - 1, 0, DefaultBackoff.Length - 1)];

    public void Dispose() => Retire();
}
