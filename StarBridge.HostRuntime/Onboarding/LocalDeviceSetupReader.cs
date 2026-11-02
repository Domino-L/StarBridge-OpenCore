using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Reminders;
using StarBridge.HostRuntime.Settings;

namespace StarBridge.HostRuntime.Onboarding;

// Observations, not reviewed choices, consent, native functional readiness or a
// first-use completion receipt. Missing files retain each existing owner's defaults.
internal sealed record LocalDeviceSetting<T>(string State, T? Value = null) where T : class;

internal sealed record LocalOverlaySetupChoices(long Revision, string RenderMode,
    string HotkeyBinding, bool HotkeyEnabled, double Opacity,
    bool AutoOpenOnGameStart, bool AutoOpenOnGameForeground, bool AutoCloseOnGameBackground,
    bool ShowEventNotifications);

internal sealed record LocalDeviceSetupChoices(long HostGeneration, long LocalRevision,
    string GameVersion, bool? ListeningEnabled,
    LocalDeviceSetting<ApplicationPreferencesSnapshot> Application,
    LocalDeviceSetting<LocalOverlaySetupChoices> Overlay,
    LocalDeviceSetting<LocalNotificationSettings> Notifications,
    LocalDeviceSetting<ContinuousPlaySettings> PlayReminder);

internal sealed record LocalDeviceSetupObservation(string State, LocalDeviceSetupChoices? Choices = null);

// Both routes borrow the same device owners. No timer, settings writer, account
// context, native command or publication callback is accepted by this boundary.
internal sealed class LocalDeviceSetupReader(LocalFirstUseStore local,
    Func<long> generation, ApplicationPreferencesBridgeDispatcher application,
    OverlayBridgeDispatcher overlay, NotificationSettingsBridgeDispatcher notifications,
    ContinuousPlayReminderRuntime reminder)
{
    private sealed record Scope(long Generation, long Revision, string SourceKey, string ProfileId,
        string Version, bool? ListeningEnabled);

    internal async ValueTask<LocalDeviceSetupObservation> ReadAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Scope? scope;
        try { scope = Capture(); }
        catch { return new("unavailable"); }
        if (scope is null) return new("needsIdentity");
        if (scope.Generation < 0) return new("contextChanged");

        // Repeated immutable projections reject overlapping ordinary settings
        // writes. This is not a filesystem/OS transaction or a grant to finish.
        var first = await Observe(scope, cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();
        if (!Current(scope)) return new("contextChanged");
        var second = await Observe(scope, cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();
        if (!Current(scope)) return new("contextChanged");
        return first == second ? new("observed", second) : new("settingsChanged");
    }

    private Scope? Capture()
    {
        var hostGeneration = generation();
        var value = local.Read();
        var source = value.Sources.SingleOrDefault(s => s.SourceKey == value.SelectedSourceKey);
        return source is { NeedsFreshGameEvidence: false, ConfirmedProfileId: not null } &&
               value.ActiveProfileId == source.ConfirmedProfileId
            ? new(hostGeneration, value.Revision, source.SourceKey, source.ConfirmedProfileId,
                source.Version, source.ListeningEnabled)
            : null;
    }

    private bool Current(Scope scope)
    {
        try { return Capture() == scope; }
        catch { return false; }
    }

    // Final identity/source/Host guard for explicit review commits. Shared setting
    // values are reread independently before and after saving a review record.
    internal bool IsScopeCurrent(LocalDeviceSetupChoices choices)
    {
        try
        {
            var scope = Capture();
            return scope is not null && scope.Generation >= 0 && scope.Generation == choices.HostGeneration &&
                scope.Revision == choices.LocalRevision && scope.Version == choices.GameVersion &&
                scope.ListeningEnabled == choices.ListeningEnabled;
        }
        catch { return false; }
    }

    private async ValueTask<LocalDeviceSetupChoices> Observe(Scope scope, CancellationToken token)
    {
        var app = await ReadArea(async () =>
        {
            var value = await application.InspectLocalSetupAsync(token);
            if (!value.Snapshot.IsSupported()) throw new InvalidDataException();
            return value.StorageState switch
            {
                "ready" => new LocalDeviceSetting<ApplicationPreferencesSnapshot>("saved", value.Snapshot),
                "defaulted" => new("defaulted", value.Snapshot),
                "recoveredDefaults" => new("needsRepair"),
                _ => new("unavailable")
            };
        }, token);
        var hud = await ReadArea(async () =>
        {
            var value = await overlay.InspectLocalSetupAsync(token);
            // Corrupt or pending migration must not silently become accepted defaults.
            if (value.StorageState is "corrupt" or "recoveredDefaults" or "migrationPending")
                return new LocalDeviceSetting<LocalOverlaySetupChoices>("needsRepair");
            if (value.StorageState is not ("ready" or "defaulted"))
                return new LocalDeviceSetting<LocalOverlaySetupChoices>("unavailable");
            var choices = new LocalOverlaySetupChoices(value.Revision, value.RenderMode,
                value.Hotkey.Binding, value.Hotkey.Enabled, value.Settings.Opacity,
                value.Settings.AutoOpenOverlayOnGameStart, value.Settings.AutoOpenOverlayOnGameForeground,
                value.Settings.AutoCloseOverlayOnGameBackground, value.Settings.ShowEventNotifications);
            return new LocalDeviceSetting<LocalOverlaySetupChoices>(
                value.StorageState == "ready" ? "saved" : "defaulted", choices);
        }, token);
        var notices = await ReadArea(() => ValueTask.FromResult(
            new LocalDeviceSetting<LocalNotificationSettings>("observed", notifications.InspectLocalSetup(token))), token);
        var play = await ReadArea(async () => new LocalDeviceSetting<ContinuousPlaySettings>(
            "observed", await reminder.ReadAsync(token)), token);
        return new(scope.Generation, scope.Revision, scope.Version, scope.ListeningEnabled, app, hud, notices, play);
    }

    private static async ValueTask<LocalDeviceSetting<T>> ReadArea<T>(
        Func<ValueTask<LocalDeviceSetting<T>>> read, CancellationToken token) where T : class
    {
        token.ThrowIfCancellationRequested();
        try
        {
            var value = await read();
            token.ThrowIfCancellationRequested();
            return value;
        }
        catch (OperationCanceledException) { throw; }
        catch { return new("unavailable"); }
    }
}
