using StarBridge.Core.Presence;

namespace StarBridge.Desktop;

internal static class LocationArrivalPresentation
{
    internal const string PendingLocation = "地点待确认";
    internal const string PendingBadge = "到达待确认";
    internal const string CompactPendingBadge = "待确认";

    internal static string ResolveLocation(
        PlayerPresenceKind presence,
        bool? hasServerSession,
        string? location,
        bool arrivalPendingConfirmation)
    {
        var resolved = PlayerSessionStatePresentation.ResolveLocation(
            presence,
            hasServerSession,
            location);
        if (!arrivalPendingConfirmation ||
            presence != PlayerPresenceKind.InGame ||
            hasServerSession == false ||
            PlayerSessionStatePresentation.HasRecognizedValue(location))
        {
            return resolved;
        }

        return PendingLocation;
    }

    internal static string ResolveCompactLocation(
        PlayerPresenceKind presence,
        bool? hasServerSession,
        string? location,
        bool arrivalPendingConfirmation,
        string language = "zh")
    {
        var resolved = ResolveLocation(
            presence,
            hasServerSession,
            location,
            arrivalPendingConfirmation);
        if (!ShouldShowPending(arrivalPendingConfirmation, presence, hasServerSession) ||
            resolved.Equals(PendingLocation, StringComparison.OrdinalIgnoreCase))
        {
            return resolved;
        }

        return language.Equals("zh", StringComparison.OrdinalIgnoreCase)
            ? $"{resolved} · {CompactPendingBadge}"
            : $"{resolved} · pending";
    }

    internal static string ResolveBadge(
        bool arrivalPendingConfirmation,
        PlayerPresenceKind presence,
        bool? hasServerSession,
        string language = "zh")
    {
        if (!ShouldShowPending(arrivalPendingConfirmation, presence, hasServerSession))
        {
            return string.Empty;
        }

        return language.Equals("zh", StringComparison.OrdinalIgnoreCase)
            ? PendingBadge
            : "Arrival pending";
    }

    internal static string ResolveDetail(
        bool arrivalPendingConfirmation,
        PlayerPresenceKind presence,
        bool? hasServerSession,
        string? confirmedLocation,
        string? arrivalTarget,
        string language = "zh")
    {
        if (!ShouldShowPending(arrivalPendingConfirmation, presence, hasServerSession))
        {
            return ResolveLocation(presence, hasServerSession, confirmedLocation, false);
        }

        var zh = language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var target = PlayerSessionStatePresentation.HasRecognizedValue(arrivalTarget)
            ? LocationNameLocalizer.DisplayName(arrivalTarget, zh ? "zh" : "en")
            : null;
        var confirmedCode = FleetLocationProjection.NormalizeKey(confirmedLocation);
        var confirmed = PlayerSessionStatePresentation.HasRecognizedValue(confirmedCode)
            ? LocationNameLocalizer.DisplayName(confirmedCode, zh ? "zh" : "en")
            : null;

        if (zh)
        {
            var arrival = string.IsNullOrWhiteSpace(target)
                ? "量子航行已结束"
                : $"已抵达 {target}";
            var history = string.IsNullOrWhiteSpace(confirmed)
                ? "尚无已确认地点。"
                : $"上次确认地点：{confirmed}。";
            return $"{arrival}，正在等待游戏日志确认当前位置。{history}";
        }

        var englishArrival = string.IsNullOrWhiteSpace(target)
            ? "Quantum travel has ended"
            : $"Arrived at {target}";
        var englishHistory = string.IsNullOrWhiteSpace(confirmed)
            ? "No confirmed location is available yet."
            : $"Last confirmed location: {confirmed}.";
        return $"{englishArrival}; waiting for the game log to confirm the current location. {englishHistory}";
    }

    private static bool ShouldShowPending(
        bool arrivalPendingConfirmation,
        PlayerPresenceKind presence,
        bool? hasServerSession) =>
        arrivalPendingConfirmation &&
        presence == PlayerPresenceKind.InGame &&
        hasServerSession != false;
}
