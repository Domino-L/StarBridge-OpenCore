namespace StarBridge.Core.Presence;

/// <summary>A privacy-filtered fact's reason is not a place or arrival evidence.</summary>
public static class SharedLocationVisibility
{
    public const string LowConfidence = "lowConfidence";

    public static string? NormalizeReason(string? reason, string? location,
        bool inGame, bool arrivalPending = false) =>
        inGame && !arrivalPending && reason == LowConfidence &&
        (string.IsNullOrWhiteSpace(location) || location.Trim().Equals("Unknown", StringComparison.OrdinalIgnoreCase))
            ? LowConfidence : null;
}
