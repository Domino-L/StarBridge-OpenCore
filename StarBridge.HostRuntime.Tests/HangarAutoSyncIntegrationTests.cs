using System.Text.Json.Nodes;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

internal static class HangarAutoSyncIntegrationTests
{
    internal static async Task Verify()
    {
        await VerifySave(false);
        await VerifySave(true);
        await VerifySave(false, withNonVehicles: true);
    }

    private static async Task VerifySave(bool switchAccount, bool withNonVehicles = false)
    {
        var root = Directory.CreateTempSubdirectory("sb-hangar-auto-sync-");
        var host = new Host();
        try
        {
            var store = new LocalHangarStore(root.FullName);
            using var runtime = new AccountBridgeRuntime(host, localHangar: store);
            var changed = new TaskCompletionSource<BridgeEnvelope>(TaskCreationOptions.RunContinuationsAsynchronously);
            runtime.EventReady += envelope => { if (envelope.Name == "hangarReader.changed") changed.TrySetResult(envelope); };
            using var source = new HangarLockedScanTests.Harness();
            string? operation = null;
            async Task<BridgeDispatchBatch> Send(string action, JsonObject body)
            {
                body["schemaVersion"] = 1;
                if (operation is not null) body["operationId"] = operation;
                return await runtime.DispatchAsync(BridgeEnvelope.Request("hangarReader." + action,
                    Guid.NewGuid().ToString("N"), host.Generation, body, host.CurrentContext));
            }
            operation = (await Send("begin", new())).Response.Payload.GetProperty("operationId").GetString();
            await Send("verify", source.Initial());
            foreach (var (page, document) in new[] { (1, 1), (1, 1), (2, 2), (2, 2), (1, 3), (1, 3) })
            {
                var body = source.Page(page, document);
                if (withNonVehicles)
                {
                    var items = body["observation"]!["page"]!["pledges"]![0]!["items"]!.AsArray();
                    for (var i = 1; i < 4; i++)
                        items.Add(new JsonObject { ["title"] = "Synthetic Vehicle " + i, ["kind"] = "Ship", ["liner"] = "Test Builder" });
                    items.Add(new JsonObject { ["title"] = "Unlisted ancillary item", ["kind"] = null });
                    items.Add(new JsonObject { ["title"] = "Another accessory", ["kind"] = "New Kind" });
                    foreach (var title in new[] { "FBL-8u 'SecondWind' Undersuit", "ADP-mk4 'SecondWind' Core",
                        "ADP-mk4 'SecondWind' Helmet", "ADP-mk4 'SecondWind' Legs", "ADP-mk4 'SecondWind' Arms",
                        "ORC-mkX 'SecondWind' Helmet", "ORC-mkX 'SecondWind' Core", "ORC-mkX 'SecondWind' Arms",
                        "ORC-mkX 'SecondWind' Legs", "FBL-8a 'SecondWind' Helmet", "FBL-8a 'SecondWind' Core",
                        "FBL-8a 'SecondWind' Arms", "FBL-8a 'SecondWind' Legs", "VFG Industrial Hangar",
                        "Reclaimer Name Reservation", "Quirinus Tech Shogun Kiba ‘Akuma’ Helmet", "Quirinus Tech Artimex ‘Akuma’ Core" })
                        items.Add(new JsonObject { ["title"] = title, ["kind"] = null, ["liner"] = null });
                }
                await Send("observe", body);
            }
            var save = Send("save", new() { ["expectedRevision"] = 0, ["confirmEmpty"] = false });
            if (withNonVehicles)
            {
                var result = await save;
                if (result.Response.Error is not null || result.Response.Payload.GetProperty("partial").GetBoolean())
                    throw new Exception("Eight ships plus confirmed non-vehicles must save complete and trigger organization publication.");
                if (store.Read(host.CurrentContext!).Ships.Count != 8)
                    throw new Exception("Non-vehicle exclusions changed ship occurrences.");
            }
            await host.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
            if (store.Read(host.CurrentContext!).Revision != 1) throw new Exception("Local import was not committed.");
            var winner = await Task.WhenAny(save, Task.Delay(200));
            if (winner != save) throw new Exception("Committed local save is blocked behind the organization network upload.");
            if ((await save).Response.Error is not null) throw new Exception("Local success was lost.");
            if (switchAccount) host.Switch();
            host.Release.TrySetResult();
            if (switchAccount)
            {
                await host.Finished.Task.WaitAsync(TimeSpan.FromSeconds(2));
                if (changed.Task.IsCompleted) throw new Exception("Old account upload emitted a refresh after switching.");
            }
            else
            {
                var envelope = await changed.Task.WaitAsync(TimeSpan.FromSeconds(2));
                if (envelope.SessionGeneration != 7) throw new Exception("Upload refresh used another account generation.");
            }
        }
        finally { host.Release.TrySetResult(); root.Delete(true); }
    }

    private sealed class Host : IAccountBridgeHost
    {
        public long Generation { get; private set; } = 7;
        public BridgeAccountContext? CurrentContext => new("development", "synthetic-issuer", "subject-a");
        public HangarAccountIdentity? HangarIdentity => new(CurrentContext!, Generation,
            new(StarBridge.Core.Identity.ScmGameIdentityStatus.Verified, "Pilot_Alpha", "pilot_alpha"));
        public event Action<long>? AccountChanged;
        internal void Switch() { Generation++; AccountChanged?.Invoke(Generation); }
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Finished = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public async Task<HangarPublicationOutcome> UpdateSharedHangarAfterSaveAsync(BridgeAccountContext context, long generation, long revision, CancellationToken token)
        {
            Started.TrySetResult();
            try { await Release.Task.WaitAsync(token); return HangarPublicationOutcome.Complete; }
            finally { Finished.TrySetResult(); }
        }
        private static Task<T> Unexpected<T>() => throw new Exception("Unexpected account operation.");
        public Task<AccountBridgeSessionProjection> GetCurrentAsync(CancellationToken t) => Unexpected<AccountBridgeSessionProjection>();
        public Task<AccountBridgeSessionProjection> LoginAsync(CancellationToken t) => Unexpected<AccountBridgeSessionProjection>();
        public Task CancelLoginAsync() => Task.CompletedTask;
        public Task LogoutAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<bool>();
        public Task<AccountBridgeProfileProjection> GetProfileAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeProfileProjection>();
        public Task<PersonalProfileDocumentContract> GetPersonalProfileAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<PersonalProfileDocumentContract>();
        public Task<PersonalProfileDocumentContract> UpdatePersonalProfileAsync(BridgeAccountContext c, PersonalProfilePresentationUpdateContract p, CancellationToken t) => Unexpected<PersonalProfileDocumentContract>();
        public Task<AccountBridgeOfficialFleetProjection> GetOfficialFleetAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeOfficialFleetProjection>();
        public Task<AccountBridgeCompatibilityProjection> GetCompatibilityStateAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeCompatibilityProjection>();
        public Task<AccountBridgeCompatibilityProjection> LinkLegacyAccountAsync(BridgeAccountContext c, AccountBridgeLegacyCredential? p, CancellationToken t) => Unexpected<AccountBridgeCompatibilityProjection>();
        public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeCompatibilityProjection>();
        public Task<AccountBridgeProfileProjection> PatchPreferencesAsync(BridgeAccountContext c, AccountBridgePreferencePatch p, CancellationToken t) => Unexpected<AccountBridgeProfileProjection>();
        public Task<bool> ClearProfileCacheAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<bool>();
        public Task<AccountBridgeIdentityProjection> GetGameIdentityPolicyAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeIdentityProjection>();
    }
}
