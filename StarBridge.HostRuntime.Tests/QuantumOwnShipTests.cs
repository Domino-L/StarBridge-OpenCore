using System.Reflection;
using StarBridge.Core.State;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Support;

internal static class QuantumOwnShipTests
{
    private static readonly DateTimeOffset Start = DateTimeOffset.Parse("2026-11-01T12:00:00Z");
    private const string Pilot = "FixturePilot";
    private const string Ship = "TEST_Voyager";
    private const string OwnId = "10101";
    private const string OtherId = "20202";
    private const string Target = "FixtureDestination";
    private const string Arrival = "<Quantum Drive Arrived - Arrived at Final Destination>";

    // Synthetic lines only. AUTH/NOT AUTH does not identify local ownership.
    private static string Navigation(string id = OwnId, bool route = false, string authority = "NOT AUTH") =>
        route
            ? $"<Calculate Route> | {authority} | {Ship}_{id}[1]|CSCItemNavigation::CalculateRoute Successfully calculated route to {Target}"
            : $"<Player Selected Quantum Target - Local> | {authority} | {Ship}_{id}[1]| Player has selected point {Target} as their destination";
    private static string Arrived(string id = OwnId, string ship = Ship, string authority = "NOT AUTH") =>
        $"{Arrival} | {authority} | {ship}_{id}[1]|CSCItemNavigation::OnQuantumDriveArrived";
    private static string Driving(string id = OwnId) => $"SetDriver: Local client node accepted '{Ship}_{id}'";
    // Ship-channel exit is disembarkation; ClearDriver depends on the vehicle.
    private static string Exited(string player = Pilot) =>
        $"<SHUDEvent_OnNotification> Added notification \"You left channel '{Ship} : {player}'\"";
    private static string Joined(string ship = Ship, string owner = "OtherPilot") =>
        $"<SHUDEvent_OnNotification> Added notification \"You joined channel '{ship} : {owner}'\"";
    private static string Inventory => $"<RequestLocationInventory> Player[{Pilot}] requested inventory for Location[FixtureOrigin]";
    private static void Check(bool yes, string reason) { if (!yes) throw new Exception(reason); }

    private sealed class Fixture : IDisposable
    {
        private readonly string _root = Path.Combine(Path.GetTempPath(), "sb-quantum-own-" + Guid.NewGuid().ToString("N"));
        internal readonly LocalGameEventJournal Journal;
        internal readonly GameLogJournalBatch Batch;
        internal readonly GameLogSessionTracker Tracker;
        internal readonly List<LocalEventEntry> Published = [];
        private readonly IDisposable _subscription;

        internal Fixture()
        {
            Journal = new(Path.Combine(_root, "local-event-log.json"), () => Start);
            Journal.Load();
            _subscription = Journal.SubscribeNewEntries(Published.Add);
            Batch = new(Journal);
            Tracker = new(Batch);
            Batch.BeginRead();
            Observe($"nickname=\"{Pilot}\" playerGEID=12345");
            Observe("<Join PU> connected shard[pub_sc_fixture_use1_111]");
            Batch.Complete(() => true); // Baseline establishes identity without history.
        }

        internal void Observe(string body, double minutes = 0) =>
            Tracker.Observe($"<{Start.AddMinutes(minutes):O}> {body}", live: true);
        internal void Read(Action lines)
        {
            Batch.BeginRead();
            lines();
            Batch.Complete(() => true);
        }
        internal GameLogSessionSnapshot Snapshot(double minutes = 0) => Tracker.Snapshot(Start.AddMinutes(minutes));
        internal FleetState Fleet => (FleetState)typeof(GameLogSessionTracker)
            .GetField("_fleet", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(Tracker)!;
        internal void IsolateNavigationProof()
        {
            // Synthetic state isolation: neither current nor LastKnown can accept
            // an arrival. Ground inventory now invalidates navigation too.
            Fleet.Clear();
        }
        internal void ExpectClearedProof()
        {
            Check(typeof(GameLogSessionTracker).GetField("_lastLocalNavigation", BindingFlags.Instance | BindingFlags.NonPublic)!
                .GetValue(Tracker) is null, "Disembarkation / ground inventory clears local navigation proof");
            var evidence = (Dictionary<string, DateTimeOffset>)typeof(GameLogSessionTracker)
                .GetField("_localShipEvidence", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(Tracker)!;
            Check(evidence.Count == 0, "Disembarkation / ground inventory clears LastKnown proof");
        }
        internal void ExpectArrival(string? target)
        {
            Check(Journal.Entries.Count(e => e.EventType == "PlayerLocationChanged" && e.Title.Contains("已结束量子航行")) +
                  Journal.Entries.Count(e => e.EventType == "PlayerLocationChanged" && e.Title.Contains("已抵达导航目标")) == 1,
                "Exactly one local quantum arrival must be journaled");
            var location = Snapshot().Location;
            Check(location.ArrivalPendingConfirmation && location.ArrivalTargetCode == target, "Accepted arrival reaches FleetState");
        }
        internal void Reject(string body, double minutes = 0)
        {
            var before = Snapshot(minutes);
            var records = Journal.Entries.Length;
            var published = Published.Count;
            var cityEvents = 0;
            Tracker.CityArrived += OnCity;
            try { Read(() => Observe(body, minutes)); }
            finally { Tracker.CityArrived -= OnCity; }
            Check(Snapshot(minutes) == before, "Rejected arrival must not change location, ship or arrival confirmation");
            Check(!Snapshot(minutes).Location.ArrivalPendingConfirmation, "Rejected arrival must not enter confirmation");
            Check(Journal.Entries.Length == records && Published.Count == published, "Rejected arrival has no history or journal publication");
            Check(cityEvents == 0, "Rejected arrival must not emit downstream city evidence");
            void OnCity(string player, string city, string evidence) => cityEvents++;
        }
        public void Dispose()
        {
            _subscription.Dispose();
            Journal.FlushAsync().GetAwaiter().GetResult();
            Journal.Dispose();
            if (Directory.Exists(_root)) Directory.Delete(_root, true);
        }
    }

    internal static Task OtherShipWithoutNavigation()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Inventory); f.Observe(Driving()); });
        f.Reject(Arrived(OtherId)); // Same model is not the same instance.
        f.Reject(Arrived(OtherId, "TEST_Stranger"));
        f.Reject(Arrived(OtherId, authority: "AUTH"));
        return Task.CompletedTask;
    }

    internal static Task MatchingNavigation()
    {
        foreach (var route in new[] { false, true })
        foreach (var authority in new[] { "NOT AUTH", "AUTH" })
        {
            using var f = new Fixture();
            f.Read(() => f.Observe(Navigation(route: route, authority: authority)));
            f.IsolateNavigationProof();
            f.Read(() => f.Observe(Arrived(authority: authority), 30));
            f.ExpectArrival(Target);
        }
        return Task.CompletedTask;
    }

    internal static Task CurrentShipWithoutNavigation()
    {
        using var f = new Fixture();
        f.Read(() => f.Observe(Driving()));
        f.Read(() => f.Observe(Arrived(), 1));
        f.ExpectArrival(null);
        return Task.CompletedTask;
    }

    internal static Task ReleasedControlWithoutNavigation()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Driving()); f.Observe($"ClearDriver: Local client node accepted '{Ship}_{OwnId}'"); });
        f.Read(() => f.Observe(Arrived(), 1));
        f.ExpectArrival(null);
        return Task.CompletedTask;
    }

    internal static Task ExpiredOrFutureNavigation()
    {
        foreach (var minutes in new[] { 31d, -1d })
        {
            using var f = new Fixture();
            f.Read(() => f.Observe(Navigation()));
            f.IsolateNavigationProof();
            f.Read(() => f.Observe(Driving(OtherId)));
            f.Reject(Arrived(), minutes);
        }
        return Task.CompletedTask;
    }

    internal static Task MissingInstanceNeverAccepted()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Driving()); f.Observe(Navigation()); });
        f.Reject($"{Arrival} CSCItemNavigation::OnQuantumDriveArrived", 1);
        // Rejection cannot consume the valid pending navigation context.
        f.Read(() => f.Observe(Arrived(), 2));
        f.ExpectArrival(Target);
        return Task.CompletedTask;
    }

    internal static Task ForeignArrivalPreservesNavigation()
    {
        using var f = new Fixture();
        f.Read(() => f.Observe(Navigation()));
        f.IsolateNavigationProof();
        f.Reject(Arrived(OtherId), 1);
        f.Read(() => f.Observe(Arrived(), 2));
        f.ExpectArrival(Target);
        return Task.CompletedTask;
    }

    internal static Task LatestNavigationWins()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Navigation()); f.Observe(Navigation(OtherId), 1); });
        f.IsolateNavigationProof();
        f.Reject(Arrived(), 2);
        f.Read(() => f.Observe(Arrived(OtherId), 3));
        f.ExpectArrival(Target);
        return Task.CompletedTask;
    }

    internal static Task RepeatedNavigationRefreshesProof()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Navigation()); f.Observe(Navigation(), 29); });
        f.IsolateNavigationProof();
        f.Read(() => f.Observe(Arrived(), 31));
        f.ExpectArrival(Target);
        return Task.CompletedTask;
    }

    internal static Task SessionBoundariesClearNavigation()
    {
        foreach (var boundary in new[] { "shard", "reconnect", "frontend", "reset", "identity" })
        {
            using var f = new Fixture();
            f.Read(() => f.Observe(Navigation()));
            f.IsolateNavigationProof();
            f.Read(() =>
            {
                if (boundary == "shard") f.Observe("<Update Shard Id> New Shard Id: pub_sc_fixture_use1_222");
                if (boundary == "reconnect")
                {
                    f.Observe("<Channel Disconnection> gamerules=\"SC_Default\" reason=\"Remote Disconnect\"");
                    f.Observe("<Join PU> connected shard[pub_sc_fixture_use1_111]");
                }
                if (boundary == "frontend")
                {
                    f.Observe("<Change Server End> IsPersistedInGameMode[0]");
                    f.Observe("<Join PU> connected shard[pub_sc_fixture_use1_111]");
                }
                if (boundary == "reset") { f.Tracker.Reset(); f.Observe($"nickname=\"{Pilot}\" playerGEID=12345"); }
                if (boundary == "identity") f.Observe("nickname=\"NextFixturePilot\" playerGEID=67890");
            });
            f.Reject(Arrived(), 1);
        }
        return Task.CompletedTask;
    }

    internal static Task NavigationThenExitRejectsArrival()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Navigation()); f.Observe(Exited(), 1); });
        f.ExpectClearedProof();
        f.Reject(Arrived(), 2);
        return Task.CompletedTask;
    }

    internal static Task DrivingThenExitRejectsArrival()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Driving()); f.Observe(Exited(), 1); });
        f.ExpectClearedProof();
        f.Reject(Arrived(), 2);
        return Task.CompletedTask;
    }

    internal static Task GroundInventoryRejectsLaterArrival()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Navigation()); f.Observe(Inventory, 1); });
        f.ExpectClearedProof();
        f.Reject(Arrived(), 2);
        return Task.CompletedTask;
    }

    internal static Task InventoryConfirmsAcceptedArrival()
    {
        foreach (var seconds in new[] { 0d, 10d, 15d })
        {
            using var f = new Fixture();
            f.Read(() => { f.Observe(Driving()); f.Observe(Navigation()); f.Observe(Arrived(), 1); });
            f.ExpectArrival(Target);
            var arrivalCount = f.Journal.Entries.Count(e => e.Title.Contains("已抵达导航目标"));
            f.Read(() => f.Observe(Inventory, 1 + seconds / 60));
            f.ExpectClearedProof();
            var player = f.Fleet.Players.Single();
            Check(player.Location == "FixtureOrigin" && !player.ArrivalPendingConfirmation,
                "Inventory within 15 seconds confirms the accepted arrival location");
            Check(player.ShipInstanceId == OwnId, "Post-arrival inventory retains the current ship as before");
            Check(f.Journal.Entries.Count(e => e.Title.Contains("已抵达导航目标")) == arrivalCount,
                "Inventory confirmation neither retracts nor duplicates the accepted arrival");
            // Keep Core's display-retained instance: it must not authorize another arrival.
            f.Reject(Arrived(), 3);
        }
        return Task.CompletedTask;
    }

    internal static Task ForeignExitAndInventoryPreserveProof()
    {
        using var f = new Fixture();
        f.Read(() =>
        {
            f.Observe(Navigation());
            f.Observe($"PLAYER_EXIT_SHIP player=\"OtherPilot\" ship=\"{Ship}\"", 1);
            f.Observe(Inventory.Replace(Pilot, "OtherPilot"), 1);
        });
        f.IsolateNavigationProof();
        f.Read(() => f.Observe(Arrived(), 2));
        f.ExpectArrival(Target);
        return Task.CompletedTask;
    }

    internal static Task ForeignOwnedChannelExitRevokesProof()
    {
        foreach (var navigation in new[] { false, true })
        {
            using var f = new Fixture();
            f.Read(() =>
            {
                f.Observe(Joined());
                f.Observe(Driving());
                if (navigation) f.Observe(Navigation());
                f.Observe(Exited("OtherPilot"), 1);
            });
            Check(f.Fleet.Players.Single().ShipInstanceId == OwnId,
                "Foreign-owner exit must not be applied to FleetState");
            f.ExpectClearedProof();
            f.Reject(Arrived(), 2);
        }
        return Task.CompletedTask;
    }

    internal static Task ClearDriverRespectsCoreDisembarkation()
    {
        foreach (var ship in new[] { "ANVL_Arrow", Ship })
        {
            using var f = new Fixture();
            f.Read(() =>
            {
                f.Observe(Driving().Replace(Ship, ship));
                f.Observe(Navigation().Replace(Ship, ship));
                f.Observe($"ClearDriver: Local client node accepted '{ship}_{OwnId}'", 1);
            });
            if (ship == "ANVL_Arrow")
            {
                Check(f.Fleet.Players.Single().ShipInstanceId is null, "Arrow release is an immediate exit");
                f.ExpectClearedProof();
                f.Reject(Arrived(ship: ship), 2);
            }
            else
            {
                Check(f.Fleet.Players.Single().ShipInstanceId == OwnId, "Voyager release retains occupancy");
                f.Read(() => f.Observe(Arrived(), 2));
                f.ExpectArrival(Target);
            }
        }
        return Task.CompletedTask;
    }

    internal static Task ReboardingDoesNotRestoreOldTarget()
    {
        foreach (var boundary in new[] { "own channel", "foreign channel", "inventory", "immediate exit" })
        {
            using var f = new Fixture();
            var ship = boundary == "immediate exit" ? "ANVL_Arrow" : Ship;
            f.Read(() =>
            {
                f.Observe(Driving().Replace(Ship, ship));
                f.Observe(Navigation().Replace(Ship, ship));
                f.Observe(boundary switch
                {
                    "own channel" => Exited(),
                    "foreign channel" => Exited("OtherPilot"),
                    "inventory" => Inventory,
                    _ => $"ClearDriver: Local client node accepted '{ship}_{OwnId}'"
                }, 1);
            });
            f.ExpectClearedProof();
            f.Read(() =>
            {
                f.Observe(Driving().Replace(Ship, ship), 2);
                f.Observe(Arrived(ship: ship), 3);
            });
            f.ExpectArrival(null);
            Check(!f.Journal.Entries.Any(e => e.EventType == "PlayerLocationChanged" && e.Title.Contains(Target)),
                "Reboarding without navigation must not journal the old target");
        }
        return Task.CompletedTask;
    }

    internal static Task DifferentChannelCannotRestoreExitedInstance()
    {
        using var f = new Fixture();
        f.Read(() =>
        {
            f.Observe(Driving());
            f.Observe(Exited("OtherPilot"), 1);
            f.Observe(Joined("RSI_Galaxy", "AnotherPilot"), 2);
        });
        Check(f.Fleet.Players.Single().ShipInstanceId == OwnId, "Owner-filtered channels retain A for display");
        f.Reject(Arrived(), 3);
        return Task.CompletedTask;
    }

    internal static Task DifferentChannelCannotRestoreInventoryInstance()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Driving()); f.Observe(Arrived(), 1); });
        f.ExpectArrival(null);
        f.Read(() =>
        {
            f.Observe(Inventory, 1 + 10d / 60);
            f.Observe(Joined("RSI_Galaxy", "AnotherPilot"), 2);
        });
        Check(f.Fleet.Players.Single().ShipInstanceId == OwnId, "Inventory retains A for display after arrival");
        f.Reject(Arrived(), 3);
        return Task.CompletedTask;
    }

    internal static Task SameInstanceDrivingRestoresArrival()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Driving()); f.Observe(Exited(), 1); });
        f.ExpectClearedProof();
        f.Read(() => { f.Observe(Driving(), 2); f.Observe(Arrived(), 3); });
        f.ExpectArrival(null);
        return Task.CompletedTask;
    }

    internal static Task SameInstanceNavigationRestoresArrival()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Driving()); f.Observe(Exited(), 1); });
        f.ExpectClearedProof();
        f.Read(() => { f.Observe(Navigation(), 2); f.Observe(Arrived(), 3); });
        f.ExpectArrival(Target);
        return Task.CompletedTask;
    }

    internal static Task DifferentModelExitPreservesCurrentJourney()
    {
        foreach (var owner in new[] { Pilot, "OtherPilot" })
        {
            using var f = new Fixture();
            f.Read(() =>
            {
                f.Observe(Driving().Replace(Ship, "RSI_Galaxy"));
                f.Observe(Navigation().Replace(Ship, "RSI_Galaxy"));
                f.Observe(Exited(owner).Replace(Ship, "ANVL_Arrow"), 1);
            });
            var player = f.Fleet.Players.Single();
            Check(player.ShipInstanceId == OwnId && player.NavigationTarget == Target &&
                  player.NavigationTargetSelectedAt == Start, "Different-model exit preserves current ship and navigation fields");
            Check(typeof(GameLogSessionTracker).GetField("_lastLocalNavigation", BindingFlags.Instance | BindingFlags.NonPublic)!
                .GetValue(f.Tracker) is not null, "Different-model exit preserves local navigation proof");
            // Remove FleetState's fallback so acceptance and target require the
            // preserved local navigation proof and QuantumTravelContextTracker.
            f.IsolateNavigationProof();
            f.Read(() => f.Observe(Arrived(ship: "RSI_Galaxy"), 2));
            f.ExpectArrival(Target);
        }
        return Task.CompletedTask;
    }

    internal static Task MatchingOrUnknownModelExitRevokesCurrentJourney()
    {
        var galaxyAlias = GameShipNames.FindRuntimeIdentity("RSI_Galaxy")!.EnglishName;
        foreach (var (current, exited) in new[]
                 { ("RSI_Galaxy", galaxyAlias), ("RSI_Galaxy", Ship), (Ship, "ANVL_Arrow") })
        {
            using var f = new Fixture();
            f.Read(() =>
            {
                f.Observe(Driving().Replace(Ship, current));
                f.Observe(Navigation().Replace(Ship, current));
                f.Observe(Exited().Replace(Ship, exited), 1);
            });
            f.ExpectClearedProof();
            f.Reject(Arrived(ship: current), 2);
        }
        return Task.CompletedTask;
    }

    internal static Task DifferentModelExitRevokesOnlyMatchingLastKnown()
    {
        foreach (var lastKnownShip in new[] { "ANVL_Arrow", "RSI_Galaxy" })
        {
            using var f = new Fixture();
            f.Read(() => f.Observe(Driving().Replace(Ship, "RSI_Galaxy")));
            // Isolate LastKnown independently of current, as in the existing
            // reconnect fallback fixture; the notification itself carries no ID.
            var player = f.Fleet.Players.Single();
            player.LastKnownShip = lastKnownShip;
            player.LastKnownShipInstanceId = OtherId;
            f.Read(() => f.Observe(Exited().Replace(Ship, "ANVL_Arrow"), 1));
            var revoked = (List<string>)typeof(GameLogSessionTracker)
                .GetField("_revokedShipInstances", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(f.Tracker)!;
            Check(!revoked.Contains(OwnId) && revoked.Contains(OtherId) == (lastKnownShip == "ANVL_Arrow"),
                "Different-model exit revokes only a matching LastKnown instance");
            f.Read(() => f.Observe(Arrived(ship: "RSI_Galaxy"), 2));
            f.ExpectArrival(null);
        }
        return Task.CompletedTask;
    }

    internal static Task WeakControlCannotRestoreRevokedInstance()
    {
        foreach (var count in new[] { 1, 9, 256 })
        {
            using var f = new Fixture();
            f.Read(() =>
            {
                for (var i = 0; i < count; i++)
                {
                    f.Observe(Driving((10101 + i).ToString()), i * 2);
                    f.Observe(Inventory, i * 2 + 1);
                }
                f.Observe($"<Failed to get starmap route data!> | NOT AUTH | {Ship}_{OwnId}[1]|CSCItemNavigation::GetStarmapRouteSegmentData", count * 2);
            });
            Check(f.Fleet.Players.Single().ShipInstanceId == OwnId,
                "Weak signal re-establishes Core display state so rejection must come from revocation");
            f.Reject(Arrived(), count * 2 + 1);
        }
        return Task.CompletedTask;
    }

    internal static Task TwoJourneysWithInventoryConfirmation()
    {
        using var f = new Fixture();
        for (var journey = 0; journey < 2; journey++)
        {
            var target = journey == 0 ? Target : "FixtureSecondDestination";
            var departure = journey * 3d;
            f.Read(() =>
            {
                f.Observe(Driving(), departure);
                f.Observe(Navigation().Replace(Target, target), departure);
                // Synthetic jump marker: the parser has no jump-start event;
                // only local target selection and arrival establish the journey.
                f.Observe($"<Quantum Drive Jump> | NOT AUTH | {Ship}_{OwnId}[1]", departure + 0.5);
                f.Observe(Arrived(), departure + 1);
            });
            var location = f.Snapshot(departure + 1).Location;
            Check(location.ArrivalPendingConfirmation && location.ArrivalTargetCode == target,
                "Each journey independently reaches arrival confirmation with its own target");
            var arrivalCount = f.Journal.Entries.Count(e => e.EventType == "PlayerLocationChanged" &&
                e.Title.Contains("已抵达导航目标"));
            Check(arrivalCount == journey + 1, "Both journeys count exactly once in local history");
            f.Read(() => f.Observe(Inventory.Replace("FixtureOrigin", target), departure + 1 + 10d / 60));
            f.ExpectClearedProof();
            var player = f.Fleet.Players.Single();
            Check(player.Location == target && !player.ArrivalPendingConfirmation,
                "Ground inventory ten seconds later confirms each destination");
            Check(f.Journal.Entries.Count(e => e.EventType == "PlayerLocationChanged" &&
                e.Title.Contains("已抵达导航目标")) == arrivalCount, "Confirmation preserves each accepted arrival");
        }
        return Task.CompletedTask;
    }

    internal static Task PassengerChannelRejectsMatchingModelWithoutInstance()
    {
        using var f = new Fixture();
        f.Read(() => f.Observe(Joined("RSI_Galaxy")));
        Check(!f.Fleet.Players.Any(), "Foreign-owner channel join must not be applied to FleetState");
        f.Reject(Arrived(ship: "RSI_Galaxy"), 1);
        return Task.CompletedTask;
    }

    internal static Task PassengerChannelRejectsDifferentModel()
    {
        using var f = new Fixture();
        f.Read(() => f.Observe(Joined("RSI_Galaxy")));
        f.Reject(Arrived(ship: "RSI_Constellation_Andromeda"), 1);
        return Task.CompletedTask;
    }

    internal static Task PassengerChannelExitRejectsMatchingModel()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Joined()); f.Observe(Exited("OtherPilot"), 1); });
        f.ExpectClearedProof();
        f.Reject(Arrived(), 2);
        return Task.CompletedTask;
    }

    internal static Task PassengerChannelRejectsConflictingInstance()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Driving(OtherId)); f.Observe(Joined()); });
        Check(f.Fleet.Players.Single().ShipInstanceId == OtherId, "Fixture has a different current instance of the same model");
        f.Reject(Arrived(), 1);
        return Task.CompletedTask;
    }

    internal static Task PassengerInventoryRevokesChannel()
    {
        using var f = new Fixture();
        f.Read(() => { f.Observe(Joined()); f.Observe(Inventory, 1); });
        f.Reject(Arrived(), 2);
        // New local navigation can establish a new journey after ground inventory.
        f.Read(() => { f.Observe(Navigation(), 3); f.Observe(Arrived(), 4); });
        f.ExpectArrival(Target);
        return Task.CompletedTask;
    }

    internal static Task RecentLastKnownShipOnly()
    {
        foreach (var minutes in new[] { 30d, 31d, -1d })
        foreach (var otherCurrent in new[] { false, true })
        {
            using var f = new Fixture();
            f.Read(() => f.Observe(Driving()));
            // Host normally clears the whole fleet on disconnect. Seed the existing
            // Core offline transition to exercise the LastKnown-only fallback without
            // changing production tracker handling of non-quantum events.
            var fleet = (FleetState)typeof(GameLogSessionTracker).GetField("_fleet", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(f.Tracker)!;
            fleet.SetPlayerOnlineState("LocalPlayer", false, Start);
            Check(fleet.Players.Single().ShipInstanceId is null && fleet.Players.Single().LastKnownShipInstanceId == OwnId,
                "Fixture must exercise LastKnown rather than current ship");
            if (otherCurrent) f.Read(() => f.Observe(Driving(OtherId)));
            if (minutes == 30)
            {
                f.Read(() => f.Observe(Arrived(), minutes));
                f.ExpectArrival(null);
            }
            else f.Reject(Arrived(), minutes);
        }
        return Task.CompletedTask;
    }
}
