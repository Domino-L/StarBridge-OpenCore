namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private void PublishInboxChanged(long generation, bool healthy)
    {
        if (_disposed || _localBusinessRetired || generation != _host.Generation) return;
        _dispatcher.PublishLiveEvent("notificationInbox.changed", generation,
            new { schemaVersion = 1, scmPushHealthy = healthy });
    }
}
