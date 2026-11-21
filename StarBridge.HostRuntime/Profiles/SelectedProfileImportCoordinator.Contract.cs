using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Profiles;

internal sealed partial class SelectedProfileImportCoordinator
{
    // Frozen fe6c1cfc serialization graph, including every nested record.
    // Never add members here; runtime additions belong in the encrypted sidefile.
    private sealed record DiskEnvelope(int Version, string Owner, DiskIntent? Intent);
    private sealed record DiskIntent(string Ticket, long ExpectedRevision, string Operation,
        DiskContent? Content, DiskPreview Preview, bool Confirmed = false, bool Applied = false,
        DiskSnapshot? Previous = null, long? HangarRevision = null);
    private sealed record DiskLayout(string Id, int Span, bool IsVisible, int Position,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? FavoriteShipIds = null);
    private sealed record DiskContent(string CallSign, string Introduction, int AvatarStyle,
        string WallpaperId, IReadOnlyList<DiskLayout> Modules, IReadOnlyList<string>? FavoriteShipIds,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] DiskPlayStyle? PlayStyle = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] DiskSchedule? Schedule = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] bool PreserveEmptyFields = false);
    private sealed record DiskPlayStyle(
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? Roles = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? Interests = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? Support = null);
    private sealed record DiskWindow(IReadOnlyList<int> Days, string StartTime, string EndTime);
    private sealed record DiskSchedule(string TimeZoneId, string Rhythm, IReadOnlyList<DiskWindow> Windows);
    private sealed record DiskSnapshot(long Revision, DateTimeOffset? SavedAt, string? OperationId, DiskContent? Content);
    private sealed record DiskSummary(string CallSign, string Introduction, int Modules, int Favorites, long? PlayTimeSeconds);
    private sealed record DiskPreview(string State, string? PreviewId = null, string? SourceGameId = null,
        long SourceRevision = 0, long TargetRevision = 0, DateTimeOffset? ExpiresAt = null,
        bool Conflict = false, DiskSummary? Source = null, DiskSummary? Target = null, long? CompletedRevision = null,
        DiskChoices? Choices = null, string? AvatarPreview = null,
        DiskSelected? SelectedContent = null, DiskPresentation? Presentation = null);
    private sealed record DiskChoices(int Version, string[] Modules, string[] ReplaceModules,
        bool UseLegacyCallSign, string[] NeedsReselection, bool UseLegacyAvatar = false);
    private sealed record DiskSelectedModule(string Id, int Span);
    private sealed record DiskSelected(string? CallSign, DiskSelectedModule[] Modules,
        string[]? SkilledRoles, string[]? SupportCapabilities, string[]? ParticipationInterests);
    private sealed record DiskPresentation(string CallSign, int AvatarStyle, string WallpaperId, DiskPresentationContent Content);
    private sealed record DiskModule(string Id, int Span, bool IsVisible, int Order, int Position = -1,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string[]? FavoriteShipIds = null);
    private sealed record DiskAvailability(int[] Days, string StartTime, string EndTime);
    private sealed record DiskPresentationContent(bool ShowOnlineTime, string OnlineTimeStart, string OnlineTimeEnd,
        string ActivityRhythm, string Introduction, string[] SkilledRoles, string[] SupportCapabilities,
        string[] ParticipationInterests, string[] ShipWishlist, string[] FavoriteShipCodes, DiskModule[] Modules,
        string? AvailabilityTimeZoneId = null, DiskAvailability[]? AvailabilityWindows = null, string? PresenceIntent = null);

    // Projection skips runtime-only members, but the output graph above is closed
    // and independent of all evolving domain types. Disk reads remain Disallow.
    private static readonly JsonSerializerOptions ProjectionJson = new(LocalPersonalProfileStore.Json)
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip };
    private static byte[] FrozenBytes(string key, Intent value)
    {
        var runtime = JsonSerializer.SerializeToUtf8Bytes(new Envelope(1, key, value), LocalPersonalProfileStore.Json);
        try
        {
            var frozen = JsonSerializer.Deserialize<DiskEnvelope>(runtime, ProjectionJson);
            return JsonSerializer.SerializeToUtf8Bytes(frozen, LocalPersonalProfileStore.Json);
        }
        finally { System.Security.Cryptography.CryptographicOperations.ZeroMemory(runtime); }
    }
}
