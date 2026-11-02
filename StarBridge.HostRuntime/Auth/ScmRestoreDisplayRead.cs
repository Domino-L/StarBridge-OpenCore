namespace StarBridge.HostRuntime.Auth;

// One original restore's presentation receipt. It contains no refresh/access
// secret. Only that restore's completed vault rotation may renew its version.
internal sealed class ScmRestoreDisplayRead(WindowsTokenVault vault, ScmOfflineDisplayOwner selected,
    CancellationToken token, Task? drained = null, CancellationToken displayOwnerCancellation = default) : IDisposable
{
    internal Task DrainAsync() => drained ?? Task.CompletedTask;
    private ScmOfflineDisplayOwner _selected = selected;
    private int _closed;
    internal ScmOfflineDisplayOwner? ReadCurrent()
    {
        var value = Volatile.Read(ref _selected);
        if (Volatile.Read(ref _closed) != 0 || token.IsCancellationRequested || displayOwnerCancellation.IsCancellationRequested) return null;
        try
        {
            return vault.IsRetirementCurrent(value.CredentialVersion) &&
                Volatile.Read(ref _closed) == 0 && !token.IsCancellationRequested && !displayOwnerCancellation.IsCancellationRequested &&
                ReferenceEquals(value, Volatile.Read(ref _selected)) ? value : null;
        }
        catch (Exception error) when (error is System.IO.IOException or UnauthorizedAccessException or
            System.Security.Cryptography.CryptographicException or System.Text.Json.JsonException or
            System.Security.SecurityException or NotSupportedException) { return null; }
    }
    internal void Rotate(ScmOfflineDisplayOwner next)
    {
        var before = Volatile.Read(ref _selected);
        if (Volatile.Read(ref _closed) == 0 && next.Authority == before.Authority && next.Subject == before.Subject)
            Volatile.Write(ref _selected, next);
    }
    public void Dispose() => Interlocked.Exchange(ref _closed, 1);
}
