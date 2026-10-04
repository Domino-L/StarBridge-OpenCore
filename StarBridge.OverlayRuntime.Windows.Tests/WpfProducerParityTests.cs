using System.Reflection;
using System.Text.Json;
using StarBridge.Core.Events;
using StarBridge.Core.Parsing;
using StarBridge.Core.Ships;
using StarBridge.Core.State;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.Desktop.Tests;

// A bounded same-input comparison of the real old pure producer seams against
// the actual Host tracker. This does not execute MainWindow, HTTP or an HWND,
// and deliberately does not claim that the entire legacy application is equal.
internal static class WpfProducerParityTests
{
    private static readonly Type Tracker = typeof(GameLogRuntime).Assembly.GetType(
        "StarBridge.HostRuntime.Presence.GameLogSessionTracker", throwOnError: true)!;
    private static readonly MethodInfo Observe = Tracker.GetMethod("Observe", BindingFlags.Instance | BindingFlags.NonPublic)!;
    private static readonly FieldInfo Fleet = Tracker.GetField("_fleet", BindingFlags.Instance | BindingFlags.NonPublic)!;
    private static readonly string[] ComparedProperties = [
        nameof(FleetPlayer.Ship), nameof(FleetPlayer.ShipConfidence), nameof(FleetPlayer.ShipInstanceId),
        nameof(FleetPlayer.ShipChannelMembershipConfirmed), nameof(FleetPlayer.LastControlSeatLeftAt),
        nameof(FleetPlayer.Location), nameof(FleetPlayer.LocationConfidence), nameof(FleetPlayer.ConfirmedLocationCode),
        nameof(FleetPlayer.ArrivalPendingConfirmation), nameof(FleetPlayer.ArrivalTargetCode),
        nameof(FleetPlayer.NavigationTarget), nameof(FleetPlayer.NavigationTargetSelectedAt),
        nameof(FleetPlayer.NavigationOriginLocation)];

    internal static void RunAll()
    {
        using var resource = typeof(ShipNameIndex).Assembly.GetManifestResourceStream("StarBridge.ShipNamePack.json")!;
        using var pack = JsonDocument.Parse(resource);
        var cases = 0;
        foreach (var row in pack.RootElement.GetProperty("entries").EnumerateArray())
        {
            var runtime = row.GetProperty("runtimeId").GetString()!;
            var english = row.GetProperty("englishName").GetString()!;
            foreach (var channel in new[] { runtime, english }.Where(raw => ShipNameIndex.Bundled.Find(raw)?.RuntimeId == runtime))
            {
                CompareSequence(runtime, channel);
                cases++;
            }
        }
        Console.WriteLine($"PASS WPF pure producer / actual Host tracker: {cases} ship sequences, navigation/arrival/confirmation/seat/exit; {ComparedProperties.Length} state fields per step");
        ContextIsClearedAtAuthorityBoundaries();
    }

    private static void ContextIsClearedAtAuthorityBoundaries()
    {
        const string route = "<Calculate Route> | AUTH | ANVL_Arrow_45678[45678]|CSCItemNavigation::CalculateRoute|Projected Start Location is Stanton4_NewBabbage for route to destination LOC_rs_ext_pyro3_l1";
        const string arrival = "<Quantum Drive Arrived - Arrived at Final Destination> | AUTH | ANVL_Arrow_45678[45678]|CSCItemNavigation::OnQuantumDriveArrived";
        foreach (var boundary in new[] { "reset", "server", "identity", "disconnect" })
        {
            var host = Activator.CreateInstance(Tracker, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
                binder: null, args: [null], culture: null)!;
            var now = DateTimeOffset.Parse("2026-09-30T12:00:00Z");
            void Line(string body) { Observe.Invoke(host, [$"<{now:O}> {body}"]); now = now.AddSeconds(1); }
            Line("nickname=\"FixturePilot\" playerGEID=12345");
            Line("<Join PU> shard[pub_use1_fixture_alpha]");
            Line(route);
            if (boundary == "reset")
            {
                Tracker.GetMethod("Reset", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(host, null);
                Line("nickname=\"FixturePilot\" playerGEID=12345");
            }
            else if (boundary == "server") Line("<Join PU> shard[pub_use1_fixture_beta]");
            else if (boundary == "identity") Line("nickname=\"FixtureOther\" playerGEID=67890");
            else Line("<Channel Disconnection> gamerules=\"SC_Default\" reason=\"Player requested disconnect\"");
            Line(arrival);
            var actual = ((FleetState)Fleet.GetValue(host)!).Players.Single(p => p.Name == "LocalPlayer");
            if (actual.ArrivalTargetCode is not null || actual.NavigationOriginLocation is not null)
                throw new Exception("Old route leaked across authority boundary: " + boundary);
        }
        Console.WriteLine("PASS actual Host quantum context reset/server/identity/disconnect guards");
    }

    private static void CompareSequence(string runtime, string channel)
    {
        var parser = new RegexLogEventParser();
        var legacyFleet = new FleetState();
        var quantum = new QuantumTravelContextTracker();
        var host = Activator.CreateInstance(Tracker, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
            binder: null, args: [null], culture: null)!;
        const string player = "FixturePilot";
        var time = DateTimeOffset.Parse("2026-09-30T12:00:00Z");
        var bodies = new[] {
            $"nickname=\"{player}\" playerGEID=12345",
            $"<SHUDEvent_OnNotification> Added notification \"You joined channel '{channel} : {player}'\"",
            $"SetDriver: Local client node accepted '{runtime}_45678'",
            $"<Calculate Route> | AUTH | {runtime}_45678[45678]|CSCItemNavigation::CalculateRoute|Projected Start Location is Stanton4_NewBabbage for route to destination LOC_rs_ext_pyro3_l1",
            $"<Quantum Drive Arrived - Arrived at Final Destination> | AUTH | {runtime}_45678[45678]|CSCItemNavigation::OnQuantumDriveArrived",
            $"<RequestLocationInventory> Player[{player}] requested inventory for Location[RR_P3_L1]",
            $"ClearDriver: Local client node released '{runtime}_45678'",
            $"PLAYER_EXIT_SHIP player={player} ship={runtime}"
        };
        for (var step = 0; step < bodies.Length; step++)
        {
            var line = $"<{time.AddSeconds(step):O}> {bodies[step]}";
            var parsed = parser.TryParse(line) ?? throw new Exception("Fixture did not parse step " + step);
            if (parsed.Player.Equals("LocalPlayer", StringComparison.OrdinalIgnoreCase)) parsed = parsed with { Player = player };
            parsed = quantum.Resolve(FleetEventShipNormalizer.Normalize(parsed));
            legacyFleet.Apply(parsed);
            Observe.Invoke(host, [line]);
            if (step == 0) continue; // Host identity warmup deliberately does not publish a player row.
            var expected = legacyFleet.Players.Single(p => p.Name == player);
            var actual = ((FleetState)Fleet.GetValue(host)!).Players.Single(p => p.Name == "LocalPlayer");
            foreach (var property in ComparedProperties)
            {
                var field = typeof(FleetPlayer).GetProperty(property)!;
                var left = field.GetValue(expected); var right = field.GetValue(actual);
                if (!Equals(left, right)) throw new Exception($"WPF/Host mismatch: model={runtime}, channel={channel}, step={step}, field={property}, WPF={left}, Host={right}");
            }
            // Some catalogued single-seat craft intentionally clear on seat
            // release. The comparison above preserves the actual WPF policy;
            // it must not replace that policy with an all-model assertion.
            if (step == 7 && actual.ShipConfidence != "None") throw new Exception("Exact ship exit must clear the retained current ship.");
        }
    }
}
