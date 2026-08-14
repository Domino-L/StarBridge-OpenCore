namespace StarBridge.Desktop;

internal static class AcceptanceControlPolicy
{
    internal const string OptInEnvironmentVariable = "STARBRIDGE_SHOW_ACCEPTANCE_CONTROLS";

    internal static bool IsVisible => ShouldExpose(
        IsDebugBuild,
        Environment.GetEnvironmentVariable(OptInEnvironmentVariable));

    internal static bool ShouldExpose(bool isDebugBuild, string? optInValue) =>
        isDebugBuild && string.Equals(optInValue?.Trim(), "1", StringComparison.Ordinal);

    private static bool IsDebugBuild
    {
        get
        {
#if DEBUG
            return true;
#else
            return false;
#endif
        }
    }
}
