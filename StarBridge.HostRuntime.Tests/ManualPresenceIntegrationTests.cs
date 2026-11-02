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
            Check((await Set("invisible")).Payload.GetProperty("state").GetString()=="ready" && bridge.PublicationMode==PlayerPresenceVisibilityMode.Invisible && publication.ClearPending,"confirmed invisible and pending clear are separate; positive publication stays blocked");
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
            Check(bridge.ReadPublicationSnapshot().SuspensionError == "privacy_local.read_failed", "corrupt visibility is not a manual pause or a network claim");
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
            int? realtimeStatus = 1;
            PresenceVisibilityBridge Create() => new(store, () => (owner, generation),
                async (_, _, change, token) => { await change(token); return true; },
                (_, _, mode, _) => { authorityCalls++; return Task.FromResult(mode); }, () => true, () => realtimeStatus);
            using var bridge = Create();
            async Task<string?> Read(PresenceVisibilityBridge target) => (await target.DispatchAsync(
                BridgeEnvelope.Request("presence.read", Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1 }, owner)))
                .Response.Payload.GetProperty("state").GetString();
            async Task Set() => await bridge.DispatchAsync(BridgeEnvelope.Request("presence.set", Guid.NewGuid().ToString("N"), generation,
                new { schemaVersion = 1, expectedRevision = store.Read().Revision, mode = "online" }, owner));
            void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
            Check(await Read(bridge) == "unconfirmed" && authorityCalls == 0 && bridge.PublicationMode == PlayerPresenceVisibilityMode.Invisible,
                "SCM initial read is not a remote confirmation and never implicitly writes");
            using (var applying = Create())
            {
                var policies = new LocalPrivacyStore(root);
                var policy = new LocalPrivacySettings(true,
                    new(PlayerSharedStateFields.Presence, false, true, []),
                    new(PlayerSharedStateFields.None, false));
                var saved = policies.Save(owner, 0, Guid.NewGuid().ToString("N"), policy, () => true);
                var sentOnline = false;
                var rejectClear = false;
                var clearClock = new SharingTestClock();
                using var publication = new PrivacyPublication(policies,
                    () => new(owner, generation, "Pilot", true, null, GameLogSessionSnapshot.Empty),
                    (_, payload, _) => {
                        sentOnline = payload.GetProperty("online").GetBoolean();
                        if (rejectClear && !sentOnline) throw new HttpRequestException();
                        return Task.CompletedTask;
                    },
                    startTimer: false, visibility: () => applying.PublicationMode, timeProvider: clearClock,
                    visibilitySnapshot: () => applying.ReadPublicationSnapshot(),
                    confirmExplicitSharing: applying.ConfirmObservedModeForExplicitSharing);
                await publication.ApplyAsync(owner, generation, saved.Revision, default);
                Check(publication.Status.State == "applied" && sentOnline && authorityCalls == 0,
                    "Explicit sharing with current SCM online acknowledgement must not silently withdraw or issue a presence write.");
                var states = new List<string>();
                publication.StatusChanged += () => states.Add(publication.Status.State);
                foreach (var disconnected in new int?[] { null, 0 })
                {
                    states.Clear();
                    realtimeStatus = disconnected;
                    rejectClear = true;
                    await publication.TickAsync();
                    Check(!sentOnline && publication.Status.State == "reconnecting" &&
                        publication.Status.ErrorCode == "privacy_publication.network_unavailable" && policies.HasPublicationConsent(owner),
                        "SCM observation loss and failed withdrawal must preserve automatic recovery.");
                    rejectClear = false;
                    clearClock.Advance(60);
                    await publication.TickAsync();
                    await publication.TickAsync();
                    Check(!sentOnline && publication.Status.State == "reconnecting" && !states.Contains("withdrawn"),
                        "Disconnected SCM must stay fail-closed without a manual-pause event.");
                    realtimeStatus = 1;
                    await publication.TickAsync();
                    Check(sentOnline && publication.Status.State == "applied" && authorityCalls == 0,
                        "SCM observation recovery resumes existing sharing without a UI action or presence PUT.");
                }
                realtimeStatus = null;
                states.Clear();
                Check(await publication.ChangeVisibilityAsync(owner, generation, _ => Task.CompletedTask, default) &&
                    publication.Status.State == "reconnecting" && !sentOnline && !states.Contains("withdrawn"),
                    "An online visibility confirmation during connection loss must not become a manual pause.");
                realtimeStatus = 1;
                await publication.TickAsync();
                Check(sentOnline && publication.Status.State == "applied", "Visibility confirmation resumes after current connection evidence returns.");
                realtimeStatus = null;
                await publication.ApplyAsync(owner, generation, saved.Revision, default);
                Check(!sentOnline && publication.Status.State == "reconnecting" && policies.HasPublicationConsent(owner),
                    "Disconnected observation must retain consent and reconnect without enabling sharing.");
                realtimeStatus = 3;
                await publication.ApplyAsync(owner, generation, saved.Revision, default);
                Check(!sentOnline && publication.Status.State == "withdrawn", "SCM invisibility cannot be bypassed by reapply.");
                realtimeStatus = 1;
                store.Save(PlayerPresenceVisibilityMode.Invisible, store.Read().Revision, () => { });
                await publication.ApplyAsync(owner, generation, saved.Revision, default);
                Check(!sentOnline && publication.Status.State == "withdrawn", "Local invisibility cannot be bypassed by an online SCM observation.");
                realtimeStatus = null;
                await publication.ApplyAsync(owner, generation, saved.Revision, default);
                Check(!sentOnline && publication.Status.State == "withdrawn", "Local manual invisibility still wins while disconnected.");
                realtimeStatus = 1;
                store.Save(PlayerPresenceVisibilityMode.Online, store.Read().Revision, () => { });
                applying.ConfirmObservedModeForExplicitSharing(owner, generation - 1);
                Check(applying.PublicationMode == PlayerPresenceVisibilityMode.Invisible, "Stale generation cannot confirm the new mode revision.");
                await publication.ApplyAsync(owner, generation, saved.Revision, default);
                Check(sentOnline && publication.Status.State == "applied" && authorityCalls == 0, "Fresh explicit sharing recovers without a remote presence write.");
            }
            using (var restoredVisibility = Create())
            {
                var policies = new LocalPrivacyStore(root);
                var sends = new List<bool>();
                realtimeStatus = null;
                using var restoredPublication = new PrivacyPublication(policies,
                    () => new(owner, generation, "Pilot", true, null, GameLogSessionSnapshot.Empty),
                    (_, payload, _) => { sends.Add(payload.GetProperty("online").GetBoolean()); return Task.CompletedTask; },
                    startTimer: false, visibility: () => restoredVisibility.PublicationMode,
                    visibilitySnapshot: () => restoredVisibility.ReadPublicationSnapshot(),
                    confirmExplicitSharing: restoredVisibility.ConfirmObservedModeForExplicitSharing);
                await restoredPublication.TickAsync();
                Check(!sends.Contains(true) && restoredPublication.Status.State == "reconnecting",
                    "Startup without current SCM confirmation waits for the connection without publishing or pausing.");
                realtimeStatus = 1;
                await restoredPublication.TickAsync();
                Check(restoredPublication.Status.State == "applied" && sends[^1] && authorityCalls == 0,
                    "Remembered sharing must resume after current SCM acknowledgement without manual apply or authority writes.");
                await restoredPublication.StopAsync(default, explicitRequest: true);
                await restoredPublication.TickAsync();
                Check(!sends[^1] && !policies.HasPublicationConsent(owner), "Manual stop must not be undone by online acknowledgement.");
            }
            await Set();
            Check(await Read(bridge) == "ready" && authorityCalls == 1 && bridge.PublicationMode == PlayerPresenceVisibilityMode.Online,
                "explicit authority write confirms only its current generation and revision");
            realtimeStatus = 3;
            Check(bridge.PublicationMode == PlayerPresenceVisibilityMode.Invisible,
                "remote invisibility overrides an older confirmed online preference");
            realtimeStatus = null;
            Check(bridge.PublicationMode == PlayerPresenceVisibilityMode.Invisible,
                "disconnection cannot publish using an older confirmation");
            realtimeStatus = 1;
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
