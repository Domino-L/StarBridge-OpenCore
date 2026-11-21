using System.Reflection;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class AccountRuntimeSubscriptionTests
{
    private const BindingFlags Fields = BindingFlags.Instance | BindingFlags.NonPublic;
    private static int _checks;
    private static void Check(bool value, string message)
    {
        _checks++;
        if (!value) throw new InvalidOperationException(message);
    }
    private static T Field<T>(object value, string name) =>
        (T)value.GetType().GetField(name, Fields)!.GetValue(value)!;

    internal static Task Run()
    {
        _checks = 0;
        foreach (var notificationsFirst in new[] { false, true })
        {
            SequentialOwners(notificationsFirst);
            OverlappingOwners(notificationsFirst);
        }
        Console.WriteLine($"PASS account runtime subscriptions: {_checks} assertions, 0 failed");
        return Task.CompletedTask;
    }

    private static void Configure(AccountBridgeRuntime runtime, string root,
        NotificationSettingsBridgeDispatcher settings, bool notificationsFirst)
    {
        if (notificationsFirst) Check(runtime.ConfigureCommunityNotifications(settings), "Notifications must configure.");
        runtime.ConfigureOverlayCommunitySource(root, startDriver: false);
        if (!notificationsFirst) Check(runtime.ConfigureCommunityNotifications(settings), "Notifications must configure.");
    }

    private static Delegate?[] Subscriptions(ScmAccountBridgeHost host) =>
    [
        host.CommunityDirectoryObserved, host.CommunityRosterRevoked, host.FleetMembershipObserved,
        host.CommunityNameChanged, host.CommunityRosterObserved, Field<Delegate?>(host, "NotificationMembershipChanged")
    ];

    private static void AssertOwner(ScmAccountBridgeHost host, AccountBridgeRuntime? runtime)
    {
        var subscriptions = Subscriptions(host);
        for (var index = 0; index < subscriptions.Length; index++)
        {
            var handlers = subscriptions[index]?.GetInvocationList() ?? [];
            var expected = runtime is null ? 0 : index < 3 ? 2 : 1;
            Check(handlers.Length == expected, $"Subscription {index}: expected {expected}, actual {handlers.Length}.");
            Check(handlers.All(handler => ReferenceEquals(handler.Target, runtime)),
                $"Subscription {index} must retain only the current runtime.");
        }
    }

    private static void SequentialOwners(bool notificationsFirst)
    {
        using var fixture = new LocalAccountStopTests.Fixture();
        using var settings = new NotificationSettingsBridgeDispatcher(fixture.Root, () => fixture.Host.Generation);
        Configure(fixture.Runtime, fixture.Root, settings, notificationsFirst);
        AssertOwner(fixture.Host, fixture.Runtime);
        AssertDelivery(fixture.Runtime, fixture.Host, fixture.Root);
        var owner = fixture.Host.CurrentContext!;
        var generation = fixture.Host.Generation;
        fixture.Runtime.Dispose();
        AssertOwner(fixture.Host, null);
        // This is a subscription-lifetime test, not permission to revive a disposed
        // host's session. Reuse the same event source with a fresh runtime and fire
        // late observations. Real authenticated delivery is checked above.
        using (var second = new AccountBridgeRuntime(fixture.Host))
        {
            Configure(second, fixture.Root, settings, !notificationsFirst);
            AssertOwner(fixture.Host, second);
            FireLateObservations(fixture.Host, owner, generation);
        }
        AssertOwner(fixture.Host, null);
        FireLateObservations(fixture.Host, owner, generation);
    }

    private static void OverlappingOwners(bool notificationsFirst)
    {
        using var fixture = new LocalAccountStopTests.Fixture();
        using var settings = new NotificationSettingsBridgeDispatcher(fixture.Root, () => fixture.Host.Generation);
        Configure(fixture.Runtime, fixture.Root, settings, notificationsFirst);
        using (var second = new AccountBridgeRuntime(fixture.Host))
        {
            Configure(second, fixture.Root, settings, !notificationsFirst);
            var subscriptions = Subscriptions(fixture.Host);
            Check(subscriptions.Take(3).All(value => value?.GetInvocationList().Length == 4) &&
                subscriptions.Skip(3).All(value => value?.GetInvocationList().Length == 2),
                "Configuring a successor must preserve both owners until predecessor retirement.");
            AssertDelivery(second, fixture.Host, fixture.Root);
            var owner = fixture.Host.CurrentContext!;
            var generation = fixture.Host.Generation;
            fixture.Runtime.Dispose();
            AssertOwner(fixture.Host, second);
            FireLateObservations(fixture.Host, owner, generation);
        }
        AssertOwner(fixture.Host, null);
    }

    private static void FireLateObservations(ScmAccountBridgeHost host, BridgeAccountContext owner, long generation)
    {
        var now = DateTimeOffset.UtcNow;
        host.CommunityDirectoryObserved?.Invoke(owner, generation, 10, now, [new("B", "Beta", [])]);
        host.CommunityRosterRevoked?.Invoke(owner, generation, 11, "B");
        host.FleetMembershipObserved?.Invoke(owner, generation, "officialFleet:42");
        host.CommunityNameChanged?.Invoke(owner, generation, "B", "Renamed");
        host.CommunityRosterObserved?.Invoke(owner, generation, 12, now, new("B", "Beta", []));
        Field<Action<BridgeAccountContext, long>?>(host, "NotificationMembershipChanged")?.Invoke(owner, generation);
    }

    private static void AssertDelivery(AccountBridgeRuntime runtime, ScmAccountBridgeHost host, string root)
    {
        var owner = host.CurrentContext!;
        var generation = host.Generation;
        var overlay = Field<OverlayCommunitySource>(runtime, "_overlayCommunities");
        var notifications = Field<CommunityNotificationRuntime>(runtime, "_communityNotifications");
        void Confirmed(string code) => notifications.GetType().GetField("_confirmedSources", Fields)!.SetValue(notifications,
            new CommunityNotificationSource[] { new("fixture", "Fixture", null, false, null, false, [],
                AnnouncementIdentity: "community:" + code) });
        Confirmed("A");
        var epoch = Field<long>(notifications, "_epoch");
        host.CommunityDirectoryObserved!.Invoke(owner, generation, 1, DateTimeOffset.UtcNow, [new("B", "Beta", [])]);
        Check(overlay.ReadModuleSource(owner, generation, "B")?.Community?.Name == "Beta" &&
            Field<long>(notifications, "_epoch") > epoch,
            "Directory observations reach both overlay content and notification membership invalidation.");
        host.CommunityNameChanged!.Invoke(owner, generation, "B", "Renamed");
        Check(overlay.ReadModuleSource(owner, generation, "B")?.Community?.Name == "Renamed", "Overlay rename is preserved.");
        Confirmed("B"); epoch = Field<long>(notifications, "_epoch");
        host.CommunityRosterRevoked!.Invoke(owner, generation, 2, "B");
        Check(overlay.ReadModuleSource(owner, generation, "B") is null && Field<long>(notifications, "_epoch") > epoch,
            "Revocations reach both overlay content and notification membership invalidation.");
        host.FleetMembershipObserved!.Invoke(owner, generation, "officialFleet:42");
        var fleet = Field<OverlayCommunitySource>(overlay, "_fleetSource");
        var snapshot = new AnnouncementObservationStore(root).ReadSnapshot(AnnouncementObservationStore.Owner(owner));
        Check(Field<string>(fleet, "_fleetReference") == "officialFleet:42" &&
            snapshot.Slots.TryGetValue(AnnouncementObservationStore.Slot("", true), out var membership) &&
            membership is { Active: true, Official: true },
            "Fleet observations reach both overlay membership and durable announcement membership.");
    }
}
