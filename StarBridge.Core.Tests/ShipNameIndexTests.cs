using StarBridge.Core.Ships;
using StarBridge.Core.Events;
using StarBridge.Core.State;

namespace StarBridge.Core.Tests;

internal static class ShipNameIndexTests
{
    public static void RunAll()
    {
        const string fixture = """
          {"schemaVersion":1,"entries":[
            {"runtimeId":"TEST_A","englishName":"Test Ship","chineseName":"测试舰船","aliases":["Model Mk I","shared"]},
            {"runtimeId":"TEST_B","englishName":"Test Ship II","chineseName":"测试舰船二型","traditionalChineseName":"測試艦船二型","aliases":["Model Mk II","shared"]},
            {"runtimeId":"TEST_C","englishName":"Third Ship","chineseName":"第三型","aliases":["shared"]},
            {"runtimeId":"ANVL_Arrow","englishName":"Arrow","chineseName":"箭矢","aliases":[]}
          ]}
          """;
        var index = ShipNameIndex.Parse(fixture);
        Require(index.Find("  test-ship  ")?.ChineseName == "测试舰船", "Case/spacing/punctuation normalization");
        Require(index.Find("TEST_A")?.ChineseName == "测试舰船", "Exact runtime ID");
        Require(index.Find("Model Mk I")?.RuntimeId == "TEST_A", "First variant");
        Require(index.Find("Model Mk II")?.RuntimeId == "TEST_B", "Second variant");
        Require(index.Find("TEST_B")?.TraditionalChineseName == "測試艦船二型", "Explicit traditional name preserved");
        Require(index.Find("Anvil Arrow")?.RuntimeId == "ANVL_Arrow",
            "Catalog entries receive the original WPF manufacturer aliases.");
        foreach (var unknown in new[] { "shared", "Test Ship Special Edition", "Other Manufacturer Test Ship", "", "TEST_A\n" })
            Require(index.Find(unknown) is null, "Unknown/ambiguous names must not guess a translation");
        foreach (var malformed in new[] { "broken", "{}", fixture.Replace("\"schemaVersion\":1", "\"schemaVersion\":2"), fixture.Replace("TEST_B", "TEST_A") })
            Require(ShipNameIndex.Parse(malformed).Find("Test Ship") is null, "Invalid catalog falls back without blocking scanning");
    }
    public static void CatalogIdentityRelease()
    {
        var time = DateTimeOffset.UtcNow;
        foreach (var (channel, runtime) in new[] { ("Anvil F8C Lightning", "ANVL_Lightning_F8C"),
            ("Aegis Avenger Titan", "AEGS_Avenger_Titan"), ("Drake Cutlass Black", "DRAK_Cutlass_Black"),
            ("Aegis Sabre Raven EX", "AEGS_Sabre_Raven_EX") })
        {
            var state = new FleetState();
            state.Apply(new(FleetEventType.PlayerEnteredShip, "Fixture", Ship: channel, Timestamp: time));
            state.Apply(new(FleetEventType.PlayerExitedShip, "Fixture", Ship: runtime, Timestamp: time.AddSeconds(1)));
            Require(state.Players.Single().ShipConfidence == "None", "Exit must clear catalog aliases: " + channel);
            state.SetPlayerOnlineState("Fixture", true, time.AddSeconds(2));
            Require(state.Players.Single().Ship == "Unknown", "Released alias cannot return through reconnect fallback.");
        }
        var variant = new FleetState();
        variant.Apply(new(FleetEventType.PlayerEnteredShip, "Fixture", Ship: "Aegis Avenger Titan", Timestamp: time));
        variant.Apply(new(FleetEventType.PlayerExitedShip, "Fixture", Ship: "AEGS_Avenger_Stalker", Timestamp: time.AddSeconds(1)));
        Require(variant.Players.Single().ShipConfidence != "None", "Another model variant cannot clear the current ship.");
        var instance = new FleetState();
        instance.Apply(new(FleetEventType.PlayerControllingShip, "Fixture", Ship: "Anvil F8C Lightning", ShipInstanceId: "first", Timestamp: time));
        instance.Apply(new(FleetEventType.PlayerStoppedDrivingShip, "Fixture", Ship: "ANVL_Lightning_F8C", ShipInstanceId: "other", Timestamp: time.AddSeconds(1)));
        Require(instance.Players.Single().ShipConfidence != "None", "Name alias resolution must not bypass the vehicle-instance check.");
        var raven = new FleetState();
        raven.Apply(new(FleetEventType.PlayerEnteredShip, "Fixture", Ship: "Aegis Sabre Raven EX", Timestamp: time));
        raven.Apply(new(FleetEventType.PlayerExitedShip, "Fixture", Ship: "AEGS_Sabre_Raven", Timestamp: time.AddSeconds(1)));
        Require(raven.Players.Single().ShipConfidence != "None", "Base Raven cannot clear the independently observed Raven EX.");
        raven.Apply(new(FleetEventType.PlayerControllingShip, "Fixture", Ship: "AEGS_Sabre_Raven_EX", ShipInstanceId: "same", Timestamp: time.AddSeconds(2)));
        raven.Apply(new(FleetEventType.PlayerStoppedDrivingShip, "Fixture", Ship: "AEGS_Sabre_Raven_EX", ShipInstanceId: "same", Timestamp: time.AddSeconds(3)));
        Require(raven.Players.Single().ShipConfidence == "None", "Raven EX seat release must immediately clear the current ship.");
        foreach (var (acquire, release) in new[]
        {
            ("Aegis Sabre Raven EX", "AEGS_Sabre_Raven_EX"),
            ("AEGS_Sabre_Raven_EX", "Aegis Sabre Raven EX"),
            ("Aegis Sabre Raven", "AEGS_Sabre_Raven"),
            ("AEGS_Sabre_Raven", "Aegis Sabre Raven")
        })
        {
            var seat = new FleetState();
            seat.Apply(new(FleetEventType.PlayerControllingShip, "Fixture", Ship: acquire,
                ShipInstanceId: "current", Timestamp: time));
            seat.Apply(new(FleetEventType.PlayerStoppedDrivingShip, "Fixture", Ship: release,
                ShipInstanceId: "previous", Timestamp: time.AddSeconds(1)));
            Require(seat.Players.Single().ShipConfidence != "None", "An old Raven instance cannot clear the current ship: " + acquire);
            var otherVariant = acquire.EndsWith("EX", StringComparison.Ordinal)
                ? "AEGS_Sabre_Raven" : "AEGS_Sabre_Raven_EX";
            seat.Apply(new(FleetEventType.PlayerStoppedDrivingShip, "Fixture", Ship: otherVariant,
                ShipInstanceId: "current", Timestamp: time.AddSeconds(2)));
            Require(seat.Players.Single().ShipConfidence != "None", "Raven variants cannot clear each other: " + acquire);
            seat.Apply(new(FleetEventType.PlayerStoppedDrivingShip, "Fixture", Ship: release,
                ShipInstanceId: "current", Timestamp: time.AddSeconds(3)));
            Require(seat.Players.Single().Ship == "Unknown" && seat.Players.Single().ShipConfidence == "None",
                "Raven seat release clears both catalog name forms: " + acquire);
            seat.SetPlayerOnlineState("Fixture", true, time.AddSeconds(4));
            Require(seat.Players.Single().Ship == "Unknown", "Online refresh cannot restore Raven after seat exit: " + acquire);
        }
    }
    private static void Require(bool result, string message) { if (!result) throw new InvalidOperationException(message); }
}
