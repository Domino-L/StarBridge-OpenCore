namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Accessed only under _refreshGate. Never persisted or keyed by a token.
    private string? _restoreBackoffAccount;
    private int _restoreFailureCount;
    private DateTimeOffset _restoreRetryAt;
    private bool _restoreBackoffLogged;
    internal Func<double> RestoreBackoffRandom { get; init; } = Random.Shared.NextDouble;

    private void ResetRestoreBackoff()
    {
        _restoreBackoffAccount = null;
        _restoreFailureCount = 0;
        _restoreRetryAt = default;
        _restoreBackoffLogged = false;
    }

    private void SelectRestoreBackoffAccount(string? accountKey)
    {
        if (string.Equals(_restoreBackoffAccount, accountKey, StringComparison.Ordinal)) return;
        ResetRestoreBackoff();
        _restoreBackoffAccount = accountKey;
    }

    private void ThrowIfRestoreBackoff(string correlationId)
    {
        var remaining = _restoreRetryAt - SessionNow;
        if (_restoreFailureCount == 0 || remaining <= TimeSpan.Zero) return;
        if (!_restoreBackoffLogged)
        {
            _restoreBackoffLogged = true;
            ScmAuthDiagnostics.Write(correlationId, "refresh-token", "backoff",
                $"attempts={_restoreFailureCount} waitSeconds={(int)Math.Ceiling(remaining.TotalSeconds)}");
        }
        throw new ScmRefreshTemporarilyUnavailableException("Session recovery is temporarily unavailable.");
    }

    private void RecordRestoreFailure()
    {
        _restoreFailureCount = Math.Min(_restoreFailureCount + 1, 31);
        var seconds = Math.Min(300d, 5d * Math.Pow(2, Math.Min(_restoreFailureCount - 1, 6)));
        var jitter = 0.8d + 0.4d * Math.Clamp(RestoreBackoffRandom(), 0d, 1d);
        // Five minutes is also the absolute ceiling after jitter.
        _restoreRetryAt = SessionNow.AddSeconds(Math.Min(300d, seconds * jitter));
        _restoreBackoffLogged = false;
    }
}
