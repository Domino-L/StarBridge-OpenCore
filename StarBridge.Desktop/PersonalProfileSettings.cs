namespace StarBridge.Desktop;

using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

internal sealed record PersonalProfileModuleSetting(
    string Id,
    int Span,
    bool IsVisible,
    int Order,
    int Position = -1);

internal sealed record PersonalProfileAvailabilityWindowSetting(
    int[] Days,
    string StartTime,
    string EndTime);

internal sealed record PersonalProfilePresenceIntentOption(string? Id, string DisplayName)
{
    public override string ToString() => DisplayName;
}

internal static class PersonalProfilePresenceIntentCatalog
{
    public static IReadOnlyList<PersonalProfilePresenceIntentOption> Options { get; } =
    [
        new(null, "不显示意向"),
        new("looking-for-group", "可组队"),
        new("available-support", "可提供支援"),
        new("busy", "忙碌"),
        new("do-not-disturb", "请勿打扰")
    ];

    public static string? Normalize(string? value) =>
        Options.Any(option => string.Equals(option.Id, value, StringComparison.OrdinalIgnoreCase))
            ? Options.First(option => string.Equals(option.Id, value, StringComparison.OrdinalIgnoreCase)).Id
            : null;

    public static string? Format(string? value) =>
        Options.FirstOrDefault(option =>
            option.Id is not null &&
            string.Equals(option.Id, value, StringComparison.OrdinalIgnoreCase))?.DisplayName;
}

internal static class PersonalProfileModuleConstraints
{
    public static int GetMaximumSpan(string? moduleId) =>
        PersonalProfileProductContract.GetModuleMaximumSpan(moduleId);

    public static int NormalizeSpan(string? moduleId, int span) =>
        string.Equals(moduleId, "skilled-roles", StringComparison.OrdinalIgnoreCase)
            ? 2
            : Math.Clamp(span, 1, GetMaximumSpan(moduleId));
}

internal sealed record PersonalProfileSettings(
    bool ShowOnlineTime,
    string OnlineTimeStart,
    string OnlineTimeEnd,
    string Introduction,
    PersonalProfileModuleSetting[] Modules,
    string ActivityRhythm = "休闲",
    string[]? SkilledRoles = null,
    string[]? SupportCapabilities = null,
    string[]? ParticipationInterests = null,
    string[]? ShipWishlist = null,
    string[]? FavoriteShipCodes = null,
    bool IsProfilePublic = false,
    string? AvailabilityTimeZoneId = null,
    PersonalProfileAvailabilityWindowSetting[]? AvailabilityWindows = null,
    string? PresenceIntent = null)
{
    private static readonly string SettingsPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "personal-profile.json");
    private static readonly string AccountSettingsDirectory = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "personal-profiles");
    private static readonly string LegacyMigrationMarkerPath = Path.Combine(
        AccountSettingsDirectory,
        ".legacy-profile-owner");

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    public static PersonalProfileSettings CreateDefault() => new(
        false,
        "19:00",
        "22:00",
        "",
        [
            new("favorite-ships", 1, false, 0),
            new("hangar-summary", 2, false, 1),
            new("skilled-roles", 2, false, 2)
        ],
        "休闲",
        [],
        [],
        [],
        [],
        [],
        false,
        TimeZoneInfo.Local.Id,
        [],
        null);

    public static PersonalProfileSettings Load(string? accountIdentity = null)
    {
        var path = ResolveSettingsPath(accountIdentity);
        if (!string.IsNullOrWhiteSpace(accountIdentity) && !File.Exists(path))
        {
            TryMigrateLegacySettings(accountIdentity, path);
        }

        try
        {
            if (!File.Exists(path))
            {
                return CreateDefault();
            }

            var settings = JsonSerializer.Deserialize<PersonalProfileSettings>(
                File.ReadAllText(path),
                JsonOptions);
            return Normalize(settings);
        }
        catch
        {
            try
            {
                var backupPath = $"{path}.bak";
                if (File.Exists(backupPath))
                {
                    return Normalize(JsonSerializer.Deserialize<PersonalProfileSettings>(
                        File.ReadAllText(backupPath),
                        JsonOptions));
                }
            }
            catch
            {
                // Preserve the last readable state without replacing damaged files.
            }

            return CreateDefault();
        }
    }

    public void Save(string? accountIdentity = null)
    {
        var path = ResolveSettingsPath(accountIdentity);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var tempPath = $"{path}.tmp";
        File.WriteAllText(tempPath, JsonSerializer.Serialize(Normalize(this), JsonOptions));
        if (File.Exists(path))
        {
            File.Copy(path, $"{path}.bak", overwrite: true);
        }

        File.Move(tempPath, path, overwrite: true);
    }

    public PersonalProfileSettings Copy() => this with
    {
        Modules = Modules.Select(module => module with { }).ToArray(),
        SkilledRoles = SkilledRoles?.ToArray() ?? [],
        SupportCapabilities = SupportCapabilities?.ToArray() ?? [],
        ParticipationInterests = ParticipationInterests?.ToArray() ?? [],
        ShipWishlist = ShipWishlist?.ToArray() ?? [],
        FavoriteShipCodes = FavoriteShipCodes?.ToArray() ?? [],
        AvailabilityWindows = AvailabilityWindows?
            .Select(window => window with { Days = window.Days?.ToArray() ?? [] })
            .ToArray() ?? []
    };

    private static string ResolveSettingsPath(string? accountIdentity) =>
        string.IsNullOrWhiteSpace(accountIdentity)
            ? SettingsPath
            : Path.Combine(AccountSettingsDirectory, $"{HashAccountIdentity(accountIdentity)}.json");

    private static string HashAccountIdentity(string accountIdentity) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(accountIdentity.Trim())))
            .ToLowerInvariant();

    private static void TryMigrateLegacySettings(string accountIdentity, string accountPath)
    {
        try
        {
            if (!File.Exists(SettingsPath) || File.Exists(LegacyMigrationMarkerPath))
            {
                return;
            }

            Directory.CreateDirectory(AccountSettingsDirectory);
            File.Copy(SettingsPath, accountPath, overwrite: false);
            File.WriteAllText(LegacyMigrationMarkerPath, HashAccountIdentity(accountIdentity));
        }
        catch
        {
            // Migration is best-effort; the legacy file remains untouched for recovery.
        }
    }

    private static PersonalProfileSettings Normalize(PersonalProfileSettings? settings)
    {
        var defaults = CreateDefault();
        if (settings is null)
        {
            return defaults;
        }

        var known = defaults.Modules.ToDictionary(module => module.Id, StringComparer.Ordinal);
        var normalized = (settings.Modules ?? [])
            .Select(module => (Module: module, Id: CanonicalizeModuleId(module.Id)))
            .Where(item => item.Id is not null && known.ContainsKey(item.Id))
            .GroupBy(item => item.Id!, StringComparer.Ordinal)
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
                    Span = PersonalProfileModuleConstraints.NormalizeSpan(
                        group.Key,
                        sources.Max(module => module.Span)),
                    IsVisible = visibleSource is not null,
                    Order = Math.Max(0, sources.Min(module => module.Order)),
                    Position = visibleSource?.Position ?? -1
                };
            })
            .ToList();

        foreach (var module in defaults.Modules)
        {
            if (normalized.All(item => item.Id != module.Id))
            {
                normalized.Add(module);
            }
        }

        var ordered = normalized
            .OrderBy(module => module.Order)
            .Select((module, index) => module with { Order = index })
            .ToArray();

        var occupied = new bool[PersonalProfileProductContract.LegacyCellCount];
        for (var index = 0; index < ordered.Length; index++)
        {
            var module = ordered[index];
            if (!module.IsVisible)
            {
                ordered[index] = module with { Position = -1 };
                continue;
            }

            var position = CanPlaceModule(occupied, module.Position, module.Span)
                ? module.Position
                : FindFirstModulePosition(occupied, module.Span);
            if (position < 0)
            {
                ordered[index] = module with { IsVisible = false, Position = -1 };
                continue;
            }

            MarkModuleCells(occupied, position, module.Span);
            ordered[index] = module with { Position = position };
        }

        var availabilityWindows = NormalizeAvailabilityWindows(settings, defaults);
        var firstWindow = availabilityWindows.FirstOrDefault();
        return settings with
        {
            OnlineTimeStart = firstWindow?.StartTime ?? NormalizeTime(settings.OnlineTimeStart, defaults.OnlineTimeStart),
            OnlineTimeEnd = firstWindow?.EndTime ?? NormalizeTime(settings.OnlineTimeEnd, defaults.OnlineTimeEnd),
            Introduction = (settings.Introduction ?? "").Trim(),
            Modules = ordered,
            ActivityRhythm = NormalizeActivityRhythm(settings.ActivityRhythm, defaults.ActivityRhythm),
            SkilledRoles = PersonalProfileRoleCatalog.NormalizeRoleIds(settings.SkilledRoles),
            SupportCapabilities = NormalizeProfileItems(settings.SupportCapabilities),
            ParticipationInterests = NormalizeProfileItems(settings.ParticipationInterests),
            ShipWishlist = NormalizeProfileItems(settings.ShipWishlist),
            FavoriteShipCodes = NormalizeFavoriteShipCodes(settings.FavoriteShipCodes),
            AvailabilityTimeZoneId = NormalizeTimeZoneId(settings.AvailabilityTimeZoneId),
            AvailabilityWindows = availabilityWindows,
            PresenceIntent = PersonalProfilePresenceIntentCatalog.Normalize(settings.PresenceIntent)
        };
    }

    private static string? CanonicalizeModuleId(string? value) =>
        (value ?? "").Trim().ToLowerInvariant() switch
        {
            "favorite-ships" => "favorite-ships",
            "hangar-summary" or "ship-type-distribution" => "hangar-summary",
            "skilled-roles" or "support-capabilities" or "participation-interests" => "skilled-roles",
            _ => null
        };

    private static PersonalProfileAvailabilityWindowSetting[] NormalizeAvailabilityWindows(
        PersonalProfileSettings settings,
        PersonalProfileSettings defaults)
    {
        IEnumerable<PersonalProfileAvailabilityWindowSetting> source = settings.AvailabilityWindows ??
            (settings.ShowOnlineTime
                ? [new PersonalProfileAvailabilityWindowSetting(
                    [0, 1, 2, 3, 4, 5, 6],
                    NormalizeTime(settings.OnlineTimeStart, defaults.OnlineTimeStart),
                    NormalizeTime(settings.OnlineTimeEnd, defaults.OnlineTimeEnd))]
                : []);

        return source
            .Where(window => window is not null)
            .Select(window => new PersonalProfileAvailabilityWindowSetting(
                (window.Days ?? [])
                    .Where(day => day is >= 0 and <= 6)
                    .Distinct()
                    .OrderBy(day => day == 0 ? 7 : day)
                    .ToArray(),
                NormalizeTime(window.StartTime, defaults.OnlineTimeStart),
                NormalizeTime(window.EndTime, defaults.OnlineTimeEnd)))
            .Where(window => window.Days.Length > 0)
            .Take(3)
            .ToArray();
    }

    private static string NormalizeTimeZoneId(string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            try
            {
                return TimeZoneInfo.FindSystemTimeZoneById(value).Id;
            }
            catch (TimeZoneNotFoundException)
            {
            }
            catch (InvalidTimeZoneException)
            {
            }
        }

        return TimeZoneInfo.Local.Id;
    }

    private static string NormalizeActivityRhythm(string? value, string fallback)
    {
        string[] options = ["休闲", "稳定活跃", "高频活跃", "周末为主", "不固定"];
        return options.Contains(value, StringComparer.Ordinal) ? value! : fallback;
    }

    private static string[] NormalizeProfileItems(IEnumerable<string>? values) =>
        (values ?? [])
        .Select(value => (value ?? "").Trim())
        .Where(value => value.Length > 0)
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .Take(8)
        .ToArray();

    private static string[] NormalizeFavoriteShipCodes(IEnumerable<string>? values) =>
        (values ?? [])
        .Select(value => (value ?? "").Trim())
        .Where(value => value.Length > 0)
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .Take(3)
        .ToArray();

    private static int FindFirstModulePosition(bool[] occupied, int span)
    {
        for (var position = 0; position < occupied.Length; position++)
        {
            if (CanPlaceModule(occupied, position, span))
            {
                return position;
            }
        }

        return -1;
    }

    private static bool CanPlaceModule(bool[] occupied, int position, int span)
    {
        if (position < 0 || position >= occupied.Length || span is < 1 or > 3)
        {
            return false;
        }

        var column = position % 3;
        if (column + span > 3 || position + span > occupied.Length)
        {
            return false;
        }

        for (var offset = 0; offset < span; offset++)
        {
            if (occupied[position + offset])
            {
                return false;
            }
        }

        return true;
    }

    private static void MarkModuleCells(bool[] occupied, int position, int span)
    {
        for (var offset = 0; offset < span; offset++)
        {
            occupied[position + offset] = true;
        }
    }

    private static string NormalizeTime(string? value, string fallback) =>
        TimeOnly.TryParseExact(value, "HH:mm", out _) ? value! : fallback;
}

internal static class PersonalProfileVisibilityPolicy
{
    public static bool CanViewProfile(bool isOwner, bool isProfilePublic) =>
        isOwner || isProfilePublic;

    public static bool CanExposePresence(bool canViewProfile, bool isInvisible) =>
        canViewProfile && !isInvisible;
}

internal static class PersonalProfileModuleLayout
{
    private const int ColumnCount = PersonalProfileProductContract.ColumnCount;
    private const int CellCount = PersonalProfileProductContract.LegacyCellCount;

    public static PersonalProfileModuleSetting[] Move(
        IEnumerable<PersonalProfileModuleSetting> source,
        string sourceId,
        int requestedPosition)
    {
        var modules = source.OrderBy(module => module.Order).ToArray();
        var moving = modules.FirstOrDefault(module =>
            module.IsVisible && string.Equals(module.Id, sourceId, StringComparison.Ordinal));
        if (moving is null)
        {
            return modules;
        }

        var targetPosition = NormalizePosition(requestedPosition, moving.Span);
        if (targetPosition == moving.Position)
        {
            return modules;
        }

        var occupied = new bool[CellCount];
        MarkCells(occupied, targetPosition, moving.Span, true);
        var positions = new Dictionary<string, int>(StringComparer.Ordinal)
        {
            [moving.Id] = targetPosition
        };
        var remaining = modules
            .Where(module => module.IsVisible && !string.Equals(module.Id, moving.Id, StringComparison.Ordinal))
            .OrderByDescending(module => Overlaps(module.Position, module.Span, targetPosition, moving.Span))
            .ThenBy(module => module.Order)
            .ToArray();

        if (!TryPlaceModules(remaining, 0, moving.Position, targetPosition, moving.Span, occupied, positions))
        {
            return modules;
        }

        var visible = modules
            .Where(module => module.IsVisible)
            .Select(module => module with { Position = positions[module.Id] })
            .OrderBy(module => module.Position)
            .ThenBy(module => module.Order);
        var hidden = modules
            .Where(module => !module.IsVisible)
            .Select(module => module with { Position = -1 });

        return visible
            .Concat(hidden)
            .Select((module, order) => module with { Order = order })
            .ToArray();
    }

    public static bool HasSameLayout(
        IEnumerable<PersonalProfileModuleSetting> first,
        IEnumerable<PersonalProfileModuleSetting> second)
    {
        var firstById = first.ToDictionary(module => module.Id, StringComparer.Ordinal);
        var secondById = second.ToDictionary(module => module.Id, StringComparer.Ordinal);
        return firstById.Count == secondById.Count && firstById.All(pair =>
            secondById.TryGetValue(pair.Key, out var module) &&
            pair.Value.Position == module.Position &&
            pair.Value.Span == module.Span &&
            pair.Value.IsVisible == module.IsVisible);
    }

    private static bool TryPlaceModules(
        IReadOnlyList<PersonalProfileModuleSetting> modules,
        int index,
        int vacatedPosition,
        int targetPosition,
        int targetSpan,
        bool[] occupied,
        IDictionary<string, int> positions)
    {
        if (index >= modules.Count)
        {
            return true;
        }

        var module = modules[index];
        var displaced = Overlaps(module.Position, module.Span, targetPosition, targetSpan);
        foreach (var position in CandidatePositions(module, displaced, vacatedPosition))
        {
            if (!CanPlace(occupied, position, module.Span))
            {
                continue;
            }

            MarkCells(occupied, position, module.Span, true);
            positions[module.Id] = position;
            if (TryPlaceModules(modules, index + 1, vacatedPosition, targetPosition, targetSpan, occupied, positions))
            {
                return true;
            }

            positions.Remove(module.Id);
            MarkCells(occupied, position, module.Span, false);
        }

        return false;
    }

    private static IEnumerable<int> CandidatePositions(
        PersonalProfileModuleSetting module,
        bool displaced,
        int vacatedPosition)
    {
        var candidates = new List<int>();
        if (displaced)
        {
            candidates.Add(NormalizePosition(vacatedPosition, module.Span));
        }

        candidates.Add(NormalizePosition(module.Position, module.Span));
        candidates.AddRange(Enumerable.Range(0, CellCount)
            .Select(position => NormalizePosition(position, module.Span))
            .OrderBy(position => Math.Abs(position - module.Position)));
        return candidates.Distinct();
    }

    private static int NormalizePosition(int position, int span)
    {
        position = Math.Clamp(position, 0, CellCount - 1);
        span = Math.Clamp(span, 1, ColumnCount);
        var row = position / ColumnCount;
        var column = Math.Min(position % ColumnCount, ColumnCount - span);
        return (row * ColumnCount) + column;
    }

    private static bool Overlaps(int firstPosition, int firstSpan, int secondPosition, int secondSpan)
    {
        if (firstPosition / ColumnCount != secondPosition / ColumnCount)
        {
            return false;
        }

        return firstPosition < secondPosition + secondSpan && secondPosition < firstPosition + firstSpan;
    }

    private static bool CanPlace(bool[] occupied, int position, int span)
    {
        if (position < 0 || position >= occupied.Length || span is < 1 or > ColumnCount ||
            position % ColumnCount + span > ColumnCount)
        {
            return false;
        }

        for (var offset = 0; offset < span; offset++)
        {
            if (occupied[position + offset])
            {
                return false;
            }
        }

        return true;
    }

    private static void MarkCells(bool[] occupied, int position, int span, bool value)
    {
        for (var offset = 0; offset < span; offset++)
        {
            occupied[position + offset] = value;
        }
    }
}
