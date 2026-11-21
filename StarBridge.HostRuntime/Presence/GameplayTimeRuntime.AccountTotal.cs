using StarBridge.Core.Profiles;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

public sealed record GameplayAccountTotal(string State, long? Seconds = null);

public interface IGameplayAccountTotalRemote
{
    Task<GameplayAccountTotal> ReadAccountTotalAsync(BridgeAccountContext owner, CancellationToken token);
}

public sealed partial class GameplayTimeRuntime
{
    // Login is read-only. Later reads follow the existing publication cadence.
    public async Task RefreshAccountTotalAsync(bool once = false, CancellationToken cancellation = default)
    {
        using var work = _work.Enter(cancellation);
        if (work is null || _historyRemote is not IGameplayAccountTotalRemote remote) return;
        if (once) await _historyGate.WaitAsync(work.Token).ConfigureAwait(false);
        else if (!await _historyGate.WaitAsync(0, work.Token).ConfigureAwait(false)) return;
        (BridgeAccountContext? Context, long Generation) owner = default;
        try
        {
            lock (_sync)
            {
                owner = _current();
                if (!work.IsCurrent || owner.Context is null) return;
                if (!_entries.TryGetValue(owner.Context, out var entry))
                    _entries.Add(owner.Context, entry = new Entry());
                if (once && entry.AccountReadGeneration == owner.Generation) return;
                entry.AccountReadGeneration = owner.Generation;
            }
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(work.Token);
            budget.CancelAfter(TimeSpan.FromSeconds(8));
            var total = await remote.ReadAccountTotalAsync(owner.Context!, budget.Token).ConfigureAwait(false);
            lock (_sync)
                if (OwnerIsCurrent(owner, budget.Token)) SetAccountTotal(_entries[owner.Context!], total);
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            lock (_sync)
                if (owner.Context is not null && OwnerIsCurrent(owner)) SetAccountTotal(_entries[owner.Context!], new("unavailable"));
        }
        finally { _historyGate.Release(); }
    }

    private static void SetAccountTotal(Entry entry, GameplayAccountTotal total)
    {
        var valid = total.State == "available" && total.Seconds is >= 0 ||
            total.State == "empty" && total.Seconds is null;
        entry.AccountTotalState = valid ? total.State : "unavailable";
        entry.AccountTotalSeconds = valid ? total.Seconds : null;
    }

    private async Task ObservePublishedTotalAsync(Entry entry, GameplayTimeResetState state,
        (BridgeAccountContext? Context, long Generation) owner, CancellationToken token)
    {
        // Revision zero also exists in old saved statistics. The own-profile
        // nullable statistics field settles this ambiguity without a server change.
        GameplayAccountTotal total;
        try
        {
            total = state.Revision > 0
                ? new("available", state.PlayTimeSeconds)
                : _historyRemote is IGameplayAccountTotalRemote remote
                    ? await remote.ReadAccountTotalAsync(owner.Context!, token).ConfigureAwait(false)
                    : new("unavailable");
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            // The optional absence check cannot change the existing publisher's
            // max merge or write eligibility after its authoritative read succeeded.
            total = new("unavailable");
        }
        lock (_sync)
            // A cancelled display read must invalidate an older observation.
            // Check ownership independently of that request's expired budget.
            if (OwnerIsCurrent(owner) &&
                _entries.TryGetValue(owner.Context!, out var current) && ReferenceEquals(current, entry))
                SetAccountTotal(entry, token.IsCancellationRequested ? new("unavailable") : total);
    }
}
