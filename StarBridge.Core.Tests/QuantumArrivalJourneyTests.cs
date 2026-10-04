using StarBridge.Core.Events;
using StarBridge.Core.State;

namespace StarBridge.Core.Tests;

internal static class QuantumArrivalJourneyTests
{
    internal static void RunAll()
    {
        StationDisplayDoesNotConfirmArrival();
        var origin = new DateTimeOffset(2026, 9, 30, 12, 0, 0, TimeSpan.Zero);
        var state = new FleetState();
        state.Apply(new(FleetEventType.PlayerLocationChanged, "Self", Location: "Old place", Timestamp: origin,
            LocationEvidenceScore: 100));
        state.Apply(new(FleetEventType.PlayerNavigationTargetChanged, "Self", NavigationTarget: "Current target", Timestamp: origin));
        state.Apply(new(FleetEventType.PlayerLocationChanged, "Self", Location: "Arrived - awaiting location confirmation", Timestamp: origin.AddMinutes(2)));
        var player = state.Players.Single();
        Check(player.ArrivalTargetCode == "Current target" && player.Location == "Old place", "current journey target remains distinct from last confirmed history");
        state.Apply(new(FleetEventType.PlayerLocationChanged, "Self", Location: "Arrived - awaiting location confirmation", Timestamp: origin.AddMinutes(2).AddSeconds(1)));
        Check(player.ArrivalTargetCode == "Current target", "duplicate arrival retains the same pending target");
        state.Apply(new(FleetEventType.PlayerLocationChanged, "Self", Location: "Arrived - awaiting location confirmation", Timestamp: origin.AddMinutes(5)));
        Check(player.ArrivalTargetCode is null, "later arrival with no new selection cannot reuse the consumed journey target");

        var expired = new FleetState();
        expired.Apply(new(FleetEventType.PlayerNavigationTargetChanged, "Self", NavigationTarget: "Expired target", Timestamp: origin));
        expired.Apply(new(FleetEventType.PlayerLocationChanged, "Self", Location: "Arrived - awaiting location confirmation", Timestamp: origin.AddHours(2)));
        Check(expired.Players.Single().ArrivalTargetCode is null, "unrecovered selection obeys the existing one-hour WPF context age bound");
    }
    private static void StationDisplayDoesNotConfirmArrival()
    {
        const string route = "LOC_rs_ext_pyro3_l1";
        Check(StarBridge.Core.Locations.NavigationStationDisplay.TryGetStationCode(route, out var station) && station == "RR_P3_L1",
            "Starlight navigation uses the station display pairing");
        Check(!StarBridge.Core.Locations.NavigationStationDisplay.TryGetStationCode("Pyro3_L1", out _) &&
            !StarBridge.Core.Locations.NavigationStationDisplay.TryGetStationCode("rs_ext_pyro3_l2", out _),
            "canonical facts and unobserved navigation targets are not rewritten or guessed");
        var state = new FleetState();
        var time = new DateTimeOffset(2026, 10, 1, 12, 0, 0, TimeSpan.Zero);
        state.Apply(new(FleetEventType.PlayerLocationChanged, "Self", Location: "Old place", Timestamp: time, LocationEvidenceScore: 100));
        state.Apply(new(FleetEventType.PlayerNavigationTargetChanged, "Self", NavigationTarget: route, Timestamp: time.AddSeconds(1)));
        state.Apply(new(FleetEventType.PlayerLocationChanged, "Self", Location: "Arrived - awaiting location confirmation", Timestamp: time.AddSeconds(2)));
        var player = state.Players.Single();
        Check(player.ArrivalTargetCode == route && player.ArrivalPendingConfirmation && player.ConfirmedLocationCode == "Old place",
            "display pairing never turns navigation into confirmed location or changes its raw event code");
        state.Apply(new(FleetEventType.PlayerLocationChanged, "Self", Location: station, Timestamp: time.AddSeconds(3), LocationEvidenceScore: 100));
        Check(!player.ArrivalPendingConfirmation && player.ConfirmedLocationCode == station, "real station evidence confirms arrival normally");
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
