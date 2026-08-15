namespace StarBridge.Desktop;

using StarBridge.Core.Presence;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows;

public enum OverlayRosterOverflowMode
{
    Summary,
    Rotate,
    Truncate
}

/// <summary>
/// Local display preferences for the information overlay roster. Account ids in this
/// file are never uploaded and never participate in a relay request.
/// </summary>
public sealed record OverlayRosterSelectionSettings(
    string[]? PinnedAccountIds = null,
    string[]? ExcludedAccountIds = null,
    bool IncludeOfflineMembers = false,
    OverlayRosterOverflowMode OverflowMode = OverlayRosterOverflowMode.Summary,
    int UserRowLimit = 0,
    int RotationIntervalSeconds = 10)
{
    internal const int MinimumRotationIntervalSeconds = 5;
    internal const int MaximumRotationIntervalSeconds = 60;
    internal const int MaximumRowLimit = 12;

    internal static OverlayRosterSelectionSettings Default { get; } = new();

    internal OverlayRosterSelectionSettings Normalize()
    {
        var excluded = NormalizeIds(ExcludedAccountIds);
        var excludedSet = excluded.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var pinned = NormalizeIds(PinnedAccountIds)
            .Where(id => !excludedSet.Contains(id))
            .ToArray();

        return this with
        {
            PinnedAccountIds = pinned,
            ExcludedAccountIds = excluded,
            OverflowMode = Enum.IsDefined(OverflowMode)
                ? OverflowMode
                : OverlayRosterOverflowMode.Summary,
            UserRowLimit = UserRowLimit <= 0
                ? 0
                : Math.Clamp(UserRowLimit, 1, MaximumRowLimit),
            RotationIntervalSeconds = Math.Clamp(
                RotationIntervalSeconds,
                MinimumRotationIntervalSeconds,
                MaximumRotationIntervalSeconds)
        };
    }

    private static string[] NormalizeIds(IEnumerable<string>? values) =>
        (values ?? [])
        .Where(value => !string.IsNullOrWhiteSpace(value))
        .Select(value => value.Trim())
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .ToArray();
}

/// <summary>
/// Owns the automatic roster page independently from live roster refreshes. Presence,
/// ship and location updates must not keep pulling the visible member page back to zero;
/// only a real scene or local presentation-setting change starts a new rotation cycle.
/// </summary>
internal sealed class OverlayRosterRotationCursor
{
    private OverlayRosterSelectionSettings? _settings;
    private OverlaySceneKind? _sceneKind;

    internal int Page { get; private set; }

    internal bool ApplyContext(
        OverlayRosterSelectionSettings settings,
        OverlaySceneKind sceneKind)
    {
        ArgumentNullException.ThrowIfNull(settings);
        var normalized = settings.Normalize();
        var changed = !_sceneKind.HasValue ||
                      _sceneKind.Value != sceneKind ||
                      !Equivalent(_settings, normalized);
        _settings = normalized;
        _sceneKind = sceneKind;
        if (changed)
        {
            Page = 0;
        }

        return changed;
    }

    internal void Advance() => Page++;

    private static bool Equivalent(
        OverlayRosterSelectionSettings? left,
        OverlayRosterSelectionSettings right) =>
        left is not null &&
        left.IncludeOfflineMembers == right.IncludeOfflineMembers &&
        left.OverflowMode == right.OverflowMode &&
        left.UserRowLimit == right.UserRowLimit &&
        left.RotationIntervalSeconds == right.RotationIntervalSeconds &&
        SequenceEqual(left.PinnedAccountIds, right.PinnedAccountIds) &&
        SequenceEqual(left.ExcludedAccountIds, right.ExcludedAccountIds);

    private static bool SequenceEqual(string[]? left, string[]? right) =>
        (left ?? []).SequenceEqual(right ?? [], StringComparer.OrdinalIgnoreCase);
}

/// <summary>
/// Owns the local profile partition used by roster-selection preferences. A signed-out
/// session is a real profile, not an uninitialized cache sentinel.
/// </summary>
internal static class OverlayRosterSelectionProfileIdentity
{
    internal static string Resolve(string? accountId) =>
        string.IsNullOrWhiteSpace(accountId)
            ? "local"
            : $"account:{accountId.Trim().ToUpperInvariant()}";
}

/// <summary>
/// Keeps the account-partitioned settings cache honest. Persistence completes before
/// the in-memory value changes, so a failed disk write cannot become the live setting.
/// </summary>
internal sealed class OverlayRosterSelectionSettingsCache
{
    private string? _profileKey;
    private OverlayRosterSelectionSettings _settings = OverlayRosterSelectionSettings.Default;

    internal OverlayRosterSelectionSettings Load(
        string? accountId,
        Func<string?, OverlayRosterSelectionSettings> load)
    {
        ArgumentNullException.ThrowIfNull(load);
        var profileKey = OverlayRosterSelectionProfileIdentity.Resolve(accountId);
        if (_profileKey is not null &&
            _profileKey.Equals(profileKey, StringComparison.OrdinalIgnoreCase))
        {
            return _settings;
        }

        var loaded = load(accountId).Normalize();
        _settings = loaded;
        _profileKey = profileKey;
        return loaded;
    }

    internal OverlayRosterSelectionSettings Save(
        string? accountId,
        OverlayRosterSelectionSettings settings,
        Action<string?, OverlayRosterSelectionSettings> persist)
    {
        ArgumentNullException.ThrowIfNull(persist);
        var normalized = settings.Normalize();
        persist(accountId, normalized);
        _settings = normalized;
        _profileKey = OverlayRosterSelectionProfileIdentity.Resolve(accountId);
        return normalized;
    }
}

/// <summary>
/// Binds one open editor to both the account-session revision and its local settings
/// partition. A later login cannot save rows captured for an earlier account.
/// </summary>
internal readonly record struct OverlayRosterSelectionEditLease(
    AccountSessionLease AccountLease,
    string ProfileKey)
{
    internal static OverlayRosterSelectionEditLease Capture(
        AccountSessionCoordinator coordinator,
        string? accountId)
    {
        ArgumentNullException.ThrowIfNull(coordinator);
        return new(
            coordinator.Capture(),
            OverlayRosterSelectionProfileIdentity.Resolve(accountId));
    }

    internal bool IsCurrent(AccountSessionCoordinator coordinator, string? accountId)
    {
        ArgumentNullException.ThrowIfNull(coordinator);
        return coordinator.IsCurrent(AccountLease) &&
               ProfileKey.Equals(
                   OverlayRosterSelectionProfileIdentity.Resolve(accountId),
                   StringComparison.OrdinalIgnoreCase);
    }
}

/// <summary>
/// Keeps identity-bearing roster preferences out of shareable overlay presets. The
/// document is local-only and partitioned by the signed-in account.
/// </summary>
internal static class OverlayRosterSelectionSettingsStore
{
    private static readonly string SettingsPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "overlay-roster-selection.json");
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    internal static OverlayRosterSelectionSettings Load(string? accountId)
    {
        try
        {
            var document = LoadDocument();
            return document.Accounts.TryGetValue(
                    OverlayRosterSelectionProfileIdentity.Resolve(accountId),
                    out var settings)
                ? settings.Normalize()
                : OverlayRosterSelectionSettings.Default;
        }
        catch
        {
            return OverlayRosterSelectionSettings.Default;
        }
    }

    internal static void Save(string? accountId, OverlayRosterSelectionSettings settings)
    {
        Directory.CreateDirectory(DesktopAppConfig.ConfigDirectory);
        var document = LoadDocument();
        document.Accounts[OverlayRosterSelectionProfileIdentity.Resolve(accountId)] = settings.Normalize();
        var temporaryPath = SettingsPath + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(document, JsonOptions));
        File.Move(temporaryPath, SettingsPath, overwrite: true);
    }

    private static SettingsDocument LoadDocument()
    {
        if (!File.Exists(SettingsPath))
        {
            return EmptyDocument();
        }

        var parsed = JsonSerializer.Deserialize<SettingsDocument>(File.ReadAllText(SettingsPath));
        return parsed?.Accounts is { Count: > 0 }
            ? new SettingsDocument(new Dictionary<string, OverlayRosterSelectionSettings>(
                parsed.Accounts,
                StringComparer.OrdinalIgnoreCase))
            : EmptyDocument();
    }

    private static SettingsDocument EmptyDocument() =>
        new(new Dictionary<string, OverlayRosterSelectionSettings>(StringComparer.OrdinalIgnoreCase));

    private sealed record SettingsDocument(
        Dictionary<string, OverlayRosterSelectionSettings> Accounts);
}

/// <summary>
/// A closed roster produced after the relay visibility decision. The planner can only
/// filter, order, and take members from this collection; it has no data-source API.
/// </summary>
public sealed class OverlayAuthorizedRoster
{
    internal OverlayAuthorizedRoster(IEnumerable<PlayerRow> members)
    {
        var seenStableIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var closedSet = new List<PlayerRow>();
        foreach (var member in members ?? [])
        {
            if (member is null)
            {
                continue;
            }

            var stableId = OverlayRosterPreferenceIdentity.Resolve(member);
            if (stableId is not null && !seenStableIds.Add(stableId))
            {
                continue;
            }

            // Rows without a stable id are distinct authorized observations. They
            // remain visible, but cannot acquire a persistent local preference.
            closedSet.Add(member);
        }

        Members = closedSet;
    }

    internal IReadOnlyList<PlayerRow> Members { get; }

    internal IReadOnlyList<PlayerRow> Resolve(OverlayRosterProjection projection) =>
        projection.VisibleSourceIndices.Select(index => Members[index]).ToArray();
}

/// <summary>
/// Resolves the only identity that local roster preferences may persist. Display
/// identity is intentionally excluded: callsigns and game ids can change and must
/// never become a back door around the relay-authorized roster.
/// </summary>
internal static class OverlayRosterPreferenceIdentity
{
    internal static string? Resolve(PlayerRow? member) =>
        member is null || string.IsNullOrWhiteSpace(member.AccountId)
            ? null
            : member.AccountId.Trim();
}

/// <summary>
/// Projects the relay-authorized roster into editable local preferences and merges
/// the visible edit surface back without erasing keys that this refresh cannot
/// represent.
/// </summary>
internal static class OverlayRosterPreferencePolicy
{
    internal static IReadOnlyList<OverlayRosterPreferenceRow> ProjectRows(
        OverlayAuthorizedRoster closedSet,
        OverlayRosterSelectionSettings settings)
    {
        ArgumentNullException.ThrowIfNull(closedSet);
        settings = (settings ?? OverlayRosterSelectionSettings.Default).Normalize();

        var pinned = (settings.PinnedAccountIds ?? [])
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var excluded = (settings.ExcludedAccountIds ?? [])
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var rows = new List<OverlayRosterPreferenceRow>();

        foreach (var member in closedSet.Members
                     .OrderBy(ResolveDisplayName, StringComparer.OrdinalIgnoreCase))
        {
            var preferenceKey = OverlayRosterPreferenceIdentity.Resolve(member);
            var canEdit = preferenceKey is not null;
            rows.Add(new OverlayRosterPreferenceRow
            {
                PreferenceIdentityKey = preferenceKey,
                Callsign = ResolveDisplayName(member),
                GameId = member.Name,
                AvatarPath = member.AvatarPath,
                CanEditPreference = canEdit,
                IsPinned = canEdit && pinned.Contains(preferenceKey!),
                IsExcluded = canEdit && excluded.Contains(preferenceKey!)
            });
        }

        return rows;
    }

    internal static OverlayRosterSelectionSettings MergeVisibleRows(
        OverlayRosterSelectionSettings existing,
        IEnumerable<OverlayRosterPreferenceRow> visibleRows)
    {
        existing = (existing ?? OverlayRosterSelectionSettings.Default).Normalize();
        var rows = (visibleRows ?? [])
            .Where(row => row.CanEditPreference && row.PreferenceIdentityKey is not null)
            .ToArray();
        var representedKeys = rows
            .Select(row => row.PreferenceIdentityKey!)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var pinned = (existing.PinnedAccountIds ?? [])
            .Where(key => !representedKeys.Contains(key))
            .Concat(rows.Where(row => row.IsPinned).Select(row => row.PreferenceIdentityKey!))
            .ToArray();
        var excluded = (existing.ExcludedAccountIds ?? [])
            .Where(key => !representedKeys.Contains(key))
            .Concat(rows.Where(row => row.IsExcluded).Select(row => row.PreferenceIdentityKey!))
            .ToArray();

        return (existing with
        {
            PinnedAccountIds = pinned,
            ExcludedAccountIds = excluded
        }).Normalize();
    }

    internal static OverlayRosterPreferenceSummary Summarize(
        OverlayRosterSelectionSettings existing,
        IEnumerable<OverlayRosterPreferenceRow> visibleRows)
    {
        existing = (existing ?? OverlayRosterSelectionSettings.Default).Normalize();
        var representedRows = (visibleRows ?? [])
            .Where(row => row.CanEditPreference && row.PreferenceIdentityKey is not null)
            .GroupBy(row => row.PreferenceIdentityKey!, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.Last())
            .ToArray();
        var representedKeys = representedRows
            .Select(row => row.PreferenceIdentityKey!)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        return new OverlayRosterPreferenceSummary(
            representedRows.Count(row => row.IsPinned),
            representedRows.Count(row => row.IsExcluded),
            (existing.PinnedAccountIds ?? []).Count(key => !representedKeys.Contains(key)),
            (existing.ExcludedAccountIds ?? []).Count(key => !representedKeys.Contains(key)));
    }

    private static string ResolveDisplayName(PlayerRow member) =>
        string.IsNullOrWhiteSpace(member.Callsign) ? member.Name : member.Callsign!;
}

internal readonly record struct OverlayRosterPreferenceSummary(
    int VisiblePinned,
    int VisibleExcluded,
    int UnrepresentedPinned,
    int UnrepresentedExcluded)
{
    internal int TotalPinned => VisiblePinned + UnrepresentedPinned;
    internal int TotalExcluded => VisibleExcluded + UnrepresentedExcluded;
    internal int UnrepresentedCount => UnrepresentedPinned + UnrepresentedExcluded;
}

internal readonly record struct OverlayRosterViewport(
    double PanelHeight,
    string? LocalServerShard = null,
    string? LocalLocationKey = null,
    int RotationPage = 0);

internal sealed record OverlayRosterProjection(
    IReadOnlyList<int> VisibleSourceIndices,
    int HiddenOnlineCount,
    int HiddenOfflineCount,
    int HiddenPinnedCount,
    bool ShowOverflowSummary,
    int Capacity);

/// <summary>
/// The single policy seam for overlay member selection. It intentionally accepts only
/// an already-authorized closed roster, so pinned ids cannot expand the input set.
/// </summary>
internal static class OverlayRosterPlanner
{
    private const double HeaderAndPaddingHeight = 52;
    private const double MemberRowHeight = 35;

    internal static OverlayRosterProjection Project(
        OverlayAuthorizedRoster closedSet,
        OverlayRosterSelectionSettings preferences,
        OverlayRosterViewport viewport)
    {
        ArgumentNullException.ThrowIfNull(closedSet);
        preferences = (preferences ?? OverlayRosterSelectionSettings.Default).Normalize();

        var capacity = ResolveCapacity(viewport.PanelHeight, preferences.UserRowLimit);
        if (capacity <= 0)
        {
            return new OverlayRosterProjection([], 0, 0, 0, false, 0);
        }

        var excluded = (preferences.ExcludedAccountIds ?? [])
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var pinnedOrder = (preferences.PinnedAccountIds ?? [])
            .Select((id, index) => (Id: id, Index: index))
            .ToDictionary(pair => pair.Id, pair => pair.Index, StringComparer.OrdinalIgnoreCase);
        var self = closedSet.Members.FirstOrDefault(member => member.IsSelf);
        var localLocation = NormalizeComparableLocation(viewport.LocalLocationKey) ??
                            NormalizeComparableLocation(self);
        var localShard = NormalizeComparableShard(viewport.LocalServerShard) ??
                         NormalizeComparableShard(self?.ServerShard);

        var eligible = closedSet.Members
            .Select((member, sourceIndex) => new RankedMember(
                member,
                sourceIndex,
                ResolvePinnedIndex(member, pinnedOrder),
                IsOnSameServer(member, localShard),
                IsAtSameLocation(member, localLocation),
                IsOnline(member)))
            .Where(member => !IsExcluded(member.Player, excluded))
            // An explicit pin overrides the default density preference, but it can
            // never revive a member absent from the authorized closed set.
            .Where(member => preferences.IncludeOfflineMembers ||
                             member.Online ||
                             member.PinnedIndex < int.MaxValue)
            .OrderBy(member => member.PinnedIndex < int.MaxValue ? 0 : 1)
            .ThenBy(member => member.PinnedIndex)
            .ThenByDescending(member => member.SameServer)
            .ThenByDescending(member => member.SameLocation)
            .ThenByDescending(member => member.Online)
            .ThenBy(member => ResolveDisplayName(member.Player), StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (eligible.Length <= capacity)
        {
            return new OverlayRosterProjection(
                eligible.Select(member => member.SourceIndex).ToArray(),
                0,
                0,
                0,
                false,
                capacity);
        }

        return preferences.OverflowMode switch
        {
            OverlayRosterOverflowMode.Rotate => ProjectRotating(eligible, capacity, viewport.RotationPage),
            OverlayRosterOverflowMode.Truncate => ProjectTruncated(eligible, capacity),
            _ => ProjectWithSummary(eligible, capacity)
        };
    }

    internal static int ResolveCapacity(double panelHeight, int userRowLimit = 0)
    {
        if (!double.IsFinite(panelHeight) || panelHeight <= HeaderAndPaddingHeight)
        {
            return 0;
        }

        var physicalCapacity = Math.Clamp(
            (int)Math.Floor((panelHeight - HeaderAndPaddingHeight) / MemberRowHeight),
            0,
            OverlayRosterSelectionSettings.MaximumRowLimit);
        return userRowLimit <= 0
            ? physicalCapacity
            : Math.Min(physicalCapacity, Math.Clamp(
                userRowLimit,
                1,
                OverlayRosterSelectionSettings.MaximumRowLimit));
    }

    private static OverlayRosterProjection ProjectWithSummary(RankedMember[] eligible, int capacity)
    {
        var memberSlots = Math.Max(0, capacity - 1);
        var members = eligible.Take(memberSlots).ToArray();
        return CreateProjection(eligible, members, showSummary: true, capacity);
    }

    private static OverlayRosterProjection ProjectTruncated(RankedMember[] eligible, int capacity)
    {
        var members = eligible.Take(capacity).ToArray();
        return CreateProjection(eligible, members, showSummary: false, capacity);
    }

    private static OverlayRosterProjection ProjectRotating(
        RankedMember[] eligible,
        int capacity,
        int rotationPage)
    {
        var fixedPinned = eligible
            .Where(member => member.PinnedIndex < int.MaxValue)
            .Take(capacity)
            .ToArray();
        var remainingCapacity = Math.Max(0, capacity - fixedPinned.Length);
        if (remainingCapacity == 0)
        {
            return CreateProjection(eligible, fixedPinned, showSummary: false, capacity);
        }

        var automatic = eligible
            .Where(member => member.PinnedIndex == int.MaxValue)
            .ToArray();
        var offset = automatic.Length == 0
            ? 0
            : (int)((Math.Abs((long)rotationPage) * remainingCapacity) % automatic.Length);
        var rotated = automatic
            .Skip(offset)
            .Concat(automatic.Take(offset))
            .Take(remainingCapacity)
            .ToArray();
        var selected = fixedPinned.Concat(rotated).ToArray();
        return CreateProjection(eligible, selected, showSummary: false, capacity);
    }

    private static OverlayRosterProjection CreateProjection(
        RankedMember[] eligible,
        RankedMember[] selected,
        bool showSummary,
        int capacity)
    {
        var selectedIndices = selected.Select(member => member.SourceIndex).ToHashSet();
        var hidden = eligible.Where(member => !selectedIndices.Contains(member.SourceIndex)).ToArray();
        return new OverlayRosterProjection(
            selected.Select(member => member.SourceIndex).ToArray(),
            hidden.Count(member => member.Online),
            hidden.Count(member => !member.Online),
            hidden.Count(member => member.PinnedIndex < int.MaxValue),
            showSummary && hidden.Length > 0,
            capacity);
    }

    private static bool IsExcluded(PlayerRow member, HashSet<string> excluded)
    {
        var accountId = OverlayRosterPreferenceIdentity.Resolve(member);
        return accountId is not null && excluded.Contains(accountId);
    }

    private static int ResolvePinnedIndex(PlayerRow member, IReadOnlyDictionary<string, int> pinnedOrder)
    {
        var accountId = OverlayRosterPreferenceIdentity.Resolve(member);
        return accountId is not null && pinnedOrder.TryGetValue(accountId, out var index)
            ? index
            : int.MaxValue;
    }

    private static bool IsOnline(PlayerRow player) =>
        PlayerPresence.IsOnline(player.SharedPresence);

    private static bool IsOnSameServer(PlayerRow player, string? localShard)
    {
        var playerShard = NormalizeComparableShard(player.ServerShard);
        return localShard is not null &&
               playerShard is not null &&
               playerShard.Equals(localShard, StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsAtSameLocation(PlayerRow player, string? localLocation)
    {
        var playerLocation = NormalizeComparableLocation(player);
        return localLocation is not null &&
               playerLocation is not null &&
               playerLocation.Equals(localLocation, StringComparison.OrdinalIgnoreCase);
    }

    private static string? NormalizeComparableLocation(PlayerRow? player)
    {
        if (player is null || player.SharedPresence != PlayerPresenceKind.InGame)
        {
            return null;
        }

        var raw = !string.IsNullOrWhiteSpace(player.SharedLocation)
            ? player.SharedLocation
            : !string.IsNullOrWhiteSpace(player.RawLocation)
                ? player.RawLocation
                : player.Location;
        return NormalizeComparableLocation(raw);
    }

    private static string? NormalizeComparableLocation(string? raw)
    {
        if (!PlayerSessionStatePresentation.HasRecognizedValue(raw))
        {
            return null;
        }

        var normalized = LocationNameLocalizer.NormalizeLocation(raw)
            .Replace("地点：", "", StringComparison.OrdinalIgnoreCase)
            .Trim();
        return normalized.Equals("Unknown", StringComparison.OrdinalIgnoreCase)
            ? null
            : normalized;
    }

    private static string? NormalizeComparableShard(string? value) =>
        string.IsNullOrWhiteSpace(value) ||
        !PlayerSessionStatePresentation.HasRecognizedValue(value)
            ? null
            : value.Trim();

    private static string ResolveDisplayName(PlayerRow player) =>
        string.IsNullOrWhiteSpace(player.Callsign) ? player.Name : player.Callsign!;

    private sealed record RankedMember(
        PlayerRow Player,
        int SourceIndex,
        int PinnedIndex,
        bool SameServer,
        bool SameLocation,
        bool Online);
}

internal sealed class OverlayRosterPreferenceRow : INotifyPropertyChanged
{
    private bool _isPinned;
    private bool _isExcluded;

    public string? PreferenceIdentityKey { get; init; }
    public required string Callsign { get; init; }
    public required string GameId { get; init; }
    public string? AvatarPath { get; init; }
    public bool CanEditPreference { get; init; }

    public string PreferenceStatusText => CanEditPreference
        ? ""
        : "稳定账号身份尚未同步，暂不可钉住或排除";

    public Visibility PreferenceStatusVisibility => CanEditPreference
        ? Visibility.Collapsed
        : Visibility.Visible;

    public string IdentityLine => Callsign.Equals(GameId, StringComparison.OrdinalIgnoreCase)
        ? Callsign
        : $"{Callsign} · {GameId}";

    public bool IsPinned
    {
        get => _isPinned;
        set
        {
            if (!CanEditPreference)
            {
                return;
            }

            if (!SetProperty(ref _isPinned, value) || !value || !_isExcluded)
            {
                return;
            }

            _isExcluded = false;
            OnChanged(nameof(IsExcluded));
        }
    }

    public bool IsExcluded
    {
        get => _isExcluded;
        set
        {
            if (!CanEditPreference)
            {
                return;
            }

            if (!SetProperty(ref _isExcluded, value) || !value || !_isPinned)
            {
                return;
            }

            _isPinned = false;
            OnChanged(nameof(IsPinned));
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private bool SetProperty(ref bool field, bool value, [CallerMemberName] string propertyName = "")
    {
        if (field == value)
        {
            return false;
        }

        field = value;
        OnChanged(propertyName);
        return true;
    }

    private void OnChanged(string propertyName) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
