using System.Text.Json.Serialization;

internal static partial class ProfileImportJournalTests
{
    // Exact record declarations copied from fe6c1cfc; behavioral methods excluded.
    private sealed record OldEnvelope(int Version, string Owner, OldIntent? Intent);
    private sealed record OldIntent(string Ticket, long ExpectedRevision, string Operation,
        OldLocalProfileContent? Content, OldLegacyProfileMigrationView Preview, bool Confirmed = false, bool Applied = false,
        OldLocalProfileSnapshot? Previous = null, long? HangarRevision = null);
    private sealed record OldLocalProfileLayout(string Id, int Span, bool IsVisible, int Position,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? FavoriteShipIds = null);
    private sealed record OldLocalProfileContent(string CallSign, string Introduction, int AvatarStyle,
        string WallpaperId, IReadOnlyList<OldLocalProfileLayout> Modules, IReadOnlyList<string>? FavoriteShipIds,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] OldLocalProfilePlayStyle? PlayStyle = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] OldLocalProfileSchedule? Schedule = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] bool PreserveEmptyFields = false);
    private sealed record OldLocalProfileSnapshot(long Revision, DateTimeOffset? SavedAt, string? OperationId, OldLocalProfileContent? Content);
    private sealed record OldPersonalProfileModuleContract(
        string Id,
        int Span,
        bool IsVisible,
        int Order,
        int Position = -1,
        [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)]
        string[]? FavoriteShipIds = null);
    private sealed record OldPersonalProfileAvailabilityWindowContract(
        int[] Days,
        string StartTime,
        string EndTime);
    private sealed record OldPersonalProfileContentContract(
        bool ShowOnlineTime,
        string OnlineTimeStart,
        string OnlineTimeEnd,
        string ActivityRhythm,
        string Introduction,
        string[] SkilledRoles,
        string[] SupportCapabilities,
        string[] ParticipationInterests,
        string[] ShipWishlist,
        string[] FavoriteShipCodes,
        OldPersonalProfileModuleContract[] Modules,
        string? AvailabilityTimeZoneId = null,
        OldPersonalProfileAvailabilityWindowContract[]? AvailabilityWindows = null,
        string? PresenceIntent = null);
    private sealed record OldLocalProfilePlayStyle(
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? Roles = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? Interests = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? Support = null);
    private sealed record OldLocalProfileTimeWindow(IReadOnlyList<int> Days, string StartTime, string EndTime);
    private sealed record OldLocalProfileSchedule(string TimeZoneId, string Rhythm, IReadOnlyList<OldLocalProfileTimeWindow> Windows);
    private sealed record OldLegacyProfileMigrationSummary(
        string CallSign, string Introduction, int Modules, int Favorites, long? PlayTimeSeconds);
    private sealed record OldLegacyProfileMigrationView(
        string State, string? PreviewId = null, string? SourceGameId = null,
        long SourceRevision = 0, long TargetRevision = 0, DateTimeOffset? ExpiresAt = null,
        bool Conflict = false, OldLegacyProfileMigrationSummary? Source = null,
        OldLegacyProfileMigrationSummary? Target = null, long? CompletedRevision = null,
        OldLegacyProfileImportChoices? Choices = null, string? AvatarPreview = null,
        OldLegacyProfileSelectedContent? SelectedContent = null, OldLegacyProfilePresentation? Presentation = null);
    private sealed record OldLegacyProfilePresentation(string CallSign, int AvatarStyle, string WallpaperId,
        OldPersonalProfileContentContract Content);
    private sealed record OldLegacyProfileSelectedModule(string Id, int Span);
    private sealed record OldLegacyProfileSelectedContent(string? CallSign, OldLegacyProfileSelectedModule[] Modules,
        string[]? SkilledRoles, string[]? SupportCapabilities, string[]? ParticipationInterests);
    private sealed record OldLegacyProfileImportChoices(int Version, string[] Modules, string[] ReplaceModules,
        bool UseLegacyCallSign, string[] NeedsReselection, bool UseLegacyAvatar = false);
}
