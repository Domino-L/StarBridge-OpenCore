namespace StarBridge.HostRuntime.Notifications;

/// <summary>Read-only, authenticated observation; never a membership write or a notification itself.</summary>
public sealed record PlayerActivityObservation(long Generation, string Scope, string Source,
    string SourceKey, long Sequence, bool IsComplete, PlayerActivityObservedMember[] Members,
    Func<bool> IsCurrent);

public sealed record PlayerActivityObservedMember(string MemberKey, string Callsign, string GameId,
    string Presence, bool IsSelf, bool AllowsPresenceEvents, string? AvatarImageData = null, string[]? PolicySources = null,
    PlayerActivityOrganization[]? Organizations = null);

public sealed record PlayerActivityOrganization(string PolicySource, string Name);

// Raw identities stay inside Host and never enter the Bridge payload.
internal sealed record PlayerActivitySourceMember(string AccountId, string Callsign, string GameId,
    string Presence, bool AllowsPresenceEvents, string? AvatarImageData = null, string[]? PolicySources = null,
    PlayerActivityOrganization[]? Organizations = null);
internal sealed record PlayerActivitySourceSnapshot(string Source, bool IsComplete,
    PlayerActivitySourceMember[] Members);
