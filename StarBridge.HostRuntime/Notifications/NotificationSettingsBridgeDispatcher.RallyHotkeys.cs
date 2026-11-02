namespace StarBridge.HostRuntime.Notifications;

using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

public sealed partial class NotificationSettingsBridgeDispatcher
{
    private sealed record RallyHotkeyOwner(string Id, long Generation, long Lease, Func<bool> Current);
    private static long _nextRallyHotkeyLease;
    private RallyHotkeyOwner? _rallyHotkeyOwner;
    private Task _rallyHotkeyWork = Task.CompletedTask;
    private ITimer? _rallyHotkeyExpiry;
    private bool _rallyHotkeySubscribed;
    internal Task RallyHotkeysIdle { get { lock (_gate) return _rallyHotkeyWork; } }

    // Caller owns _gate. Only queue work here: native dispatch can wait on its
    // control thread, and must never do so while the notification gate is held.
    private void QueueRallyHotkeys(RallyHotkeyOwner? owner)
    {
        if (hotkeys is null) return;
        var previous = _rallyHotkeyWork;
        _rallyHotkeyWork = Task.Run(async () =>
        {
            await previous.ConfigureAwait(false);
            lock (_gate) { } // Wait for the queuing decision to leave the gate.
            try
            {
                if (owner is null)
                {
                    await RemoveRallyHotkeysAsync().ConfigureAwait(false);
                    return;
                }
                if (!owner.Current()) return;
                await hotkeys.ConfigureHostHotkeyAsync(100, TemporaryHotkeyDefaults.Accept, owner.Lease).ConfigureAwait(false);
                if (!owner.Current()) { await RemoveRallyHotkeysAsync().ConfigureAwait(false); return; }
                await hotkeys.ConfigureHostHotkeyAsync(101, TemporaryHotkeyDefaults.Decline, owner.Lease).ConfigureAwait(false);
                if (!owner.Current()) await RemoveRallyHotkeysAsync().ConfigureAwait(false);
            }
            catch (Exception)
            {
                LogRallyHotkeyFailure();
                lock (_gate)
                    if (owner is not null && ReferenceEquals(_rallyHotkeyOwner, owner)) ClearRallyHotkeys();
                await RemoveRallyHotkeysAsync().ConfigureAwait(false);
            }
        });
    }

    private void LogRallyHotkeyFailure() =>
        _delivery.Record(NotificationDeliveryChannel.RallyHotkey, NotificationDeliveryStage.Failed);

    private async Task RemoveRallyHotkeysAsync()
    {
        foreach (var command in new[] { 100, 101 })
        {
            try { await hotkeys!.ConfigureHostHotkeyAsync(command, null, 0).ConfigureAwait(false); }
            catch (Exception) { LogRallyHotkeyFailure(); }
        }
    }

    private void RegisterRallyHotkeys(string id, long session, DateTimeOffset expiresAt, Func<bool> current)
    {
        if (hotkeys is null || hostEvent is null) return;
        if (id.Length != 32 || id.Any(c => c is not (>= '0' and <= '9' or >= 'a' and <= 'f')))
        { LogRallyHotkeyFailure(); return; }
        if (!_rallyHotkeySubscribed)
        {
            hotkeys.HostHotkeyTriggered += OnRallyHotkey;
            _rallyHotkeySubscribed = true;
        }
        // Process-wide and never reset with a dispatcher/session or rally ID.
        var lease = Interlocked.Increment(ref _nextRallyHotkeyLease);
        if (lease <= 0) throw new InvalidOperationException("Host hotkey leases exhausted.");
        var owner = new RallyHotkeyOwner(id, session, lease, current);
        _rallyHotkeyOwner = owner;
        var remaining = expiresAt - _rallyTime.GetUtcNow();
        _rallyHotkeyExpiry = _rallyTime.CreateTimer(_ =>
        {
            lock (_gate)
                if (ReferenceEquals(_rallyHotkeyOwner, owner)) InvalidateRally();
        }, null, remaining > TimeSpan.Zero ? remaining : TimeSpan.Zero, Timeout.InfiniteTimeSpan);
        QueueRallyHotkeys(owner);
    }

    private void ClearRallyHotkeys()
    {
        _rallyHotkeyExpiry?.Dispose();
        _rallyHotkeyExpiry = null;
        if (_rallyHotkeyOwner is null) return;
        _rallyHotkeyOwner = null;
        QueueRallyHotkeys(null);
    }

    private void OnRallyHotkey(int command, long lease)
    {
        if (command is not (100 or 101)) return;
        BridgeEnvelope? frame = null;
        lock (_gate)
        {
            if (_rallyHotkeyOwner is not { } owner || owner.Lease != lease)
            {
                _delivery.Record(NotificationDeliveryChannel.RallyHotkey, NotificationDeliveryStage.Stale);
                return;
            }
            if (!owner.Current()) { InvalidateRally(); return; }
            try
            {
                frame = hostEvent!(owner.Generation, BridgeHostEventNames.RallyHotkey,
                    new { schemaVersion = 1, rallyId = owner.Id, answer = command == 100 ? "coming" : "cannot" });
            }
            catch (Exception) { LogRallyHotkeyFailure(); }
            // Consume under the gate before another physical press can arrive.
            InvalidateRally();
        }
        if (frame is not null)
        {
            try { EventReady?.Invoke(frame); }
            catch (Exception) { LogRallyHotkeyFailure(); }
        }
    }

    private void UnsubscribeRallyHotkeys()
    {
        if (_rallyHotkeySubscribed) hotkeys!.HostHotkeyTriggered -= OnRallyHotkey;
    }
}
