using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class OfficialFleetAudienceTests
{
    private static readonly OfficialFleetRealtimeTarget Target = new("synthetic",7,"TEST","scm-observed-membership-row-v1:1");
    private static readonly BridgeAccountContext Owner = new("test","https://audience.invalid","synthetic");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(),"sb-audience-"+Guid.NewGuid().ToString("N"));
        var store = new LocalPrivacyStore(root);
        bool support = false;
        long generation = 1;
        var bridge = new OfficialFleetRealtimePrivacyBridge(store,()=> (Owner,generation),
            (_,_,_)=>Task.FromResult(new OfficialRealtimeContextWire(4,"officialFleet:7",Target,null,"initial",true,support)),()=>true);
        async Task<BridgeEnvelope> Read() => (await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetRead",
            Guid.NewGuid().ToString("N"),generation,new {schemaVersion=1},Owner),default)).Response;
        async Task<BridgeEnvelope> Save(BridgeEnvelope scope,object? maximum) => (await bridge.DispatchAsync(BridgeEnvelope.Request(
            "privacy.officialFleetSave",Guid.NewGuid().ToString("N"),generation,new {schemaVersion=1,
                contextRef=scope.Payload.GetProperty("contextRef").GetString(),expectedRevision=store.Read(Owner).Revision,
                operationId=Guid.NewGuid().ToString("N"),fields=15,maximumRankValue=maximum}.AsWire(),Owner),default)).Response;
        var old = await Read();
        Check(old.Status=="ok","initial synthetic audience read: "+old.Error?.Code);
        Check(!bridge.AudienceSupported && old.Payload.GetProperty("maximumRankValue").ValueKind==JsonValueKind.Null,
            "old relay defaults to all members and no audience capability");
        Check((await Save(old,2)).Error?.Code=="official_fleet.audience_unsupported" && store.Read(Owner).Revision==0,
            "old relay rejects non-null before saving any local choice");
        Check((await Save(old,null)).Status=="ok", "old relay accepts null choice");
        var oldFile = Directory.GetFiles(Path.Combine(root,"privacy-local-v1"),"*.json").Single();
        Check(!File.ReadAllText(oldFile).Contains("maximumRankValue",StringComparison.Ordinal) &&
            new LocalPrivacyStore(root).Read(Owner).Settings!.OfficialFleet!.MaximumRankValue is null,
            "signed old storage without new field reads without integrity drift");
        using var lifecycle = new HostBridgeDispatcher(Guid.NewGuid().ToString("N"),()=>generation,["host.lifecycle"],
            additionalCapabilities:()=>bridge.AudienceSupported ? new[]{"privacy.officialFleetAudience"}:[]);
        async Task<bool> Advertised() {
            var response=await lifecycle.DispatchAsync(BridgeEnvelope.Request("host.ready",Guid.NewGuid().ToString("N"),generation,new{}));
            return response.Response.Payload.GetProperty("hostCapabilities").EnumerateArray().Any(p=>p.GetString()=="privacy.officialFleetAudience");
        }
        Check(!await Advertised(),"Ready does not advertise absent relay support");
        support = true;
        foreach (var maximum in new int?[]{null,4,3,2,1}) {
            var scope=await Read();
            Check(await Advertised(),"Ready advertises observed relay audience support");
            Check((await Save(scope,maximum)).Status=="ok", "save audience tier "+maximum);
            var read=await Read();
            Check(read.Payload.GetProperty("maximumRankValue").Deserialize<int?>()==maximum &&
                new LocalPrivacyStore(root).Read(Owner).Settings!.OfficialFleet!.MaximumRankValue==maximum,
                "bridge and signed store audience roundtrip "+maximum);
        }
        foreach (var bad in new object[]{-1,0,5,6,99,1.5,"2",true}) {
            var revision=store.Read(Owner).Revision;
            Check((await Save(await Read(),bad)).Error?.Code=="privacy_local.invalid_request" && store.Read(Owner).Revision==revision,
                "invalid audience leaves local choice unchanged: "+bad);
        }
        var supportedContext=await Read();
        var legacy=await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetSave",Guid.NewGuid().ToString("N"),generation,
            new {schemaVersion=1,contextRef=supportedContext.Payload.GetProperty("contextRef").GetString(),
                expectedRevision=store.Read(Owner).Revision,operationId=Guid.NewGuid().ToString("N"),fields=15},Owner),default);
        Check(legacy.Response.Status=="ok" && store.Read(Owner).Settings!.OfficialFleet!.MaximumRankValue==1,
            "legacy Bridge fields editor cannot silently erase a restrictive audience");
        var before=store.Read(Owner).Revision;
        support=false;
        Check((await Save(supportedContext,2)).Error?.Code=="official_fleet.audience_unsupported" && store.Read(Owner).Revision==before,
            "relay downgrade between read/save is rechecked and cannot broaden choice");
        Check(!await Advertised(),"downgrade retires audience capability");
        var existing=await Read();
        Check(existing.Payload.GetProperty("maximumRankValue").GetInt32()==1,"unsupported relay still reads exact saved restrictive choice");
        var withdraw=await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetSave",Guid.NewGuid().ToString("N"),generation,
            new{schemaVersion=1,contextRef=existing.Payload.GetProperty("contextRef").GetString(),expectedRevision=store.Read(Owner).Revision,
                operationId=Guid.NewGuid().ToString("N"),fields=0},Owner),default);
        Check(withdraw.Response.Status=="ok" && store.Read(Owner).Settings!.OfficialFleet is {Fields:0,MaximumRankValue:null},
            "full withdrawal remains available after relay downgrade");
        support=true; await Read(); generation++;
        Check(!bridge.AudienceSupported,"account generation change cannot retain audience capability");
        await SavedRetry();
        await WithdrawalWithAudience();
        await WriterCompatibility();
        Console.WriteLine("PASS Host audience bridge/store/Ready/old relay/downgrade/writer regression");
    }
    private static async Task SavedRetry()
    {
        var root=Path.Combine(Path.GetTempPath(),"sb-audience-retry-"+Guid.NewGuid().ToString("N"));
        var store=new LocalPrivacyStore(root);
        var remoteRevision="initial"; bool support=true; int reads=0; long generation=1;
        var bridge=new OfficialFleetRealtimePrivacyBridge(store,()=> (Owner,generation),(_,_,_)=> {
            reads++; return Task.FromResult(new OfficialRealtimeContextWire(4,"officialFleet:7",Target,null,remoteRevision,true,support));
        },()=>true);
        var scope=(await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetRead",Guid.NewGuid().ToString("N"),1,
            new{schemaVersion=1},Owner),default)).Response;
        var operation=Guid.NewGuid().ToString("N");
        async Task<BridgeEnvelope> Save(int fields=15,int? maximum=2,long expected=0,string? op=null,long gen=1) =>
            (await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetSave",Guid.NewGuid().ToString("N"),gen,
                new{schemaVersion=1,contextRef=scope.Payload.GetProperty("contextRef").GetString(),expectedRevision=expected,
                    operationId=op??operation,fields,maximumRankValue=maximum},Owner),default)).Response;
        Check((await Save()).Status=="ok","restricted operation initially commits");
        remoteRevision=Guid.NewGuid().ToString("N"); // publication advanced the remote consent
        var calls=reads;
        var retry=await Save();
        Check(retry.Status=="ok" && retry.Payload.GetProperty("revision").GetInt64()==1 && reads==calls && store.Read(Owner).Revision==1,
            "exact committed retry returns original revision without remote precheck after publication");
        support=false;
        Check((await Save()).Status=="ok" && reads==calls,"exact committed retry survives relay capability loss without publishing");
        support=true;
        Check((await Save(fields:1)).Status=="error" && (await Save(maximum:1)).Status=="error" &&
            (await Save(expected:1)).Status=="error" && store.Read(Owner).Revision==1,
            "operation reuse with changed fields, audience or version cannot receive committed success");
        Check((await Save(expected:1,op:Guid.NewGuid().ToString("N"))).Error?.Code=="privacy_local.changed",
            "new restricted save still checks remote revision");
        support=false;
        Check((await Save(expected:1,op:Guid.NewGuid().ToString("N"))).Error?.Code=="official_fleet.audience_unsupported",
            "new restricted save still checks current remote capability");
        generation=2;
        Check((await Save(gen:2)).Error?.Code=="privacy_local.account_changed","committed retry cannot cross account generation");
    }
    private static async Task WithdrawalWithAudience()
    {
        foreach(var cancel in new[]{false,true}) foreach(var supported in new[]{false,true}) {
            var root=Path.Combine(Path.GetTempPath(),"sb-audience-withdraw-"+Guid.NewGuid().ToString("N"));
            var store=new LocalPrivacyStore(root); int remoteReads=0;
            store.Save(Owner,0,Guid.NewGuid().ToString("N"),new(true,new(0,false,false,[]),new(0,false),[],
                OfficialFleet:new(Target,CommunityRealtimeScope.SupportedFields,"initial",Guid.NewGuid().ToString("N"),2)),()=>true);
            var bridge=new OfficialFleetRealtimePrivacyBridge(store,()=> (Owner,1),(_,_,_)=> {
                remoteReads++; return Task.FromResult(new OfficialRealtimeContextWire(4,"officialFleet:7",Target,null,"initial",true,supported));
            },()=>true);
            var scope=(await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetRead",Guid.NewGuid().ToString("N"),1,
                new{schemaVersion=1},Owner),default)).Response;
            var context=scope.Payload.GetProperty(cancel?"cancelContextRef":"contextRef").GetString();
            var reads=remoteReads;
            async Task<BridgeEnvelope> Save(long expected, long generation=1) => (await bridge.DispatchAsync(BridgeEnvelope.Request(
                "privacy.officialFleetSave",Guid.NewGuid().ToString("N"),generation,new{schemaVersion=1,contextRef=context,
                    expectedRevision=expected,operationId=Guid.NewGuid().ToString("N"),fields=0,maximumRankValue=2},Owner),default)).Response;
            Check((await Save(0)).Error?.Code=="privacy_local.conflict","withdrawal with audience retains local version fence");
            Check((await Save(1,2)).Error?.Code=="privacy_local.account_changed","withdrawal with audience retains account generation fence");
            Check((await Save(1)).Status=="ok" && store.Read(Owner).Settings!.OfficialFleet is {Fields:0,MaximumRankValue:null} && remoteReads==reads,
                $"withdrawal normalizes retained audience before capability check cancel={cancel} support={supported}");
            if(cancel) {
                var saved=store.Read(Owner);
                store.Save(Owner,saved.Revision,Guid.NewGuid().ToString("N"),saved.Settings! with {
                    OfficialFleet=saved.Settings!.OfficialFleet! with{Target=Target with{MembershipEpoch="scm-observed-membership-row-v1:2"}}
                },()=>true);
                Check((await Save(3)).Error?.Code=="privacy_local.changed","cancel context cannot withdraw a replacement target");
            }
        }
    }
    private static async Task WriterCompatibility()
    {
        using var handler = new Relay();
        using var writer = new PrivacyRelayWriter(new Uri("https://relay.example.invalid/"),handler);
        var input = new PrivacyPublicationInput(Owner,1,"",true,null,GameLogSessionSnapshot.Empty,AppPresenceConfirmed:true);
        LocalPrivacySettings Settings(int? maximum) => new(true,new(0,false,false,[]),new(0,false),[],
            OfficialFleet:new(Target,CommunityRealtimeScope.SupportedFields,"initial",Guid.NewGuid().ToString("N"),maximum));
        async Task Send(LocalPrivacySettings settings) => await writer.SendAsync("synthetic",PrivacyPublicationPayload.Build(input,settings,false),
            default,allowOfficialPositive:true);
        await Send(Settings(null));
        Check(handler.Publishes==1 && !handler.SavedChoice!.Value.TryGetProperty("maximumRankValue",out _),
            "new Host plus old relay saves and publishes original null wire shape");
        var sent=handler.Publishes;var saved=handler.Saves;
        try { await Send(Settings(2)); throw new Exception("Expected audience refusal"); }
        catch(AccountBridgeHostException error) when(error.Code=="official_fleet.audience_unsupported") { }
        Check(handler.Publishes==sent && handler.Saves==saved,"old relay never receives restricted consent or positive publication");
        handler.Support=true;
        await Send(Settings(2));
        Check(handler.SavedChoice!.Value.GetProperty("maximumRankValue").GetInt32()==2 && handler.Publishes==sent+1,
            "supported relay receives exact restricted choice and publication");
        handler.Support=false;
        try { await Send(Settings(2)); throw new Exception("Expected downgrade refusal"); }
        catch(AccountBridgeHostException error) when(error.Code=="official_fleet.audience_unsupported") { }
        Check(handler.Publishes==sent+1,"downgraded relay cannot publish even with previously matching restricted consent");
        handler.Support=true;handler.DropAudience=true;
        try { await Send(Settings(3)); throw new Exception("Expected receipt refusal"); }
        catch(AccountBridgeHostException) { }
        Check(handler.Publishes==sent+1,"relay dropping threshold from saved receipt cannot trigger positive publication");
    }
    private sealed class Relay : HttpMessageHandler
    {
        internal bool Support,DropAudience;
        internal int Saves,Publishes;
        internal JsonElement? SavedChoice;
        private object? _consent;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)
        {
            var path=request.RequestUri!.AbsolutePath;
            object payload;
            if(path.EndsWith("/context",StringComparison.Ordinal)) {
                Check(request.Headers.TryGetValues("X-StarBridge-Official-Audience",out var values) && values.Single()=="1",
                    "new Host explicitly opts into extensible audience context");
                var fields=new Dictionary<string,object?> { ["schemaVersion"]=4,["sourceRef"]="officialFleet:7",["target"]=Target,
                    ["consent"]=null,["expectedRevision"]="initial",["writesAvailable"]=true };
                if(Support)fields["audienceRankSupported"]=true;
                payload=fields;
            } else if(path.EndsWith("/consent",StringComparison.Ordinal)) {
                Check(request.Headers.TryGetValues("X-StarBridge-Official-Audience",out var values) && values.Single()=="1",
                    "new Host opts into negotiated GET and PUT consent, including null audience");
                if(request.Method==HttpMethod.Put) {
                    Saves++;
                    var body=await request.Content!.ReadFromJsonAsync<JsonElement>(cancellationToken:token);
                    SavedChoice=body.GetProperty("choice").Clone();
                    var choice=SavedChoice.Value.Deserialize<OfficialFleetRealtimeChoice>(Json)!;
                    _consent=new OfficialRealtimeConsentWire("synthetic",choice.Target,choice.Fields,Guid.NewGuid().ToString("N"),
                        choice.OperationId,DropAudience ? null : choice.MaximumRankValue);
                }
                payload=new{schemaVersion=4,consent=_consent};
            } else if(path.EndsWith("/publish",StringComparison.Ordinal)) {
                Publishes++;
                var body=await request.Content!.ReadFromJsonAsync<JsonElement>(cancellationToken:token);
                payload=new{schemaVersion=4,state=body.GetProperty("state"),communities=body.GetProperty("communities"),
                    officialAudience=new{target=body.GetProperty("target"),consentRevision=body.GetProperty("consentRevision"),withdrawOnly=false}};
            } else throw new InvalidOperationException("Unexpected synthetic relay path");
            var response=new HttpResponseMessage(HttpStatusCode.OK){Content=JsonContent.Create(payload)};
            response.Headers.Add("X-StarBridge-Realtime-Version","4");
            return response;
        }
    }
    private static void Check(bool condition,string text) { if(!condition)throw new InvalidOperationException(text); }
    private static JsonElement AsWire(this object value) => JsonSerializer.SerializeToElement(value,Json);
}
