using StarBridge.Core.PartyRooms;
using System.Text.Json;
namespace StarBridge.Core.Tests;

internal static class PartyRoomHostTransferTests
{
    internal static void RunAll()
    {
        if (!PartyRoomHostTransferPolicy.CanTransfer("HOST", "host", "peer") ||
            PartyRoomHostTransferPolicy.CanTransfer("peer", "host", "other") ||
            PartyRoomHostTransferPolicy.CanTransfer("host", "host", "HOST") ||
            PartyRoomHostTransferPolicy.CanTransfer(null, "host", "peer") ||
            PartyRoomHostTransferPolicy.CanTransfer("host", "host", ""))
            throw new Exception("Host transfer requires current owner and a different identified target.");
        var legacy = JsonSerializer.Deserialize<PartyRoomDirectoryResponse>(
            "{\"Rooms\":[],\"CurrentRoomId\":null,\"ServerTime\":\"2026-10-03T00:00:00Z\"}")!;
        if (legacy.SupportsHostTransfer) throw new Exception("Old servers must not imply host transfer support.");
    }
}
