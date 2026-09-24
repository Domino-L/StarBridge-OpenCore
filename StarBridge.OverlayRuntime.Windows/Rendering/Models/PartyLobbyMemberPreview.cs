namespace StarBridge.Desktop;

public sealed record PartyLobbyMemberPreview(
    string Callsign,
    string GameId,
    string? AvatarImageData = null,
    bool IsHost = false,
    string? AccountId = null)
{
    public string PresenceText { get; init; } = "在线";

    public string PresenceBrush { get; init; } = "#42CF7C";

    public string LocationText { get; init; } = "等待位置同步";

    public string ShipText { get; init; } = "等待舰船同步";

    public string ShardText { get; init; } = "等待服务器同步";
}

