using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.HostRuntime.Lifecycle;

namespace StarBridge.HostRuntime.Onboarding;

internal sealed record LocalDeviceReviewObservation(string State, string? ReviewKey = null,
    LocalDeviceSetupChoices? Choices = null);

// Records review only. Domain choices must first be saved through their existing
// owners. Native preview/hotkey readiness and per-profile statistics stay separate.
internal sealed class LocalDeviceSetupReviewRuntime(LocalDeviceSetupReader reader, LocalDeviceReviewStore store)
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly AsyncWorkRetirement _work = new();
    private volatile bool _closed;
    private Issued? _issued;
    private sealed record Issued(string Key, LocalDeviceSetupChoices Choices, LocalDeviceReview Stored);
    private static readonly string[] Sections = ["application", "overlay", "notifications", "playReminder"];

    internal async Task<LocalDeviceReviewObservation> ReadAsync(CancellationToken token = default)
    {
        using var work = _work.Enter(token);
        if (work is null) return new("unavailable");
        await _gate.WaitAsync(work.Token).ConfigureAwait(false);
        try { return await ReadCore(work.Token).ConfigureAwait(false); }
        finally { _gate.Release(); }
    }
    private async Task<LocalDeviceReviewObservation> ReadCore(CancellationToken token)
    {
        _issued = null;
        var value = await reader.ReadAsync(token).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        if (_closed) return new("unavailable");
        if (value is not { State: "observed", Choices: not null }) return new(value.State);
        var choices = value.Choices;
        if (!Usable(choices)) return new("unavailable", Choices: choices);
        var stored = store.Read();
        if (!reader.IsScopeCurrent(choices) || _closed) return new("contextChanged");
        if (choices.Application.Value is not { StartupChoiceMade: true, CloseBehaviorChoiceMade: true })
            return new("choicesRequired", Choices: choices);
        _issued = new(Guid.NewGuid().ToString("N"), choices, stored);
        return new(stored.Fingerprint == Fingerprint(choices) ? "reviewed" : "reviewRequired", _issued.Key, choices);
    }
    internal async Task<LocalDeviceReviewObservation> ConfirmAsync(string reviewKey, IReadOnlyList<string> reviewedSections,
        CancellationToken token = default)
    {
        if (!LocalFirstUseValidation.Id(reviewKey) || reviewedSections is null || reviewedSections.Count != Sections.Length ||
            reviewedSections.Distinct(StringComparer.Ordinal).Count() != Sections.Length ||
            reviewedSections.Except(Sections, StringComparer.Ordinal).Any())
            throw new LocalFirstUseException("firstUse.invalid_request");
        using var work = _work.Enter(token);
        if (work is null) throw new LocalFirstUseException("firstUse.context_changed");
        if (!await _gate.WaitAsync(0, work.Token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            var issued = _issued;
            if (_closed || issued is null || issued.Key != reviewKey || !reader.IsScopeCurrent(issued.Choices))
                throw new LocalFirstUseException("firstUse.context_changed");
            var observed = await reader.ReadAsync(work.Token).ConfigureAwait(false);
            work.Token.ThrowIfCancellationRequested();
            if (_closed || observed is not { State: "observed", Choices: not null } || observed.Choices != issued.Choices)
            { _issued = null; throw new LocalFirstUseException("firstUse.context_changed"); }
            store.Save(issued.Stored, Guid.NewGuid().ToString("N"), Fingerprint(issued.Choices),
                () => !_closed && !work.Token.IsCancellationRequested && ReferenceEquals(_issued, issued) && reader.IsScopeCurrent(issued.Choices));
            // This reread verifies the actual settings again. A concurrent ordinary
            // write may leave a historical review, but it cannot return reviewed.
            return await ReadCore(work.Token).ConfigureAwait(false);
        }
        finally { _gate.Release(); }
    }
    private static bool Usable(LocalDeviceSetupChoices value) =>
        value.Application is { State: "saved" or "defaulted", Value: not null } &&
        value.Overlay is { State: "saved" or "defaulted", Value: not null } &&
        value.Notifications is { State: "observed", Value: not null } && value.PlayReminder is { State: "observed", Value: not null };
    private static string Fingerprint(LocalDeviceSetupChoices value)
    {
        var app = value.Application.Value!; var hud = value.Overlay.Value!;
        var notices = value.Notifications.Value!; var reminder = value.PlayReminder.Value!;
        // Presentation changes and owner revision increments are not a change to
        // the choices the user reviewed. Live confirmation tokens still bind the
        // whole actual observation; only the durable device review is semantic.
        return Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new {
            application = new { app.LaunchAtStartup, app.KeepRunningInBackground, app.StartMinimized,
                app.StartupChoiceMade, app.CloseBehaviorChoiceMade },
            overlay = new { hud.RenderMode, hud.HotkeyBinding, hud.HotkeyEnabled, hud.Opacity,
                hud.AutoOpenOnGameStart, hud.AutoOpenOnGameForeground, hud.AutoCloseOnGameBackground, hud.ShowEventNotifications },
            notifications = new { notices.InAppEnabled, notices.Position, notices.Preview, notices.WindowsEnabled,
                notices.OverlayEnabled, notices.DirectMessageWindowsEnabled },
            playReminder = new { reminder.Enabled, reminder.FirstReminderMinutes, reminder.RepeatReminderMinutes }
        })));
    }
    internal Task RetireAsync()
    { _closed = true; Volatile.Write(ref _issued, null); return _work.Close(); }

    // Used only by the Native completion writer's final guard. All device
    // readers are non-UI inspections; they observe existing stores and perform
    // no registration, native command, publication or domain write.
    internal bool CompletionChoicesCurrent(LocalDeviceSetupChoices expected, CancellationToken token)
    {
        if (_closed || !reader.IsScopeCurrent(expected)) return false;
        var actual = reader.ReadAsync(token).AsTask().GetAwaiter().GetResult();
        return !_closed && actual is { State: "observed", Choices: not null } && actual.Choices == expected &&
            store.Read().Fingerprint == Fingerprint(expected) && reader.IsScopeCurrent(expected);
    }
}
