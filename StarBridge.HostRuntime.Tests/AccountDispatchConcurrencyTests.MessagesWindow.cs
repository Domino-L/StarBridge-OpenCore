using System.Reflection;
using StarBridge.HostRuntime.Account;

internal static partial class AccountDispatchConcurrencyTests
{
    public class MessagesWindowProbe : StartupReadProbe
    {
        internal int MessageReads, Sends;
        internal readonly TaskCompletionSource<object> SendRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override object? Invoke(MethodInfo? method, object?[]? args)
        {
            switch (method!.Name)
            {
                case "ReadDirectMessagesAsync":
                    Interlocked.Increment(ref MessageReads); return Task.FromResult<object>(new { schemaVersion = 1 });
                case "SendDirectMessageAsync":
                    Interlocked.Increment(ref Sends); return SendRelease.Task;
                default: return base.Invoke(method, args);
            }
        }
    }

    // 2026-10-21 user report: the messages, friends and notifications windows
    // stall on open. The messages window asks the primary engine for its
    // directory and history (directMessages.read), which was still a barrier:
    // it waited for every queued account request and held later reads behind it.
    private static async Task MessagesWindowReadPassesQueuedReads()
    {
        var host = DispatchProxy.Create<IAccountBridgeHost, MessagesWindowProbe>();
        var probe = (MessagesWindowProbe)(object)host;
        probe.ConcurrentReads = false;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var queued = new[]
        {
            AccountBridgeRequestNames.ReadDirectMessagePrivacy,
            AccountBridgeRequestNames.ReadFriendRequestPrivacy,
            AccountBridgeRequestNames.ReadNotificationInbox,
        }.Select(name => dispatcher.DispatchAsync(Request(name))).ToArray();
        await Task.Delay(20);
        var messages = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadDirectMessages));
        await Task.Delay(20);
        try
        {
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            await slow;
            Check(await Task.WhenAny(messages, Task.Delay(1000)) == messages && (await messages).Response.Status == "ok",
                "The messages window read waits behind queued privacy and inbox reads.");
            Check(probe.StartupReads <= 1, "The messages window read must be admitted before queued normal reads.");
        }
        finally { probe.ReadRelease.TrySetResult(new { schemaVersion = 1 }); probe.ReleaseStartupReads(); }
        foreach (var read in queued)
            Check((await read.WaitAsync(TimeSpan.FromSeconds(2))).Response.Status == "ok", "Queued reads still complete.");
    }

    // Reordering never lets a read pass a queued send to the same conversation.
    private static async Task MessagesWindowReadKeepsSendFence()
    {
        var host = DispatchProxy.Create<IAccountBridgeHost, MessagesWindowProbe>();
        var probe = (MessagesWindowProbe)(object)host;
        probe.ConcurrentReads = false;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var send = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.SendDirectMessage));
        await Task.Delay(20);
        var messages = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadDirectMessages));
        await Task.Delay(20);
        try
        {
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            await slow;
            await Until(() => probe.Sends == 1);
            await Task.Delay(20);
            Check(probe.MessageReads == 0, "A message read may not overlap or overtake a queued send.");
        }
        finally
        {
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            probe.SendRelease.TrySetResult(new { schemaVersion = 1 });
        }
        await Task.WhenAll(send, messages).WaitAsync(TimeSpan.FromSeconds(2));
        Check(probe.MessageReads == 1, "The message read runs after the send.");
    }
}
