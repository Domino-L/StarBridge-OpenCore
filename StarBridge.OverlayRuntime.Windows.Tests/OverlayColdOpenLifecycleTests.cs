using System.Diagnostics;
using System.Windows;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

namespace StarBridge.Desktop.Tests;

// Uses the production data source, notification wiring and native window.
// No account store, network, hotkey or onscreen acceptance window is involved.
internal static class OverlayColdOpenLifecycleTests
{
    internal static async Task Run()
    {
        var reader = new Reader();
        var owner = new BridgeAccountContext("test", "example.invalid", "fixture");
        using var source = new OverlayCommunitySource(() => (owner, 1), reader, startDriver: false);
        using var runtime = new NativeInformationOverlayRuntime(
            communityProvider: source.ReadForDisplay, sceneModeProvider: () => "community",
            prepareCommunity: source.PrepareForDisplayAsync);
        runtime.TestSurfaceBounds = new Rect(-30000, -30000, 800, 600);
        source.ContentChanged += runtime.RequestContentRefresh;
        OverlaySceneSnapshot? firstFrame = null;
        runtime.BeforeWindowCreation = scene => firstFrame = scene; // Do not abort actual window creation.
        var workspace = new InformationOverlayRuntimeWorkspace(1,
            InformationOverlayDefaults.DefaultSettings with
            {
                AutoFocusGameWindowOnOpen = false,
                AutoOpenOverlayOnGameStart = false,
                AutoOpenOverlayOnGameForeground = false,
                AutoCloseOverlayOnGameBackground = false
            }, [], "Alt+O", false, GameLogSessionSnapshot.Empty, "zh");
        var opening = await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Open, workspace);
        Check(opening.WindowState == "opening" && !opening.IsVisible, "cold open starts pending without an invalid window");
        await reader.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        source.SuspendDisplayDemand(); // Same activity-receiver action while window is not yet visible.
        var timer = Stopwatch.StartNew();
        reader.RosterReady.SetResult();
        InformationOverlayRuntimeSnapshot state = opening;
        while (timer.Elapsed < TimeSpan.FromSeconds(3))
        {
            state = await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Sync, workspace);
            if (state.WindowState != "opening") break;
            await Task.Delay(10);
        }
        Check(state is { WindowState: "open", IsVisible: true } && runtime.IsVisible,
            $"authorized roster must finish real window open promptly; state={state.WindowState} error={state.FailureCode}");
        Check(firstFrame is { HasContent: true } && firstFrame.Players.Count == 1,
            "the first real window has the authorized member");
        Check(!reader.OptionalReads.Task.IsCompleted, "optional reads do not delay window visibility");
        Console.WriteLine($"PASS real cold source -> offscreen HWND opens {timer.ElapsedMilliseconds} ms after roster; optional reads pending");
        var closed = await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Close, workspace);
        Check(closed is { WindowState: "closed", IsVisible: false }, "close finishes actual window lifecycle");
        var reopened = await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Open, workspace);
        Check(reopened is { WindowState: "open", IsVisible: true }, "warm reopen does not prepare again");
        await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Close, workspace);
        source.ContentChanged -= runtime.RequestContentRefresh;
    }

    private sealed class Reader : IOverlayCommunityReader
    {
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource RosterReady = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource OptionalReads = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([new("A", "Fixture", "ref")]);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner,
            OverlayCommunityTarget target, CancellationToken token) => ReadContentAsync(owner, target, _ => { }, token);
        public async Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner,
            OverlayCommunityTarget target, Action<InformationOverlayCommunityContent> rosterReady, CancellationToken token)
        {
            Started.TrySetResult();
            await RosterReady.Task.WaitAsync(token);
            var content = new InformationOverlayCommunityContent("A", "Fixture",
                [new("Fixture", "Fixture", "", "AppOnline", "", "", "", true)]);
            rosterReady(content);
            await OptionalReads.Task.WaitAsync(token);
            return content;
        }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
