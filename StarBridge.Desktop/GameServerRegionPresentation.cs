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

        // A concrete shard identifier is direct runtime evidence. Prefer it over
        // a reported region value because older clients/replicas may still carry
        // a stale broad AP-family classification (for example ASIA + APSE2).
        var code = ResolvePreferredCode(shard, region);
        return FormatCode(code, zh) ?? "—";
    }

    internal static string? ResolvePreferredCode(string? shard, string? reportedRegion) =>
        ResolveCode(shard) ?? ResolveCode(reportedRegion);

    internal static string? ResolvePreferredRegion(
        string? shard,
        string? reportedRegion,
        bool zh = true) =>
        FormatCode(ResolvePreferredCode(shard, reportedRegion), zh);

    internal static string? ResolveCode(string? value)
    {
        return TryResolveKind(value) switch
        {
            GameServerRegionKind.UnitedStates => "US",
            GameServerRegionKind.Europe => "EU",
            GameServerRegionKind.Australia => "AU",
            GameServerRegionKind.Asia => "ASIA",
            _ => null
        };
    }

    internal static string? ResolveRegion(string? value, bool zh = true)
    {
        return FormatCode(ResolveCode(value), zh);
    }

    private static string? FormatCode(string? code, bool zh)
    {
        return code switch
        {
            "US" => zh ? "美服" : "US",
            "EU" => zh ? "欧服" : "Europe",
            "AU" => zh ? "澳服" : "Australia",
            "ASIA" => zh ? "亚服" : "Asia",
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
            normalized.StartsWith("us-", StringComparison.Ordinal) ||
            normalized.EndsWith("_us", StringComparison.Ordinal))
        {
            return GameServerRegionKind.UnitedStates;
        }

        if (normalized.Contains("欧服", StringComparison.Ordinal) ||
            normalized is "eu" or "eur" ||
            normalized.Contains("europe", StringComparison.Ordinal) ||
            normalized.StartsWith("eu-", StringComparison.Ordinal) ||
            normalized.Contains("_eu", StringComparison.Ordinal))
        {
            return GameServerRegionKind.Europe;
        }

        if (normalized.Contains("澳服", StringComparison.Ordinal) ||
            normalized is "au" or "aus" or "aps" or "oce" or "oceania" ||
            normalized.Contains("australia", StringComparison.Ordinal) ||
            normalized.Contains("sydney", StringComparison.Ordinal) ||
            normalized.Contains("melbourne", StringComparison.Ordinal) ||
            ContainsRegionToken(normalized, "aps") ||
            ContainsRegionTokenStartingWith(normalized, "apse2") ||
            ContainsRegionTokenStartingWith(normalized, "apse4") ||
            ContainsRegionTokenStartingWith(normalized, "apse6") ||
            ContainsCloudRegion(normalized, "ap-southeast-2") ||
            ContainsCloudRegion(normalized, "ap-southeast-4") ||
            ContainsCloudRegion(normalized, "ap-southeast-6") ||
            normalized.StartsWith("au-", StringComparison.Ordinal) ||
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
            ContainsRegionTokenStartingWith(normalized, "ape1") ||
            ContainsRegionTokenStartingWith(normalized, "apse1") ||
            ContainsRegionTokenStartingWith(normalized, "apse3") ||
            ContainsRegionTokenStartingWith(normalized, "apse5") ||
            ContainsRegionTokenStartingWith(normalized, "apse7") ||
            ContainsRegionTokenStartingWith(normalized, "apse8") ||
            ContainsRegionTokenStartingWith(normalized, "apne1") ||
            ContainsRegionTokenStartingWith(normalized, "apne2") ||
            ContainsRegionTokenStartingWith(normalized, "apne3") ||
            ContainsRegionTokenStartingWith(normalized, "aps1") ||
            ContainsRegionTokenStartingWith(normalized, "aps2") ||
            ContainsCloudRegion(normalized, "ap-southeast-1") ||
            ContainsCloudRegion(normalized, "ap-northeast-1") ||
            ContainsCloudRegion(normalized, "ap-northeast-2") ||
            ContainsCloudRegion(normalized, "ap-northeast-3") ||
            ContainsCloudRegion(normalized, "ap-east-1") ||
            normalized.StartsWith("asia-", StringComparison.Ordinal) ||
            normalized.Contains("_apse", StringComparison.Ordinal) ||
            normalized.Contains("_ap", StringComparison.Ordinal))
        {
            return GameServerRegionKind.Asia;
        }

        return null;
    }

    private static bool ContainsCloudRegion(string value, string region)
    {
        return value.Contains(region, StringComparison.Ordinal) ||
               value.Contains(region.Replace('-', '_'), StringComparison.Ordinal);
    }

    private static bool ContainsRegionToken(string value, string token)
    {
        return value
            .Split(['_', '-', '.', ' ', '/', '\\', ':'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Any(part => part.Equals(token, StringComparison.OrdinalIgnoreCase));
    }

    private static bool ContainsRegionTokenStartingWith(string value, string tokenPrefix)
    {
        return value
            .Split(['_', '-', '.', ' ', '/', '\\', ':'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Any(part => part.StartsWith(tokenPrefix, StringComparison.OrdinalIgnoreCase));
    }

    private enum GameServerRegionKind
    {
        UnitedStates,
        Europe,
        Australia,
        Asia
    }
}
