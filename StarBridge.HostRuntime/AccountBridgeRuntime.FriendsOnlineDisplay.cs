using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private readonly AsyncLocal<FriendsDisplayTransaction?> _friendsDisplayRequest = new();

    private sealed class FriendsDisplayTransaction(AccountBridgeRuntime owner, BridgeEnvelope request,
        CancellationToken token, FriendsDisplayTransaction? previous) : IDisposable
    {
        internal readonly BridgeEnvelope Request = request;
        private readonly Onboarding.FirstUseModeRuntime? _mode = owner.FirstUseMode;
        private readonly long? _revision = owner.FirstUseMode?.Current.Revision;
        private readonly long _pageRevision = Volatile.Read(ref owner._friendPageRevision);
        private int _closed, _published;
        internal bool Current => Volatile.Read(ref _closed) == 0 && !token.IsCancellationRequested &&
            !owner._disposed && !owner._firstUseCandidate && !owner._requestRetirement.IsClosed &&
            Request.SessionGeneration == owner.Generation && Request.AccountContext == owner._host.CurrentContext &&
            ReferenceEquals(_mode, owner.FirstUseMode) && (_mode is null ||
                _mode.Current is { State: "online", ActiveMode: "online" } observed && observed.Revision == _revision);
        internal bool BeginPublish() => Interlocked.Exchange(ref _published, 1) == 0;
        internal Func<bool> CaptureSnapshotCurrent(long? completedCommandRevision = null)
        {
            var revision = completedCommandRevision ?? _pageRevision;
            return () => !owner._disposed && !owner._firstUseCandidate &&
            revision == Volatile.Read(ref owner._friendPageRevision) &&
            !owner._requestRetirement.IsClosed && Request.SessionGeneration == owner.Generation &&
            Request.AccountContext == owner._host.CurrentContext && ReferenceEquals(_mode, owner.FirstUseMode) &&
            (_mode is null || _mode.Current is { State: "online", ActiveMode: "online" } observed && observed.Revision == _revision);
        }
        public void Dispose()
        {
            Interlocked.Exchange(ref _closed, 1);
            if (ReferenceEquals(owner._friendsDisplayRequest.Value, this)) owner._friendsDisplayRequest.Value = previous;
        }
    }

    private FriendsDisplayTransaction? EnterFriendsDisplay(BridgeEnvelope request, CancellationToken token)
    {
        if (request.Name is not (AccountBridgeRequestNames.ReadFriends or AccountBridgeRequestNames.ExecuteFriend) || _firstUseCandidate ||
            request.AccountContext is null) return null;
        var next = new FriendsDisplayTransaction(this, request, token, _friendsDisplayRequest.Value);
        _friendsDisplayRequest.Value = next;
        return next;
    }

    private void PrepareFriendsDisplay(OfflineFriendsReadLease lease, long generation, Func<bool> current)
    {
        var transaction = _friendsDisplayRequest.Value;
        if (transaction is null || !transaction.Current || transaction.Request.AccountContext != lease.Owner ||
            transaction.Request.SessionGeneration != generation || lease.Display is not { } display ||
            !transaction.BeginPublish()) return;
        var snapshotCurrent = transaction.CaptureSnapshotCurrent();
        bool Current()
        {
            if (!transaction.Current || !snapshotCurrent() || !current()) return false;
            try
            {
                BridgeAccountContext? storage = null;
                try { storage = _host.ResolveLocalDataOwner(lease.Owner); }
                catch (Privacy.LocalPrivacyOwnerUnavailableException) { }
                return storage == lease.StorageOwner && _offlineAccount?.IsFriendsDisplayCurrent(lease, current) == true;
            }
            catch (Exception error) when (CacheFailure(error) || error is Privacy.LocalPrivacyException) { return false; }
        }
        object directory = display.Directory;
        if (FriendsReader.WantsPagedResponse(transaction.Request.Payload))
        {
            try
            {
                directory = _friendPages.Open(JsonSerializer.SerializeToElement(display.Directory, BridgeProtocol.JsonOptions),
                    lease.Owner, generation, "display:" + transaction.Request.CorrelationId, Current);
            }
            catch (AccountBridgeHostException) { return; } // optional presentation cannot fail the actual read
        }
        _dispatcher.PublishFriendsDisplayProgress(generation, new {
            schemaVersion = 1, requestCorrelationId = transaction.Request.CorrelationId,
            directory, display.CachedAtUtc
        }, Current);
    }
}
