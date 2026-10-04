namespace StarBridge.Core.PartyRooms;

public static class PartyRoomMemberRemovalPolicy
{
    public static bool CanRemove(string? viewer, string? owner, string? target) =>
        !string.IsNullOrWhiteSpace(viewer) && !string.IsNullOrWhiteSpace(owner) &&
        !string.IsNullOrWhiteSpace(target) &&
        string.Equals(viewer, owner, StringComparison.OrdinalIgnoreCase) &&
        !string.Equals(owner, target, StringComparison.OrdinalIgnoreCase);
}
