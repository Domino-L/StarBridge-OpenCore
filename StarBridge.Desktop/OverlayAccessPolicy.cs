namespace StarBridge.Desktop;

public sealed record OverlayAccessProjection(
    OverlaySceneSnapshot Scene,
    OverlayDisplaySettings Settings,
    OverlayCommandState CommandState,
    IReadOnlyList<OverlayChatMessage> ChatMessages,
    bool IsLocalOnly);

public static class OverlayAccessPolicy
{
    public static OverlayAccessProjection Apply(
        bool isAuthenticated,
        OverlaySceneSnapshot scene,
        OverlayDisplaySettings settings,
        OverlayCommandState commandState,
        IEnumerable<OverlayChatMessage>? chatMessages)
    {
        if (!isAuthenticated)
        {
            var localPlayers = scene.Players
                .Where(player => player.IsSelf)
                .Select(player => player with
                {
                    Role = "成员",
                    RoleBrush = null,
                    ShowMemberActions = false
                })
                .ToArray();
            return new OverlayAccessProjection(
                scene with
                {
                    Players = localPlayers,
                    HasContent = false,
                    Context = OverlaySceneContext.Local(scene.Context.Preference)
                },
                settings with
                {
                    ShowNotice = false,
                    ShowSquads = false,
                    ShowMembers = false,
                    ShowChat = false
                },
                new OverlayCommandState(null, null, null, null, null, null),
                [],
                IsLocalOnly: true);
        }

        return new OverlayAccessProjection(
            scene,
            settings,
            commandState,
            chatMessages?.ToArray() ?? [],
            IsLocalOnly: false);
    }
}
