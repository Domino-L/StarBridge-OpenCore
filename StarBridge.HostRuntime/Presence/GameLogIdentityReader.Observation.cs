using System.Globalization;
using StarBridge.Core.Identity;
using StarBridge.Core.Parsing;

namespace StarBridge.HostRuntime.Presence;

public sealed partial class GameLogIdentityReader
{
    private void Observe(string line, GameProcessSession? process, DateTimeOffset now, bool? contractLive = null)
    {
        var recent = process is null;
        if (_session?.SkipBlockedContractLine(line) == true) { _contractNotification = null; return; }
        if (_session?.TracksContracts == true && contractLive is null &&
            ObserveContractNotification(line, process, now)) return;
        if (_strictLocalEvidence) { ObserveStrict(line, process!, now, contractLive); return; }
        var containsIdentity = line.Contains("nickname=", StringComparison.Ordinal);
        var containsQuit = line.Contains("SystemQuit", StringComparison.Ordinal);
        if (_journal is null && !containsIdentity && !containsQuit &&
            (_session is null || !_session.TracksContracts && !GameLogSessionTracker.MightContainEvidence(line))) return;
        if (line.Length < 22 || line[0] != '<') {
            if (recent && containsIdentity) _invalidIdentityEvidence = true;
            return;
        }
        var end = line.IndexOf('>');
        if (end is < 20 or > 40 ||
            !DateTimeOffset.TryParse(line.AsSpan(1, end - 1), CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var timestamp) ||
            (!recent && timestamp < process!.StartedAt!.Value.AddSeconds(-2)) || timestamp > now.AddSeconds(5)) {
            if (recent && containsIdentity) _invalidIdentityEvidence = true;
            return;
        }
        if (!recent && _contractFirstTimestamp is null)
        {
            _contractFirstTimestamp = timestamp;
            _contractCoverageFromStart = timestamp <= process!.StartedAt!.Value.AddSeconds(2);
        }
        var live = contractLive ?? (!recent && _following && _lineStart >= _liveFrom);
        _session?.Observe(line, live: live);
        if (line.Contains("SystemQuit", StringComparison.Ordinal) && line.Contains("CSystem::Quit", StringComparison.Ordinal))
        {
            _quit = true;
            _session?.Reset();
        }
        if (!containsIdentity)
        {
            return;
        }
        var match = Identity.Match(line);
        if (!match.Success || !IdentityBindingPolicy.IsValidGameName(match.Groups["handle"].Value) ||
            match.Groups["id"].Value.All(c => c == '0')) {
            if (recent) _invalidIdentityEvidence = true;
            return;
        }
        if (recent) {
            if (_recentIdentityAt is { } previous && timestamp < previous) return;
            if (_recentIdentityAt != timestamp) _identities.Clear();
            _recentIdentityAt = timestamp;
        }
        // Same timestamp/session and valid nickname/playerGEID rules as the snapshot.
        // Observe even after the snapshot reaches its two-entry limit.
        ObserveHandle(match.Groups["handle"].Value);
        if (_identities.Count < 2)
            _identities.TryAdd((match.Groups["handle"].Value.ToLowerInvariant(), match.Groups["id"].Value),
                match.Groups["handle"].Value);
    }
    private void ObserveStrict(string line, GameProcessSession process, DateTimeOffset now, bool? contractLive)
    {
        var state = LocalGameIdentityLine.Parse(line, now, out var identity);
        var quit = line.Contains("<SystemQuit>", StringComparison.OrdinalIgnoreCase) &&
            line.Contains("CSystem::Quit", StringComparison.OrdinalIgnoreCase);
        if (!LocalGameIdentityLine.TryTimestamp(line, now, out var at, out var resolution))
        { if (state == LocalGameIdentityLineState.Invalid || quit) _invalidIdentityEvidence = true; return; }
        if (!LocalGameIdentityLine.MeetsSessionTime(new("", "", at) { ResolutionTicks = resolution },
            process!.StartedAt!.Value, process.StartedAt.Value, now)) return;
        if (state == LocalGameIdentityLineState.Invalid) { _invalidIdentityEvidence = true; return; }
        if (quit) { _quit = true; _session?.Reset(); return; }
        // A remote/unrelated nickname must not change the session tracker's
        // local identity while the strict identity observer ignores it.
        if (state == LocalGameIdentityLineState.Unrelated &&
            line.Contains("nickname", StringComparison.OrdinalIgnoreCase)) return;
        _session?.Observe(line, live: contractLive ?? (_following && _lineStart >= _liveFrom));
        if (identity is not null) ObserveHandle(identity.Handle);
        if (identity is not null && _identities.Count < 2)
            _identities.TryAdd((identity.Handle.ToLowerInvariant(), identity.PlayerId), identity.Handle);
    }
}
