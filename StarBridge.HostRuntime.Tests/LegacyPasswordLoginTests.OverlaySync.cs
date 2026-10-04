using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    private sealed class OverlayWaitTransport : HttpMessageHandler
    {
        internal int Calls;
        internal TaskCompletionSource<HttpResponseMessage> Reply = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            Check(request.RequestUri?.AbsolutePath == "/api/fleets/activity" && request.Headers.Authorization?.Scheme == "Bearer",
                "native organization changes use the existing authenticated fleets wait");
            return Reply.Task.WaitAsync(token);
        }
    }

    internal static async Task OverlayLiveChangeAdapter()
    {
        using var transport = new Transport();
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), transport);
        var waitTransport = new OverlayWaitTransport();
        using var friends = new FriendsReader(new Uri("https://example.invalid/"), waitTransport);
        using var host = CreateHost(login, friends: friends);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        var owner = host.CurrentContext!;
        var reader = (IOverlayCommunityChangeReader)host;
        var cursor = new OverlayActivityCursor();
        foreach (var advertised in new[] { false, true })
        {
            waitTransport.Reply = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var pending = reader.WaitForChangesAsync(owner, host.Generation, cursor, default);
            Check(!pending.IsCompleted, "the native adapter holds the actual long poll");
            var instance = Guid.NewGuid().ToString("N");
            waitTransport.Reply.SetResult(new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(
                advertised ? (object)new { instanceId = instance, version = 2, presenceEvents = true }
                    : new { instanceId = instance, version = 2 })) });
            cursor = await pending;
            Check(cursor.Instance == instance && cursor.Version == 2 && cursor.PresenceEvents == advertised,
                "the actual Host adapter preserves the cursor and only explicit presence capability");
        }
        var calls = waitTransport.Calls;
        try { await reader.WaitForChangesAsync(owner, host.Generation + 1, cursor, default); throw new Exception("stale generation accepted"); }
        catch (BridgeStaleGenerationException) { }
        Check(waitTransport.Calls == calls, "stale generation never reaches HTTP");
        waitTransport.Reply = new(TaskCreationOptions.RunContinuationsAsynchronously);
        using var stop = new CancellationTokenSource();
        var cancelled = reader.WaitForChangesAsync(owner, host.Generation, cursor, stop.Token);
        stop.Cancel();
        try { await cancelled; throw new Exception("cancelled overlay wait accepted"); }
        catch (OperationCanceledException) { }
        waitTransport.Reply = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var late = reader.WaitForChangesAsync(owner, host.Generation, cursor, default);
        host.Dispose();
        waitTransport.Reply.SetResult(new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(
            new { instanceId = cursor.Instance, version = 3, presenceEvents = true })) });
        try { await late; throw new Exception("late closed-session response accepted"); }
        catch (Exception error) when (error is BridgeStaleGenerationException or OperationCanceledException) { }
    }
}
