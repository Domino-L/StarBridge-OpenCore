using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private readonly AsyncLocal<RestoreDisplayObserver?> _restoreDisplayObserver = new();
    private sealed class RestoreDisplayObserver(ScmAccountBridgeHost owner, Action<AccountRestoreDisplayScope>? observe,
        RestoreDisplayObserver? previous) : IDisposable
    {
        private Action<AccountRestoreDisplayScope>? _observe = observe;
        private int _closed;
        internal bool Active => Volatile.Read(ref _closed) == 0 && Volatile.Read(ref _observe) is not null;
        internal void Emit(AccountRestoreDisplayScope scope)
        {
            var action = Volatile.Read(ref _observe);
            if (Volatile.Read(ref _closed) == 0) action?.Invoke(scope);
        }
        public void Dispose()
        {
            Interlocked.Exchange(ref _closed, 1);
            Volatile.Write(ref _observe, null);
            if (ReferenceEquals(owner._restoreDisplayObserver.Value, this)) owner._restoreDisplayObserver.Value = previous;
        }
    }
    internal IDisposable BeginRestoreDisplayObservation(Action<AccountRestoreDisplayScope>? observe)
    {
        var next = new RestoreDisplayObserver(this, observe, _restoreDisplayObserver.Value);
        _restoreDisplayObserver.Value = next;
        return next;
    }
    private bool WantsRestoreDisplay => _restoreDisplayObserver.Value?.Active == true;
    internal bool MayPrepareRestoreDisplay => !_disposed && !IsBusinessStartupDeferred && !_localModeSessionLoopsStopped &&
        _session is null && _legacySession is null && (!_restoreAttempted || _credentialTemporarilyUnavailable || _legacyRestoreUnavailable);
    private void PublishRestoredSession(ScmOAuthSession session, AccountRestoreDisplayScope? scope)
    {
        lock (_realtimeGate)
            PublishSessionState(session, false, null, false, null, null, null, null, scope);
    }
    private AccountRestoreDisplayScope? ObserveRestoreDisplay(ScmRestoreDisplayRead read)
    {
        if (_disposed || IsBusinessStartupDeferred || _localModeSessionLoopsStopped ||
            _session is not null || _legacySession is not null || _restoreDisplayObserver.Value is not { Active: true } observe ||
            read.ReadCurrent() is not { } selected)
        { read.Dispose(); return null; }
        var scope = new AccountRestoreDisplayScope(read, new(_environment, selected.Authority, selected.Subject),
            Generation, () => Generation, () => CurrentContext,
            () => !_disposed && !IsBusinessStartupDeferred && !_localModeSessionLoopsStopped && !_reauthorizationRequired);
        observe.Emit(scope);
        return scope;
    }
}
