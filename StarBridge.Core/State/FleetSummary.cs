namespace StarBridge.Core.State;

public sealed record FleetSummary(
    int TotalPlayers,
    int OnlinePlayers,
    int ShipsKnown,
    int LocationsKnown);
