using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Friends;

// Host-only extension: the Core record is also a relay output contract.
// LastOnlineHour is read from the relay only; the bridge carries LastOnlineDays (local calendar days) instead.
internal sealed record FriendSharedWire(
    string? Presence = null,
    bool? SameServer = null,
    string? ServerId = null,
    string? ServerRegion = null,
    string? Ship = null,
    string? Location = null,
    DateTimeOffset? LastOnlineAt = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? LastOnlineHour = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] int? LastOnlineDays = null);
