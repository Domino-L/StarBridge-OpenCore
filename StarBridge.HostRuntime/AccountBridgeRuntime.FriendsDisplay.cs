using System.Diagnostics;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private async Task<OfflineFriendsReadLease?> BeginFriendsDisplayRead(BridgeAccountContext owner, long generation, bool displayRequested, CancellationToken token)
    {
        bool Current() => !token.IsCancellationRequested && !_disposed && !_firstUseCandidate && !_requestRetirement.IsClosed &&
            generation == Generation && owner == _host.CurrentContext;
        var started = Stopwatch.GetTimestamp();
        while (true)
        {
            token.ThrowIfCancellationRequested();
            if (!Current()) return null;
            try {
                var capture = displayRequested && _friendsDisplayRequest.Value?.Current == true;
                var lease = _offlineAccount?.BeginFriendsRead(owner, Current, capture);
                if (capture && lease is not null)
                    try { PrepareFriendsDisplay(lease, generation, Current); }
                    catch { lease.Dispose(); throw; }
                return lease;
            }
            catch (IOException error) when ((error.HResult & 0xffff) is 32 or 33 &&
                Stopwatch.GetElapsedTime(started) < TimeSpan.FromMilliseconds(250))
            { await Task.Delay(TimeSpan.FromMilliseconds(10), token); }
            catch (Exception error) when (CacheFailure(error))
            { token.ThrowIfCancellationRequested(); throw new AccountBridgeHostException("friends.read_transient", true); }
        }
    }

    private void CompleteFriendsDisplayRead(OfflineFriendsReadLease lease, long generation,
        OfflineFriendsReadOutcome outcome, FriendsView? result)
    {
        bool Current() => !_disposed && !_firstUseCandidate && generation == Generation && lease.Owner == _host.CurrentContext;
        // A rejected directory also closes pages from previous successful reads.
        // Revision retirement prevents in-flight reads from reopening old snapshots.
        if (outcome == OfflineFriendsReadOutcome.Rejected && Current()) RetireFriendsPages();
        try { _offlineAccount?.CompleteFriendsRead(lease, outcome, result, Current); }
        catch (Exception error) when (CacheFailure(error)) { }
        finally { lease.Dispose(); }
    }
}
