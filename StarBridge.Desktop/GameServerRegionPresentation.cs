namespace StarBridge.Desktop;

using StarBridge.Core.Presence;

/// <summary>
/// Owns the user-facing game-server region vocabulary. Concrete shard IDs are
/// accepted only as a mapping input and are never returned to the interface.
/// </summary>
internal static class GameServerRegionPresentation
{
    internal static string Resolve(
        PlayerPresenceKind presence,
        string? region,
        string? shard,
        bool zh)
    {
        if (presence != PlayerPresenceKind.InGame)
        {
            return zh ? "未进入游戏" : "Not in game";
        }

        var kind = TryResolveKind(region) ?? TryResolveKind(shard);
        return kind switch
        {
            GameServerRegionKind.UnitedStates => zh ? "美服" : "US",
            GameServerRegionKind.Europe => zh ? "欧服" : "Europe",
            GameServerRegionKind.Australia => zh ? "澳服" : "Australia",
            GameServerRegionKind.Asia => zh ? "亚服" : "Asia",
            _ => "—"
        };
    }

    internal static string? ResolveRegion(string? value, bool zh = true)
    {
        var kind = TryResolveKind(value);
        return kind switch
        {
            GameServerRegionKind.UnitedStates => zh ? "美服" : "US",
            GameServerRegionKind.Europe => zh ? "欧服" : "Europe",
            GameServerRegionKind.Australia => zh ? "澳服" : "Australia",
            GameServerRegionKind.Asia => zh ? "亚服" : "Asia",
            _ => null
        };
    }

    private static GameServerRegionKind? TryResolveKind(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var normalized = value
            .Split('·', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .FirstOrDefault()?
            .Trim()
            .ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(normalized))
        {
            return null;
        }

        if (normalized.Contains("美服", StringComparison.Ordinal) ||
            normalized is "us" or "usa" or "na" or "use" or "usw" ||
            normalized.Contains("us east", StringComparison.Ordinal) ||
            normalized.Contains("us west", StringComparison.Ordinal) ||
            normalized.Contains("north america", StringComparison.Ordinal) ||
            normalized.Contains("pub_us", StringComparison.Ordinal) ||
            normalized.Contains("_use", StringComparison.Ordinal) ||
            normalized.Contains("_usw", StringComparison.Ordinal) ||
            normalized.EndsWith("_us", StringComparison.Ordinal))
        {
            return GameServerRegionKind.UnitedStates;
        }

        if (normalized.Contains("欧服", StringComparison.Ordinal) ||
            normalized is "eu" or "eur" ||
            normalized.Contains("europe", StringComparison.Ordinal) ||
            normalized.Contains("_eu", StringComparison.Ordinal))
        {
            return GameServerRegionKind.Europe;
        }

        if (normalized.Contains("澳服", StringComparison.Ordinal) ||
            normalized is "au" or "aus" or "oce" or "oceania" ||
            normalized.Contains("australia", StringComparison.Ordinal) ||
            normalized.Contains("_aus", StringComparison.Ordinal) ||
            normalized.Contains("_au", StringComparison.Ordinal) ||
            normalized.Contains("_oce", StringComparison.Ordinal))
        {
            return GameServerRegionKind.Australia;
        }

        if (normalized.Contains("亚服", StringComparison.Ordinal) ||
            normalized is "ap" or "asia" or "apse" or "sg" or "jp" or "hk" ||
            normalized.Contains("asia", StringComparison.Ordinal) ||
            normalized.Contains("singapore", StringComparison.Ordinal) ||
            normalized.Contains("hong kong", StringComparison.Ordinal) ||
            normalized.Contains("japan", StringComparison.Ordinal) ||
            normalized.Contains("_apse", StringComparison.Ordinal) ||
            normalized.Contains("_ap", StringComparison.Ordinal))
        {
            return GameServerRegionKind.Asia;
        }

        return null;
    }

    private enum GameServerRegionKind
    {
        UnitedStates,
        Europe,
        Australia,
        Asia
    }
}
