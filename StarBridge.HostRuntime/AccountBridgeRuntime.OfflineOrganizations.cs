using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;
using System.Diagnostics;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private async Task<OfflineOrganizationReadLease?> BeginOrganizationDisplayRead(BridgeAccountContext owner, long generation, CancellationToken token)
    {
        bool Current() => !token.IsCancellationRequested && !_disposed && !_firstUseCandidate && !_requestRetirement.IsClosed &&
            generation == Generation && owner == _host.CurrentContext;
        var started = Stopwatch.GetTimestamp();
        var waited = false;
        while (true)
        {
            token.ThrowIfCancellationRequested();
            if (!Current())
            {
                if (waited) throw new OperationCanceledException("Organization display read retired.", token);
                return null;
            }
            try { return _offlineAccount?.BeginOrganizationRead(owner, Current); }
            catch (IOException error) when ((error.HResult & 0xffff) is 32 or 33 &&
                Stopwatch.GetElapsedTime(started) < TimeSpan.FromMilliseconds(250))
            {
                waited = true;
                await Task.Delay(TimeSpan.FromMilliseconds(10), token);
            }
            catch (Exception error) when (CacheFailure(error))
            {
                token.ThrowIfCancellationRequested();
                // No guarded remote read is possible when persistence itself
                // fails. Sharing contention alone receives the bounded wait.
                throw new AccountBridgeHostException("communities.readTransient", true);
            }
        }
    }
    private void CompleteOrganizationDisplayRead(OfflineOrganizationReadLease lease, long generation, bool withdraw)
    {
        var currentOwner = !_disposed && generation == Generation && lease.Owner == _host.CurrentContext;
        // Completion can restore only the previously eligible version. It is
        // not a new display publication and must drain during mode shutdown.
        try { _offlineAccount?.CompleteOrganizationRead(lease, withdraw && currentOwner, () => !_firstUseCandidate); }
        catch (Exception error) when (CacheFailure(error)) { }
    }
    private void ObserveOrganizationDisplay(OfflineOrganizationReadLease lease, BridgeAccountContext owner, long generation, string? after, string? next,
        IReadOnlyList<OfflineOrganizationObservation> rows, CancellationToken token)
    {
        bool Current() => !token.IsCancellationRequested && !_disposed && !_firstUseCandidate && !_requestRetirement.IsClosed &&
            generation == Generation && owner == _host.CurrentContext;
        try { if (Current()) _offlineAccount?.ObserveOrganizations(owner, generation, after, next, rows, Current, lease); }
        catch (Exception error) when (CacheFailure(error)) { }
    }
    private OfflineOrganizationImageRead? CaptureOrganizationImageRead(BridgeAccountContext owner, long generation, CancellationToken token)
    {
        bool Current() => !token.IsCancellationRequested && !_disposed && !_firstUseCandidate && !_requestRetirement.IsClosed &&
            generation == Generation && owner == _host.CurrentContext;
        try { return Current() ? _offlineAccount?.CaptureOrganizationImageRead(owner, Current) : null; }
        catch (Exception error) when (CacheFailure(error)) { return null; }
    }
    private void ObserveOrganizationLogo(OfflineOrganizationImageRead imageRead, BridgeAccountContext owner, long generation, string code, string image, CancellationToken token)
    {
        bool Current() => !token.IsCancellationRequested && !_disposed && !_firstUseCandidate && !_requestRetirement.IsClosed &&
            generation == Generation && owner == _host.CurrentContext;
        try { if (Current()) _offlineAccount?.ObserveOrganizationLogo(owner, code, image, Current, imageRead); }
        catch (Exception error) when (CacheFailure(error)) { }
    }
    internal OfflineOrganizationDirectory? ReadOfflineOrganizations(long revision, Func<bool> current) =>
        _offlineAccount?.ReadOfflineOrganizations(revision, current);
}
