using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static partial class SharingReviewRegressionTests
{
    internal static async Task M04k()
    {
        var failures = 0;
        foreach (var (name, run) in new (string, Func<Task>)[] {
            ("room without policy stays paused across restart until explicit resume", () => RoomPauseRestart(null)),
            ("room without policy retains pending pause after failed write", RoomPauseWithoutPolicyRetry),
            ("nonmember without policy preserves all file counts and bytes", () => NonmemberLoopReadOnly(null)),
            ("fresh explicit stop leaves revision zero and creates no files", FreshExplicitStop),
            ("explicit stop preserves room pause and pending withdrawal", PausedExplicitStop),
            ("failed fresh withdrawal persists a real retry obligation", FailedFreshWithdrawal),
            ("empty metadata no-op validates revision and creates no files", EmptyMetadataRevision),
        })
        {
            try { await run(); Console.WriteLine("PASS M04k " + name); }
            catch (Exception error) { failures++; Console.WriteLine("FAIL M04k " + name + ": " + error.Message); }
        }
        Check(failures == 0, "M04k regression failures");
    }

    private static async Task RoomPauseWithoutPolicyRetry()
    {
        var root = Directory.CreateTempSubdirectory("room-no-policy-retry-").FullName;
        try
        {
            using var f = new M04jRoom(root);
            Check(f.Store.Read(f.Owner).Revision == 0, "fixture must start without a saved policy");
            await f.Renew();
            Check(f.Transport.Posts == 1, "membership initially renews without telemetry consent");
            var directory = Path.Combine(root, "privacy-local-v1");
            Directory.CreateDirectory(directory);
            var hash = (string)typeof(LocalPrivacyStore).GetMethod("ResolvedHash", PrivateInstance)!.Invoke(f.Store, [f.Owner])!;
            var pendingField = typeof(PrivacyPublication).GetField("_pendingPause", PrivateInstance)!;
            using (var held = new FileStream(Path.Combine(directory, hash + ".json.lock"),
                FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
            {
                SetM04gObservation(f.Host, 3);
                await f.Main.TickAsync();
                Check(pendingField.GetValue(f.Main) is not null, "failed pause write must retain _pendingPause");
                Check(!new LocalPrivacyStore(root).IsPublicationPaused(f.Owner), "failed write cannot claim durability");
                SetM04gObservation(f.Host, 1);
                await f.Main.TickAsync();
                await f.Renew();
                Check(pendingField.GetValue(f.Main) is not null && f.Transport.Posts == 1,
                    "ordinary online reads cannot drop the failed-write obligation or resume renewals");
            }
            await f.Main.TickAsync();
            Check(pendingField.GetValue(f.Main) is null && new LocalPrivacyStore(root).IsPublicationPaused(f.Owner),
                "retry after storage recovery persists pause before clearing _pendingPause");
            Check(!f.Store.HasPublicationConsent(f.Owner) && f.Store.Read(f.Owner).Settings?.PublicationEnabled == false,
                "new pause record must not enable publication or grant consent");
            using var restarted = new M04jRoom(root);
            SetM04gObservation(restarted.Host, 1);
            await restarted.Main.TickAsync();
            await restarted.Renew();
            Check(restarted.Transport.Posts == 0, "retried pause survives runtime reconstruction");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task FreshExplicitStop()
    {
        var root = Directory.CreateTempSubdirectory("privacy-no-policy-revoke-").FullName;
        try
        {
            using var f = new M04jRoom(root);
            var before = Directory.GetFiles(root, "*", SearchOption.AllDirectories).ToDictionary(p => p, File.ReadAllBytes);
            Check(await f.Main.StopAsync(default, explicitRequest: true), "fresh explicit stop succeeds");
            Check(f.Store.Read(f.Owner).Revision == 0 && !f.Store.HasPublicationConsent(f.Owner),
                "fresh stop cannot manufacture a saved revision or consent");
            Check(before.Count == Directory.GetFiles(root, "*", SearchOption.AllDirectories).Length &&
                before.All(pair => pair.Value.SequenceEqual(File.ReadAllBytes(pair.Key))),
                "fresh stop creates no files and changes no bytes");
            Check(!Directory.Exists(Path.Combine(root, "privacy-local-v1")), "fresh stop creates no policy directory");
            Check(f.Store.Save(f.Owner, 0, Guid.NewGuid().ToString("N"), LocalPrivacySettings.EditorDefaults, () => true).Revision == 1,
                "first editor save still succeeds against revision zero");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task PausedExplicitStop()
    {
        var root = Directory.CreateTempSubdirectory("privacy-paused-stop-").FullName;
        try
        {
            using var f = new M04jRoom(root);
            await f.Renew();
            SetM04gObservation(f.Host, 3);
            await f.Main.TickAsync();
            var revision = f.Store.Read(f.Owner).Revision;
            Check(revision == 1 && f.Store.IsPublicationPaused(f.Owner), "room pause creates minimal durable record");
            var fail = true;
            typeof(PrivacyPublication).GetField("_send", PrivateInstance)!.SetValue(f.Main,
                new Func<PrivacyPublicationInput, System.Text.Json.JsonElement, CancellationToken, Task>((_, body, _) => {
                    Check(!body.GetProperty("online").GetBoolean(), "stop never publishes positive state");
                    return fail ? Task.FromException(new IOException("fixture clear unavailable")) : Task.CompletedTask;
                }));
            Check(!await f.Main.StopAsync(default, explicitRequest: true) && f.Main.ClearPending,
                "failed explicit stop retains withdrawal obligation");
            var restarted = new LocalPrivacyStore(root);
            Check(restarted.Read(f.Owner).Revision == revision && restarted.IsPublicationPaused(f.Owner) &&
                restarted.IsPublicationRevoked(f.Owner) && !restarted.HasPublicationConsent(f.Owner),
                "stop preserves durable pause, revision and revocation without consent");
            fail = false;
            Check(await f.Main.StopAsync(default, explicitRequest: true) && !f.Main.ClearPending,
                "explicit retry fulfills retained withdrawal obligation");
            Check(new LocalPrivacyStore(root).IsPublicationPaused(f.Owner), "successful withdrawal retains room pause");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task EmptyMetadataRevision()
    {
        var root = Directory.CreateTempSubdirectory("privacy-empty-metadata-").FullName;
        try
        {
            var owner = new BridgeAccountContext("fixture", "fixture-authority", "fixture-subject");
            var store = new LocalPrivacyStore(root);
            await store.SetPublicationPausedAsync(owner, 0, false, () => true);
            Check(Directory.GetFiles(root, "*", SearchOption.AllDirectories).Length == 0,
                "clearing an absent pause is read-only");
            try
            {
                await store.SetPublicationPausedAsync(owner, 1, true, () => true);
                throw new InvalidOperationException("stale revision must conflict instead of discarding a pause");
            }
            catch (LocalPrivacyException error) { Check(error.Code == "privacy_local.conflict", "stale revision error"); }
            Check(Directory.GetFiles(root, "*", SearchOption.AllDirectories).Length == 0, "conflict must not create files");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task FailedFreshWithdrawal()
    {
        var root = Directory.CreateTempSubdirectory("privacy-fresh-withdrawal-").FullName;
        try
        {
            using (var f = new M04jRoom(root))
            {
                typeof(PrivacyPublication).GetField("_send", PrivateInstance)!.SetValue(f.Main,
                    new Func<PrivacyPublicationInput, System.Text.Json.JsonElement, CancellationToken, Task>((_, _, _) =>
                        Task.FromException(new IOException("fixture clear unavailable"))));
                Check(!await f.Main.StopAsync(default, explicitRequest: true) && f.Main.ClearPending,
                    "failed fresh clear retains an actual withdrawal obligation");
                var saved = new LocalPrivacyStore(root);
                Check(saved.Read(f.Owner).Revision == 1 && saved.IsPublicationRevoked(f.Owner) &&
                    !saved.HasPublicationConsent(f.Owner), "actual obligation creates a minimal revoked record");
                Check(saved.Read(f.Owner).Settings is { PublicationEnabled: false } settings &&
                    settings.Fleet.Fields == PlayerSharedStateFields.None && settings.Room.Fields == PlayerSharedStateFields.None,
                    "withdrawal record grants no positive sharing fields");
            }
            using var restarted = new M04jRoom(root);
            Check(await restarted.Main.StopAsync(default, explicitRequest: true), "withdrawal can complete after restart");
            Check(restarted.Store.Read(restarted.Owner).Revision == 1 && restarted.Store.IsPublicationRevoked(restarted.Owner),
                "completed withdrawal preserves remembered revocation");
        }
        finally { Directory.Delete(root, true); }
    }
}
