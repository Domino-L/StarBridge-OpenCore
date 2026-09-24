namespace StarBridge.HostRuntime.Support;

internal static class ApplicationSupportSchema
{
    internal const int Version = 1;
}

internal static class ApplicationSupportRequestNames
{
    internal const string Inspect = "diagnostics.getSafeSummary";
    internal const string OpenDataDirectory = "diagnostics.openDataDirectory";
    internal const string GetDataLocation = "diagnostics.getDataLocation";
    internal const string ClearImageCache = "diagnostics.clearImageCache";
    internal const string OpenInstalledApps = "diagnostics.openInstalledApps";
}

internal static class ApplicationSupportStates
{
    internal const string Healthy = "healthy";
    internal const string ActionRequired = "actionRequired";
    internal const string Unavailable = "unavailable";
}

internal static class ApplicationSupportStableErrors
{
    internal const string InspectionFailed = "diagnostics.inspection_failed";
    internal const string OpenFailed = "diagnostics.open_failed";
}

internal sealed record ApplicationSupportCheck(
    string State,
    string Detail);

internal sealed record ApplicationStartupCheck(
    string State,
    string Detail,
    bool Registered,
    bool? TargetExists,
    bool? TargetsCurrentExecutable);

internal sealed record ApplicationInstallationCheck(
    string State,
    string Detail,
    string Mode,
    int CurrentInstallations,
    int OtherInstallations,
    int OrphanedRegistrations,
    int ScanWarnings);

internal sealed record ApplicationSupportSnapshot(
    ApplicationSupportCheck DataDirectory,
    ApplicationSupportCheck GameLog,
    ApplicationStartupCheck Startup,
    ApplicationInstallationCheck Installation,
    ApplicationSupportCheck? Connection = null)
{
    internal bool HasIssues =>
        Connection?.State == ApplicationSupportStates.ActionRequired ||
        DataDirectory.State == ApplicationSupportStates.ActionRequired ||
        GameLog.State == ApplicationSupportStates.ActionRequired ||
        Startup.State == ApplicationSupportStates.ActionRequired ||
        Installation.State == ApplicationSupportStates.ActionRequired;

    internal bool HasUnavailableChecks =>
        Connection?.State == ApplicationSupportStates.Unavailable ||
        DataDirectory.State == ApplicationSupportStates.Unavailable ||
        GameLog.State == ApplicationSupportStates.Unavailable ||
        Startup.State == ApplicationSupportStates.Unavailable ||
        Installation.State == ApplicationSupportStates.Unavailable;
}

internal interface IApplicationSupportInspector
{
    ApplicationSupportSnapshot Inspect();
}

internal interface IApplicationSupportActions
{
    void OpenDataDirectory();
    int ClearImageCache() => throw new InvalidOperationException();
    void OpenInstalledApps() => throw new InvalidOperationException();
}

// Local settings detail only; never included in the shareable safe summary.
internal sealed record ApplicationDataLocation(string Path, bool Exists);

internal interface IApplicationDataLocationReader
{
    ApplicationDataLocation GetDataLocation();
}
