using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class OverlayAppearanceProgressTests
{
    internal static async Task Run()
    {
        BridgeEnvelopeValidator.RequireAccountContext("overlay.appearanceProgress.read", null);
        Check(BridgeRequestPolicy.RequiresAccountContext("overlay.appearanceProgress.report"),
            "Readonly route widened unrelated account request policy.");
        var root = Path.Combine(Path.GetTempPath(), "starbridge-collection-" + Guid.NewGuid().ToString("N"));
        var generation = 1L;
        var runtime = new Runtime();
        using var bridge = new OverlayBridgeDispatcher(root, () => generation,
            () => throw new InvalidOperationException("Collection read game source"), runtime);
        async Task<BridgeEnvelope> Send(object payload, long? epoch = null) =>
            (await bridge.DispatchAsync(BridgeEnvelope.Request("overlay.appearanceProgress.read",
                Guid.NewGuid().ToString("N"), epoch ?? generation, payload))).Response;
        var payload = new { schemaVersion = 1, appearanceId = "Default" };
        var metadata = (await bridge.DispatchAsync(BridgeEnvelope.Request("overlay.getWorkspace", "metadata", generation, new { schemaVersion = 1 }))).Response;
        Check(metadata.Payload.GetProperty("appearanceProgressIds").EnumerateArray().Single().GetString() == "Default" && runtime.Reads == 0,
            "Metadata must advertise explicit IDs without reading account progress.");
        runtime.Pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var inFlight = Send(payload);
        var independent = bridge.DispatchAsync(BridgeEnvelope.Request("overlay.getWorkspace", "independent", generation, new { schemaVersion = 1 })).AsTask();
        Check(await Task.WhenAny(independent, Task.Delay(1000)) == independent && (await independent).Response.Status == "ok",
            "Collection network held the workspace gate.");
        runtime.Pending.SetResult();
        Check((await inFlight).Status == "ok", "Unknown collection was not projected.");
        runtime.Pending = null;
        var unknown = await Send(payload);
        Check(unknown.AccountContext is null && unknown.Payload.GetProperty("confirmedUsageMs").ValueKind == JsonValueKind.Null &&
            unknown.Payload.GetProperty("items")[0].GetProperty("owned").GetBoolean() && !Directory.Exists(root),
            "Unknown was made zero, initial gift lost, or query wrote storage.");
        foreach (var attack in new object[] { new { schemaVersion = 1, appearanceId = "Unknown" },
            new { schemaVersion = 1, appearanceId = "Default", observedMs = 1000 }, new { schemaVersion = 1, appearanceId = "Default", accountId = "injected" } })
            Check((await Send(attack)).Status == "error", "Writable/unknown progress query accepted.");
        Check((await Send(payload, 0)).Status == "error", "Stale query accepted.");
        runtime.DuringRead = () => generation++;
        Check((await Send(payload)).Status == "error", "Late former-generation collection returned.");
        runtime.DuringRead = null;
        foreach (Action<JsonObject> corrupt in new Action<JsonObject>[] {
            node => node["accountId"]="injected", node => node["appearanceId"]="Other",
            node => node["schemaVersion"]=2, node => node["state"]="unknown", node => node["confirmedUsageMs"]=-1,
            node => node["confirmedUsageMs"]=9007199254740992L, node => node["confirmedUsageMs"]=1.5,
            node => node["items"]![1]!["owned"]=true, node => node["items"]![1]!["remainingMs"]=0,
            node => node["items"]![1]!["id"]="gift", node => node["items"]![1]!["command"]="equip",
            node => node["items"]![1]!["label"]!["en"]=new string('x',129),
            node => {node["confirmedUsageMs"]=0;node["state"]="signedOut";},
            node => node["items"]=new JsonArray(),
        }) {
            var node=JsonNode.Parse(Fixture().GetRawText())!.AsObject(); corrupt(node);
            runtime.Value=JsonSerializer.SerializeToElement(node);
            Check((await Send(payload)).Status == "error", "Invalid installed collection leaked to Bridge.");
        }
        runtime.Value=Fixture();
        runtime.Ids=["Default","Default"];
        Check((await Send(payload)).Status == "error", "Duplicate collection IDs accepted.");
        runtime.Ids=["Default"];
        using var cancellation=new CancellationTokenSource();
        runtime.DuringRead=()=>cancellation.Cancel();
        var cancelled=(await bridge.DispatchAsync(BridgeEnvelope.Request("overlay.appearanceProgress.read","cancel",generation,payload),cancellation.Token)).Response;
        Check(cancelled.Status == "cancelled", "Cancelled collection returned a receipt.");
        Check(runtime.NormalCalls == 0 && !Directory.Exists(root), "Collection query opened runtime or saved configuration.");
        Console.WriteLine("PASS appearance collection Bridge: exact bounded readonly receipts, no account/game/storage leakage, unknown is nullable, generation/cancel guards, independent workspace reads.");
    }
    private static JsonElement Fixture() => JsonSerializer.SerializeToElement(new {
        schemaVersion=1,appearanceId="Default",state="accountSyncPending",confirmedUsageMs=(long?)null,
        items=new[] {
            new {id="gift",label=new{zhCN="初始物件",zhTW="初始物件",en="Included item"},requiredUsageMs=0L,remainingMs=(long?)0,owned=true},
            new {id="later",label=new{zhCN="后续物件",zhTW="後續物件",en="Later item"},requiredUsageMs=60000L,remainingMs=(long?)null,owned=false}
        }
    });
    private sealed class Runtime : IInformationOverlayRuntime, IInformationOverlayAppearanceCatalog, IInformationOverlayAppearanceProgressCatalog
    {
        internal int Reads, NormalCalls;
        internal TaskCompletionSource? Pending;
        internal Action? DuringRead;
        internal JsonElement Value=Fixture();
        internal IReadOnlyList<string> Ids=["Default"];
        public IReadOnlyList<string> GetAppearanceProgressIds()=>Ids;
        public IReadOnlyList<InformationOverlayAppearanceProfile> GetAppearances()=>[
            new("Default","Fixture","Fixture","","",[],[],"#000000","#000000","#000000",false,false,"None",false,false,false,true)];
        public async ValueTask<JsonElement?> ReadAppearanceProgressAsync(string id,CancellationToken token=default)
        { Reads++;if(Pending is {} pending)await pending.Task;DuringRead?.Invoke();return Value.Clone(); }
        public ValueTask<InformationOverlayRuntimeSnapshot> ExecuteAsync(InformationOverlayRuntimeCommand command,InformationOverlayRuntimeWorkspace workspace,CancellationToken token=default)
        { NormalCalls++;return ValueTask.FromResult(InformationOverlayRuntimeSnapshot.Unavailable); }
        public void Dispose() { }
    }
    private static void Check(bool value,string message){if(!value)throw new InvalidOperationException(message);}
}
