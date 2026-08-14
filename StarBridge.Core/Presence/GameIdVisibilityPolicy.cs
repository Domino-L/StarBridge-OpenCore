namespace StarBridge.Core.Presence;

[Flags]
public enum GameIdVisibilityLocations
{
    None = 0,
    Fleet = 1 << 0,
    PartyRoom = 1 << 1,
    Friends = 1 << 2,
    PersonalProfile = 1 << 3,
    All = Fleet | PartyRoom | Friends | PersonalProfile
}

public sealed record GameIdVisibilityPreference(
    GameIdVisibilityLocations Locations,
    bool CanConfigure);

public static class GameIdVisibilityPolicy
{
    public static GameIdVisibilityPreference Normalize(
        string? callsign,
        string? gameId,
        GameIdVisibilityLocations? storedLocations)
    {
        if (!HasDistinctCallsign(callsign, gameId))
        {
            return new GameIdVisibilityPreference(GameIdVisibilityLocations.All, CanConfigure: false);
        }

        var normalized = storedLocations is null
            ? GameIdVisibilityLocations.All
            : storedLocations.Value & GameIdVisibilityLocations.All;
        return new GameIdVisibilityPreference(normalized, CanConfigure: true);
    }

    public static bool ShouldShow(
        GameIdVisibilityPreference preference,
        GameIdVisibilityLocations location) =>
        location != GameIdVisibilityLocations.None &&
        (preference.Locations & location) == location;

    public static bool HasDistinctCallsign(string? callsign, string? gameId)
    {
        var normalizedCallsign = callsign?.Trim();
        if (string.IsNullOrWhiteSpace(normalizedCallsign))
        {
            return false;
        }

        var normalizedGameId = gameId?.Trim();
        return string.IsNullOrWhiteSpace(normalizedGameId) ||
               !normalizedCallsign.Equals(normalizedGameId, StringComparison.OrdinalIgnoreCase);
    }
}
