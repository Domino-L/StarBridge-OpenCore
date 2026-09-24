using System.Text.Json.Serialization;

namespace StarBridge.Core.Events;

/// <summary>Stable S2 wire bits. Bit 4 belongs to the retired squad feature.</summary>
[Flags]
public enum SharedActivityEventTypes
{
    None = 0,
    Presence = 1,
    Server = 2,
    Ship = 4,
    Location = 8,
    Life = 32,
    All = Presence | Server | Ship | Location | Life
}

/// <summary>Disabling a scope preserves its selections without granting access.</summary>
public sealed record SharedEventChoice(
    [property: JsonRequired] bool Enabled,
    [property: JsonRequired] SharedActivityEventTypes SelectedTypes)
{
    public static SharedEventChoice Unconfirmed => new(false, SharedActivityEventTypes.All);

    [JsonIgnore]
    public SharedActivityEventTypes EffectiveTypes => Enabled ? Normalize(SelectedTypes) : SharedActivityEventTypes.None;

    public static SharedActivityEventTypes Normalize(SharedActivityEventTypes value) => value & SharedActivityEventTypes.All;

    public SharedEventChoice Validate()
    {
        if (Normalize(SelectedTypes) != SelectedTypes)
            throw new ArgumentException("Invalid shared event selection.");
        return this;
    }
}

/// <summary>Separate from the four realtime fields and from notification preferences.</summary>
public sealed record CommunityEventChoice(
    [property: JsonRequired] string Code,
    [property: JsonRequired] DateTimeOffset JoinedAt,
    [property: JsonRequired] SharedEventChoice Choice);

public sealed record SharedEventPreferences(
    [property: JsonRequired] SharedEventChoice Room,
    [property: JsonRequired] CommunityEventChoice[] Communities)
{
    public const int MaximumCommunities = 64;
    public static SharedEventPreferences Unconfirmed => new(SharedEventChoice.Unconfirmed, []);

    public SharedEventPreferences ValidatedCopy()
    {
        if (Room is null || Communities is null || Communities.Length > MaximumCommunities)
            throw new ArgumentException("Invalid shared event preferences.");
        Room.Validate();
        var rows = Communities.ToArray();
        foreach (var row in rows)
        {
            if (row is null || !ValidCode(row.Code) || row.JoinedAt <= DateTimeOffset.UnixEpoch || row.Choice is null)
                throw new ArgumentException("Invalid shared event membership.");
            row.Choice.Validate();
        }
        if (rows.Select(row => row.Code).Distinct(StringComparer.OrdinalIgnoreCase).Count() != rows.Length)
            throw new ArgumentException("Duplicate shared event membership.");
        return this with { Communities = rows };
    }

    // Caller supplies authenticated/current relationship facts. This function
    // cannot infer membership from a name, an organization code or a local choice.
    public SharedActivityEventTypes ResolveCommunity(string code, DateTimeOffset currentPublisherJoinedAt,
        bool recipientIsCurrentMember, bool publicationAllowed)
    {
        var settings = ValidatedCopy();
        if (!publicationAllowed || !recipientIsCurrentMember) return SharedActivityEventTypes.None;
        return settings.Communities.SingleOrDefault(row =>
            string.Equals(row.Code, code, StringComparison.OrdinalIgnoreCase) &&
            row.JoinedAt == currentPublisherJoinedAt)?.Choice.EffectiveTypes ?? SharedActivityEventTypes.None;
    }

    public SharedActivityEventTypes ResolveRoom(bool recipientIsInCurrentRoom, bool publicationAllowed) =>
        recipientIsInCurrentRoom && publicationAllowed
            ? ValidatedCopy().Room.EffectiveTypes : SharedActivityEventTypes.None;

    private static bool ValidCode(string? value) => !string.IsNullOrWhiteSpace(value) &&
        value.Length <= 256 && value == value.Trim() && !value.Any(char.IsControl);
}
