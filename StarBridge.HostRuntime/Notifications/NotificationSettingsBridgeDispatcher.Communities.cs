using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

public sealed partial class NotificationSettingsBridgeDispatcher
{
    private readonly NotificationPolicyStore _policies = new(dataRoot);
    private long _policyEpoch;
    internal NotificationPolicySnapshot ReadPolicies(BridgeAccountContext owner) { lock (_gate) return _policies.Read(owner); }
    internal NotificationPolicySnapshot SavePolicies(BridgeAccountContext owner, long revision, string operation,
        NotificationPolicyRule[] rules, Func<bool> current)
    {
        lock (_gate) {
            ObjectDisposedException.ThrowIf(_disposed, this);
            var result = _policies.Save(owner, revision, operation, rules, current);
            Interlocked.Increment(ref _policyEpoch);
            Interlocked.Increment(ref _directEpoch);
            InvalidateReminder();
            return result;
        }
    }
    internal async ValueTask PresentCommunityAsync(CommunityNotificationNotice incoming, CancellationToken token)
    {
        DesktopNotification notice;
        lock (_gate) {
            if (_disposed || token.IsCancellationRequested || !incoming.IsCurrent()) return;
            try {
                var source = incoming.Source;
                if (string.IsNullOrWhiteSpace(source.PolicyKey)) return;
                var policies = _policies.Read(incoming.Owner);
                if (!NotificationSourcePolicy.Allows(policies.For(source.PolicyKey), incoming.Kind)) return;
                var settings = Read();
                if (!settings.WindowsEnabled || desktop == null || !(canNotifyDesktop?.Invoke() ?? false)) return;
                var management = incoming.Kind == NotificationEventKind.OrganizationManagement;
                if (management ? !source.ManagementAvailable : incoming.Kind != NotificationEventKind.OrganizationChat || !source.ChatAvailable) return;
                var epoch = Interlocked.Read(ref _directEpoch);
                var policyEpoch = Interlocked.Read(ref _policyEpoch);
                bool Current() => !_disposed && epoch == Interlocked.Read(ref _directEpoch) &&
                    policyEpoch == Interlocked.Read(ref _policyEpoch) && incoming.IsCurrent();
                var id = Guid.NewGuid();
                notice = CreateDesktop(id, false, 0, 0, settings, Current) with {
                    Community = new(settings.Preview == "hiddenDetails" ? "" : source.Name,
                        settings.Preview == "fullContent" && !management ? source.Chat?.Callsign ?? "" : "",
                        settings.Preview == "fullContent" && !management ? source.Chat?.Text ?? "" : "", management),
                    // Opens the authorized organization directory, never an old
                    // raw target, chat receipt or management command.
                    Activated = activationEvent == null ? null : () => Activate(id, Current, "communities")
                };
            } catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or
                Settings.ApplicationPreferencesException) { return; }
        }
        if (notice.IsCurrent()) await desktop!.TryPresentDetailedAsync(notice, token).ConfigureAwait(false);
    }
}
