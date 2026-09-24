using System.Text.Json.Serialization;
using StarBridge.Core.Presence;
using StarBridge.Core.Events;

namespace StarBridge.HostRuntime.Privacy;

// This is the current WPF dual-axis editor, not the retired friends-only model.
// Room visibility groups are deliberately absent: WPF removed that control.
public sealed record FleetPrivacySettings(
    [property: JsonRequired] PlayerSharedStateFields Fields,
    [property: JsonRequired] bool AdministratorsCanView,
    [property: JsonRequired] bool AllMembersCanView,
    [property: JsonRequired] IReadOnlyList<string> VisibilityGroupIds);

public sealed record RoomPrivacySettings(
    [property: JsonRequired] PlayerSharedStateFields Fields,
    [property: JsonRequired] bool AllMembersCanView);

public sealed record LocalPrivacySettings(
    [property: JsonRequired] bool PublicationEnabled,
    [property: JsonRequired] FleetPrivacySettings Fleet,
    [property: JsonRequired] RoomPrivacySettings Room,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] CommunityRealtimeScope[]? Communities = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] SharedEventPreferences? Events = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] bool? HideLowConfidenceLocation = null)
{
    // Suggestions are not consent. An absent saved record remains null.
    public static LocalPrivacySettings EditorDefaults => new(true,
        new(PlayerSharedStateFields.All, false, true, Array.Empty<string>()),
        new(PlayerSharedStateFields.All, true));

    internal LocalPrivacySettings ValidatedCopy()
    {
        if (Fleet is null || Room is null || Fleet.VisibilityGroupIds is null ||
            !ValidFields(Fleet.Fields) || !ValidFields(Room.Fields) || Fleet.VisibilityGroupIds.Count > 12 ||
            Fleet.VisibilityGroupIds.Any(id => string.IsNullOrWhiteSpace(id) || id.Length > 128 ||
                id != id.Trim() || id.Any(char.IsControl)) ||
            Fleet.VisibilityGroupIds.Distinct(StringComparer.OrdinalIgnoreCase).Count() != Fleet.VisibilityGroupIds.Count)
            throw new LocalPrivacyException("privacy_local.invalid_request");
        CommunityRealtimeScope[]? scopes;
        SharedEventPreferences? events;
        try
        {
            scopes = Communities is null ? null : CommunityRealtimeScope.ValidateAndCopy(Communities);
            events = Events?.ValidatedCopy();
        }
        catch (ArgumentException) { throw new LocalPrivacyException("privacy_local.invalid_request"); }
        return this with { Fleet = Fleet with { VisibilityGroupIds = Fleet.VisibilityGroupIds.ToArray() }, Communities = scopes, Events = events };
    }

    private static bool ValidFields(PlayerSharedStateFields fields) =>
        (fields & ~PlayerSharedStateFields.All) == 0;
}

public sealed record LocalPrivacySnapshot(long Revision, DateTimeOffset? SavedAt, string? OperationId,
    LocalPrivacySettings? Settings);

public sealed class LocalPrivacyException(string code) : Exception(code)
{
    public string Code { get; } = code;
}
