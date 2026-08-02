namespace StarBridge.Desktop;

internal enum InGameWorkspaceRequestLane
{
    SocialRefresh,
    SocialSelection,
    SocialSend,
    FriendSearch,
    FriendAction,
    RoomRefresh,
    RoomMutation
}

internal enum InGameWorkspaceRequestPolicy
{
    LatestWins,
    DropIfRunning
}

internal sealed class InGameWorkspaceRequest : IDisposable
{
    private InGameWorkspaceRequestGate? _owner;

    internal InGameWorkspaceRequest(
        InGameWorkspaceRequestGate? owner,
        long lifetimeRevision,
        long requestRevision,
        AccountSessionLease accountSession,
        InGameWorkspaceRequestLane lane,
        string targetKey,
        bool ownsLane)
    {
        _owner = owner;
        LifetimeRevision = lifetimeRevision;
        RequestRevision = requestRevision;
        AccountSession = accountSession;
        Lane = lane;
        TargetKey = targetKey;
        OwnsLane = ownsLane;
    }

    internal static InGameWorkspaceRequest Rejected { get; } = new(
        null,
        0,
        0,
        default,
        default,
        "",
        false);

    internal long LifetimeRevision { get; }
    internal long RequestRevision { get; }
    internal AccountSessionLease AccountSession { get; }
    internal InGameWorkspaceRequestLane Lane { get; }
    internal string TargetKey { get; }
    internal bool OwnsLane { get; }
    internal bool Started => _owner is not null;
    internal bool IsCurrent => _owner?.IsCurrent(this) == true;

    public void Dispose()
    {
        var owner = Interlocked.Exchange(ref _owner, null);
        owner?.Complete(this);
    }
}

/// <summary>
/// Owns request freshness for the retained in-game workspace. Account changes and
/// application shutdown invalidate every request; hiding a tool does not, because
/// hidden tools deliberately keep their content for the current application session.
/// </summary>
internal sealed class InGameWorkspaceRequestGate : IDisposable
{
    private readonly Dictionary<InGameWorkspaceRequestLane, long> _latestRequests = [];
    private readonly Dictionary<InGameWorkspaceRequestLane, long> _runningLaneOwners = [];
    private AccountSessionLease _accountSession;
    private long _lifetimeRevision = 1;
    private long _requestRevision;
    private bool _hasAccountSession;
    private bool _disposed;

    internal bool BeginAccountSession(AccountSessionLease accountSession)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_hasAccountSession && Matches(_accountSession, accountSession))
        {
            return false;
        }

        _hasAccountSession = true;
        _accountSession = accountSession;
        _lifetimeRevision++;
        _latestRequests.Clear();
        _runningLaneOwners.Clear();
        return true;
    }

    internal InGameWorkspaceRequest Begin(
        AccountSessionLease accountSession,
        InGameWorkspaceRequestLane lane,
        string? targetKey = null,
        InGameWorkspaceRequestPolicy policy = InGameWorkspaceRequestPolicy.LatestWins)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        _ = BeginAccountSession(accountSession);
        if (policy == InGameWorkspaceRequestPolicy.DropIfRunning &&
            _runningLaneOwners.ContainsKey(lane))
        {
            return InGameWorkspaceRequest.Rejected;
        }

        var revision = ++_requestRevision;
        _latestRequests[lane] = revision;
        var ownsLane = policy == InGameWorkspaceRequestPolicy.DropIfRunning;
        if (ownsLane)
        {
            _runningLaneOwners[lane] = revision;
        }

        return new InGameWorkspaceRequest(
            this,
            _lifetimeRevision,
            revision,
            _accountSession,
            lane,
            NormalizeTarget(targetKey),
            ownsLane);
    }

    internal bool Accepts(AccountSessionLease accountSession) =>
        !_disposed &&
        _hasAccountSession &&
        Matches(_accountSession, accountSession);

    internal bool IsCurrent(InGameWorkspaceRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        return !_disposed &&
               request.Started &&
               request.LifetimeRevision == _lifetimeRevision &&
               Matches(request.AccountSession, _accountSession) &&
               _latestRequests.TryGetValue(request.Lane, out var revision) &&
               revision == request.RequestRevision;
    }

    internal void Invalidate()
    {
        if (_disposed)
        {
            return;
        }

        _lifetimeRevision++;
        _latestRequests.Clear();
        _runningLaneOwners.Clear();
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        Invalidate();
        _disposed = true;
    }

    internal void Complete(InGameWorkspaceRequest request)
    {
        if (!request.OwnsLane)
        {
            return;
        }

        if (_runningLaneOwners.TryGetValue(request.Lane, out var ownerRevision) &&
            ownerRevision == request.RequestRevision)
        {
            _runningLaneOwners.Remove(request.Lane);
        }
    }

    private static bool Matches(
        AccountSessionLease left,
        AccountSessionLease right) =>
        left.Revision == right.Revision &&
        string.Equals(
            left.StableKey,
            right.StableKey,
            StringComparison.OrdinalIgnoreCase);

    private static string NormalizeTarget(string? targetKey) =>
        string.IsNullOrWhiteSpace(targetKey) ? "" : targetKey.Trim();
}
