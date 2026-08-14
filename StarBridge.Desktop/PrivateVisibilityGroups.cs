using System.ComponentModel;
using System.Net.Http;
using System.Net.Http.Json;

namespace StarBridge.Desktop;

internal sealed record PrivateVisibilityGroupContract(
    string GroupId,
    string Name,
    string[] MemberAccountIds);

internal sealed record SavePrivateVisibilityGroupContract(
    string? GroupId,
    string? Name,
    string[]? MemberAccountIds);

internal sealed class PrivateVisibilityGroupClient(StarBridgeRelayClient relayClient)
{
    internal async Task<PrivateVisibilityGroupContract[]> LoadAsync(CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            relayClient.BuildUri("api/privacy/visibility-groups"));
        using var response = await relayClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<PrivateVisibilityGroupContract[]>(cancellationToken)
               ?? [];
    }

    internal async Task<PrivateVisibilityGroupContract> SaveAsync(
        string? groupId,
        string name,
        IEnumerable<string> memberAccountIds,
        CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Put,
            relayClient.BuildUri("api/privacy/visibility-groups"))
        {
            Content = JsonContent.Create(new SavePrivateVisibilityGroupContract(
                groupId,
                name,
                memberAccountIds.ToArray()))
        };
        using var response = await relayClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<PrivateVisibilityGroupContract>(cancellationToken)
               ?? throw new InvalidOperationException("服务器没有返回可见性分组。");
    }

    internal async Task DeleteAsync(string groupId, CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Delete,
            relayClient.BuildUri($"api/privacy/visibility-groups/{Uri.EscapeDataString(groupId)}"));
        using var response = await relayClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
    }
}

internal sealed class PrivateVisibilityGroupDirectoryLoader(
    AccountSessionCoordinator accountSessions,
    Func<CancellationToken, Task<PrivateVisibilityGroupContract[]>> load)
{
    private long _generation;

    internal async Task<PrivateVisibilityGroupContract[]?> LoadLatestAsync(
        CancellationToken cancellationToken = default)
    {
        var generation = Interlocked.Increment(ref _generation);
        var session = accountSessions.Capture();
        try
        {
            var groups = await load(cancellationToken);
            return IsCurrent(session, generation) ? groups : null;
        }
        catch when (!IsCurrent(session, generation))
        {
            return null;
        }
    }

    private bool IsCurrent(AccountSessionLease session, long generation) =>
        generation == Volatile.Read(ref _generation) &&
        accountSessions.IsCurrent(session);
}

internal sealed class PrivateVisibilityGroupMutationGate(AccountSessionCoordinator accountSessions)
{
    private long _generation;

    internal async Task<T?> RunLatestAsync<T>(
        Func<CancellationToken, Task<T>> mutate,
        CancellationToken cancellationToken = default)
        where T : class
    {
        var generation = Interlocked.Increment(ref _generation);
        var session = accountSessions.Capture();
        try
        {
            var result = await mutate(cancellationToken);
            return IsCurrent(session, generation) ? result : null;
        }
        catch when (!IsCurrent(session, generation))
        {
            return null;
        }
    }

    private bool IsCurrent(AccountSessionLease session, long generation) =>
        generation == Volatile.Read(ref _generation) &&
        accountSessions.IsCurrent(session);
}

internal sealed class PrivateVisibilityGroupRow : INotifyPropertyChanged
{
    private bool _fleetSelected;

    internal required string GroupId { get; init; }
    internal required string Name { get; init; }
    internal required string[] MemberAccountIds { get; init; }
    internal bool IsPendingMigration { get; init; }

    public string DisplayName => Name;
    public string MemberCountText => $"{MemberAccountIds.Length} 人";
    public string StateText => IsPendingMigration ? "待完成旧设置迁移" : "私有分组";

    public bool FleetSelected
    {
        get => _fleetSelected;
        set
        {
            if (_fleetSelected == value)
            {
                return;
            }

            _fleetSelected = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(FleetSelected)));
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}

internal readonly record struct DualAxisPrivacyWireSettings(
    bool UsesDualAxisWire,
    StarBridge.Core.Presence.PlayerSharedStateFields FleetFields,
    StarBridge.Core.Presence.PlayerSharedStateFields RoomFields,
    bool FleetAdministratorsCanView,
    bool FleetMembersCanView,
    string[] FleetVisibilityGroupIds,
    bool RoomMembersCanView,
    string[] RoomVisibilityGroupIds);

internal static class DualAxisPrivacyTakeover
{
    internal static bool IsReadyForWire(DualAxisPrivacySettings settings) =>
        !settings.TracksLegacySettings && settings.PendingGroupMigrations.Length == 0;

    internal static DualAxisPrivacySettings WithoutRoomGroupReferences(DualAxisPrivacySettings settings)
    {
        var normalized = settings.Normalize();
        return (normalized with
        {
            Room = normalized.Room with { VisibilityGroupIds = [] }
        }).Normalize();
    }

    internal static DualAxisPrivacySettings ReplaceGroupReference(
        DualAxisPrivacySettings settings,
        string previousReferenceId,
        string currentGroupId)
    {
        string[] Replace(IEnumerable<string>? values) =>
            (values ?? [])
            .Select(value => value.Equals(previousReferenceId, StringComparison.OrdinalIgnoreCase)
                ? currentGroupId
                : value)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        return (settings with
        {
            Fleet = settings.Fleet with
            {
                VisibilityGroupIds = Replace(settings.Fleet.VisibilityGroupIds)
            },
            Room = settings.Room with
            {
                VisibilityGroupIds = Replace(settings.Room.VisibilityGroupIds)
            },
            PendingGroupMigrations = settings.PendingGroupMigrations
                .Where(group => !group.LocalReferenceId.Equals(
                    previousReferenceId,
                    StringComparison.OrdinalIgnoreCase))
                .ToArray()
        }).Normalize();
    }

    internal static DualAxisPrivacySettings RemoveGroupReference(
        DualAxisPrivacySettings settings,
        string groupId)
    {
        string[] Remove(IEnumerable<string>? values) =>
            (values ?? [])
            .Where(value => !value.Equals(groupId, StringComparison.OrdinalIgnoreCase))
            .ToArray();

        return (settings with
        {
            Fleet = settings.Fleet with
            {
                VisibilityGroupIds = Remove(settings.Fleet.VisibilityGroupIds)
            },
            Room = settings.Room with
            {
                VisibilityGroupIds = Remove(settings.Room.VisibilityGroupIds)
            },
            PendingGroupMigrations = settings.PendingGroupMigrations
                .Where(group => !group.LocalReferenceId.Equals(groupId, StringComparison.OrdinalIgnoreCase))
                .ToArray()
        }).Normalize();
    }

    internal static DualAxisPrivacyWireSettings ToWire(DualAxisPrivacySettings settings)
    {
        var normalized = settings.Normalize();
        var ready = IsReadyForWire(normalized);
        if (!ready)
        {
            return new DualAxisPrivacyWireSettings(
                false,
                StarBridge.Core.Presence.PlayerSharedStateFields.None,
                StarBridge.Core.Presence.PlayerSharedStateFields.None,
                false,
                false,
                [],
                false,
                []);
        }

        return new DualAxisPrivacyWireSettings(
            true,
            normalized.PublicationEnabled ? normalized.Fleet.Fields : StarBridge.Core.Presence.PlayerSharedStateFields.None,
            normalized.PublicationEnabled ? normalized.Room.Fields : StarBridge.Core.Presence.PlayerSharedStateFields.None,
            normalized.PublicationEnabled && normalized.Fleet.AdministratorsCanView,
            normalized.PublicationEnabled && normalized.Fleet.AllMembersCanView,
            normalized.PublicationEnabled ? normalized.Fleet.VisibilityGroupIds ?? [] : [],
            normalized.PublicationEnabled && normalized.Room.AllMembersCanView,
            normalized.PublicationEnabled ? normalized.Room.VisibilityGroupIds ?? [] : []);
    }
}
