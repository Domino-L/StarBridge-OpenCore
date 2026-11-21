using System.Net;
using System.Reflection;
using System.Text;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.LegacyRelay;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

// Account plan item 8 (owner-alias-073/DESIGN.md, MIGRATION-INTERFACE-073.md).
internal static class OwnerAlias073Tests
{
    private const string LegacyId = "Synthetic-Legacy-ID";

    internal static async Task<int> Run()
    {
        var failures = 0;
        var cases = new (string, Func<Task>)[] {
            ("MigratedOwnerKeepsTheSameFiveFiles", MigratedOwnerKeepsTheSameFiveFiles),
            ("AliasSurvivesRelayOutageAndRestart", AliasSurvivesRelayOutageAndRestart),
            ("RollbackRoundTripKeepsFiles", RollbackRoundTripKeepsFiles),
            ("AliasIsPerScmIdentity", AliasIsPerScmIdentity),
            ("LiveOwnerConflictPauses", LiveOwnerConflictPauses),
            ("UnlinkAfterMigrationKeepsAlias", UnlinkAfterMigrationKeepsAlias),
            ("NoAliasBeforeMigration", NoAliasBeforeMigration),
            ("AliasStoreRejectsOverwriteAndKeepsCorruptFile", AliasStoreRejectsOverwriteAndKeepsCorruptFile),
            ("AliasStoreConcurrentHostsKeepEveryEntry", AliasStoreConcurrentHostsKeepEveryEntry),
            ("AliasStoreRefusesLinkedDataRoot", AliasStoreRefusesLinkedDataRoot),
            ("AliasStoreFileBrokenAfterLoad", AliasStoreFileBrokenAfterLoad),
            ("RelayClientsNeverFollowRedirects", RelayClientsNeverFollowRedirects),
            ("RealtimeGatewayStaysOnRelayOrigin", RealtimeGatewayStaysOnRelayOrigin),
            ("RelaySessionMigratedAnswer", RelaySessionMigratedAnswer),
            ("EveryRelayClientSendsVersion", EveryRelayClientSendsVersion),
        };
        foreach (var (name, run) in cases)
        {
            try
            {
                using (IdentityGateJournal.Capture((_, _) => { })) await run();
                Console.WriteLine("PASS ALIAS073 " + name);
            }
            catch (Exception error) { failures++; Console.WriteLine("FAIL ALIAS073 " + name + " " + error.GetType().Name + " " + error.Message); }
        }
        Console.WriteLine($"ALIAS073 owner alias: {cases.Length - failures} passed, {failures} failed");
        return failures;
    }

    // The "ready" path and the alias path must resolve the identical owner, so every
    // store derives the identical file name, and nothing but the alias file changes.
    private static async Task MigratedOwnerKeepsTheSameFiveFiles()
    {
        var root = Directory.CreateTempSubdirectory("sb-alias073-files-").FullName;
        try
        {
            using var legacy = Legacy();
            var legacyOwner = new BridgeAccountContext("development", legacy.AuthorityId, LegacyId);
            var stores = Seed(root, legacyOwner);
            var session = Session("fixture-subject");

            BridgeAccountContext readyOwner;
            string[] readyFiles;
            {
                var relay = new Relay { State = LegacyRelayAccessState.Ready };
                using var reader = new S2CompatibilityReader(new Coordinator(), relay);
                using var host = Host(session, reader, legacy, new LocalOwnerAliasStore(root));
                await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
                readyOwner = host.ResolveLocalDataOwner(host.CurrentContext!);
                readyFiles = stores.Touch(host);
                Check(host.LocalDataOwnerAliasState(host.CurrentContext!) == "none", "no alias before migration");
                Check(!File.Exists(Path.Combine(root, LocalOwnerAliasStore.FileName)), "ready must not write an alias");
            }
            var before = Snapshot(root);
            {
                var relay = new Relay { State = LegacyRelayAccessState.Migrated };
                using var reader = new S2CompatibilityReader(new Coordinator(), relay);
                using var host = Host(session, reader, legacy, new LocalOwnerAliasStore(root));
                var state = await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
                Check(state.RelayState == "migrated" && !state.LegacyFeaturesAvailable && state.AvailableActions.Count == 0,
                    "migrated projection");
                Check(host.LocalDataOwnerAliasState(host.CurrentContext!) == "written", "result page sees the alias");
                var aliasOwner = host.ResolveLocalDataOwner(host.CurrentContext!);
                Check(aliasOwner == readyOwner && aliasOwner == legacyOwner &&
                    string.Equals(aliasOwner.Subject, readyOwner.Subject, StringComparison.Ordinal) &&
                    string.Equals(aliasOwner.Authority, readyOwner.Authority, StringComparison.Ordinal),
                    "alias owner must equal the ready owner byte for byte");
                var aliasFiles = stores.Touch(host);
                Check(aliasFiles.SequenceEqual(readyFiles), "all five stores must read the same values through the alias");
            }
            var after = Snapshot(root);
            var aliasPath = Path.Combine(root, LocalOwnerAliasStore.FileName);
            Check(after.Keys.Except(before.Keys).Order(StringComparer.Ordinal).SequenceEqual([aliasPath, aliasPath + ".lock"]) &&
                new FileInfo(aliasPath + ".lock").Length == 0,
                "only the alias file and its empty lock file may appear");
            Check(before.All(pair => after.TryGetValue(pair.Key, out var bytes) && bytes.SequenceEqual(pair.Value)),
                "no business file may move, change or disappear");
        }
        finally { Directory.Delete(root, true); }
    }

    // 0.7.3 -> rollback to 0.7.2.1 -> 0.7.3 again (scheduler 11-06). The middle step is
    // 0.7.2.1-shaped: no alias store, and the relay answers its compatibility read
    // with 426, which it reports as "unavailable". File list and bytes never change.
    private static async Task RollbackRoundTripKeepsFiles()
    {
        var root = Directory.CreateTempSubdirectory("sb-alias073-rollback-").FullName;
        try
        {
            using var legacy = Legacy();
            var legacyOwner = new BridgeAccountContext("development", legacy.AuthorityId, LegacyId);
            var stores = Seed(root, legacyOwner);
            var session = Session("fixture-subject");
            using (var reader = new S2CompatibilityReader(new Coordinator(), new Relay { State = LegacyRelayAccessState.Migrated }))
            using (var host = Host(session, reader, legacy, new LocalOwnerAliasStore(root)))
            {
                await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
                stores.Touch(host);
            }
            var upgraded = Snapshot(root);
            Check(upgraded.ContainsKey(Path.Combine(root, LocalOwnerAliasStore.FileName)), "0.7.3 wrote the alias");
            using (var reader = new S2CompatibilityReader(new Coordinator(), new Relay { State = LegacyRelayAccessState.Unavailable }))
            using (var host = Host(session, reader, legacy, null))
            {
                try { await host.GetCompatibilityStateAsync(host.CurrentContext!, default); } catch (AccountBridgeHostException) { }
                try { host.ResolveLocalDataOwner(host.CurrentContext!); throw new Exception("rolled-back client found an owner"); }
                catch (StarBridge.HostRuntime.Privacy.LocalPrivacyOwnerUnavailableException) { }
                stores.Privacy.ResolveOwner = stores.Profile.ResolveOwner = stores.Hangar.ResolveOwner =
                    stores.Log.ResolveOwner = stores.Time.ResolveOwner = host.ResolveLocalDataOwner;
                var owner = host.CurrentContext!;
                foreach (var write in new Action[] {
                    () => stores.Hangar.Save(owner, 1, "rollback-save",
                        [new StarBridge.Core.Hangar.CollectedHangarShip("synthetic-pledge", 0, "Aurora MR", null, null)], false, false),
                    () => stores.Privacy.Read(owner),
                    () => stores.Profile.Read(owner),
                    () => stores.Log.Open(owner).Dispose(),
                    () => stores.Time.Open(owner).Dispose(),
                })
                {
                    try { write(); throw new Exception("rolled-back client touched a store without an owner"); }
                    catch (Exception error) when (error.Message != "rolled-back client touched a store without an owner") { }
                }
            }
            var rolledBack = Snapshot(root);
            using (var reader = new S2CompatibilityReader(new Coordinator(), new Relay { State = LegacyRelayAccessState.Unavailable }))
            using (var host = Host(session, reader, legacy, new LocalOwnerAliasStore(root)))
            {
                Check(host.ResolveLocalDataOwner(host.CurrentContext!) == legacyOwner, "re-upgrade resolves at once");
                stores.Touch(host);
            }
            var reupgraded = Snapshot(root);
            foreach (var (name, later) in new[] { ("rollback", rolledBack), ("re-upgrade", reupgraded) })
                Check(later.Count == upgraded.Count && upgraded.All(pair => later.TryGetValue(pair.Key, out var bytes) &&
                    bytes.SequenceEqual(pair.Value)), name + " changed the data directory");
        }
        finally { Directory.Delete(root, true); }
    }

    // build 66: ownership no longer depends on a minute-by-minute relay answer.
    private static async Task AliasSurvivesRelayOutageAndRestart()
    {
        var root = Directory.CreateTempSubdirectory("sb-alias073-outage-").FullName;
        try
        {
            using var legacy = Legacy();
            var legacyOwner = new BridgeAccountContext("development", legacy.AuthorityId, LegacyId);
            var stores = Seed(root, legacyOwner);
            var session = Session("fixture-subject");
            var relay = new Relay { State = LegacyRelayAccessState.Migrated };
            var clock = new Clock();
            using (var reader = new S2CompatibilityReader(new Coordinator(), relay))
            using (var host = Host(session, reader, legacy, new LocalOwnerAliasStore(root), clock))
            {
                await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
                relay.State = LegacyRelayAccessState.Unavailable;
                try { await host.GetCompatibilityStateAsync(host.CurrentContext!, default); } catch (AccountBridgeHostException) { }
                clock.Advance(TimeSpan.FromMinutes(30));
                Check(host.ResolveLocalDataOwner(host.CurrentContext!) == legacyOwner, "alias must outlive a relay outage");
                stores.Touch(host);
            }
            // A new process that never reaches the relay still owns the same files.
            var coordinator = new Coordinator { Failure = true };
            using (var reader = new S2CompatibilityReader(coordinator, new Relay { State = LegacyRelayAccessState.Unavailable }))
            using (var host = Host(session, reader, legacy, new LocalOwnerAliasStore(root), new Clock()))
            {
                Check(host.ResolveLocalDataOwner(host.CurrentContext!) == legacyOwner,
                    "restart must resolve from the alias without any compatibility read");
                stores.Touch(host);
            }
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task AliasIsPerScmIdentity()
    {
        var root = Directory.CreateTempSubdirectory("sb-alias073-other-").FullName;
        try
        {
            using var legacy = Legacy();
            using (var reader = new S2CompatibilityReader(new Coordinator(), new Relay { State = LegacyRelayAccessState.Migrated }))
            using (var host = Host(Session("fixture-subject"), reader, legacy, new LocalOwnerAliasStore(root)))
                await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
            using (var reader = new S2CompatibilityReader(new Coordinator { Linked = false }, new Relay()))
            using (var host = Host(Session("another-subject"), reader, legacy, new LocalOwnerAliasStore(root)))
            {
                try { host.ResolveLocalDataOwner(host.CurrentContext!); throw new Exception("another SCM identity borrowed the alias"); }
                catch (StarBridge.HostRuntime.Privacy.LocalPrivacyOwnerUnavailableException) { }
                await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
                Check(host.ResolveLocalDataOwner(host.CurrentContext!) == host.CurrentContext, "unlinked identity keeps its own files");
            }
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task LiveOwnerConflictPauses()
    {
        var root = Directory.CreateTempSubdirectory("sb-alias073-conflict-").FullName;
        try
        {
            using var legacy = Legacy();
            var session = Session("fixture-subject");
            var entries = new List<string>();
            using var reader = new S2CompatibilityReader(new Coordinator(), new Relay { State = LegacyRelayAccessState.Migrated });
            using var host = Host(session, reader, legacy, new LocalOwnerAliasStore(root));
            var scm = host.CurrentContext!;
            var older = new BridgeAccountContext(scm.Environment, legacy.AuthorityId, "Older-Legacy");
            Check(new LocalOwnerAliasStore(root).Record(scm, older) == LocalOwnerAliasStore.RecordResult.Written, "seed alias");
            using (IdentityGateJournal.Capture((stage, code) => entries.Add(stage + " " + code)))
            {
                await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
                try { host.ResolveLocalDataOwner(host.CurrentContext!); throw new Exception("conflict chose an owner"); }
                catch (StarBridge.HostRuntime.Privacy.LocalPrivacyOwnerUnavailableException) { }
            }
            Check(entries.Any(e => e.Contains("alias-conflict")), "conflict must be journaled");
            Check(host.LocalDataOwnerAliasState(scm) == "conflict", "result page sees the conflict");
            Check(new LocalOwnerAliasStore(root).TryGet(scm, out var kept) && kept == older, "existing alias is never overwritten");
        }
        finally { Directory.Delete(root, true); }
    }

    // MIGRATION-INTERFACE-073 §5: once written, only the local alias counts.
    private static async Task UnlinkAfterMigrationKeepsAlias()
    {
        var root = Directory.CreateTempSubdirectory("sb-alias073-unlink-").FullName;
        try
        {
            using var legacy = Legacy();
            var legacyOwner = new BridgeAccountContext("development", legacy.AuthorityId, LegacyId);
            var coordinator = new Coordinator();
            var relay = new Relay { State = LegacyRelayAccessState.Migrated };
            using var reader = new S2CompatibilityReader(coordinator, relay);
            using var host = Host(Session("fixture-subject"), reader, legacy, new LocalOwnerAliasStore(root));
            await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
            coordinator.Linked = false;
            await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
            Check(host.ResolveLocalDataOwner(host.CurrentContext!) == legacyOwner, "SCM unlink must not split local data");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task NoAliasBeforeMigration()
    {
        var root = Directory.CreateTempSubdirectory("sb-alias073-before-").FullName;
        try
        {
            using var legacy = Legacy();
            foreach (var state in new[] { LegacyRelayAccessState.Ready, LegacyRelayAccessState.Unavailable,
                         LegacyRelayAccessState.AccountMismatch, LegacyRelayAccessState.AuthorizationRequired })
            {
                using var reader = new S2CompatibilityReader(new Coordinator(), new Relay { State = state });
                using var host = Host(Session("fixture-subject"), reader, legacy, new LocalOwnerAliasStore(root));
                try { await host.GetCompatibilityStateAsync(host.CurrentContext!, default); } catch (AccountBridgeHostException) { }
            }
            Check(!File.Exists(Path.Combine(root, LocalOwnerAliasStore.FileName)), "only a migrated answer writes an alias");
            // A host without an alias store keeps the 0.7.2 behaviour exactly.
            using (var reader = new S2CompatibilityReader(new Coordinator(), new Relay { State = LegacyRelayAccessState.Migrated }))
            using (var host = Host(Session("fixture-subject"), reader, legacy, null))
            {
                await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
                Check(host.ResolveLocalDataOwner(host.CurrentContext!).Subject == LegacyId, "verified migrated owner still binds");
                Check(!File.Exists(Path.Combine(root, LocalOwnerAliasStore.FileName)), "no store, no file");
            }
        }
        finally { Directory.Delete(root, true); }
    }

    private static Task AliasStoreRejectsOverwriteAndKeepsCorruptFile()
    {
        var root = Directory.CreateTempSubdirectory("sb-alias073-store-").FullName;
        try
        {
            var scm = new BridgeAccountContext("development", "scm", "subject");
            var legacy = new BridgeAccountContext("development", "relay", LegacyId);
            var store = new LocalOwnerAliasStore(root);
            Check(store.Record(scm, legacy) == LocalOwnerAliasStore.RecordResult.Written, "first write");
            Check(store.Record(scm, legacy) == LocalOwnerAliasStore.RecordResult.AlreadyRecorded, "same write");
            Check(store.Record(scm, legacy with { Subject = "other" }) == LocalOwnerAliasStore.RecordResult.Conflict, "no overwrite");
            Check(store.Record(scm, legacy with { Environment = "production" }) == LocalOwnerAliasStore.RecordResult.Failed, "same environment only");
            Check(store.Record(legacy, legacy) == LocalOwnerAliasStore.RecordResult.Failed, "no self alias");
            var raw = File.ReadAllBytes(store.FilePath);
            var latin = Encoding.Latin1.GetString(raw);
            Check(!latin.Contains(LegacyId, StringComparison.Ordinal) && !Encoding.Unicode.GetString(raw).Contains(LegacyId, StringComparison.Ordinal),
                "the legacy ID is stored only encrypted");
            Check(new LocalOwnerAliasStore(root).TryGet(scm, out var read) && read == legacy &&
                read.Subject == LegacyId, "round trip keeps exact case");
            var second = new LocalOwnerAliasStore(root);
            Check(second.TryGet(scm, out _), "second owner loads");
            Check(store.Record(scm with { Subject = "late" }, legacy) == LocalOwnerAliasStore.RecordResult.Written, "late entry");
            Check(second.Record(scm with { Subject = "parallel" }, legacy) == LocalOwnerAliasStore.RecordResult.Written &&
                new LocalOwnerAliasStore(root).TryGet(scm with { Subject = "late" }, out _),
                "a second owner on the same root must not drop the other's entry");
            for (var i = 0; i < LocalOwnerAliasStore.MaximumEntries - 3; i++)
                Check(store.Record(scm with { Subject = "s" + i }, legacy) == LocalOwnerAliasStore.RecordResult.Written, "fill");
            Check(store.Record(scm with { Subject = "overflow" }, legacy) == LocalOwnerAliasStore.RecordResult.Full, "bounded");
            Check(Directory.GetFiles(root, "*.tmp").Length == 0, "no temporary file left");

            // Tampered: set aside (never deleted), then rebuilt only through Record.
            var tampered = File.ReadAllBytes(store.FilePath);
            tampered[tampered.Length / 2] ^= 0x5A;
            File.WriteAllBytes(store.FilePath, tampered);
            var reopened = new LocalOwnerAliasStore(root);
            Check(!reopened.TryGet(scm, out _), "tampered alias must not be used");
            var aside = Directory.GetFiles(root, "local-owner-aliases.corrupt-*.bin");
            Check(aside.Length == 1 && File.ReadAllBytes(aside[0]).SequenceEqual(tampered), "corrupt file kept for inspection, unchanged");
            Check(reopened.Record(scm, legacy) == LocalOwnerAliasStore.RecordResult.Written, "rebuilt after set-aside");
        }
        finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }

    private static async Task RelaySessionMigratedAnswer()
    {
        var session = Session("fixture-subject");
        foreach (var (status, body, expected) in new (HttpStatusCode, string, LegacyRelayAccessState)[] {
            (HttpStatusCode.Conflict, $$"""{"code":"legacy_account_migrated","legacyAccountId":"{{LegacyId}}"}""", LegacyRelayAccessState.Migrated),
            // Main fleet 11-06: the relay compares legacy IDs ignoring case, so the client does too.
            (HttpStatusCode.Conflict, """{"code":"legacy_account_migrated","legacyAccountId":"synthetic-legacy-id"}""", LegacyRelayAccessState.Migrated),
            (HttpStatusCode.Conflict, """{"code":"legacy_account_migrated","legacyAccountId":"Other-Legacy-ID"}""", LegacyRelayAccessState.AccountMismatch),
            (HttpStatusCode.Conflict, """{"code":"account_migrating"}""", LegacyRelayAccessState.Unavailable),
            (HttpStatusCode.Conflict, "not json", LegacyRelayAccessState.Unavailable),
            ((HttpStatusCode)426, """{"code":"client_upgrade_required"}""", LegacyRelayAccessState.Unavailable),
            (HttpStatusCode.OK, $$"""{"accountId":"{{LegacyId}}"}""", LegacyRelayAccessState.Ready),
        })
        {
            var handler = new Recording(status, body);
            using var client = new LegacyRelayAccountClient(new HttpClient(handler), new Uri("https://relay.example.invalid/"));
            var state = await client.EstablishAsync(session, LegacyId, default);
            Check(state == expected, $"{(int)status} {body} -> {state}, expected {expected}");
            Check(handler.Versions.Single() == RelayClientVersion.Value, "session request carries the client version");
        }
        // The relay may spell the ID in another case; the alias still stores the SCM
        // link's ID exactly as the ready path passes it to ResolveLocalDataOwner, so
        // all five stores keep deriving the same file names.
        var root = Directory.CreateTempSubdirectory("sb-alias073-case-").FullName;
        try
        {
            using var legacy = Legacy();
            var lower = new Recording(HttpStatusCode.Conflict,
                $$"""{"code":"legacy_account_migrated","legacyAccountId":"{{LegacyId.ToLowerInvariant()}}"}""");
            using (var relay = new LegacyRelayAccountClient(new HttpClient(lower), new Uri("https://relay.example.invalid/")))
            using (var reader = new S2CompatibilityReader(new Coordinator(), relay))
            using (var host = Host(session, reader, legacy, new LocalOwnerAliasStore(root)))
            {
                var state = await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
                Check(state.RelayState == "migrated", "case-only difference is the same account");
                Check(new LocalOwnerAliasStore(root).TryGet(host.CurrentContext!, out var target) &&
                    string.Equals(target.Subject, LegacyId, StringComparison.Ordinal) &&
                    host.ResolveLocalDataOwner(host.CurrentContext!) == target,
                    "alias keeps the SCM link's spelling byte for byte");
            }
        }
        finally { Directory.Delete(root, true); }
        Check(RelayClientVersion.Value.Split('.').Length == 4 && RelayClientVersion.Value.StartsWith("0.7.3", StringComparison.Ordinal),
            "four-part product version: " + RelayClientVersion.Value);
        Check(RelayClientVersion.Format(new Version(0, 7, 3)) == "0.7.3.0", "missing parts become zero");
    }

    // Every HttpClient that talks to the Japan relay carries the header from construction.
    // CX-OWNER-ALIAS-073-R #1: two Host processes share one data root. Separate store
    // instances have separate in-process gates, so only the lock file serializes them.
    private static Task AliasStoreConcurrentHostsKeepEveryEntry()
    {
        var legacy = new BridgeAccountContext("development", "relay", LegacyId);
        for (var round = 0; round < 5; round++)
        {
            var root = Directory.CreateTempSubdirectory("sb-alias073-race-").FullName;
            try
            {
                var hosts = new[] { new LocalOwnerAliasStore(root), new LocalOwnerAliasStore(root) };
                using var start = new Barrier(LocalOwnerAliasStore.MaximumEntries);
                var results = Enumerable.Range(0, LocalOwnerAliasStore.MaximumEntries).Select(i => Task.Run(() =>
                {
                    start.SignalAndWait();
                    return hosts[i % 2].Record(new BridgeAccountContext("development", "scm", "subject-" + i), legacy);
                })).ToArray();
                Task.WaitAll(results);
                Check(results.All(r => r.Result == LocalOwnerAliasStore.RecordResult.Written),
                    "every concurrent write lands: " + string.Join(",", results.Select(r => r.Result)));
                var fresh = new LocalOwnerAliasStore(root);
                Check(Enumerable.Range(0, LocalOwnerAliasStore.MaximumEntries).All(i =>
                    fresh.TryGet(new BridgeAccountContext("development", "scm", "subject-" + i), out _)),
                    "no Host drops the other Host's entry");

                // Same SCM identity, two different targets at once: one wins, the other pauses.
                var scm = new BridgeAccountContext("development", "scm", "contested");
                var contestedRoot = Directory.CreateTempSubdirectory("sb-alias073-race-c-").FullName;
                try
                {
                    var pair = new[] { new LocalOwnerAliasStore(contestedRoot), new LocalOwnerAliasStore(contestedRoot) };
                    using var gate = new Barrier(2);
                    var contested = Enumerable.Range(0, 2).Select(i => Task.Run(() =>
                    {
                        gate.SignalAndWait();
                        return pair[i].Record(scm, legacy with { Subject = "target-" + i });
                    })).ToArray();
                    Task.WaitAll(contested);
                    Check(contested.Count(r => r.Result == LocalOwnerAliasStore.RecordResult.Written) == 1 &&
                        contested.Count(r => r.Result == LocalOwnerAliasStore.RecordResult.Conflict) == 1,
                        "one target is recorded and the other is a conflict: " + string.Join(",", contested.Select(r => r.Result)));
                }
                finally { Directory.Delete(contestedRoot, true); }
            }
            finally { Directory.Delete(root, true); }
        }
        return Task.CompletedTask;
    }

    // #2: a junction at the data root or any directory above it is never followed.
    private static Task AliasStoreRefusesLinkedDataRoot()
    {
        var fixture = Path.Combine(Path.GetTempPath(), "StarBridge-owner-alias-junction-" + Guid.NewGuid().ToString("N"));
        var target = Path.Combine(Path.GetTempPath(), "StarBridge-owner-alias-junction-" + Guid.NewGuid().ToString("N"));
        var link = Path.Combine(fixture, "linked");
        Directory.CreateDirectory(fixture);
        var real = Directory.CreateDirectory(Path.Combine(target, "data")).FullName;
        var scm = new BridgeAccountContext("development", "scm", "subject");
        var legacy = new BridgeAccountContext("development", "relay", LegacyId);
        var created = false;
        try
        {
            Check(new LocalOwnerAliasStore(real).Record(scm, legacy) == LocalOwnerAliasStore.RecordResult.Written, "valid alias behind the link");
            var before = Directory.GetFiles(real).Select(Path.GetFileName).Order().ToArray();
            var bytes = File.ReadAllBytes(Path.Combine(real, LocalOwnerAliasStore.FileName));
            CacheFixtureJunction.Create(fixture, link, target);
            created = true;
            foreach (var root in new[] { Path.Combine(link, "data"), link })
            {
                var store = new LocalOwnerAliasStore(root);
                Check(!store.TryGet(scm, out _), "a linked tree is not read: " + root);
                Check(store.Record(scm with { Subject = "new" }, legacy) == LocalOwnerAliasStore.RecordResult.Failed,
                    "a linked tree is not written: " + root);
            }
            Check(Directory.GetFiles(real).Select(Path.GetFileName).Order().SequenceEqual(before) &&
                File.ReadAllBytes(Path.Combine(real, LocalOwnerAliasStore.FileName)).SequenceEqual(bytes),
                "nothing behind the link changed, no lock or set-aside file");
        }
        finally
        {
            if (created) CacheFixtureJunction.Remove(fixture, link); // the link itself, never its target
            Directory.Delete(fixture, true);
            Directory.Delete(target, true);
        }
        return Task.CompletedTask;
    }

    // #3: an instance that already loaded meets a file that went bad afterwards.
    private static Task AliasStoreFileBrokenAfterLoad()
    {
        var root = Directory.CreateTempSubdirectory("sb-alias073-broken-").FullName;
        try
        {
            var scm = new BridgeAccountContext("development", "scm", "subject");
            var legacy = new BridgeAccountContext("development", "relay", LegacyId);
            var store = new LocalOwnerAliasStore(root);
            Check(store.Record(scm, legacy) == LocalOwnerAliasStore.RecordResult.Written && store.TryGet(scm, out _), "loaded");
            foreach (var broken in new[] { Array.Empty<byte>(), new byte[] { 1, 2, 3 } })
            {
                File.WriteAllBytes(store.FilePath, broken);
                var next = scm with { Subject = "after-" + broken.Length };
                Check(store.Record(next, legacy) == LocalOwnerAliasStore.RecordResult.Written,
                    "a broken file is set aside and rebuilt from this call's agreeing sources");
                Check(Directory.GetFiles(root, "local-owner-aliases.corrupt-*.bin").Any(path => File.ReadAllBytes(path).SequenceEqual(broken)),
                    "the broken file is kept unchanged for inspection");
                var fresh = new LocalOwnerAliasStore(root);
                Check(fresh.TryGet(next, out var read) && read == legacy, "the rebuilt file is valid");
            }

            // A lookup (not a write) that finds a bad file sets it aside under the lock, once.
            var reader = new LocalOwnerAliasStore(root);
            File.WriteAllBytes(store.FilePath, [9]);
            var corruptBefore = Directory.GetFiles(root, "local-owner-aliases.corrupt-*.bin").Length;
            Check(!reader.TryGet(scm, out _), "bad file is not used");
            Check(Directory.GetFiles(root, "local-owner-aliases.corrupt-*.bin").Length == corruptBefore + 1, "set aside once");
        }
        finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }

    // #4: no relay client follows a redirect (header, bearer or password body to another host).
    private static Task RelayClientsNeverFollowRedirects()
    {
        static HttpMessageHandler Handler(HttpClient client) => (HttpMessageHandler)typeof(HttpMessageInvoker)
            .GetField("_handler", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(client)!;
        using var made = RelayClientVersion.NewClient(TimeSpan.FromSeconds(8));
        Check(Handler(made) is HttpClientHandler { AllowAutoRedirect: false } &&
            made.DefaultRequestHeaders.GetValues(RelayClientVersion.HeaderName).Single() == RelayClientVersion.Value &&
            made.Timeout == TimeSpan.FromSeconds(8), "shared relay client: no redirects, version header");
        using var account = new LegacyRelayAccountClient(new Uri("https://relay.example.invalid/"));
        var inner = (HttpClient)typeof(LegacyRelayAccountClient).GetField("_httpClient", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(account)!;
        Check(Handler(inner) is HttpClientHandler { AllowAutoRedirect: false }, "legacy relay account client does not follow redirects");
        // Same fallback as the other source checks: official gates run from the repository root.
        var workspace = Environment.GetEnvironmentVariable("STARBRIDGE_TEST_WORKSPACE_ROOT") ?? Environment.CurrentDirectory;
        var source = File.ReadAllText(Path.Combine(workspace, "StarBridge.HostRuntime", "Account", "S2CompatibilityReader.cs"));
        Check(source.Contains("RelayClientVersion.NewClient(", StringComparison.Ordinal) &&
            !source.Contains("new HttpClient", StringComparison.Ordinal), "S2 compatibility relay client uses the no-redirect client");
        return Task.CompletedTask;
    }

    // #5: the ticket's gateway is a path on the relay origin, never another host.
    private static Task RealtimeGatewayStaysOnRelayOrigin()
    {
        var origin = new Uri("https://relay.example.invalid/");
        var ok = StarBridge.HostRuntime.Realtime.RelayRealtimeClient.GatewayUri(origin, "/ws/realtime", "t k");
        Check(ok is not null && ok.Scheme == "wss" && ok.Host == "relay.example.invalid" && ok.AbsolutePath == "/ws/realtime" &&
            ok.Query == "?ticket=t%20k", "ordinary gateway path: " + ok);
        Check(StarBridge.HostRuntime.Realtime.RelayRealtimeClient.GatewayUri(new Uri("http://127.0.0.1:5080/"), "/ws", "t")?.ToString() == "ws://127.0.0.1:5080/ws?ticket=t",
            "local relay keeps its port");
        foreach (var bad in new[] { "//other.example.invalid/socket", "/\\other.example.invalid/socket", "\\\\other.example.invalid/x",
                     "https://other.example.invalid/ws", "ws", "", "/ws\r\nX: y" })
            Check(StarBridge.HostRuntime.Realtime.RelayRealtimeClient.GatewayUri(origin, bad, "t") is null, "rejected gateway: " + bad);
        return Task.CompletedTask;
    }

    private static async Task EveryRelayClientSendsVersion()
    {
        var origin = new Uri("https://relay.example.invalid/");
        var root = Directory.CreateTempSubdirectory("sb-alias073-clients-").FullName;
        try
        {
            using var accountSafety = new AccountSafetyClient(origin, new Recording());
            using var ideas = new AchievementIdeaClient(origin, new Recording());
            using var daily = new DailySupportClient(origin, new Recording());
            using var login = Legacy();
            using var recovery = new LegacyPasswordRecoveryClient(origin, new Recording());
            using var account = new LegacyRelayAccountClient(new HttpClient(new Recording()), origin);
            using var communities = new StarBridge.HostRuntime.Communities.CommunityClient(origin, new Recording());
            using var friends = new StarBridge.HostRuntime.Friends.FriendsReader(origin, new Recording(), realtime: true);
            using var media = new StarBridge.HostRuntime.Hangar.HangarMediaClient(origin, new Recording());
            using var rooms = new StarBridge.HostRuntime.PartyRooms.PartyRoomReader(origin, new Recording());
            using var privacy = new StarBridge.HostRuntime.Privacy.PrivacyRelayWriter(origin, new Recording());
            using var device = new StarBridge.HostRuntime.Sessions.RelayDeviceSession(origin, "device", new Recording());
            using var stats = new AppStatsHeartbeatRuntime(origin, null, StarBridge.HostRuntime.Lifecycle.DeviceNetworkAdmission.Unavailable,
                "0.7.3.0", TimeProvider.System, root, new Recording());
            using var help = new HelpSupportBridgeDispatcher(origin, () => 1, new Recording());
            var owners = new object?[] { accountSafety, ideas, daily, login, recovery, account, communities, friends,
                friends.RealtimeClient, media, rooms, privacy, device, stats, help };
            foreach (var owner in owners)
            {
                Check(owner is not null, "client constructed");
                var clients = owner!.GetType().GetFields(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public)
                    .Where(f => f.FieldType == typeof(HttpClient)).Select(f => (HttpClient?)f.GetValue(owner)).ToArray();
                Check(clients.Length > 0 && clients.All(c => c is not null &&
                    c.DefaultRequestHeaders.TryGetValues(RelayClientVersion.HeaderName, out var v) &&
                    v.Single() == RelayClientVersion.Value), owner.GetType().Name + " lacks the client version header");
            }
            var probe = new Recording();
            await DiagnosticConnectionProbe.CheckAsync(origin, default, probe);
            Check(probe.Versions.Single() == RelayClientVersion.Value, "connection probe carries the client version");
        }
        finally { Directory.Delete(root, true); }
    }

    private sealed record SeededStores(
        StarBridge.HostRuntime.Privacy.LocalPrivacyStore Privacy,
        StarBridge.HostRuntime.Profiles.LocalPersonalProfileStore Profile,
        StarBridge.HostRuntime.Hangar.LocalHangarStore Hangar,
        StarBridge.HostRuntime.Presence.GameLogSettingsStore Log,
        StarBridge.HostRuntime.Presence.GameplayTimeStore Time)
    {
        // Reads all five stores through the host's owner rule; returns what each saw.
        internal string[] Touch(ScmAccountBridgeHost host)
        {
            Privacy.ResolveOwner = Profile.ResolveOwner = Hangar.ResolveOwner = Log.ResolveOwner = Time.ResolveOwner =
                host.ResolveLocalDataOwner;
            var owner = host.CurrentContext!;
            using var log = Log.Open(owner);
            using var time = Time.Open(owner);
            var seen = new[] {
                "privacy:" + Privacy.Read(owner).Revision,
                "profile:" + Profile.Read(owner).Content?.CallSign,
                "hangar:" + Hangar.Read(owner).Ships.Single().Title,
                "log:" + log.Read().Channel,
                "time:" + time.Read().Seconds,
            };
            Check(seen.SequenceEqual(["privacy:1", "profile:Original callsign", "hangar:Aurora MR", "log:PTU", "time:3600"]),
                "seeded values: " + string.Join(", ", seen));
            return seen;
        }
    }

    private static SeededStores Seed(string root, BridgeAccountContext owner)
    {
        var privacy = new StarBridge.HostRuntime.Privacy.LocalPrivacyStore(root);
        privacy.Save(owner, 0, Guid.NewGuid().ToString("N"),
            StarBridge.HostRuntime.Privacy.LocalPrivacySettings.EditorDefaults with { PublicationEnabled = false }, () => true);
        var profile = new StarBridge.HostRuntime.Profiles.LocalPersonalProfileStore(root);
        profile.Save(owner, 0, Guid.NewGuid().ToString("N"), new StarBridge.HostRuntime.Profiles.LocalProfileContent(
            "Original callsign", "Original introduction", 1, "none", [new("favorite-ships", 3, true, 0)], null), () => true);
        var hangar = new StarBridge.HostRuntime.Hangar.LocalHangarStore(root);
        hangar.Save(owner, 0, "original-inventory",
            [new StarBridge.Core.Hangar.CollectedHangarShip("synthetic-pledge", 0, "Aurora MR", null, null)], false, false);
        var log = new StarBridge.HostRuntime.Presence.GameLogSettingsStore(root);
        using (var lease = log.Open(owner)) lease.Save(lease.Read(), new(Enabled: false, Channel: "PTU"), () => true);
        var time = new StarBridge.HostRuntime.Presence.GameplayTimeStore(root);
        using (var lease = time.Open(owner))
        {
            var empty = lease.Read();
            lease.Save(empty, empty with { Consent = StarBridge.HostRuntime.Presence.GameplayRecordingConsent.Declined,
                Seconds = 3600, ShowOnProfile = false }, () => true);
        }
        return new(privacy, profile, hangar, log, time);
    }

    private static Dictionary<string, byte[]> Snapshot(string root) =>
        Directory.GetFiles(root, "*", SearchOption.AllDirectories).ToDictionary(path => path, File.ReadAllBytes);

    private static LegacyPasswordLoginClient Legacy() =>
        new(new Uri("https://relay.example.invalid/"), new NoCredentials(), new Recording());

    private static ScmOAuthSession Session(string subject) => new("fixture-scm", subject, "Fixture", "synthetic-token",
        DateTimeOffset.UtcNow.AddMinutes(5), [], GameIdentityHandle: "FixturePilot", GameIdentityStatus: ScmGameIdentityStatus.Verified);

    private static ScmAccountBridgeHost Host(ScmOAuthSession session, S2CompatibilityReader reader,
        LegacyPasswordLoginClient legacy, LocalOwnerAliasStore? aliases, TimeProvider? clock = null) => new(
        new OAuthPkceClient(new ScmHttpClient(new Offline()), new Vault(), ScmOAuthOptions.CreateDefault()),
        new ScmProfileCacheStore(), "development", () => null, initialSession: session,
        compatibilityReader: reader, legacyPasswordLogin: legacy)
        { LocalDataOwnerClock = clock ?? new Clock(), LocalOwnerAliases = aliases };

    private static void Check(bool ok, string message) { if (!ok) throw new Exception(message); }

    private sealed class Clock : TimeProvider
    {
        private long _ticks;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => Interlocked.Read(ref _ticks);
        internal void Advance(TimeSpan duration) => Interlocked.Add(ref _ticks, duration.Ticks);
    }

    private sealed class Recording(HttpStatusCode status = HttpStatusCode.ServiceUnavailable, string body = "") : HttpMessageHandler
    {
        internal readonly List<string?> Versions = [];
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Versions.Add(request.Headers.TryGetValues(RelayClientVersion.HeaderName, out var v) ? v.Single() : null);
            return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") });
        }
    }

    private sealed class Offline : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
    }

    private sealed class NoCredentials : ILegacyMigrationCredentialStore
    {
        public LegacyMigrationCredential? Load() => null;
        public void Save(LegacyMigrationCredential credential) => throw new Exception("Unexpected credential write");
        public void Delete() => throw new Exception("Unexpected credential delete");
    }

    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected delete");
    }

    private sealed class Coordinator : IAccountCompatibilityCoordinator
    {
        internal bool Linked = true, Failure;
        public Task<AccountBridgeCompatibilityProjection> ReadAsync(ScmOAuthSession s, CancellationToken t) =>
            Failure ? Task.FromException<AccountBridgeCompatibilityProjection>(new HttpRequestException()) :
            Task.FromResult(Linked ? new AccountBridgeCompatibilityProjection("linked", "notEstablished", false, false, [], LegacyId)
                : new AccountBridgeCompatibilityProjection("unlinked", "notApplicable", false, false, ["linkExistingAccount"], null));
        public Task<AccountBridgeCompatibilityProjection> LinkExistingAsync(ScmOAuthSession s, LegacyIdentityLinkPasswordCredential? c, CancellationToken t) =>
            throw new Exception("Unexpected link");
        public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(ScmOAuthSession s, CancellationToken t) =>
            throw new Exception("Unexpected provision");
    }

    private sealed class Relay : ILegacyRelayAccountPort
    {
        internal LegacyRelayAccessState State = LegacyRelayAccessState.Ready;
        public Task<LegacyRelayAccessState> EstablishAsync(ScmOAuthSession s, string id, CancellationToken t) => Task.FromResult(State);
        public Task<LegacyRelayProfileReadResult> ReadOwnProfileAsync(ScmOAuthSession s, string id, CancellationToken t) =>
            throw new Exception("Unexpected profile read");
        public void Reset() { }
    }
}
