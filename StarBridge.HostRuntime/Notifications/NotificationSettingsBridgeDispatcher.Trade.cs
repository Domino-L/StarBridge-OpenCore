using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

public sealed partial class NotificationSettingsBridgeDispatcher
{
    private readonly TradeNotificationObserver _trade = new(time);
    private long _tradeEpoch;

    // Caller already owns _gate (same lifecycle as other automatic notification sources).
    private void ResetTrade() { _trade.Reset(); Interlocked.Increment(ref _tradeEpoch); }
    internal void InvalidateTrade() { lock (_gate) { ResetTrade(); desktop?.ClearMessages(); } }

    // Trade alerts may use the compact in-game card; the native host supplies that wider gate.
    private string TradeSuppressionReason()
    {
        if (tradeSuppressionReason is null) return DesktopSuppressionReason();
        try { return tradeSuppressionReason(); } catch { return "unavailable"; }
    }

    private void TryPlayTrade(bool chat, Func<bool> current)
    {
        try { if (current()) playTrade?.Invoke(chat, current); }
        catch (Exception) { /* A failed cue never blocks the card. */ }
    }

    internal async Task PresentTradeAsync(BridgeAccountContext owner, long sessionGeneration,
        TradeNotificationEvent item, Func<bool> sourceCurrent, CancellationToken token = default)
    {
        try {
            DesktopNotification notice;
            Func<bool> fresh;
            LocalNotificationSettings settings;
            long epoch;
            lock (_gate) {
                if (_disposed || token.IsCancellationRequested || sessionGeneration != generation() || !sourceCurrent()) return;
                var observed = _trade.Observe(owner, sessionGeneration, item);
                if (observed is null) return;
                fresh = observed;
                _delivery.Record(NotificationDeliveryChannel.Desktop, NotificationDeliveryStage.FreshEvent);
                // Consume before preferences, focus and native delivery. Suppressed messages never replay.
                settings = Read();
                epoch = Interlocked.Read(ref _tradeEpoch);
            }
            bool Current() => !_disposed && epoch == Interlocked.Read(ref _tradeEpoch) &&
                sessionGeneration == generation() && sourceCurrent() && fresh();
            // Sound follows the trade switch, not the Windows card master, like other arrival cues.
            // Outside _gate: audio holds its own gate while it rechecks currency, and rally's check takes _gate.
            if (settings.TradeWindowsEnabled) TryPlayTrade(item.Chat, Current);
            lock (_gate) {
                if (!settings.WindowsEnabled || !settings.TradeWindowsEnabled || desktop is null) {
                    RecordDesktop(NotificationDeliveryStage.ChannelDisabled); return;
                }
                var reason = TradeSuppressionReason();
                if (reason.Length != 0) {
                    _delivery.Record(NotificationDeliveryChannel.Desktop, NotificationDeliveryStage.EnvironmentSuppressed, result: reason); return;
                }
                var activated = false;
                var id = Guid.NewGuid();
                notice = CreateDesktop(id, false, 0, 0, settings, Current);
                var english = !notice.Locale.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
                var hidden = settings.Preview == "hiddenDetails";
                var title = item.Chat ? english ? "New trade message" : "新的交易私信" : item.LocalTitle(english);
                var body = item.Chat ? settings.Preview == "fullContent" && item.Text.Length > 0 ? item.Text : english ? "Sent you a trade message." : "发来一条交易私信。"
                    : item.Item;
                if (item.Chat && !hidden && item.Peer.Length > 0) title += " · " + item.Peer;
                notice = notice with {
                    Trade = hidden ? new("", "") : new(title, body, item.Kind, item.Item, item.Quantity, item.Amount,
                        item.Chat ? item.Peer : "", item.Chat && settings.Preview == "fullContent" ? item.Text : ""),
                    Activated = activationEvent is null ? null : () => {
                        lock (_gate) {
                            if (!Current()) return;
                            // Each card may enter the shared activation flow only once.
                            if (activated) return;
                            activated = true;
                            Activate(id, Current, item.Chat ? "tradeChat" : item.Reference is { Length: > 0 } ? "trade" : "myTrades",
                                reference: item.Reference);
                        }
                    },
                    Diagnostic = outcome => _delivery.Record(NotificationDeliveryChannel.Desktop,
                        NotificationDeliveryStage.NativeLifecycle, transport: desktop.DiagnosticTransport, result: outcome),
                };
            }
            if (!notice.IsCurrent() || token.IsCancellationRequested) return;
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(1));
            var result = await desktop!.TryPresentDetailedAsync(notice, deadline.Token).ConfigureAwait(false);
            _delivery.Record(NotificationDeliveryChannel.Desktop, result.Submitted ? NotificationDeliveryStage.NativeAccepted
                : NotificationDeliveryStage.NativeRejected, transport: desktop.DiagnosticTransport, result: result.DiagnosticOutcome ?? result.Reason);
        }
        catch (Exception) {
            // An uncertain submission is consumed. This observer never retries or logs source content.
            RecordDesktop(NotificationDeliveryStage.Failed);
        }
    }
}
