namespace StarBridge.Desktop;

using StarBridge.Core.Presence;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

internal sealed record FleetAxisPrivacySettings(
    PlayerSharedStateFields Fields,
    bool AdministratorsCanView = false,
    bool AllMembersCanView = false,
    string[]? VisibilityGroupIds = null);

internal sealed record RoomAxisPrivacySettings(
    PlayerSharedStateFields Fields,
    bool AllMembersCanView = false,
    string[]? VisibilityGroupIds = null);

internal sealed record PendingPrivateVisibilityGroupMigration(
    string LocalReferenceId,
    string Name,
    string[] MemberAccountIds);

internal sealed record DualAxisPrivacySettings(
    FleetAxisPrivacySettings Fleet,
    RoomAxisPrivacySettings Room,
    PendingPrivateVisibilityGroupMigration[] PendingGroupMigrations,
    bool PublicationEnabled = true,
    bool TracksLegacySettings = true)
{
    internal const int MaxVisibilityGroups = 12;
    internal const int MaxVisibilityGroupNameLength = 32;
    private const string LegacySpecifiedMembersReferenceId = "pending:legacy-specified-members";

    internal static DualAxisPrivacySettings CreateDefault() =>
        new(
            new FleetAxisPrivacySettings(
                PlayerSharedStateFields.All,
                AllMembersCanView: true),
            new RoomAxisPrivacySettings(
                PlayerSharedStateFields.All,
                AllMembersCanView: true),
            [],
            PublicationEnabled: true,
            TracksLegacySettings: false);

    internal static DualAxisPrivacySettings Migrate(
        SyncPrivacySettings legacy,
        PlayerEventSharingSettings eventSharing)
    {
        var legacyScope = Enum.IsDefined(legacy.VisibilityScope)
            ? legacy.VisibilityScope
            : SyncPrivacyVisibilityScope.Private;
        var normalizedLegacy = (legacy with { VisibilityScope = legacyScope }).NormalizeVisibilityScope();
        var fleetFields = ResolveLegacyFleetFields(normalizedLegacy, eventSharing);
        var specifiedMembers = PlayerSharedStateVisibility.NormalizeSpecifiedMemberAccountIds(
            normalizedLegacy.SpecifiedMemberAccountIds);
        var migratesSpecifiedMembers =
            normalizedLegacy.EffectiveVisibilityScope == SyncPrivacyVisibilityScope.SpecifiedMembers &&
            specifiedMembers.Length > 0;
        PendingPrivateVisibilityGroupMigration[] pendingGroups = migratesSpecifiedMembers
            ?
            [
                new PendingPrivateVisibilityGroupMigration(
                    LegacySpecifiedMembersReferenceId,
                    "原指定成员",
                    specifiedMembers)
            ]
            : [];

        var fleet = normalizedLegacy.EffectiveVisibilityScope switch
        {
            SyncPrivacyVisibilityScope.AdminOnly => new FleetAxisPrivacySettings(
                fleetFields,
                AdministratorsCanView: true),
            SyncPrivacyVisibilityScope.SpecifiedMembers => new FleetAxisPrivacySettings(
                fleetFields,
                AdministratorsCanView: true,
                VisibilityGroupIds: migratesSpecifiedMembers ? [LegacySpecifiedMembersReferenceId] : []),
            SyncPrivacyVisibilityScope.Fleet => new FleetAxisPrivacySettings(
                fleetFields,
                AllMembersCanView: true),
            _ => new FleetAxisPrivacySettings(fleetFields)
        };

        return new DualAxisPrivacySettings(
            fleet,
            new RoomAxisPrivacySettings(PlayerSharedStateFields.None),
            pendingGroups,
            PublicationEnabled: normalizedLegacy.SyncEnabled).Normalize();
    }

    internal DualAxisPrivacySettings Normalize()
    {
        var pending = (PendingGroupMigrations ?? [])
            .Select(group => new PendingPrivateVisibilityGroupMigration(
                (group.LocalReferenceId ?? "").Trim(),
                Truncate((group.Name ?? "").Trim(), MaxVisibilityGroupNameLength),
                PlayerSharedStateVisibility.NormalizeSpecifiedMemberAccountIds(group.MemberAccountIds)))
            .Where(group => group.LocalReferenceId.Length > 0 && group.Name.Length > 0)
            .GroupBy(group => group.LocalReferenceId, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .Take(MaxVisibilityGroups)
            .ToArray();

        var fleet = Fleet ?? new FleetAxisPrivacySettings(PlayerSharedStateFields.None);
        var room = Room ?? new RoomAxisPrivacySettings(PlayerSharedStateFields.None);
        return this with
        {
            Fleet = fleet with
            {
                Fields = fleet.Fields & PlayerSharedStateFields.All,
                VisibilityGroupIds = NormalizeGroupReferences(fleet.VisibilityGroupIds)
            },
            Room = room with
            {
                Fields = room.Fields & PlayerSharedStateFields.All,
                VisibilityGroupIds = NormalizeGroupReferences(room.VisibilityGroupIds)
            },
            PendingGroupMigrations = pending
        };
    }

    internal PlayerSharedStatePublicationPolicy ToPublicationPolicy(
        bool friendsCanViewPresence,
        bool personalHangarSharedWithFleet)
    {
        var settings = Normalize();
        if (!settings.PublicationEnabled)
        {
            return new PlayerSharedStatePublicationPolicy(
                FleetScope: PlayerSharedStateVisibility.PrivateScope,
                FleetFields: PlayerSharedStateFields.None,
                RoomScope: PlayerSharedStateVisibility.PrivateScope,
                RoomFields: PlayerSharedStateFields.None,
                FriendsCanViewPresence: false,
                PersonalHangarSharedWithFleet: false,
                UsesFleetAudienceSources: true,
                UsesRoomAudienceSources: true);
        }

        return new PlayerSharedStatePublicationPolicy(
            FleetScope: PlayerSharedStateVisibility.PrivateScope,
            FleetFields: settings.Fleet.Fields,
            RoomScope: PlayerSharedStateVisibility.PrivateScope,
            RoomFields: settings.Room.Fields,
            FriendsCanViewPresence: friendsCanViewPresence,
            PersonalHangarSharedWithFleet: personalHangarSharedWithFleet,
            UsesFleetAudienceSources: true,
            FleetAdministratorsCanView: settings.Fleet.AdministratorsCanView,
            FleetMembersCanView: settings.Fleet.AllMembersCanView,
            UsesRoomAudienceSources: true,
            RoomMembersCanView: settings.Room.AllMembersCanView);
    }

    private static string[] NormalizeGroupReferences(IEnumerable<string?>? groupIds) =>
        (groupIds ?? [])
        .Select(groupId => (groupId ?? "").Trim())
        .Where(groupId => groupId.Length > 0)
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .Take(MaxVisibilityGroups)
        .ToArray();

    private static string Truncate(string value, int maximumCharacters) =>
        string.Concat(value.EnumerateRunes().Take(maximumCharacters).Select(rune => rune.ToString()));

    private static PlayerSharedStateFields ResolveLegacyFleetFields(
        SyncPrivacySettings legacy,
        PlayerEventSharingSettings eventSharing)
    {
        var fields = PlayerSharedStateFields.None;
        if (legacy.SyncOnlineStatus)
        {
            fields |= PlayerSharedStateFields.Presence;
        }

        if (legacy.SyncShipStatus)
        {
            fields |= PlayerSharedStateFields.Ship;
        }

        if (legacy.SyncLocationStatus)
        {
            fields |= PlayerSharedStateFields.Location;
        }

        if (legacy.SyncServerInfo)
        {
            fields |= PlayerSharedStateFields.Server;
        }

        if (eventSharing.EffectiveTypes != PlayerSharedEventTypes.None)
        {
            fields |= PlayerSharedStateFields.SharedEvents;
        }

        if (legacy.PersonalHangarVisible)
        {
            fields |= PlayerSharedStateFields.PersonalHangar;
        }

        return fields;
    }
}

internal sealed class DualAxisPrivacySettingsStore
{
    private const string SettingsDirectoryName = "dual-axis-privacy";
    private readonly string _settingsDirectory;
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        WriteIndented = true
    };

    internal DualAxisPrivacySettingsStore(string configDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(configDirectory);
        _settingsDirectory = Path.Combine(configDirectory, SettingsDirectoryName);
    }

    internal DualAxisPrivacySettings LoadOrMigrate(
        string? accountIdentity,
        SyncPrivacySettings legacy,
        PlayerEventSharingSettings eventSharing,
        bool hasStoredLegacySettings = true)
    {
        var migrated = DualAxisPrivacySettings.Migrate(legacy, eventSharing);
        if (string.IsNullOrWhiteSpace(accountIdentity))
        {
            return hasStoredLegacySettings
                ? migrated
                : DualAxisPrivacySettings.CreateDefault();
        }

        var path = ResolveSettingsPath(accountIdentity);
        var loaded = TryLoad(path) ?? TryLoad($"{path}.bak");
        if (loaded is not null)
        {
            var normalized = loaded.Normalize();
            if (!normalized.TracksLegacySettings)
            {
                return normalized;
            }

            if (!hasStoredLegacySettings)
            {
                return normalized;
            }

            TrySaveMigration(accountIdentity, migrated);
            return migrated;
        }

        var initial = hasStoredLegacySettings
            ? migrated
            : DualAxisPrivacySettings.CreateDefault();
        TrySaveMigration(accountIdentity, initial);

        return initial;
    }

    internal void Save(string? accountIdentity, DualAxisPrivacySettings settings)
    {
        if (string.IsNullOrWhiteSpace(accountIdentity))
        {
            return;
        }

        var path = ResolveSettingsPath(accountIdentity);
        Directory.CreateDirectory(_settingsDirectory);
        var temporaryPath = $"{path}.tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(settings.Normalize(), _jsonOptions));
        if (File.Exists(path))
        {
            File.Copy(path, $"{path}.bak", overwrite: true);
        }

        File.Move(temporaryPath, path, overwrite: true);
    }

    private DualAxisPrivacySettings? TryLoad(string path)
    {
        try
        {
            return File.Exists(path)
                ? JsonSerializer.Deserialize<DualAxisPrivacySettings>(File.ReadAllText(path), _jsonOptions)
                : null;
        }
        catch
        {
            return null;
        }
    }

    private void TrySaveMigration(string accountIdentity, DualAxisPrivacySettings settings)
    {
        try
        {
            Save(accountIdentity, settings);
        }
        catch
        {
            // Keep the exact in-memory migration when local persistence is unavailable.
        }
    }

    private string ResolveSettingsPath(string accountIdentity)
    {
        var normalizedIdentity = accountIdentity.Trim().ToUpperInvariant();
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(normalizedIdentity)))
            .ToLowerInvariant();
        return Path.Combine(_settingsDirectory, $"{hash}.json");
    }
}
