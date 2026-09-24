namespace StarBridge.HostRuntime.Overlay;

internal static class OverlaySettingsSchema
{
    internal const int Version = 1;
    internal static readonly IReadOnlySet<string> Positions =
        new HashSet<string>(StringComparer.Ordinal)
        {
            "topLeft",
            "topRight",
            "bottomLeft",
            "bottomRight"
        };
}

internal static class OverlayRequestNames
{
    internal const string GetState = "overlay.getState";
    internal const string Update = "overlay.update";
    internal const string Preview = "overlay.preview";
    internal const string GetWorkspace = "overlay.getWorkspace";
    internal const string UpdateWorkspace = "overlay.updateWorkspace";
    internal const string RuntimeGetState = "overlay.runtime.getState";
    internal const string RuntimeOpen = "overlay.runtime.open";
    internal const string RuntimeClose = "overlay.runtime.close";
    internal const string RuntimeRetry = "overlay.runtime.retry";
}

public sealed record OverlaySettingsSnapshot(
    int SchemaVersion,
    long Revision,
    bool Enabled,
    double Opacity,
    string Position,
    bool ShowTeam)
{
    public static OverlaySettingsSnapshot Default { get; } = new(
        OverlaySettingsSchema.Version,
        Revision: 0,
        Enabled: true,
        Opacity: 0.85,
        Position: "topRight",
        ShowTeam: true);

    internal OverlaySettingsSnapshot Normalize() => this with
    {
        Opacity = Math.Round(Math.Clamp(Opacity, 0.35, 1.0), 2)
    };

    internal bool IsSupported() =>
        SchemaVersion == OverlaySettingsSchema.Version &&
        Revision >= 0 &&
        double.IsFinite(Opacity) &&
        Opacity is >= 0.35 and <= 1.0 &&
        OverlaySettingsSchema.Positions.Contains(Position);
}

internal sealed record OverlaySettingsReadResult(
    OverlaySettingsSnapshot Snapshot,
    string StorageState);

internal interface IOverlaySettingsStore
{
    OverlaySettingsReadResult Load();
    void Save(OverlaySettingsSnapshot snapshot);
}

internal sealed class OverlaySettingsException(
    string code,
    bool retryable = false,
    Exception? innerException = null)
    : Exception("Overlay settings operation failed.", innerException)
{
    internal string Code { get; } = code;
    internal bool Retryable { get; } = retryable;
}
