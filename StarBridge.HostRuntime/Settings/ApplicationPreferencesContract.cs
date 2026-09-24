namespace StarBridge.HostRuntime.Settings;

internal static class ApplicationPreferencesSchema
{
    internal const int Version = 1;
    internal const string DefaultAppearanceMode = "dark";
    internal const string DefaultMotionPreference = "followSystem";

    internal static readonly IReadOnlySet<string> SupportedLocales =
        new HashSet<string>(StringComparer.Ordinal)
        {
            "zh-CN",
            "zh-TW",
            "en-US"
        };

    internal static readonly IReadOnlySet<string> SupportedAppearanceModes =
        new HashSet<string>(StringComparer.Ordinal)
        {
            "dark",
            "light"
        };

    internal static readonly IReadOnlySet<string> SupportedMotionPreferences =
        new HashSet<string>(StringComparer.Ordinal)
        {
            "followSystem",
            "reduce"
        };
}

internal static class ApplicationPreferencesRequestNames
{
    internal const string Get = "applicationPreferences.get";
    internal const string Update = "applicationPreferences.update";
}

internal static class ApplicationPreferencesStorageStates
{
    internal const string Ready = "ready";
    internal const string Defaulted = "defaulted";
    internal const string RecoveredDefaults = "recoveredDefaults";
}

internal static class ApplicationPreferencesStableErrors
{
    internal const string InvalidValue = "applicationPreferences.invalid_value";
    internal const string ReadFailed = "applicationPreferences.read_failed";
    internal const string SaveFailed = "applicationPreferences.save_failed";
    internal const string RevisionConflict = "applicationPreferences.revision_conflict";
    internal const string StartupRegistrationFailed =
        "applicationPreferences.startup_registration_failed";
}

internal sealed record ApplicationPreferencesSnapshot(
    int SchemaVersion,
    long Revision,
    string? LocaleOverride,
    string AppearanceMode,
    string MotionPreference,
    bool LaunchAtStartup,
    bool KeepRunningInBackground,
    bool StartMinimized,
    bool StartupChoiceMade,
    bool CloseBehaviorChoiceMade,
    bool BackgroundHintShown)
{
    internal static ApplicationPreferencesSnapshot Default { get; } = new(
        ApplicationPreferencesSchema.Version,
        Revision: 0,
        LocaleOverride: null,
        ApplicationPreferencesSchema.DefaultAppearanceMode,
        ApplicationPreferencesSchema.DefaultMotionPreference,
        LaunchAtStartup: false,
        KeepRunningInBackground: true,
        StartMinimized: false,
        StartupChoiceMade: false,
        CloseBehaviorChoiceMade: false,
        BackgroundHintShown: false);

    // Remember the selected destination even while automatic startup is off.
    internal ApplicationPreferencesSnapshot Normalize() => this;

    internal bool IsSupported() =>
        SchemaVersion == ApplicationPreferencesSchema.Version &&
        Revision >= 0 &&
        (LocaleOverride is null ||
         ApplicationPreferencesSchema.SupportedLocales.Contains(LocaleOverride)) &&
        ApplicationPreferencesSchema.SupportedAppearanceModes.Contains(AppearanceMode) &&
        ApplicationPreferencesSchema.SupportedMotionPreferences.Contains(MotionPreference);
}

internal sealed record ApplicationPreferencesReadResult(
    ApplicationPreferencesSnapshot Snapshot,
    string StorageState)
{
    internal static ApplicationPreferencesReadResult Defaulted { get; } = new(
        ApplicationPreferencesSnapshot.Default,
        ApplicationPreferencesStorageStates.Defaulted);

    internal static ApplicationPreferencesReadResult RecoveredDefaults { get; } = new(
        ApplicationPreferencesSnapshot.Default,
        ApplicationPreferencesStorageStates.RecoveredDefaults);
}

internal interface IApplicationPreferencesStore
{
    ApplicationPreferencesReadResult Load();

    void Save(ApplicationPreferencesSnapshot snapshot);
}

internal sealed class ApplicationPreferencesException : Exception
{
    internal ApplicationPreferencesException(
        string code,
        string message,
        bool retryable = false,
        Exception? innerException = null)
        : base(message, innerException)
    {
        Code = code;
        Retryable = retryable;
    }

    internal string Code { get; }
    internal bool Retryable { get; }
}
