using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static class ManualPresenceIntegrationTests
{
    internal static async Task Verify()
    {
        var owner = new BridgeAccountContext("test", "presence.invalid", "sample");
        var root = Path.Combine(Path.GetTempPath(), "starbridge-presence-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var passed = 0;
        void Check(bool ok, string label) { if (!ok) throw new Exception(label); Console.WriteLine("PASS " + label); passed++; }
        try
        {
            var modeStore = new PresenceVisibilityStore(root);
            var first = modeStore.Read();
            Check(first.Mode == PlayerPresenceVisibilityMode.Online && !File.Exists(Path.Combine(root, "sync-privacy.settings.json")), "missing uses WPF default without writing");
            File.WriteAllText(Path.Combine(root,"sync-privacy.settings.json"), "{\"PresenceVisibilityMode\":0,\"SyncEnabled\":false,\"Future\":{\"keep\":[1,2]}}");
            var before = modeStore.Read();
            var savedMode = modeStore.Save(PlayerPresenceVisibilityMode.Invisible, before.Revision, () => {});
            using (var json = JsonDocument.Parse(File.ReadAllText(Path.Combine(root,"sync-privacy.settings.json"))))
                Check(!json.RootElement.GetProperty("SyncEnabled").GetBoolean() && json.RootElement.GetProperty("Future").GetProperty("keep").GetArrayLength() == 2, "preserve unrelated original settings");
            Check(new PresenceVisibilityStore(root).Read() == savedMode, "mode survives reload");
            try { modeStore.Save(PlayerPresenceVisibilityMode.Online, before.Revision, () => {}); throw new Exception("missing conflict"); }
            catch(PresenceVisibilityConflictException) { Check(modeStore.Read() == savedMode, "stale revision never overwrites"); }

            var policyStore = new LocalPrivacyStore(root);
            var policy = new LocalPrivacySettings(true,new(PlayerSharedStateFields.Presence,false,true,[]),new(PlayerSharedStateFields.None,false));
            policyStore.Save(owner,0,Guid.NewGuid().ToString("N"),policy,()=>true);
            PrivacyPublicationInput? current = new(owner,1,"Sample_Handle",true,null,GameLogSessionSnapshot.Empty);
            var sent = new List<JsonElement>();
            var fail = false;
            PresenceVisibilityBridge? bridge = null;
            using var publication = new PrivacyPublication(policyStore,()=>current,(_,payload,_)=>{
                sent.Add(payload.Clone()); return fail ? Task.FromException(new HttpRequestException()) : Task.CompletedTask;
            },startTimer:false,visibility:()=>bridge?.PublicationMode ?? modeStore.Read().Mode);
            var authorityCalls=0;
            bridge = new PresenceVisibilityBridge(modeStore,()=> (current?.Owner,current?.Generation ?? 2),publication.ChangeVisibilityAsync,
                (_,_,mode,_)=> { authorityCalls++; return Task.FromResult(mode); });
            using var ownedBridge = bridge;
            BridgeEnvelope Req(string name, object payload, long generation=1) => BridgeEnvelope.Request(name,Guid.NewGuid().ToString("N"),generation,payload,owner);
            async Task<BridgeEnvelope> Set(string mode) => (await bridge.DispatchAsync(Req("presence.set", new {schemaVersion=1,expectedRevision=modeStore.Read().Revision,mode}))).Response;
            var beforeConsent = sent.Count;
            await Set("online");
            Check(sent.Count == beforeConsent, "online does not invent first publication consent");
            await Set("invisible");
            Check((await publication.ApplyAsync(owner,1,1,default)).State == "withdrawn" && !sent[^1].GetProperty("online").GetBoolean(), "apply cannot bypass persisted invisibility");
            var count=sent.Count; await publication.TickAsync();
            Check(sent.Count==count,"invisible stops periodic snapshot sends");
            Check((await Set("online")).Payload.GetProperty("state").GetString()=="ready" && sent.Count==count+1,"online resumes the account's explicit remembered consent");
            await publication.ApplyAsync(owner,1,1,default);
            Check(sent[^1].GetProperty("online").GetBoolean(),"existing explicit publication still works");
            Check((await Set("invisible")).Payload.GetProperty("state").GetString()=="ready" && !sent[^1].GetProperty("online").GetBoolean(),"invisible confirms only after clear");
            count=sent.Count; await publication.TickAsync();
            Check(sent.Count==count,"no invisible periodic publishing");
            Check((await Set("inGame")).Payload.GetProperty("state").GetString()=="ready" && sent[^1].GetProperty("liveStatus").GetString()=="InGame" && sent[^1].GetProperty("ship").GetString()=="Unknown", "resume previous consent with forced status but no fabricated game facts");
            fail=true;
            Check((await Set("invisible")).Payload.GetProperty("state").GetString()=="unconfirmed" && bridge.PublicationMode==PlayerPresenceVisibilityMode.Invisible,"failed clear stays unconfirmed and blocks publication");
            fail=false;
            Check((await Set("invisible")).Payload.GetProperty("state").GetString()=="ready","explicit retry confirms failed clear");
            await publication.StopAsync(default,explicitRequest:true);
            count=sent.Count;
            await Set("online");
            Check(sent.Count==count,"explicit sharing stop removes resume consent");
            fail=true;
            await Set("invisible");
            fail=false;
            count=sent.Count;
            await Set("online");
            Check(sent.Skip(count).All(p=>!p.GetProperty("online").GetBoolean()),"failed clear cannot invent consent on retry");
            var calls=authorityCalls;
            var malformed = await bridge.DispatchAsync(Req("presence.set",new {schemaVersion=1,mode="invisible",expectedRevision=modeStore.Read().Revision,extra=true}));
            Check(malformed.Response.Error?.Code=="presence.invalid_request" && calls==authorityCalls,"unknown fields cannot mutate");
            var stale = await bridge.DispatchAsync(Req("presence.read",new {schemaVersion=1},2));
            Check(stale.Response.Error?.Code=="presence.account_changed","stale account rejected");
            current=current with { Generation=2,Owner=owner with {Subject="other"} }; publication.Invalidate();
            count=sent.Count; await publication.TickAsync();
            Check(sent.Count==count,"account change removes old publication consent");
            File.WriteAllText(Path.Combine(root,"sync-privacy.settings.json"),"{\"PresenceVisibilityMode\":1,\"PresenceVisibilityMode\":0}");
            Check(bridge.PublicationMode==PlayerPresenceVisibilityMode.Invisible,"corrupt duplicate settings fail closed");
            Console.WriteLine($"PASS {passed}/{passed}");
        }
        finally { Directory.Delete(root,true); }
        await VerifySessionConfirmation();
    }

    private static async Task VerifySessionConfirmation()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-presence-confirmation-").FullName;
        try
        {
            var store = new PresenceVisibilityStore(root);
            var owner = new BridgeAccountContext("test", "scm", "first");
            long generation = 1;
            var authorityCalls = 0;
            PresenceVisibilityBridge Create() => new(store, () => (owner, generation),
                async (_, _, change, token) => { await change(token); return true; },
                (_, _, mode, _) => { authorityCalls++; return Task.FromResult(mode); }, () => true);
            using var bridge = Create();
            async Task<string?> Read(PresenceVisibilityBridge target) => (await target.DispatchAsync(
                BridgeEnvelope.Request("presence.read", Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1 }, owner)))
                .Response.Payload.GetProperty("state").GetString();
            async Task Set() => await bridge.DispatchAsync(BridgeEnvelope.Request("presence.set", Guid.NewGuid().ToString("N"), generation,
                new { schemaVersion = 1, expectedRevision = store.Read().Revision, mode = "online" }, owner));
            void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
            Check(await Read(bridge) == "unconfirmed" && authorityCalls == 0 && bridge.PublicationMode == PlayerPresenceVisibilityMode.Invisible,
                "SCM initial read is not a remote confirmation and never implicitly writes");
            await Set();
            Check(await Read(bridge) == "ready" && authorityCalls == 1 && bridge.PublicationMode == PlayerPresenceVisibilityMode.Online,
                "explicit authority write confirms only its current generation and revision");
            using (var restarted = Create())
                Check(await Read(restarted) == "unconfirmed" && restarted.PublicationMode == PlayerPresenceVisibilityMode.Invisible,
                    "process restart does not promote a stored device mode to SCM confirmation");
            store.Save(PlayerPresenceVisibilityMode.InGame, store.Read().Revision, () => { });
            Check(await Read(bridge) == "unconfirmed" && bridge.PublicationMode == PlayerPresenceVisibilityMode.Invisible,
                "external settings revision invalidates confirmation");
            await Set();
            generation++;
            Check(await Read(bridge) == "unconfirmed", "new login generation needs explicit confirmation");
            owner = owner with { Subject = "second" };
            Check(await Read(bridge) == "unconfirmed" && authorityCalls == 2, "another account cannot inherit confirmed mode or trigger a read-time PUT");
        }
        finally { Directory.Delete(root, true); }
    }
}
