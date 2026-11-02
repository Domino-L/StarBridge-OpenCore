using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class AccountDispatchConcurrencyTests
{
    internal static async Task DisplayProgressPreservesInvalidations()
    {
        var (host, probe) = Create();
        using var dispatcher = new AccountBridgeDispatcher(host);
        var published = new List<BridgeEnvelope>();
        dispatcher.EventReady += published.Add;
        var pending = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        try
        {
            dispatcher.PublishDomainEvent("communities.changed", 1, new { schemaVersion = 1 });
            dispatcher.PublishFriendsDisplayProgress(1, new { schemaVersion = 1 }, () => true);
            dispatcher.PublishRestoreDisplayProgress(1, new { schemaVersion = 1 }, () => true);
            Check(published.Count == 0, "Progress must not overtake an older queued invalidation and make it stale at the receiver.");
        }
        finally { probe.ReadRelease.TrySetResult(new { schemaVersion = 1 }); }
        var result = await pending;
        Check(result.Events.Count == 1 && result.Events[0].Name == "communities.changed", "Original queued invalidation must remain in the response batch.");
        dispatcher.PublishFriendsDisplayProgress(1, new { schemaVersion = 1 }, () => true);
        Check(published.Count == 1 && published[0].Sequence > result.Events[0].Sequence, "Later progress keeps monotonic sequence after the original event.");
    }

    internal static async Task DisplayProgressFrameBudget()
    {
        var (host, probe) = Create();
        using var dispatcher = new AccountBridgeDispatcher(host);
        var published = new List<BridgeEnvelope>();
        dispatcher.EventReady += frame => {
            Check(System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(frame, BridgeProtocol.JsonOptions).Length <= BridgeProtocol.MaximumFrameBytes,
                "An optional oversized display frame must not reach the transport and break the authoritative request.");
            published.Add(frame);
        };
        var pending = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        try
        {
            dispatcher.PublishFriendsDisplayProgress(1, new { schemaVersion = 1, padding = new string('x', BridgeProtocol.MaximumFrameBytes) }, () => true);
            Check(published.Count == 0, "A display larger than the unchanged v1 frame budget must be withheld.");
            dispatcher.PublishFriendsDisplayProgress(1, new { schemaVersion = 1 }, () => true);
            Check(published.Count == 1, "The next bounded display remains publishable.");
        }
        finally { probe.ReadRelease.TrySetResult(new { schemaVersion = 1 }); }
        Check((await pending).Response.Status == "ok", "Optional display overflow does not fail ordinary business IO.");
    }
}
