namespace StarBridge.Desktop;

/// <summary>Member rotation: fixed pages, hold while a row shows its cue, jump to unseen relevant changes.</summary>
public sealed partial class OverlayViewModel
{
    private readonly OverlayMemberPagingTracker _memberPaging = new();
    private IReadOnlyDictionary<string, int> _memberPageByKey = new Dictionary<string, int>();
    private IReadOnlyList<string> _visibleRotatingMemberKeys = [];
    private int _memberPageIndex;
    private int _memberFlipSequence;
    private long _memberPagingAuthorizationGeneration;
    private bool _memberPageHeld;
    private bool _observeMemberChanges;
    private OverlayMemberPagingFrame _memberPagingFrame = OverlayMemberPagingFrame.Single;

    public OverlayMemberPagingFrame MemberPaging => _memberPagingFrame;

    private void ObserveMemberPaging(
        OverlayAuthorizedRoster source,
        OverlayRosterProjection projection,
        OverlayRosterViewport viewport,
        IReadOnlyList<PlayerRow> visible,
        bool rotating,
        DateTimeOffset now)
    {
        var visibleKeys = visible.Select(OverlayMemberPagingTracker.KeyOf).ToHashSet(StringComparer.OrdinalIgnoreCase);
        // Rotation ticks re-project the same roster; only a fresh roster can carry changes.
        if (_observeMemberChanges)
        {
            _observeMemberChanges = false;
            var local = OverlayRosterPlanner.ResolveLocalContext(source, viewport);
            _memberPaging.Observe(OverlayRosterPlanner.ClassifyMembers(source, viewport), visibleKeys,
                local.Shard is not null, now, local.Location is not null);
        }

        _memberPaging.ShowPendingIfVisible(visibleKeys, now);
        _memberPageByKey = projection.RotationPages
            .Where(pair => pair.Key >= 0 && pair.Key < source.Members.Count)
            .GroupBy(pair => OverlayMemberPagingTracker.KeyOf(source.Members[pair.Key]), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First().Value, StringComparer.OrdinalIgnoreCase);
        _visibleRotatingMemberKeys = visible
            .Where((_, index) => index < projection.Groups.Count && projection.Groups[index] != OverlayRosterGroup.Pinned)
            .Select(OverlayMemberPagingTracker.KeyOf)
            .ToArray();
        _memberPageIndex = projection.PageIndex;
        _memberPagingFrame = rotating
            ? new OverlayMemberPagingFrame(projection.PageIndex, projection.PageCount,
                _memberPaging.PendingPages(_memberPageByKey, projection.PageIndex), _memberFlipSequence)
                { AuthorizationGeneration = _memberPagingAuthorizationGeneration }
            : OverlayMemberPagingFrame.Single with { FlipSequence = _memberFlipSequence, AuthorizationGeneration = _memberPagingAuthorizationGeneration };
    }

    private void AdvanceMemberPage()
    {
        var now = DateTimeOffset.UtcNow;
        if (_memberPaging.TryHold(_visibleRotatingMemberKeys, now, out var wait))
        {
            // Keep this page until its change cue has played, then check again.
            _memberPageHeld = true;
            _rosterRotationTimer.Interval = wait;
            return;
        }

        _memberPageHeld = false;
        _rosterRotationTimer.Interval = TimeSpan.FromSeconds(_rosterSelectionSettings.RotationIntervalSeconds);
        if (_memberPaging.TryTakeJump(_memberPageByKey, _memberPageIndex, now, out var page))
            _rosterRotationCursor.JumpTo(page);
        else
            _rosterRotationCursor.Advance();
        _memberFlipSequence++;
        RefreshMembersFromAuthorizedRoster();
    }

    private void ResetMemberPaging()
    {
        _memberPagingAuthorizationGeneration++;
        _memberPaging.Reset();
        _memberPageByKey = new Dictionary<string, int>();
        _visibleRotatingMemberKeys = [];
        _memberPageIndex = 0;
        _memberPageHeld = false;
        _observeMemberChanges = false;
        _memberPagingFrame = OverlayMemberPagingFrame.Single with { FlipSequence = _memberFlipSequence, AuthorizationGeneration = _memberPagingAuthorizationGeneration };
    }
}
