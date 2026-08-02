namespace StarBridge.Desktop;

internal sealed record InGameRoomSnapshot(
    bool IsAvailable,
    PartyLobbyRoomCard[] Rooms,
    PartyLobbyRoomCard? CurrentRoom,
    string StatusText,
    InGameRoomChatSnapshot Chat,
    InGameRoomInvitationSnapshot Invitations);

internal sealed record InGameRoomChatSnapshot(
    object[] Messages,
    bool CanSend,
    string StatusText);

internal sealed record InGameRoomInvitationSnapshot(
    bool CanInvite,
    PartyRoomInvitationActionRow[] Friends,
    string StatusText);

internal sealed class InGameRoomJoinRequestedEventArgs(
    PartyLobbyRoomCard? room,
    string roomCode,
    string password) : EventArgs
{
    internal PartyLobbyRoomCard? Room { get; } = room;
    internal string RoomCode { get; } = roomCode;
    internal string Password { get; } = password;
}

internal sealed class InGameRoomCreateRequestedEventArgs(
    PartyRoomCreateDraft draft) : EventArgs
{
    internal PartyRoomCreateDraft Draft { get; } = draft;
}

internal sealed class InGameRoomMessageRequestedEventArgs(string text) : EventArgs
{
    internal string Text { get; } = text;
}

internal sealed class InGameRoomAttachmentRequestedEventArgs(
    System.Windows.Controls.Button anchor) : EventArgs
{
    internal System.Windows.Controls.Button Anchor { get; } = anchor;
}

internal sealed class InGameRoomInvitationActionRequestedEventArgs(
    PartyRoomInvitationActionRow invitation,
    string action) : EventArgs
{
    internal PartyRoomInvitationActionRow Invitation { get; } = invitation;
    internal string Action { get; } = action;
}
