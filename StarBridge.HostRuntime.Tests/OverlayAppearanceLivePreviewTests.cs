using System.Text.Json;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class OverlayAppearanceLivePreviewTests
{
    internal static async Task Run()
    {
        long generation = 1;
        string? owner = null;
        var runtime = new Runtime();
        using var host = new OverlayAppearanceLivePreviewDispatcher(runtime, () => generation,
            () => (owner, generation), () => new(0, 0, 2560, 1440));
        var frame = JsonSerializer.SerializeToElement(new
        {
            appearanceId = "Default", settings = OverlayWorkspaceWireProjection.Settings(OverlayDisplaySettings.Default),
            layout = new[] { "Squads", "Members", "Notice", "Chat" }.Select(key =>
                OverlayWorkspaceWireProjection.Layout(new InformationOverlayLayoutItem(key, .1, .2, .3, .4))).ToArray(),
            appearanceOptions = OverlayAppearanceOptions.Empty.ToElement(), language = "zh-CN", reduceMotion = false
        });
        _ = InformationOverlayLivePreviewDraft.Parse(frame);
        var suppliedAccount = (await host.DispatchAsync(BridgeEnvelope.Request(
            OverlayAppearanceLivePreviewDispatcher.Open, "supplied-account", generation,
            new { schemaVersion = 1, frame }, new BridgeAccountContext("fixture", "fixture", "fixture")))).Response;
        Check(suppliedAccount.Status == "error" && runtime.Opens == 0,
            "accountless route cannot accept caller-selected account authority");
        async Task<BridgeEnvelope> Send(string name, object payload, long? epoch = null, CancellationToken token = default) =>
            (await host.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), epoch ?? generation, payload), token)).Response;
        async Task<string> Open()
        {
            var response = await Send(OverlayAppearanceLivePreviewDispatcher.Open, new { schemaVersion = 1, frame });
            Check(response.Status == "ok", "accountless finite preview opens: " + response.Error?.Code);
            return response.Payload.GetProperty("sessionId").GetString()!;
        }
        var first = await Open();
        var current = await Open();
        await Send(OverlayAppearanceLivePreviewDispatcher.Close, new { schemaVersion = 1, sessionId = first });
        Check(runtime.Active == current, "late close owns only its old session");
        var before = runtime.Frame;
        var renewed = await Send(OverlayAppearanceLivePreviewDispatcher.Renew, new { schemaVersion = 1, sessionId = current, revision = 1 });
        Check(renewed.Status == "ok" && renewed.Payload.GetProperty("revision").GetInt64() == 1,
            "renewal acknowledges its exact revision");
        Check(ReferenceEquals(before, runtime.Frame) && runtime.Updates == 0 && runtime.Opens == 2,
            "renewal cannot resend a frame or reopen presentation");
        foreach (var payload in new object[]
        {
            new { schemaVersion = 1, sessionId = current, revision = 2, frame },
            new { schemaVersion = 1, sessionId = current, revision = 0 },
            new { schemaVersion = 1, sessionId = current, revision = 9007199254740992L },
            new { schemaVersion = 1, sessionId = current, revision = 2, account = "client-selected" },
            new { schemaVersion = 1, sessionId = "invalid", revision = 2 }
        })
            Check((await Send(OverlayAppearanceLivePreviewDispatcher.Renew, payload)).Status == "error", "invalid renewal rejected before runtime");
        Check(runtime.Renewals == 1, "malformed renewals never reach runtime");
        Check((await Send(OverlayAppearanceLivePreviewDispatcher.Renew,
            new { schemaVersion = 1, sessionId = current, revision = 2 }, 0)).Status == "error", "stale generation rejected");
        Check(runtime.Renewals == 1, "stale generation has no renewal side effect");
        runtime.DuringRenew = () => owner = "new-owner";
        Check((await Send(OverlayAppearanceLivePreviewDispatcher.Renew,
            new { schemaVersion = 1, sessionId = current, revision = 2 })).Status == "error", "owner change during receipt rejected");
        Check(runtime.Active is null, "owner-change receipt cleans its own session");
        runtime.DuringRenew = null;
        current = await Open();
        using var cancellation = new CancellationTokenSource();
        runtime.DuringRenew = () => cancellation.Cancel();
        Check((await Send(OverlayAppearanceLivePreviewDispatcher.Renew,
            new { schemaVersion = 1, sessionId = current, revision = 1 }, token: cancellation.Token)).Status == "cancelled",
            "cancelled renewal cannot return a successful receipt");
        Check(runtime.Active is null, "cancelled receipt cleans its own session");
        runtime.DuringRenew = null;
        current = await Open();
        string? successor = null;
        runtime.DuringRenew = () =>
        {
            generation++;
            successor = runtime.ReplaceSession();
        };
        Check((await Send(OverlayAppearanceLivePreviewDispatcher.Renew,
            new { schemaVersion = 1, sessionId = current, revision = 1 })).Status == "error", "late former-generation renewal rejected");
        Check(runtime.Active == successor, "cleanup of an old receipt cannot close its successor");
        var draft = InformationOverlayLivePreviewDraft.Parse(frame);
        var detached = draft.CopyLayout();
        detached[0].X = .9;
        Check(draft.CopyLayout()[0].X == .1, "preview layout remains detached from consumers");
        Check(new OverlayPreviewControlArea(0, 0, .25, 1).IsValid &&
            !new OverlayPreviewControlArea(-.1, 0, .25, 1).IsValid &&
            !new OverlayPreviewControlArea(0, 0, double.NaN, 1).IsValid, "control protection has finite normalized bounds");
        Console.WriteLine("PASS common appearance preview: finite accountless requests, immutable frame, renewal isolation, owner/cancellation races and successor-safe cleanup");
        var feedback = new Runtime { Placements = [new("slot0", "screen-edge")] };
        string? feedbackOwner = null;
        using var feedbackHost = new OverlayAppearanceLivePreviewDispatcher(feedback, () => 1, () => (feedbackOwner, 1));
        async Task<BridgeEnvelope> Feedback(string name, object payload, CancellationToken token = default) =>
            (await feedbackHost.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 1, payload), token)).Response;
        var opened = await Feedback(OverlayAppearanceLivePreviewDispatcher.Open, new { schemaVersion = 1, frame });
        Check(opened.Status == "ok" && opened.Payload.GetProperty("placementStates")[0].GetProperty("reason").GetString() == "screen-edge",
            "open returns finite native placement feedback");
        var feedbackId = opened.Payload.GetProperty("sessionId").GetString()!;
        feedback.Placements = [new("slot0", "placed")];
        var updated = await Feedback(OverlayAppearanceLivePreviewDispatcher.Update,
            new { schemaVersion = 1, sessionId = feedbackId, revision = 1, frame });
        Check(updated.Status == "ok" && updated.Payload.GetProperty("placementStates")[0].GetProperty("reason").GetString() == "placed",
            "updated feedback reflects its acknowledged frame");
        foreach(var reason in new[]{"interaction-space","observation-only"}) {
            feedback.Placements=[new("slot0",reason)];
            var visible=await Feedback(OverlayAppearanceLivePreviewDispatcher.Open,new{schemaVersion=1,frame});
            Check(visible.Status=="ok"&&visible.Payload.GetProperty("placementStates")[0].GetProperty("reason").GetString()==reason,
                "visible decoration interaction feedback preserves the finite receipt");
        }
        foreach (var bad in new OverlayAppearancePlacementState[][] {
            [new("slot0", "execute")], [new("bad/path", "placed")],
            [new("slot0", "placed"), new("slot0", "screen-edge")],
            Enumerable.Range(0, 13).Select(i => new OverlayAppearancePlacementState($"slot{i}", "placed")).ToArray()
        }) {
            feedback.Placements = bad;
            Check((await Feedback(OverlayAppearanceLivePreviewDispatcher.Open, new { schemaVersion = 1, frame })).Status == "error" &&
                feedback.Active is null, "invalid placement metadata rejects receipt and cleans just-opened session");
        }
        feedback.Placements = [];
        feedback.DuringRead = () => feedbackOwner = "changed";
        Check((await Feedback(OverlayAppearanceLivePreviewDispatcher.Open, new { schemaVersion = 1, frame })).Status == "error" &&
            feedback.Active is null, "owner changes during feedback clean only that opening session");
        var cancellationFailures = new List<string>();
        foreach (var updateRead in new[] { false, true })
        foreach (var readThrows in new[] { false, true })
        foreach (var replaceDuringRead in new[] { false, true })
        {
            feedback.DuringRead = null;
            using var cancelledRead = new CancellationTokenSource();
            string? readSession = null;
            if (updateRead)
            {
                var ready = await Feedback(OverlayAppearanceLivePreviewDispatcher.Open, new { schemaVersion = 1, frame });
                Check(ready.Status == "ok", "cancellation fixture starts a healthy preview");
                readSession = ready.Payload.GetProperty("sessionId").GetString()!;
            }
            string? readSuccessor = null;
            feedback.DuringRead = () => {
                if (replaceDuringRead) readSuccessor = feedback.ReplaceSession();
                cancelledRead.Cancel();
                if (readThrows) throw new OperationCanceledException(cancelledRead.Token);
            };
            var cancelled = await Feedback(updateRead ? OverlayAppearanceLivePreviewDispatcher.Update : OverlayAppearanceLivePreviewDispatcher.Open,
                updateRead ? new { schemaVersion = 1, sessionId = readSession, revision = 1, frame } :
                    (object)new { schemaVersion = 1, frame }, cancelledRead.Token);
            Check(cancelledRead.IsCancellationRequested, "read fixture really propagated cancellation through the supplied token");
            if (cancelled.Status != "cancelled" || feedback.Active != readSuccessor)
                cancellationFailures.Add($"{(updateRead ? "update" : "open")} readThrows={readThrows}, successor={replaceDuringRead}: status={cancelled.Status}, wrongActive={feedback.Active != readSuccessor}");
            if (feedback.Active is { } remaining)
                await feedback.CloseLiveAppearancePreviewAsync(remaining, CancellationToken.None);
        }
        feedback.DuringRead = null;
        Check(cancellationFailures.Count == 0, "cancelled placement read must not acknowledge success or retain its preview: " +
            string.Join("; ", cancellationFailures));
        Console.WriteLine("PASS preview placement feedback: exact-frame, bounded read-only metadata, invalid and owner-race cleanup");
    }

    private sealed class Runtime : IInformationOverlayLivePreviewRuntime
    {
        internal string? Active;
        internal InformationOverlayLivePreviewDraft? Frame;
        internal int Opens, Updates, Renewals;
        internal Action? DuringRenew;
        internal Action? DuringRead;
        internal IReadOnlyList<OverlayAppearancePlacementState> Placements = [];
        public ValueTask<IReadOnlyList<OverlayAppearancePlacementState>?> ReadLivePreviewPlacementStatesAsync(
            string id, long revision, CancellationToken cancellationToken = default)
        { var valid = id == Active; DuringRead?.Invoke(); return ValueTask.FromResult<IReadOnlyList<OverlayAppearancePlacementState>?>(valid ? Placements : null); }
        public IReadOnlyList<string> GetLiveAppearancePreviewIds() => ["Default"];
        internal string ReplaceSession() => Active = Guid.NewGuid().ToString("N");
        public ValueTask<string?> OpenLiveAppearancePreviewAsync(InformationOverlayLivePreviewDraft draft,
            InformationOverlayLivePreviewScope scope, CancellationToken cancellationToken = default)
        { Opens++; Frame = draft; return ValueTask.FromResult<string?>(ReplaceSession()); }
        public ValueTask<long?> UpdateLiveAppearancePreviewAsync(string id, long revision,
            InformationOverlayLivePreviewDraft draft, CancellationToken cancellationToken = default)
        { Updates++; Frame = draft; return ValueTask.FromResult<long?>(id == Active ? revision : null); }
        public ValueTask<long?> RenewLiveAppearancePreviewAsync(string id, long revision, CancellationToken cancellationToken = default)
        { Renewals++; var valid = id == Active; DuringRenew?.Invoke(); return ValueTask.FromResult<long?>(valid ? revision : null); }
        public ValueTask CloseLiveAppearancePreviewAsync(string id, CancellationToken cancellationToken = default)
        { if (Active == id) Active = null; return ValueTask.CompletedTask; }
    }
    private static void Check(bool value, string message)
    { if (!value) throw new InvalidOperationException(message); }
}
