namespace StarBridge.Desktop;

public enum FleetDirectoryLoadStatus
{
    Idle,
    Loading,
    Refreshing,
    Ready,
    Empty,
    OfflineCache,
    Error
}

public enum FleetDirectorySortMode
{
    Recommended,
    RecentlyActive,
    MemberCount,
    Name
}

public enum FleetDirectoryRefreshBehavior
{
    Reorder,
    PreserveVisibleOrder
}

public sealed record FleetDirectoryFilters(
    bool Recruiting,
    bool OpenJoin,
    bool Application,
    bool InviteOnly,
    bool Pending,
    bool ScaleSmall,
    bool ScaleMedium,
    bool ScaleLarge,
    bool ScaleVeryLarge,
    bool HasShips,
    bool SameTimeZone,
    bool ActiveEarlyMorning,
    bool ActiveMorning,
    bool ActiveAfternoon,
    bool ActiveEvening,
    IReadOnlyList<string> ActivityDayIds,
    IReadOnlyList<string> RecruitingTargets,
    IReadOnlyList<string> ActivityCadences,
    bool ShipCountSmall,
    bool ShipCountMedium,
    bool ShipCountLarge,
    bool ShipCountVeryLarge,
    IReadOnlyList<string> ShipRoleIds,
    bool MatchAllTags,
    IReadOnlyList<string> SystemIds,
    IReadOnlyList<string> TagIds)
{
    public static FleetDirectoryFilters Empty { get; } = new(
        false, false, false, false, false, false, false, false, false,
        false, false, false, false, false, false,
        Array.Empty<string>(), Array.Empty<string>(), Array.Empty<string>(),
        false, false, false, false, Array.Empty<string>(), false,
        Array.Empty<string>(), Array.Empty<string>());

    public bool HasAny =>
        Recruiting || OpenJoin || Application || InviteOnly || Pending ||
        ScaleSmall || ScaleMedium || ScaleLarge || ScaleVeryLarge || HasShips ||
        SameTimeZone || ActiveEarlyMorning || ActiveMorning || ActiveAfternoon ||
        ActiveEvening || ActivityDayIds.Count > 0 || RecruitingTargets.Count > 0 ||
        ActivityCadences.Count > 0 || ShipCountSmall || ShipCountMedium ||
        ShipCountLarge || ShipCountVeryLarge || ShipRoleIds.Count > 0 ||
        SystemIds.Count > 0 || TagIds.Count > 0;

    public FleetDirectoryFilters Snapshot() => this with
    {
        HasShips = false,
        SystemIds = NormalizeIds(SystemIds),
        TagIds = NormalizeIds(TagIds),
        ActivityDayIds = NormalizeIds(ActivityDayIds),
        RecruitingTargets = Recruiting ? NormalizeIds(RecruitingTargets) : Array.Empty<string>(),
        ActivityCadences = NormalizeIds(ActivityCadences),
        ShipRoleIds = NormalizeIds(ShipRoleIds)
    };

    private static string[] NormalizeIds(IEnumerable<string> values) => values
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => id.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
}

public sealed class FleetDirectoryState
{
    private long _requestVersion;

    public FleetDirectoryLoadStatus LoadStatus { get; private set; } = FleetDirectoryLoadStatus.Idle;

    public FleetDirectorySortMode SortMode { get; private set; } = FleetDirectorySortMode.Recommended;

    public FleetDirectoryFilters AppliedFilters { get; private set; } = FleetDirectoryFilters.Empty;

    public bool IsDetailVisible { get; private set; }

    public string? SelectedFleetCode { get; private set; }

    public string StatusMessage { get; private set; } = "";

    public long BeginLoad(bool hasCachedItems)
    {
        var requestVersion = ++_requestVersion;
        // Cached items do not make an in-flight startup request live. The
        // shared startup gate decides whether those items may be shown after
        // the request terminates as OfflineCache.
        LoadStatus = FleetDirectoryLoadStatus.Loading;
        StatusMessage = "正在加载公开组织...";
        return requestVersion;
    }

    public long BeginPassiveRefresh()
    {
        return ++_requestVersion;
    }

    public bool IsVisibleLoadInProgress =>
        LoadStatus is FleetDirectoryLoadStatus.Loading or FleetDirectoryLoadStatus.Refreshing;

    public bool CompleteLoad(long requestVersion, int itemCount)
    {
        if (!IsLatestRequest(requestVersion))
        {
            return false;
        }

        LoadStatus = itemCount > 0 ? FleetDirectoryLoadStatus.Ready : FleetDirectoryLoadStatus.Empty;
        StatusMessage = itemCount > 0 ? "" : "暂时没有可显示的公开组织。";
        return true;
    }

    public bool FailLoad(long requestVersion, bool hasCachedItems, string message)
    {
        if (!IsLatestRequest(requestVersion))
        {
            return false;
        }

        LoadStatus = hasCachedItems ? FleetDirectoryLoadStatus.OfflineCache : FleetDirectoryLoadStatus.Error;
        StatusMessage = hasCachedItems
            ? "目录刷新失败，当前显示上一次成功加载的组织。"
            : string.IsNullOrWhiteSpace(message) ? "组织目录加载失败，请重试。" : message.Trim();
        return true;
    }

    public bool IsLatestRequest(long requestVersion) => requestVersion == _requestVersion;

    public void InvalidateLoads()
    {
        _requestVersion++;
        LoadStatus = FleetDirectoryLoadStatus.Idle;
        StatusMessage = "";
        SelectedFleetCode = null;
        IsDetailVisible = false;
    }

    public void ApplyFilters(FleetDirectoryFilters filters)
    {
        AppliedFilters = (filters ?? FleetDirectoryFilters.Empty).Snapshot();
    }

    public void SetSortMode(FleetDirectorySortMode sortMode)
    {
        SortMode = sortMode;
    }

    public void SelectFromUser(string? fleetCode)
    {
        SelectedFleetCode = NormalizeFleetCode(fleetCode);
        IsDetailVisible = SelectedFleetCode is not null;
    }

    public void RefreshSelection(string? fleetCode)
    {
        SelectedFleetCode = NormalizeFleetCode(fleetCode);
    }

    public void CloseDetails()
    {
        IsDetailVisible = false;
    }

    private static string? NormalizeFleetCode(string? fleetCode) =>
        string.IsNullOrWhiteSpace(fleetCode) ? null : fleetCode.Trim();
}
