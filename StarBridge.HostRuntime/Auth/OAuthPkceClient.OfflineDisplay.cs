namespace StarBridge.HostRuntime.Auth;

// Native-only selector for private display data. Not an authenticated context,
// permission, entitlement receipt, or a value to expose over the Bridge.
internal sealed record ScmOfflineDisplayOwner(string Authority, string Subject,
    ScmCredentialRetirementStamp CredentialVersion);

public sealed partial class OAuthPkceClient
{
    private ScmOfflineDisplayOwner? _offlineDisplayOwner;
    private volatile bool _offlineDisplayReady;
    private ScmRestoreDisplayRead? _restoreDisplayRead;
    internal event Action<ScmRestoreDisplayRead>? RestoreDisplayPreparing;

    internal ScmOfflineDisplayOwner? ReadOfflineDisplayOwner()
    {
        var selected = Volatile.Read(ref _offlineDisplayOwner);
        if (!_offlineDisplayReady || selected is null || LastSessionRestoreOutcome != ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable ||
            tokenVault is not WindowsTokenVault windows) return null;
        try
        {
            return windows.IsRetirementCurrent(selected.CredentialVersion) && _offlineDisplayReady &&
                ReferenceEquals(selected, Volatile.Read(ref _offlineDisplayOwner)) &&
                LastSessionRestoreOutcome == ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable
                ? selected : null;
        }
        catch (Exception error) when (OfflineDisplayStorageFailure(error)) { return null; }
    }

    private void CaptureOfflineDisplayOwner(ScmResumeCredential? credential, CancellationToken token, Task drained,
        CancellationToken displayOwnerCancellation)
    {
        Volatile.Write(ref _offlineDisplayOwner, null);
        if (credential is null || !credential.AccountKey.StartsWith(options.AuthorityId + ":", StringComparison.Ordinal)) return;
        var subject = credential.AccountKey[(options.AuthorityId.Length + 1)..];
        if (string.IsNullOrWhiteSpace(subject) || subject.Any(char.IsControl)) return;
        // Share the original atomic capture used by refresh, not a later read
        // that could adopt a replacement credential even with the same secret.
        var selected = new ScmOfflineDisplayOwner(options.AuthorityId, subject, credential.Version);
        Volatile.Write(ref _offlineDisplayOwner, selected);
        if (tokenVault is WindowsTokenVault windows && RestoreDisplayPreparing is { } observe)
        {
            var read = new ScmRestoreDisplayRead(windows, selected, token, drained, displayOwnerCancellation);
            Volatile.Write(ref _restoreDisplayRead, read);
            observe(read);
        }
    }

    private void RotateOfflineDisplayOwner(string accountKey)
    {
        var selected = Volatile.Read(ref _offlineDisplayOwner);
        var version = _credentialRetirement;
        if (selected is null || version is null || accountKey != $"{selected.Authority}:{selected.Subject}")
        {
            Volatile.Write(ref _offlineDisplayOwner, null);
            return;
        }
        // Use the exact receipt returned by the completed vault write, never a
        // recapture which could silently adopt a concurrent replacement login.
        var next = selected with { CredentialVersion = version };
        Volatile.Write(ref _offlineDisplayOwner, next);
        Volatile.Read(ref _restoreDisplayRead)?.Rotate(next);
    }

    private static bool OfflineDisplayStorageFailure(Exception error) => error is
        System.IO.IOException or UnauthorizedAccessException or System.Security.Cryptography.CryptographicException or
        System.Text.Json.JsonException or System.Security.SecurityException or NotSupportedException;
}
