using StarBridge.Core.PartyRooms;
using System.Text.Json;
namespace StarBridge.Core.Tests;

internal static class PartyRoomMemberRemovalTests
{
    internal static void RunAll()
    {
        PartyRoomHostTransferTests.RunAll();
        if (!PartyRoomMemberRemovalPolicy.CanRemove("HOST", "host", "peer") ||
            PartyRoomMemberRemovalPolicy.CanRemove("peer", "host", "other") ||
            PartyRoomMemberRemovalPolicy.CanRemove("host", "host", "HOST") ||
            PartyRoomMemberRemovalPolicy.CanRemove("", "", "peer") ||
            PartyRoomMemberRemovalPolicy.CanRemove("host", "host", null))
            throw new Exception("Only the current host may remove another identified member.");
        var old = new PartyRoomMemberSnapshot("fixture", "Fixture", "", null, false, "", "", "", "", default);
        var restored = JsonSerializer.Deserialize<PartyRoomMemberSnapshot>(JsonSerializer.Serialize(old))!;
        if (restored.RemovalToken != null) throw new Exception("Old room contracts do not invent removal authority.");
    }
}
