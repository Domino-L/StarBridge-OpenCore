using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Overlay;

internal sealed partial class OverlayCommunitySource
{
    internal event Action<BridgeAccountContext, long, IReadOnlySet<string>>? DirectoryMembershipConfirmed;
    internal event Action<BridgeAccountContext, long, string>? MembershipRevoked;
    private sealed record WorkspaceRoster(long Sequence, DateTimeOffset AcceptedAt, InformationOverlayCommunityContent Content);
    private readonly Dictionary<string, WorkspaceRoster> _workspaceRosters = new(StringComparer.Ordinal);
    private DateTimeOffset _latestRosterReadStartedAt;
    private long _rejectedWorkspaceSequence;
    private DateTimeOffset _workspaceRejectedAt;
    private readonly Dictionary<string, DateTimeOffset> _workspaceSourceRejectedAt = new(StringComparer.Ordinal);

    private void RejectPendingWorkspace(string? code = null)
    {
        var now = _now();
        foreach (var expired in _workspaceSourceRejectedAt.Where(p => now >= p.Value.AddSeconds(40)).Select(p => p.Key).ToArray())
            _workspaceSourceRejectedAt.Remove(expired);
        if (code is null) _workspaceRejectedAt = now;
        else _workspaceSourceRejectedAt[code] = now;
    }

    private bool WorkspaceReadRejected(string code, DateTimeOffset startedAt) =>
        startedAt <= _workspaceRejectedAt ||
        _workspaceSourceRejectedAt.TryGetValue(code, out var rejectedAt) && startedAt <= rejectedAt;

    // Only complete authenticated joined-directory results enter here. Absence
    // revokes membership; filtered searches and failed reads never enter here.
    internal void ObserveDirectory(BridgeAccountContext owner, long generation, long sequence, DateTimeOffset startedAt,
        IReadOnlyList<InformationOverlayCommunityContent> rosters)
    {
        lock (_sync)
        {
            CheckScope();
            if (_disposed || _scope != (owner, generation) || _choiceFailed ||
                sequence <= _rejectedWorkspaceSequence || startedAt < _latestRosterReadStartedAt ||
                startedAt > _now() || _now() >= startedAt.AddSeconds(40)) return;
            if (startedAt <= _workspaceRejectedAt || _workspaceSourceRejectedAt.Values.Any(rejectedAt => startedAt <= rejectedAt)) return;
            var codes = rosters.Select(row => row.Code).ToHashSet(StringComparer.Ordinal);
            if (codes.Count != rosters.Count) return;
            if (_workspaceRosters.Values.Any(row => row.Sequence > sequence)) return;
            // Even an empty result before first display supersedes an older
            // pending read. That read must not later resurrect membership.
            InvalidateRead();
            _latestRosterReadStartedAt = startedAt;
            // Reject older directory/workspace callbacks, including ones which
            // arrive after a successful empty membership result.
            _rejectedWorkspaceSequence = sequence - 1;
            foreach (var code in _workspaceRosters.Where(pair => pair.Value.Sequence <= sequence && !codes.Contains(pair.Key))
                .Select(pair => pair.Key).ToArray()) RevokeWorkspace(code);
            foreach (var code in _moduleAuthorities.Keys.Where(code => !codes.Contains(code)).ToArray())
                RevokeWorkspace(code);
            foreach (var code in _moduleSessions.Keys.Where(code => !codes.Contains(code)).ToArray()) RemoveModuleSession(code);
            if (_content is not null && !codes.Contains(_content.Code))
            {
                _content = null;
            }
            if (_pageCode is not null && !codes.Contains(_pageCode)) _pageCode = null;
            if (_automaticCode is not null && !codes.Contains(_automaticCode)) _automaticCode = null;
            if (!_catalog.Select(row => row.Code).ToHashSet(StringComparer.Ordinal).SetEquals(codes))
            { _catalogAt = default; _catalogRevision++; }
            foreach (var roster in rosters.OrderBy(row => row.Code, StringComparer.Ordinal))
                ObserveWorkspace(owner, generation, sequence, startedAt, roster);
            _rejectedWorkspaceSequence = sequence;
            DirectoryMembershipConfirmed?.Invoke(owner, generation, codes);
        }
    }

    // A second consumer of the same authorized workspace, not a second identity
    // or a disk cache. Reusing a snapshot never restarts its original lease.
    internal void ObserveWorkspace(BridgeAccountContext owner, long generation, long sequence, DateTimeOffset startedAt,
        InformationOverlayCommunityContent roster)
    {
        lock (_sync)
        {
            CheckScope();
            if (_disposed || _scope != (owner, generation) || _choiceFailed) return;
            if (sequence <= _rejectedWorkspaceSequence) return;
            if (WorkspaceReadRejected(roster.Code, startedAt)) return;
            if (_workspaceRosters.TryGetValue(roster.Code, out var previous) && previous.Sequence >= sequence) return;
            var now = _now();
            if (startedAt > now || now >= startedAt.AddSeconds(40)) return;
            foreach (var key in _workspaceRosters.Where(p => now >= p.Value.AcceptedAt.AddSeconds(40)).Select(p => p.Key).ToArray())
                _workspaceRosters.Remove(key);
            if (_workspaceRosters.Count >= 32)
                _workspaceRosters.Remove(_workspaceRosters.MinBy(p => p.Value.AcceptedAt).Key);
            _workspaceRosters[roster.Code] = new(sequence, startedAt, roster with { Members = Array.AsReadOnly(roster.Members.ToArray()) });
            RenewModuleAuthority(roster.Code, startedAt.AddSeconds(40));
            if (_moduleSessions.TryGetValue(roster.Code, out var session))
                session.Source.ObserveWorkspace(owner, generation, sequence, startedAt, roster);
            var selected = _explicitCode ?? _pageCode ?? _automaticCode;
            if (_choice.Mode is "auto" or "community" && (selected is null || selected == roster.Code) && startedAt >= _latestRosterReadStartedAt)
            {
                // Older in-flight reads cannot erase or restore this newer UI
                // result. New reads still perform normal membership validation.
                InvalidateRead(rosterOnly: true);
                _catalogRevision++;
                AdoptWorkspace(roster.Code);
            }
            // Modules may use a different organization than the selected v1
            // scene. Its new authorized payload must wake the same native sink.
            NotifyContentChanged();
        }
    }

    private bool AdoptWorkspace(string? code = null)
    {
        if (_choiceFailed || _choice.Mode is not ("auto" or "community")) return false;
        code ??= _explicitCode ?? _pageCode ?? _automaticCode;
        if (code is null || !_workspaceRosters.TryGetValue(code, out var snapshot) ||
            _now() >= snapshot.AcceptedAt.AddSeconds(40)) return false;
        var previous = _content?.Code == code ? _content : null;
        var communicationCurrent = previous is not null && _now() < _communicationValidUntil;
        _content = snapshot.Content with
        {
            ContinuityId = previous?.ContinuityId ?? snapshot.Content.ContinuityId,
            AnnouncementTitle = communicationCurrent ? previous!.AnnouncementTitle : "",
            AnnouncementText = communicationCurrent ? previous!.AnnouncementText : "",
            LatestChatSequence = previous?.LatestChatSequence ?? 0,
            Messages = communicationCurrent ? previous!.Messages : []
        };
        _validUntil = snapshot.AcceptedAt.AddSeconds(40);
        _latestRosterReadStartedAt = snapshot.AcceptedAt;
        _chatNeedsBaseline |= !communicationCurrent;
        _transientFailures = 0;
        if (_explicitCode is null) _automaticCode = code;
        TraceRead("workspace-accepted", "none");
        return true;
    }

    private void RevokeWorkspace(string? code = null)
    {
        foreach (var moduleCode in _moduleSessions.Keys.Where(key => code is null || key == code).ToArray()) RemoveModuleSession(moduleCode);
        var hadContent = code is null ? _workspaceRosters.Count > 0 || _moduleAuthorities.Count > 0
            : _workspaceRosters.ContainsKey(code) || _moduleAuthorities.ContainsKey(code);
        if (code is null) { _workspaceRosters.Clear(); _moduleAuthorities.Clear(); }
        else { _workspaceRosters.Remove(code); _moduleAuthorities.Remove(code); }
        if (hadContent) NotifyContentChanged();
    }

    internal void RevokeWorkspace(BridgeAccountContext owner, long generation, long sequence, string code)
    {
        lock (_sync)
        {
            CheckScope();
            if (_disposed || _scope != (owner, generation) || sequence <= _rejectedWorkspaceSequence ||
                _workspaceRosters.TryGetValue(code, out var current) && current.Sequence > sequence) return;
            _rejectedWorkspaceSequence = sequence;
            MembershipRevoked?.Invoke(owner, generation, code);
            RevokeWorkspace(code);
            _catalogAt = default;
            _catalogRevision++;
            if (_content?.Code == code)
            {
                InvalidateRead();
                _content = null;
                TraceRead("rejected", "workspace-authority");
            }
        }
    }
}
