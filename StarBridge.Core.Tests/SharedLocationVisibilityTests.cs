using StarBridge.Core.Presence;

namespace StarBridge.Core.Tests;

internal static class SharedLocationVisibilityTests
{
    internal static void RunAll()
    {
        Require(SharedLocationVisibility.NormalizeReason("lowConfidence", "Unknown", true) == "lowConfidence");
        foreach (var reason in new string?[] { null, "", "lowconfidence", "unexpected" })
            Require(SharedLocationVisibility.NormalizeReason(reason, "Unknown", true) is null);
        Require(SharedLocationVisibility.NormalizeReason("lowConfidence", "Orison", true) is null);
        Require(SharedLocationVisibility.NormalizeReason("lowConfidence", "Unknown", false) is null);
        Require(SharedLocationVisibility.NormalizeReason("lowConfidence", "Unknown", true, true) is null);
        var member = new StarBridge.Core.PartyRooms.PartyRoomMemberSnapshot(
            "fixture", "Member", "", null, false, "InGame", "Previous Port", "Unknown", "US", DateTimeOffset.UnixEpoch);
        var oldWire = System.Text.Json.JsonSerializer.SerializeToNode(member)!.AsObject();
        oldWire.Remove("ArrivalPendingConfirmation");
        oldWire.Remove("ArrivalTargetCode");
        var oldMember = System.Text.Json.JsonSerializer.Deserialize<StarBridge.Core.PartyRooms.PartyRoomMemberSnapshot>(oldWire.ToJsonString())!;
        Require(!oldMember.ArrivalPendingConfirmation && oldMember.ArrivalTargetCode is null);
        var arriving = member with { ArrivalPendingConfirmation = true, ArrivalTargetCode = "Current Target" };
        var received = System.Text.Json.JsonSerializer.Deserialize<StarBridge.Core.PartyRooms.PartyRoomMemberSnapshot>(
            System.Text.Json.JsonSerializer.Serialize(arriving))!;
        Require(received.ArrivalPendingConfirmation && received.ArrivalTargetCode == "Current Target" && received.LocationText == "Previous Port");
    }

    private static void Require(bool condition)
    { if (!condition) throw new InvalidOperationException("Hidden location reasons must never become location or arrival facts."); }
}
