namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    private readonly object _restoreFlightSync = new();
    private Task<ScmOAuthSession?>? _restoreFlight;
    private ScmOAuthSession? _rejectedSession;
    private Guid? _notifiedCredentialVersion;
    private volatile bool _sessionWasInstalled;

    /// <summary>
    /// Opaque, process-local version of the latest committed credential. Rotation
    /// changes it; metadata updates do not. Null means no installed credential.
    /// Compare with ScmOAuthSession.CredentialVersion, never with account generation.
    /// It contains no token, token hash, account identifier or persistent data.
    /// </summary>
    public Guid? CurrentCredentialVersion =>
        Volatile.Read(ref _retainedRefresh)?.CredentialVersion ??
        Volatile.Read(ref _currentSession)?.CredentialVersion;

    private async Task<ScmOAuthSession?> RestoreSessionAsync(
        CancellationToken token, ScmOAuthSession? rejectedSession)
    {
        token.ThrowIfCancellationRequested();
        Task<ScmOAuthSession?> flight;
        lock (_restoreFlightSync)
        {
            // The flight owns its deadline and transport; no waiter owns its
            // cancellation. A completed failure permits a later independent retry.
            if (_restoreFlight is { IsCompleted: false } pending) flight = pending;
            else
            {
                flight = _restoreFlight = RunRestoreFlightAsync(rejectedSession, token);
                // All waiters may leave. Observe a later failure without changing
                // the task result delivered to any remaining/new waiter.
                _ = flight.ContinueWith(completed => { _ = completed.Exception; }, CancellationToken.None,
                    TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously,
                    TaskScheduler.Default);
            }
        }
        var restored = await flight.WaitAsync(token).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        if (rejectedSession is not null && restored is not null && !SameOwner(restored, rejectedSession))
            throw new ScmRefreshTemporarilyUnavailableException("Account changed during session recovery.");
        return restored;
    }

    private async Task<ScmOAuthSession?> RunRestoreFlightAsync(ScmOAuthSession? rejected, CancellationToken displayOwnerCancellation)
    {
        using var lifetime = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var drained = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        try
        {
            return await RestoreSessionCoreAsync(lifetime.Token, rejected, drained.Task, displayOwnerCancellation).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
        {
            throw new ScmRefreshTemporarilyUnavailableException("Session recovery timed out.");
        }
        finally { drained.TrySetResult(); }
    }

    private static bool SameOwner(ScmOAuthSession first, ScmOAuthSession second) =>
        first.AuthorityId == second.AuthorityId && first.Subject == second.Subject;

    private static bool SameCredential(ScmOAuthSession first, ScmOAuthSession second) =>
        SameOwner(first, second) && first.CredentialVersion == second.CredentialVersion;

    private async Task AdoptInitialResourceSessionAsync(ScmOAuthSession session, CancellationToken token)
    {
        // Existing hosts may supply an already authenticated session. Adopt it
        // once, without storage writes; a retired lifecycle can never be revived
        // by a late caller handing the old session back.
        if (_currentSession is not null || _sessionWasInstalled) return;
        await _refreshGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            if (_currentSession is null && !_sessionWasInstalled)
            {
                _currentSession = session;
                _sessionWasInstalled = true;
            }
        }
        finally { _refreshGate.Release(); }
    }

    // Successful resource reads can finish after rotation or logout. They may
    // update metadata, but must never install their old credential again.
    private ScmOAuthSession PublishResourceSession(ScmOAuthSession updated)
    {
        while (true)
        {
            var current = Volatile.Read(ref _currentSession);
            if (current is null) return updated; // A caller-owned/preloaded projection only.
            if (!SameOwner(current, updated))
                throw new ScmRefreshTemporarilyUnavailableException("Account changed during resource read.");
            if (!SameCredential(current, updated) || current.ExpiresAt == DateTimeOffset.MinValue)
                return current;
            if (ReferenceEquals(Interlocked.CompareExchange(ref _currentSession, updated, current), current))
                return updated;
        }
    }

    private async Task<ScmOAuthSession> ReuseSupersedingSessionAsync(
        ScmOAuthSession rejected, CancellationToken token)
    {
        await _refreshGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            var current = _currentSession;
            if (current is not null && SameOwner(current, rejected) && !SameCredential(current, rejected) &&
                _retainedRefresh is null && current.ExpiresAt > SessionNow)
                return current;
            throw new ScmRefreshTemporarilyUnavailableException("Session recovery is temporarily unavailable.");
        }
        finally { _refreshGate.Release(); }
    }

    private async Task<bool> ExpireRejectedResourceSessionAsync(ScmOAuthSession rejected)
    {
        await _refreshGate.WaitAsync(CancellationToken.None).ConfigureAwait(false);
        try
        {
            if (_currentSession is not { } current || !SameCredential(current, rejected) ||
                _retainedRefresh is not null) return false;
            // Resource 401 proves only that this access token is unusable. Keep
            // the refresh credential and version, without a sign-out notification.
            _currentSession = current with { ExpiresAt = DateTimeOffset.MinValue };
            _sessionWasInstalled = true;
            return true;
        }
        finally { _refreshGate.Release(); }
    }

    private async Task<(bool Retired, bool Notify)> ObserveAuthoritativeCredentialRejectionAsync(ScmOAuthSession rejected)
    {
        await _refreshGate.WaitAsync(CancellationToken.None).ConfigureAwait(false);
        try
        {
            // Only the guarded refresh/identity/device rejection path may have
            // cleared storage. Resource failures themselves never retire it.
            if (_currentSession is not null || _retainedRefresh is not null ||
                _rejectedSession is not { } actual || !SameCredential(actual, rejected)) return (false, false);
            var notify = _notifiedCredentialVersion != rejected.CredentialVersion;
            _notifiedCredentialVersion = rejected.CredentialVersion;
            return (true, notify);
        }
        finally { _refreshGate.Release(); }
    }
}

/// <summary>A token refresh/credential recovery failed temporarily, never proof of
/// user rejection. StatusCode is deliberately null; endpoint status cannot be
/// classified as a resource 401. Callers may use existing retry/backoff policy.</summary>
public sealed class ScmRefreshTemporarilyUnavailableException(string message)
    : HttpRequestException(message);
