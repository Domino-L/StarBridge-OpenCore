using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class AccountDispatchConcurrencyTests
{
    // 0.7.2 G9 "无延迟同步": a trade-chat push must not wait for an unrelated in-flight request,
    // yet must never overtake an already queued event (Flutter drops older sequences).
    internal static async Task LiveEventSkipsDispatchWaitWithoutOvertaking()
    {
        var (host, probe) = Create();
        using var dispatcher = new AccountBridgeDispatcher(host);
        var published = new List<BridgeEnvelope>();
        dispatcher.EventReady += published.Add;
        var pending = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        BridgeEnvelope[] queuedBatch;
        try
        {
            dispatcher.PublishLiveEvent("marketplace.chatPushed", 1, new { schemaVersion = 1, push = new { kind = "unread", count = 1 } });
            Check(published.Count == 1 && published[0].Name == "marketplace.chatPushed", "A live push reaches Flutter while another request is still running.");
            dispatcher.PublishDomainEvent("communities.changed", 1, new { schemaVersion = 1 });
            dispatcher.PublishLiveEvent("marketplace.chatPushed", 1, new { schemaVersion = 1, push = new { kind = "unread", count = 2 } });
            Check(published.Count == 1, "With an older event queued, the live push queues behind it instead of overtaking it.");
        }
        finally { probe.ReadRelease.TrySetResult(new { schemaVersion = 1 }); }
        queuedBatch = [.. (await pending).Events];
        Check(queuedBatch.Length == 2 && queuedBatch[0].Name == "communities.changed" && queuedBatch[1].Name == "marketplace.chatPushed" &&
              queuedBatch[0].Sequence < queuedBatch[1].Sequence && published[0].Sequence < queuedBatch[0].Sequence,
            "Every event keeps a strictly increasing sequence in delivery order.");
        dispatcher.PublishLiveEvent("marketplace.chatPushed", 1, new { schemaVersion = 1, padding = new string('x', BridgeProtocol.MaximumFrameBytes) });
        Check(published.Count == 1, "An oversized live frame is withheld.");
    }
}
