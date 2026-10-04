using StarBridge.Core.Overlay;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Overlay;

internal sealed partial class OverlayCommunitySource
{
    private sealed class ModuleAuthority(DateTimeOffset validUntil)
    {
        internal readonly Guid Continuity = Guid.NewGuid();
        // A page-to-module handoff shares identity between two resource locks.
        // Keep renewal atomic and monotonic; DateTimeOffset is not an atomic field.
        private long _validUntilTicks = validUntil.UtcDateTime.Ticks;
        internal DateTimeOffset ValidUntil => new(Volatile.Read(ref _validUntilTicks), TimeSpan.Zero);
        internal void RenewUntil(DateTimeOffset until)
        {
            var ticks = until.UtcDateTime.Ticks;
            var previous = Volatile.Read(ref _validUntilTicks);
            while (ticks > previous)
            {
                var observed = Interlocked.CompareExchange(ref _validUntilTicks, ticks, previous);
                if (observed == previous) return;
                previous = observed;
            }
        }
    }
    private readonly Dictionary<string, ModuleAuthority> _moduleAuthorities = new(StringComparer.Ordinal);
    private string? _focusedModuleCommunity;

    // Only accepted roster publications may renew continuity. A probe never
    // renews it, and a publication after the old deadline starts a new lifetime.
    private void RenewModuleAuthority(string code, DateTimeOffset validUntil)
    {
        if (!_moduleAuthorities.TryGetValue(code, out var authority)) return;
        if (_now() >= authority.ValidUntil) _moduleAuthorities.Remove(code);
        else authority.RenewUntil(validUntil);
    }

    private ModuleAuthority ModuleAuthorityFor(string code, DateTimeOffset validUntil)
    {
        var now = _now();
        foreach (var key in _moduleAuthorities.Where(p => now >= p.Value.ValidUntil).Select(p => p.Key).ToArray())
            _moduleAuthorities.Remove(key);
        if (!_moduleAuthorities.TryGetValue(code, out var authority))
            _moduleAuthorities[code] = authority = new(validUntil);
        authority.RenewUntil(validUntil);
        return authority;
    }
    // Reads the same authorized workspace cache used by ordinary pages. No I/O,
    // demand changes, selection writes or new authorization lifetime.
    internal OverlaySourceResolutionContext? CaptureResolutionContext(BridgeAccountContext owner,
        long generation, OverlaySourceLease? room)
    {
        lock (_sync)
        {
            CheckScope();
            if (_disposed || _choiceFailed || _scope != (owner, generation)) return null;
            Read(); // Ordinary capture may adopt a shared workspace. Probes may not.
            return PeekResolutionContext(owner, generation, room);
        }
    }

    internal OverlaySourceResolutionContext? PeekResolutionContext(BridgeAccountContext owner,
        long generation, OverlaySourceLease? room)
    {
        lock (_sync)
        {
            if (_disposed || _choiceFailed || _scope != (owner, generation) || _owner() != (owner, generation)) return null;
            var key = OverlaySceneChoiceStore.Hash(owner);
            var now = _now();
            var leases = _workspaceRosters.Where(p => now < p.Value.AcceptedAt.AddSeconds(40))
                .ToDictionary(p => p.Key, p => new OverlaySourceLease(OverlaySourceMode.Community,
                    p.Key, key, generation, p.Value.AcceptedAt.AddSeconds(40)), StringComparer.Ordinal);
            if (_content is { } selected && now < _validUntil)
                leases[selected.Code] = new(OverlaySourceMode.Community, selected.Code, key, generation, _validUntil);
            foreach (var (code, session) in _moduleSessions)
            {
                leases.Remove(code);
                if (session.Source.PeekResolutionContext(owner, generation, null)?.Communities.TryGetValue(code, out var lease) == true)
                    leases[code] = lease;
            }
            var choice = _choice.Mode switch
            {
                "auto" => OverlaySourceBinding.Automatic,
                "room" => new(OverlaySourceMode.Room),
                "community" => new(OverlaySourceMode.Community, _choice.Code, key),
                _ => null
            };
            if (choice is null) return null;
            // C7 means a focused organization, not an arbitrary directory row.
            return new(key, generation, now, choice, room, _focusedModuleCommunity, leases);
        }
    }

    internal bool IsModuleAuthorityCurrent(BridgeAccountContext owner, long generation, string code, object stamp)
    {
        lock (_sync)
        {
            if (_disposed || _choiceFailed || _scope != (owner, generation) || _owner() != (owner, generation)) return false;
            if (_moduleSessions.TryGetValue(code, out var session))
                return session.Source.IsModuleAuthorityCurrent(owner, generation, code, stamp);
            if (!_moduleAuthorities.TryGetValue(code, out var authority) || !ReferenceEquals(stamp, authority)) return false;
            var now = _now();
            return now < authority.ValidUntil && (_content?.Code == code && now < _validUntil ||
                _workspaceRosters.TryGetValue(code, out var roster) && now < roster.AcceptedAt.AddSeconds(40));
        }
    }

    internal InformationOverlaySourceSnapshot? ReadModuleSource(BridgeAccountContext owner, long generation, string code)
    {
        lock (_sync)
        {
            CheckScope();
            if (_disposed || _choiceFailed || _scope != (owner, generation)) return null;
            if (_moduleSessions.TryGetValue(code, out var session)) return session.Source.ReadModuleSource(owner, generation, code);
            var key = OverlaySceneChoiceStore.Hash(owner);
            if (Read() is { } selected && selected.Code == code)
            {
                var authority = ModuleAuthorityFor(code, _validUntil);
                return new(new(OverlaySourceMode.Community, code, key, generation, _validUntil),
                    _communicationValidUntil, community: selected with { ContinuityId = authority.Continuity }, authorityStamp: authority,
                    clock: _now, realtimeValidUntil: _validUntil.AddSeconds(-10));
            }
            if (!_workspaceRosters.TryGetValue(code, out var roster) || _now() >= roster.AcceptedAt.AddSeconds(40)) return null;
            var rosterAuthority = ModuleAuthorityFor(code, roster.AcceptedAt.AddSeconds(40));
            // A roster read does not authorize or refresh the communication data.
            return new(new(OverlaySourceMode.Community, code, key, generation, roster.AcceptedAt.AddSeconds(40)),
                DateTimeOffset.MinValue, community: roster.Content with
                { ContinuityId = rosterAuthority.Continuity, AnnouncementTitle = "", AnnouncementText = "", Messages = [] }, authorityStamp: rosterAuthority,
                clock: _now, realtimeValidUntil: roster.AcceptedAt.AddSeconds(30));
        }
    }

    internal bool IsModuleSourceCurrent(BridgeAccountContext owner, long generation, InformationOverlaySourceSnapshot snapshot)
    {
        lock (_sync)
        {
            if (_disposed || _choiceFailed || _scope != (owner, generation) || _owner() != (owner, generation)) return false;
            if (_moduleSessions.TryGetValue(snapshot.Lease.Id, out var session))
                return session.Source.IsModuleSourceCurrent(owner, generation, snapshot);
            // Display-time validation must not read saved choices from disk.
            if (snapshot.AuthorityStamp is null ||
                !snapshot.Lease.IsValidFor(OverlaySceneChoiceStore.Hash(owner), generation, _now())) return false;
            // Membership continuity, not the payload object: ordinary messages
            // and roster refreshes must not look like revocation to the renderer.
            if (!_moduleAuthorities.TryGetValue(snapshot.Lease.Id, out var authority) ||
                !ReferenceEquals(snapshot.AuthorityStamp, authority)) return false;
            if (_content?.Code == snapshot.Lease.Id)
                return _now() < _validUntil;
            return _workspaceRosters.TryGetValue(snapshot.Lease.Id, out var roster) &&
                _now() < roster.AcceptedAt.AddSeconds(40);
        }
    }
}
