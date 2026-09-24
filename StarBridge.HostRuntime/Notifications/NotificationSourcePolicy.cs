namespace StarBridge.HostRuntime.Notifications;

internal enum NotificationSourceMode { Normal, ImportantOnly, DoNotDisturb }
internal enum NotificationEventKind {
    DirectMessage, RoomInvitation, JoinRequest, OrganizationManagement,
    OrganizationChat, PlayerOnline, PlayerOffline, GameStarted, GameStopped
}

// Delivery only. Never controls publishing, conversation storage or receipts.
internal static class NotificationSourcePolicy
{
    internal static bool Allows(NotificationSourceMode mode, NotificationEventKind kind) => mode switch {
        NotificationSourceMode.Normal => Enum.IsDefined(kind),
        NotificationSourceMode.ImportantOnly => kind is NotificationEventKind.DirectMessage or
            NotificationEventKind.RoomInvitation or NotificationEventKind.JoinRequest or NotificationEventKind.OrganizationManagement,
        _ => false
    };
}
