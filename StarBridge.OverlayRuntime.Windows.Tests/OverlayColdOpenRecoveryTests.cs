using System.Net.Http;
using System.Windows;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

namespace StarBridge.Desktop.Tests;

internal static class OverlayColdOpenRecoveryTests
{
    internal static async Task Run()
    {
        await RetryStopsAtAuthorityAndCancellation();
        await CloseBeforeRecoveryDoesNotReopen();
        // Deterministic source-driver tick: no server, account store or timing
        // assumption about when the normal retry becomes available.
        using var tick = new SemaphoreSlim(0);
        var reader = new RecoveringReader();
        var owner = new BridgeAccountContext("test", "example.invalid", "fixture");
        using var source = new OverlayCommunitySource(() => (owner, 1), reader,
            prepareWhenIdle: true, waitForWake: (_, token) => tick.WaitAsync(token));
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var preparation = source.PrepareForDisplayAsync(deadline.Token);
        await reader.FirstAttempt.Task.WaitAsync(deadline.Token);
        // ReadTargets fails synchronously; the preparation must remain alive
        // for the existing driver, not report completion without usable data.
        Check(!preparation.IsCompleted && source.Read() is null,
            "a recoverable initial read must not complete opening before the scheduled retry");
        tick.Release();
        await preparation.WaitAsync(deadline.Token);
        Check(source.Read() is { Members.Count: 1 } && reader.Calls == 2,
            "the existing driver recovers with exactly one retry and no duplicate read loop");

        // The same production source and preparation route must open an actual
        // HWND offscreen, not merely return a successful synthetic snapshot.
        reader = new RecoveringReader();
        using var nativeTick = new SemaphoreSlim(0);
        using var nativeSource = new OverlayCommunitySource(() => (owner, 1), reader,
            prepareWhenIdle: true, waitForWake: (_, token) => nativeTick.WaitAsync(token));
        var initialReadHandled = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var runtime = new NativeInformationOverlayRuntime(
            communityProvider: nativeSource.ReadForDisplay, sceneModeProvider: () => "community",
            prepareCommunity: token =>
            {
                var pending = nativeSource.PrepareForDisplayAsync(token);
                // This fixture's first transport fails synchronously. Signal
                // after its gate is released, not while it is still throwing.
                initialReadHandled.TrySetResult();
                return pending;
            });
        runtime.TestSurfaceBounds = new Rect(-30000, -30000, 800, 600);
        nativeSource.ContentChanged += runtime.RequestContentRefresh;
        var frame = new TaskCompletionSource<OverlaySceneSnapshot>(TaskCreationOptions.RunContinuationsAsynchronously);
        runtime.BeforeWindowCreation = scene => frame.TrySetResult(scene);
        var workspace = new InformationOverlayRuntimeWorkspace(1,
            InformationOverlayDefaults.DefaultSettings with
            {
                AutoFocusGameWindowOnOpen = false, AutoOpenOverlayOnGameStart = false,
                AutoOpenOverlayOnGameForeground = false, AutoCloseOverlayOnGameBackground = false
            }, [], "Alt+O", false, GameLogSessionSnapshot.Empty, "zh");
        try
        {
            await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Open, workspace);
            await initialReadHandled.Task.WaitAsync(TimeSpan.FromSeconds(3));
            nativeTick.Release();
            var firstFrame = await frame.Task.WaitAsync(TimeSpan.FromSeconds(3));
            var state = await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Sync, workspace);
            Check(state is { WindowState: "open", IsVisible: true } && runtime.IsVisible &&
                firstFrame.HasContent && firstFrame.Players.Count == 1 && reader.Calls == 2,
                "a recovered authorized roster opens the original request without another user click");
            Console.WriteLine("PASS cold open survives transient first read; one existing-driver retry opens authorized offscreen HWND");
        }
        finally
        {
            await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Close, workspace);
            nativeSource.ContentChanged -= runtime.RequestContentRefresh;
        }
    }

    private static async Task RetryStopsAtAuthorityAndCancellation()
    {
        foreach (var outcome in new[] { "rejected", "empty", "cancelled", "scope-changed" })
        {
            using var tick = new SemaphoreSlim(0);
            var reader = new RecoveringReader();
            var owner = new BridgeAccountContext("test", "example.invalid", "fixture");
            long generation = 1;
            using var source = new OverlayCommunitySource(() => (owner, generation), reader,
                prepareWhenIdle: true, waitForWake: (_, token) => tick.WaitAsync(token));
            using var cancellation = new CancellationTokenSource();
            var preparation = source.PrepareForDisplayAsync(cancellation.Token);
            Check(!preparation.IsCompleted, "transient preparation remains pending for " + outcome);
            switch (outcome)
            {
                case "cancelled":
                    cancellation.Cancel();
                    try
                    {
                        await preparation.WaitAsync(TimeSpan.FromSeconds(3));
                        throw new InvalidOperationException("cancelled open unexpectedly completed");
                    }
                    catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
                    Check(reader.Calls == 1 && source.Read() is null, "cancellation adds no read and supplies no authority");
                    break;
                case "scope-changed":
                    generation++;
                    reader.Reject = true;
                    tick.Release();
                    await preparation.WaitAsync(TimeSpan.FromSeconds(3));
                    Check(source.Read() is null, "old account generation cannot recover a roster");
                    break;
                default:
                    reader.Reject = outcome == "rejected";
                    reader.Empty = outcome == "empty";
                    tick.Release();
                    await preparation.WaitAsync(TimeSpan.FromSeconds(3));
                    Check(source.Read() is null && reader.Calls == 2,
                        "authoritative rejection or empty membership ends preparation without more retries");
                    break;
            }
        }
        Console.WriteLine("PASS preparation preserves rejection, empty membership, cancellation and generation boundaries");
    }

    private static async Task CloseBeforeRecoveryDoesNotReopen()
    {
        using var tick = new SemaphoreSlim(0);
        var reader = new RecoveringReader();
        var owner = new BridgeAccountContext("test", "example.invalid", "fixture");
        using var source = new OverlayCommunitySource(() => (owner, 1), reader,
            prepareWhenIdle: true, waitForWake: (_, token) => tick.WaitAsync(token));
        var initialReadHandled = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var runtime = new NativeInformationOverlayRuntime(
            communityProvider: source.ReadForDisplay, sceneModeProvider: () => "community",
            prepareCommunity: token =>
            {
                var pending = source.PrepareForDisplayAsync(token);
                initialReadHandled.TrySetResult();
                return pending;
            });
        var creations = 0;
        runtime.BeforeWindowCreation = _ =>
        {
            Interlocked.Increment(ref creations);
            throw new InvalidOperationException("unexpected-window-after-close");
        };
        source.ContentChanged += runtime.RequestContentRefresh;
        var recovered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        source.ContentChanged += () => { if (source.Read() is not null) recovered.TrySetResult(); };
        var workspace = new InformationOverlayRuntimeWorkspace(1,
            InformationOverlayDefaults.DefaultSettings with
            {
                AutoFocusGameWindowOnOpen = false, AutoOpenOverlayOnGameStart = false,
                AutoOpenOverlayOnGameForeground = false, AutoCloseOverlayOnGameBackground = false
            }, [], "Alt+O", false, GameLogSessionSnapshot.Empty, "zh");
        await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Open, workspace);
        await initialReadHandled.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Close, workspace);
        tick.Release();
        await recovered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var state = await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Sync, workspace);
        Check(state is { WindowState: "closed", IsVisible: false } && creations == 0,
            "background recovery cannot reopen an explicitly closed request");
        source.ContentChanged -= runtime.RequestContentRefresh;
        Console.WriteLine("PASS closing a pending request prevents a late window after background recovery");
    }

    private sealed class RecoveringReader : IOverlayCommunityReader
    {
        internal int Calls;
        internal bool Reject;
        internal bool Empty;
        internal readonly TaskCompletionSource FirstAttempt = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token)
        {
            if (Interlocked.Increment(ref Calls) == 1)
            {
                FirstAttempt.TrySetResult();
                throw new HttpRequestException("fixture-temporary-unavailable");
            }
            if (Reject) throw new AccountBridgeHostException("communities.forbidden");
            if (Empty) return Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([]);
            return Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([new("A", "Fixture", "ref")]);
        }
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner,
            OverlayCommunityTarget target, CancellationToken token) => Task.FromResult(new InformationOverlayCommunityContent(
                "A", "Fixture", [new("Fixture", "Fixture", "", "AppOnline", "", "", "", true)]));
    }

    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
}
