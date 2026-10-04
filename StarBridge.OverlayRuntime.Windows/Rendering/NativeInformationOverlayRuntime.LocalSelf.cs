namespace StarBridge.Desktop;

using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Presence;

public sealed partial class NativeInformationOverlayRuntime
{
    internal static OverlaySceneSnapshot ProjectLocalSelf(OverlaySceneSnapshot scene,
        GameLogSessionSnapshot? session, PlayerPresenceKind? presence, string language)
    {
        // Only decorate a uniquely authorized self row. Never insert a missing
        // member, infer self by display name, or mutate the shared source DTO.
        if (session is null || presence is null || scene.Players.Count(row => row.IsSelf) != 1) return scene;
        var running = presence == PlayerPresenceKind.InGame;
        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var location = running && session.Location.State is "confirmed" or "likely" or "possible"
            ? (zh ? session.Location.ChineseName : session.Location.EnglishName) ?? session.Location.EnglishName
            : null;
        var ship = running && session.Ship.State is "confirmed" or "likely" or "possible"
            ? (zh ? session.Ship.ChineseName : session.Ship.EnglishName) ?? session.Ship.EnglishName ?? session.Ship.Key
            : null;
        location = string.IsNullOrWhiteSpace(location) ? zh ? "等待位置确认" : "Location pending" : location;
        ship = string.IsNullOrWhiteSpace(ship) ? zh ? "等待舰船确认" : "Ship pending" : ship;
        if (running && session.Location.State is "likely" or "possible")
            location = (zh ? "可能在：" : "Possibly at: ") + location;
        var wire = PlayerPresence.ToWireValue(presence.Value);
        return scene with { Players = scene.Players.Select(row => !row.IsSelf ? row : row with
        {
            LiveStatus = wire, SharedLiveStatus = wire, Status = "Online", SharedOnlineStatus = "Online",
            Ship = ship, RawShip = ship, SharedShip = ship, ShipInfo = ship,
            Location = location, RawLocation = location, SharedLocation = location,
            ServerShard = running ? session.Server.Shard : null,
            ServerRegion = running ? session.Server.Region : null,
            SharedHasServerSession = !running || session.Server.State == "notConnected" ? false :
                session.Server.State == "connected" ? true : null,
            ShipConfidence = session.Ship.State, LocationConfidence = session.Location.State,
            LocationHiddenReason = null,
            RealtimeStateUnknown = false,
            // This clone is local display only; peers retain their authorized
            // shared-event mask. Local location changes need no upload roundtrip.
            SharedEventTypes = row.SharedEventTypes | (int)PlayerSharedEventTypes.Location,
            ArrivalPendingConfirmation = running && session.Location.ArrivalPendingConfirmation,
            ArrivalTargetCode = running ? session.Location.ArrivalTargetCode : null
        }).ToArray() };
    }

    private PlayerPresenceKind? ReadLocalDisplayPresence()
    {
        if (_localPresenceProvider is null)
            return StarCitizenProcessProbe.IsRunning() ? PlayerPresenceKind.InGame : PlayerPresenceKind.AppOnline;
        try
        {
            var state = _localPresenceProvider().State;
            if (state == "running") _confirmedLocalPresence = PlayerPresenceKind.InGame;
            else if (state == "notRunning") _confirmedLocalPresence = PlayerPresenceKind.AppOnline;
        }
        catch { /* Unknown observation is not evidence of a game exit. */ }
        return _confirmedLocalPresence;
    }
}
