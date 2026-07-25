namespace StarBridge.Core.Profiles;

public static class PersonalProfileContractPolicy
{
    public const int CurrentSchemaVersion = 3;
    public const int MaximumIntroductionLength = 500;
    public const int MaximumListItems = 8;
    public const int MaximumFavoriteShips = 3;
    public const int MaximumModules = 3;

    private static readonly HashSet<string> KnownModuleIds = new(StringComparer.OrdinalIgnoreCase)
    {
        "favorite-ships",
        "hangar-summary",
        "skilled-roles"
    };

    private static readonly HashSet<string> ActivityRhythms = new(StringComparer.Ordinal)
    {
        "休闲",
        "稳定活跃",
        "高频活跃",
        "周末为主",
        "不固定"
    };

    private static readonly HashSet<string> PresenceIntents = new(StringComparer.OrdinalIgnoreCase)
    {
        "looking-for-group",
        "available-support",
        "busy",
        "do-not-disturb"
    };

    public static PersonalProfileContentContract Normalize(PersonalProfileContentContract? content)
    {
        content ??= PersonalProfileContentContract.Empty;
        var modules = (content.Modules ?? [])
            .Select(module => (Module: module, Id: CanonicalizeModuleId(module.Id)))
            .Where(item => item.Id is not null && KnownModuleIds.Contains(item.Id))
            .GroupBy(item => item.Id!, StringComparer.OrdinalIgnoreCase)
            .Select(group =>
            {
                var sources = group
                    .Select(item => item.Module)
                    .OrderBy(module => module.Order)
                    .ToArray();
                var visibleSource = sources
                    .Where(module => module.IsVisible)
                    .OrderBy(module => module.Position < 0 ? int.MaxValue : module.Position)
                    .ThenBy(module => module.Order)
                    .FirstOrDefault();
                var source = sources[0];
                return source with
                {
                    Id = group.Key,
                    Span = NormalizeModuleSpan(group.Key, sources.Max(module => module.Span)),
                    IsVisible = visibleSource is not null,
                    Order = Math.Max(0, sources.Min(module => module.Order)),
                    Position = visibleSource?.Position ?? -1
                };
            })
            .Take(MaximumModules)
            .Select((module, index) => module with
            {
                Id = module.Id.Trim().ToLowerInvariant(),
                Span = NormalizeModuleSpan(module.Id, module.Span),
                Order = index,
                Position = module.IsVisible ? Math.Max(-1, module.Position) : -1
            })
            .ToArray();

        var availabilityWindows = NormalizeAvailabilityWindows(content);
        var firstWindow = availabilityWindows.FirstOrDefault();
        return content with
        {
            OnlineTimeStart = firstWindow?.StartTime ?? NormalizeTime(content.OnlineTimeStart, "19:00"),
            OnlineTimeEnd = firstWindow?.EndTime ?? NormalizeTime(content.OnlineTimeEnd, "22:00"),
            ActivityRhythm = ActivityRhythms.Contains(content.ActivityRhythm ?? "")
                ? content.ActivityRhythm!
                : "休闲",
            Introduction = NormalizeText(content.Introduction, MaximumIntroductionLength),
            SkilledRoles = NormalizeItems(content.SkilledRoles, MaximumListItems),
            SupportCapabilities = NormalizeItems(content.SupportCapabilities, MaximumListItems),
            ParticipationInterests = NormalizeItems(content.ParticipationInterests, MaximumListItems),
            ShipWishlist = NormalizeItems(content.ShipWishlist, MaximumListItems),
            FavoriteShipCodes = NormalizeItems(content.FavoriteShipCodes, MaximumFavoriteShips),
            Modules = modules,
            AvailabilityTimeZoneId = NormalizeText(content.AvailabilityTimeZoneId, 128),
            AvailabilityWindows = availabilityWindows,
            PresenceIntent = NormalizePresenceIntent(content.PresenceIntent)
        };
    }

    private static string? NormalizePresenceIntent(string? value)
    {
        var normalized = NormalizeText(value, 32).ToLowerInvariant();
        return PresenceIntents.Contains(normalized) ? normalized : null;
    }

    private static PersonalProfileAvailabilityWindowContract[] NormalizeAvailabilityWindows(
        PersonalProfileContentContract content)
    {
        IEnumerable<PersonalProfileAvailabilityWindowContract> source = content.AvailabilityWindows ??
            (content.ShowOnlineTime
                ? [new PersonalProfileAvailabilityWindowContract(
                    [0, 1, 2, 3, 4, 5, 6],
                    NormalizeTime(content.OnlineTimeStart, "19:00"),
                    NormalizeTime(content.OnlineTimeEnd, "22:00"))]
                : []);

        return source
            .Where(window => window is not null)
            .Select(window => new PersonalProfileAvailabilityWindowContract(
                (window.Days ?? [])
                    .Where(day => day is >= 0 and <= 6)
                    .Distinct()
                    .OrderBy(day => day == 0 ? 7 : day)
                    .ToArray(),
                NormalizeTime(window.StartTime, "19:00"),
                NormalizeTime(window.EndTime, "22:00")))
            .Where(window => window.Days.Length > 0)
            .Take(3)
            .ToArray();
    }

    private static string NormalizeTime(string? value, string fallback) =>
        TimeOnly.TryParseExact(value, "HH:mm", out _) ? value! : fallback;

    private static string NormalizeText(string? value, int maximumLength)
    {
        var normalized = (value ?? "").Trim();
        return normalized.Length <= maximumLength ? normalized : normalized[..maximumLength];
    }

    private static string[] NormalizeItems(IEnumerable<string>? values, int maximumCount) =>
        (values ?? [])
        .Select(value => (value ?? "").Trim())
        .Where(value => value.Length > 0)
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .Take(maximumCount)
        .ToArray();

    private static int GetModuleMaximumSpan(string moduleId) => moduleId switch
    {
        "skilled-roles" => 2,
        _ => 3
    };

    private static int NormalizeModuleSpan(string moduleId, int span) =>
        moduleId.Equals("skilled-roles", StringComparison.OrdinalIgnoreCase)
            ? 2
            : Math.Clamp(span, 1, GetModuleMaximumSpan(moduleId));

    private static string? CanonicalizeModuleId(string? value) =>
        (value ?? "").Trim().ToLowerInvariant() switch
        {
            "favorite-ships" => "favorite-ships",
            "hangar-summary" or "ship-type-distribution" => "hangar-summary",
            "skilled-roles" or "support-capabilities" or "participation-interests" => "skilled-roles",
            _ => null
        };
}

public sealed record PersonalProfileModuleContract(
    string Id,
    int Span,
    bool IsVisible,
    int Order,
    int Position = -1);

public sealed record PersonalProfileAvailabilityWindowContract(
    int[] Days,
    string StartTime,
    string EndTime);

public sealed record PersonalProfileContentContract(
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
    PersonalProfileModuleContract[] Modules,
    string? AvailabilityTimeZoneId = null,
    PersonalProfileAvailabilityWindowContract[]? AvailabilityWindows = null,
    string? PresenceIntent = null)
{
    public static PersonalProfileContentContract Empty { get; } = new(
        false,
        "19:00",
        "22:00",
        "休闲",
        "",
        [],
        [],
        [],
        [],
        [],
        [],
        null,
        [],
        null);
}

public sealed record PersonalProfileIdentityContract(
    string Callsign,
    string GameId,
    string? AvatarAssetId = null);

public sealed record PersonalProfileFleetAffiliationContract(
    string FleetName,
    string FleetCode,
    string? FleetLogoAssetId,
    string PositionTitle,
    string PositionColor);

public sealed record PersonalProfileHangarShipContract(
    string Code,
    string DisplayName,
    DateTimeOffset ImportedAt,
    DateTimeOffset SyncedAt = default,
    string? RoleCategory = null);

public sealed record PersonalProfileHangarContract(
    PersonalProfileHangarShipContract[] Ships);

public sealed record PersonalProfileGameplayStatisticsContract(
    long PlayTimeSeconds,
    int DownedCount,
    int DeathCount,
    DateTimeOffset UpdatedAt,
    long HistoricalPlayTimeSeconds = 0,
    int HistoricalSessionCount = 0,
    int HistoricalIncompleteSessionCount = 0,
    DateTimeOffset? HistoryImportedAt = null);

public sealed record PersonalProfileDocumentContract(
    int SchemaVersion,
    string PublicId,
    bool IsPublic,
    long Revision,
    DateTimeOffset UpdatedAt,
    PersonalProfileIdentityContract Identity,
    PersonalProfileContentContract Content,
    PersonalProfileFleetAffiliationContract? FleetAffiliation,
    PersonalProfileHangarContract? Hangar = null,
    PersonalProfileGameplayStatisticsContract? GameplayStatistics = null,
    bool IsGameplayStatisticsPublic = false);

public sealed record PersonalProfileUpdateRequestContract(
    long ExpectedRevision,
    bool IsPublic,
    PersonalProfileContentContract Content);

public sealed record PersonalProfileGameplayStatisticsUpdateRequestContract(
    bool IsPublic,
    long PlayTimeSeconds,
    int DownedCount,
    int DeathCount,
    long HistoricalPlayTimeSeconds = 0,
    int HistoricalSessionCount = 0,
    int HistoricalIncompleteSessionCount = 0,
    DateTimeOffset? HistoryImportedAt = null);
