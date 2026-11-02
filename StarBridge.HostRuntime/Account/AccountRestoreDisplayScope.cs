using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

// A finite, display-only child of one pending root read, not an account session.
internal sealed class AccountRestoreDisplayScope(ScmRestoreDisplayRead read, BridgeAccountContext owner,
    long initialGeneration, Func<long> generation, Func<BridgeAccountContext?> context, Func<bool> available) : IDisposable
{
    private sealed record Binding(long Generation, BridgeAccountContext? Context);
    private Binding _binding = new(initialGeneration, null);
    private Func<bool>? _storageCurrent;
    internal BridgeAccountContext Owner { get; } = owner;
    internal long InitialGeneration { get; } = initialGeneration;
    internal bool HasAuthenticatedOwner => Volatile.Read(ref _binding).Context is not null;
    internal void BindStorageFence(Func<bool> current) => Interlocked.CompareExchange(ref _storageCurrent, current, null);
    internal ScmOfflineDisplayOwner? ReadCurrent()
    {
        var binding = Volatile.Read(ref _binding);
        var receipt = read.ReadCurrent();
        return receipt is not null && receipt.Authority == Owner.Authority && receipt.Subject == Owner.Subject &&
            available() && generation() == binding.Generation && context() == binding.Context &&
            (Volatile.Read(ref _storageCurrent)?.Invoke() ?? true) &&
            ReferenceEquals(binding, Volatile.Read(ref _binding)) ? receipt : null;
    }
    internal void BindAuthenticated(BridgeAccountContext actual, long actualGeneration)
    {
        // Only PublishSession for this original restored session calls this.
        // Other transitions, including a new same-account login, do not renew it.
        if (actual == Owner && InitialGeneration < long.MaxValue && actualGeneration == InitialGeneration + 1 &&
            read.ReadCurrent() is not null)
            Volatile.Write(ref _binding, new(actualGeneration, actual));
    }
    public void Dispose() => read.Dispose();
    internal Task DrainAsync() => read.DrainAsync();
}
