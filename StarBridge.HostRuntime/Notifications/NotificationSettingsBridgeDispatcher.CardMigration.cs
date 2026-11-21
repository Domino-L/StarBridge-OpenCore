namespace StarBridge.HostRuntime.Notifications;

public sealed partial class NotificationSettingsBridgeDispatcher
{
    private NotificationCardPreferencesStore? _cardPreferences;
    private NotificationCardPreferencesStore CardPreferences => _cardPreferences ??= new(dataRoot);

    /// <summary>Whether social cards show through Windows do-not-disturb and quiet time (default on).</summary>
    private bool SocialShowsDuringQuiet => CardPreferences.Load().ShowDuringQuiet;

    /// <summary>The environment gate for social cards: the trade rule while "show during quiet" is on.</summary>
    private string SocialSuppressionReason() => SocialCardEnvironment.SuppressionReason(
        SocialShowsDuringQuiet, DesktopSuppressionReason, TradeSuppressionReason);

    private bool CanNotifySocial() => SocialSuppressionReason().Length == 0;

    // ---- the summary after quiet time (only when "show during quiet" is off) ----
    private readonly QuietCardSummary _quietSummary = new();
    private Timer? _quietTimer;
    private static readonly TimeSpan QuietCheck = TimeSpan.FromMinutes(1);

    /// <summary>
    /// The social gate with the summary: a card held back by Windows do-not-disturb or quiet time is
    /// counted (when the user turned "show during quiet" off and kept the summary on). Caller owns _gate.
    /// </summary>
    private string SocialSuppressionReason(string kind)
    {
        var reason = SocialSuppressionReason();
        if (reason.Length == 0 || !SocialCardEnvironment.IsQuietReason(reason)) return reason;
        var preferences = CardPreferences.Load();
        if (preferences.ShowDuringQuiet || !preferences.QuietSummary) return reason;
        _quietSummary.Held(kind);
        _quietTimer ??= new Timer(_ => CheckQuietEndedSafely(), null, QuietCheck, QuietCheck);
        return reason;
    }

    private bool CanNotifySocial(string kind) => SocialSuppressionReason(kind).Length == 0;

    /// <summary>
    /// Timer entry: an exception escaping a timer callback would end the Host. Any failed read
    /// (locked preferences file and the like) keeps the summary for the next check.
    /// </summary>
    private void CheckQuietEndedSafely()
    {
        try { CheckQuietEnded(); }
        catch (Exception) { /* The summary is still held; the next check tries again. */ }
    }

    /// <summary>Once quiet time is over, one summary card; the timer stops with nothing left to report.</summary>
    private void CheckQuietEnded()
    {
        DesktopNotification? notice = null;
        lock (_gate)
        {
            if (_disposed || _quietSummary.Total == 0) { StopQuietTimer(); return; }
            if (SocialSuppressionReason().Length != 0) return;
            LocalNotificationSettings settings;
            try { settings = Read(); }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or InvalidDataException or System.Text.Json.JsonException) { return; }
            var epoch = Interlocked.Read(ref _reminderEpoch);
            var locale = new StarBridge.HostRuntime.Settings.ApplicationPreferencesStore(dataRoot).Load().Snapshot.LocaleOverride
                ?? System.Globalization.CultureInfo.CurrentUICulture.Name;
            var zh = locale.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
            var text = _quietSummary.Take(zh);
            StopQuietTimer();
            if (text is null || !settings.WindowsEnabled || desktop == null) return;
            try
            {
                notice = CreateDesktop(Guid.NewGuid(), false, 0, 0, settings, () => !_disposed && epoch == Interlocked.Read(ref _reminderEpoch)) with
                {
                    Reminder = new(zh ? "免打扰期间" : "While quiet", zh ? "免打扰期间的提醒" : "Reminders while quiet", text),
                    BackgroundOnly = false,
                };
            }
            catch (Exception exception) when (exception is IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException or
                StarBridge.HostRuntime.Settings.ApplicationPreferencesException) { return; }
        }
        _ = desktop!.TryPresentDetailedAsync(notice, CancellationToken.None).AsTask();
    }

    private void StopQuietTimer()
    {
        _quietTimer?.Dispose();
        _quietTimer = null;
    }

    /// <summary>Account change or shutdown: nothing held for the old session is reported. Caller owns _gate.</summary>
    private void ResetQuietSummary()
    {
        _quietSummary.Reset();
        StopQuietTimer();
    }

    /// <summary>
    /// Device-local continuous play: its own switch and environment gate, never a quiet summary.
    /// </summary>
    internal async Task<bool> TryPresentReminderCardAsync(ContinuousPlayNotificationContent content, Func<bool> current, CancellationToken token)
    {
        DesktopNotification? notice = null;
        lock (_gate)
        {
            if (_disposed || desktop == null || !current()) return false;
            LocalNotificationSettings settings;
            try { settings = Read(); }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or InvalidDataException or System.Text.Json.JsonException) { return false; }
            if (!ContinuousPlayEnabled() || ContinuousPlayCardEnvironment.SuppressionReason(ContinuousPlaySuppressionReason()).Length != 0) return false;
            try { notice = CreateDesktop(Guid.NewGuid(), false, 0, 0, settings, current) with { ContinuousPlay = content, BackgroundOnly = false,
                RevalidateBeforePresent = _ => Task.FromResult(current() && ContinuousPlayEnabled()) }; }
            catch (Exception exception) when (exception is IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException or
                StarBridge.HostRuntime.Settings.ApplicationPreferencesException) { return false; }
        }
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(1));
        try { return (await desktop!.TryPresentDetailedAsync(notice, deadline.Token).ConfigureAwait(false)).Submitted; }
        catch (OperationCanceledException) { return false; }
    }

    // The StarBridge window in front or an unknown game state must not hold the reminder back (review CX-CPLAY-CARD-073-R1).
    private string ContinuousPlaySuppressionReason()
    {
        if (continuousPlaySuppressionReason is null) return TradeSuppressionReason();
        try { return continuousPlaySuppressionReason(); } catch { return "unavailable"; }
    }

    private bool ContinuousPlayEnabled()
    {
        try { return new StarBridge.HostRuntime.Reminders.ContinuousPlayStore(dataRoot).ReadSettings().Enabled; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidDataException or System.Text.Json.JsonException)
        { return false; }
    }

    internal int QuietSummaryCount { get { lock (_gate) return _quietSummary.Total; } }

    /// <summary>
    /// 0.7.3, once per device: the Windows card master switch and the direct-message card are turned on
    /// (user: "windows提醒默认是需要都开的"). The old
    /// settings file cannot tell "turned off" from "never set", so every device gets it once; a user
    /// who turns it off afterwards keeps it off. An unreadable settings file is left alone and the
    /// migration is not marked, so it can run after the file is repaired.
    /// </summary>
    /// <returns>True when the switch was turned on now.</returns>
    internal bool MigrateWindowsCardsOn073(NotificationCardPreferencesStore cards)
    {
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            var preferences = cards.Load();
            if (preferences.WindowsMigrated073) return false;
            LocalNotificationSettings settings;
            try { settings = Read(); }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or InvalidDataException or System.Text.Json.JsonException)
            {
                return false;
            }
            var changed = false;
            if (!settings.WindowsEnabled || !settings.DirectMessageWindowsEnabled)
            {
                Write(settings with { Revision = checked(settings.Revision + 1), WindowsEnabled = true, DirectMessageWindowsEnabled = true });
                InvalidateReminder();
                changed = true;
            }
            cards.Save(preferences with { WindowsMigrated073 = true });
            return changed;
        }
    }
}
