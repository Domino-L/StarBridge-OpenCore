namespace StarBridge.Core.PartyRooms;

public static class PartyRoomHostTransferPolicy
{
    // The membership reference locates a target; it never grants authority.
    public static bool CanTransfer(string? actor, string? owner, string? target) =>
        PartyRoomMemberRemovalPolicy.CanRemove(actor, owner, target);
}
