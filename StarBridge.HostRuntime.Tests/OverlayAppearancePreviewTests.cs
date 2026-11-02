using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class OverlayAppearancePreviewTests
{
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-live-preview-" + Guid.NewGuid().ToString("N"));
        var generation = 1L;
        var runtime = new Runtime();
        using var host = new OverlayBridgeDispatcher(root, () => generation,
            () => throw new InvalidOperationException("Preview read business data"), runtime);
        async Task<BridgeEnvelope> Send(string name, object payload, long? epoch = null) =>
            (await host.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), epoch ?? generation, payload))).Response;
        var metadata = await Send("overlay.getWorkspace", new { schemaVersion = 1 });
        Check(metadata.Payload.GetProperty("livePreviewAppearanceIds").EnumerateArray().Single().GetString() == "Default", "Explicit preview identity");
        runtime.Ids = ["Default", "Default"];
        Check((await Send("overlay.getWorkspace", new { schemaVersion = 1 })).Payload.GetProperty("livePreviewAppearanceIds").GetArrayLength() == 0, "Duplicate IDs fail closed");
        runtime.Ids = ["Default", "Unknown"];
        Check((await Send("overlay.getWorkspace", new { schemaVersion = 1 })).Payload.GetProperty("livePreviewAppearanceIds").GetArrayLength() == 1, "Catalog authority filters unknown ID");
        runtime.Ids = ["Default"];
        var options = OverlayAppearanceOptions.Parse("""{"schemaVersion":1,"profiles":{"fixture":{"version":1,"values":{"color":1}}}}""");
        var opened = await Send("overlay.appearancePreview.open", new { schemaVersion = 1, appearanceId = "Default", appearanceOptions = options.ToElement() });
        Check(opened.Status == "ok" && runtime.Options == options && runtime.NormalCalls == 0, "Preview does not execute normal HUD commands");
        var first = opened.Payload.GetProperty("sessionId").GetString()!;
        var second = (await Send("overlay.appearancePreview.open", new { schemaVersion = 1, appearanceId = "Default", appearanceOptions = OverlayAppearanceOptions.Empty.ToElement() })).Payload.GetProperty("sessionId").GetString()!;
        await Send("overlay.appearancePreview.close", new { schemaVersion = 1, sessionId = first });
        Check(runtime.Active == second, "Late old close cannot kill new preview");
        await Send("overlay.appearancePreview.close", new { schemaVersion = 1, sessionId = second });
        Check(runtime.Active is null && !Directory.Exists(root), "Preview leaves store/revision untouched");
        foreach (var payload in new object[] {
            new { schemaVersion = 1, appearanceId = "Unknown", appearanceOptions = options.ToElement() },
            new { schemaVersion = 1, appearanceId = "Default", appearanceOptions = new { schemaVersion = 99, profiles = new {} } },
            new { schemaVersion = 1, appearanceId = "Default", appearanceOptions = options.ToElement(), path = "injected" },
        }) Check((await Send("overlay.appearancePreview.open", payload)).Status == "error", "Invalid request blocked");
        Check((await Send("overlay.appearancePreview.close", new { schemaVersion = 1, sessionId = "wrong" })).Status == "error", "Invalid close blocked");
        Check((await Send("overlay.appearancePreview.open", new { schemaVersion = 1, appearanceId = "Default", appearanceOptions = options.ToElement() }, 0)).Status == "error", "Stale request blocked");
        var request = BridgeEnvelope.Request("overlay.appearancePreview.open", Guid.NewGuid().ToString("N"), generation,
            new { schemaVersion = 1, appearanceId = "Default", appearanceOptions = options.ToElement() });
        runtime.DuringOpen = () => generation++;
        Check((await host.DispatchAsync(request)).Response.Status == "error" && runtime.Active is null, "Generation change cleans only newly opened session");
        runtime.DuringOpen = null;
        using var cancellation = new CancellationTokenSource();
        runtime.DuringOpen = () => cancellation.Cancel();
        request = request with { SessionGeneration = generation };
        Check((await host.DispatchAsync(request,cancellation.Token)).Response.Status == "cancelled" && runtime.Active is null, "Cancelled caller cleans created preview");
        Check(runtime.NormalCalls == 0 && !Directory.Exists(root), "All previews are source-free and write-free");
        Console.WriteLine("PASS live appearance preview: bounded installed IDs, source/storage isolation, publication independence, cancellation/generation cleanup and session-owned close");
    }

    private sealed class Runtime : IInformationOverlayRuntime, IInformationOverlayAppearanceCatalog, IInformationOverlayAppearancePreviewRuntime
    {
        internal IReadOnlyList<string> Ids = ["Default"];
        internal string? Active;
        internal OverlayAppearanceOptions? Options;
        internal int NormalCalls;
        internal Action? DuringOpen;
        public IReadOnlyList<string> GetLivePreviewAppearanceIds() => Ids;
        public IReadOnlyList<InformationOverlayAppearanceProfile> GetAppearances() => [
            new("Default","Fixture","Fixture","","",[],[],"#000000","#000000","#000000",false,false,"None",false,false,false,true)];
        public ValueTask<string?> OpenAppearancePreviewAsync(string id, OverlayAppearanceOptions options,bool reduceMotion=false,CancellationToken cancellationToken=default)
        { Active = Guid.NewGuid().ToString("N"); Options = options; DuringOpen?.Invoke(); return ValueTask.FromResult<string?>(Active); }
        public ValueTask CloseAppearancePreviewAsync(string id,CancellationToken cancellationToken=default)
        { if (Active == id) Active = null; return ValueTask.CompletedTask; }
        public ValueTask<InformationOverlayRuntimeSnapshot> ExecuteAsync(InformationOverlayRuntimeCommand command, InformationOverlayRuntimeWorkspace workspace,CancellationToken cancellationToken=default)
        { NormalCalls++; return ValueTask.FromResult(InformationOverlayRuntimeSnapshot.Unavailable); }
        public void Dispose() { Active = null; }
    }
    private static void Check(bool condition,string message) { if (!condition) throw new InvalidOperationException(message); }
}
