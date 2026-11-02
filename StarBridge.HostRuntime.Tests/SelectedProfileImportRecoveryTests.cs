using System.Text;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Profiles;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using System.Net;
using System.Net.Http.Json;

internal static class SelectedProfileImportRecoveryTests
{
    private static async Task HistoricLabelsAcrossRecovery()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-import-label-recovery-" + Guid.NewGuid().ToString("N"));
        try
        {
            var owner = new BridgeAccountContext("test", "https://authority.invalid", "synthetic-label-owner");
            var store = new LocalPersonalProfileStore(root);
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), new("Before", "Keep", 0, "none", [], []), () => true);
            var preview = new LegacyProfileMigrationView("previewed", "labels-ticket",
                ExpiresAt: DateTimeOffset.UtcNow.AddMinutes(15),
                Choices: new(1, ["skilled-roles"], [], false, []),
                SelectedContent: new(null, [new("skilled-roles", 2)], ["旧版岗位"],
                    ["旧支援"], ["兴趣一", "兴趣二", "兴趣三", "兴趣四"]));
            await new SelectedProfileImportCoordinator(store).RunAsync(owner, () => true, local =>
            {
                local.Stage(preview);
                local.BeforeConfirm("labels-ticket");
                return Task.FromResult(0);
            });
            Check(store.Read(owner).Revision == 1, "Historic-label preview and consent do not write profile");
            await new SelectedProfileImportCoordinator(store).RunAsync(owner, () => true, local =>
                Task.FromResult(local.Apply(preview with { State = "completed", CompletedRevision = 1 })));
            var saved = new LocalPersonalProfileStore(root).Read(owner);
            Check(saved.Revision == 2 && saved.Content!.CallSign == "Before" &&
                saved.Content.PlayStyle!.Roles!.SequenceEqual(["旧版岗位"]) &&
                saved.Content.PlayStyle.Interests!.Count == 4 &&
                saved.Content.PlayStyle.Support!.SequenceEqual(["旧支援"]),
                "Encrypted journal recovery applies all selected historic labels through real coordinator");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    public static async Task Run()
    {
        await HistoricLabelsAcrossRecovery();
        var root = Path.Combine(Path.GetTempPath(), "starbridge-import-recovery-" + Guid.NewGuid().ToString("N"));
        try
        {
            var owner = new BridgeAccountContext("test", "https://authority.invalid", "synthetic-owner");
            var store = new LocalPersonalProfileStore(root);
            var initial = new LocalProfileContent("Synthetic before", "Keep this", 2, "none", [], []);
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), initial, () => true);
            var summary = new LegacyProfileMigrationSummary("Synthetic imported", "", 0, 0, null);
            var preview = new LegacyProfileMigrationView("previewed", "synthetic-ticket",
                ExpiresAt: DateTimeOffset.UtcNow.AddMinutes(15), Source: summary, Target: summary,
                Choices: new(1, [], [], true, []),
                SelectedContent: new("Synthetic imported", [], null, null, null));
            var completed = preview with { State = "completed", ExpiresAt = null, CompletedRevision = 1 };
            var coordinator = new SelectedProfileImportCoordinator(store);
            await coordinator.RunAsync(owner, () => true, local =>
            {
                Check(local.Stage(preview) == preview, "Preview stages without profile writes");
                Check(store.Read(owner).Revision == 1, "Preview never saves local profile");
                try {
                    local.BeforePreview(new([], [], true, PreviousCompletedPreviewId: preview.PreviewId));
                    throw new InvalidOperationException("Unapplied import replaced by another round");
                } catch (LocalProfileException error) when (error.Code == "profile_local.import_preview_required") { }
                local.BeforeConfirm(preview.PreviewId!, false);
                return Task.FromResult(0);
            });
            var journal = Directory.GetFiles(store.ImportJournalDirectory, "*.dat").Single();
            Check(!Encoding.UTF8.GetString(File.ReadAllBytes(journal)).Contains("Synthetic"), "Journal is encrypted");
            // Reconstruct the coordinator as after a process restart.
            coordinator = new(store);
            await coordinator.RunAsync(owner, () => true, local =>
            {
                Check(local.Status(completed).State == "localApplyRequired", "Remote success is not local success");
                Check(store.Read(owner).Revision == 1, "Status does not apply content");
                local.BeforeConfirm(preview.PreviewId!);
                return Task.FromResult(0);
            });
            var profileFile = Directory.GetFiles(Path.Combine(root, "personal-profile-local-v1"), "*.json").Single();
            using (var locked = new FileStream(profileFile + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None))
                await Expect("profile_local.write_failed", () => coordinator.RunAsync(owner, () => true,
                    local => Task.FromResult(local.Apply(completed))));
            Check(store.Read(owner).Revision == 1, "Failed local write leaves profile unchanged");
            coordinator = new(store);
            await coordinator.RunAsync(owner, () => true, local =>
            {
                Check(local.Status(completed).State == "localApplyRequired", "Restart retains pending local work");
                local.BeforeConfirm(preview.PreviewId!);
                Check(local.Apply(completed).State == "completed", "Explicit retry applies original preview");
                Check(local.Apply(completed).State == "completed" && store.Read(owner).Revision == 2,
                    "Repeated completion is idempotent");
                local.BeforePreview(new([], [], false, true, preview.PreviewId));
                try {
                    local.BeforePreview(new([], [], true, PreviousCompletedPreviewId: "foreign-ticket"));
                    throw new InvalidOperationException("Foreign completed receipt accepted");
                } catch (LocalProfileException error) when (error.Code == "profile_local.import_preview_required") { }
                return Task.FromResult(0);
            });
            Check(store.Read(owner).Content!.CallSign == "Synthetic imported" &&
                store.Read(owner).Content!.Introduction == "Keep this", "Only approved name changed");
            store.Save(owner, 2, Guid.NewGuid().ToString("N"), initial with { CallSign = "Later edit" }, () => true);
            await new SelectedProfileImportCoordinator(store).RunAsync(owner, () => true, local =>
            {
                Check(local.Status(completed).State == "completed", "Applied receipt survives later edits");
                local.Apply(completed);
                Check(store.Read(owner).Content!.CallSign == "Later edit", "Completed retry never restores old content");
                return Task.FromResult(0);
            });
            var other = owner with { Subject = "another-synthetic-owner" };
            await coordinator.RunAsync(other, () => true, local =>
            {
                Check(local.Status(completed).State == "localPreviewRequired", "Other owner cannot borrow recovery intent");
                return Task.FromResult(0);
            });
            await Expect("profile_local.account_changed", () => coordinator.RunAsync(owner, () => false,
                local => Task.FromResult(local.Apply(completed))));
            var nextPreview = preview with { PreviewId = "new-ticket" };
            await coordinator.RunAsync(owner, () => true, local => Task.FromResult(local.Stage(nextPreview)));
            store.Save(owner, 3, Guid.NewGuid().ToString("N"), initial with { CallSign = "Concurrent edit" }, () => true);
            await Expect("profile_local.conflict", () => coordinator.RunAsync(owner, () => true, local =>
            { local.BeforeConfirm("new-ticket"); return Task.FromResult(0); }));
            Check(store.Read(owner).Content!.CallSign == "Concurrent edit", "Stale preview cannot overwrite local edit");
            await coordinator.RunAsync(owner, () => true, local =>
            {
                Check(local.Stage(completed, new([], [], false, true)).State == "selectionAlreadyCompleted",
                    "Different requested fields are not mislabeled as already imported");
                var rebased = local.Stage(completed, new([], [], true));
                Check(rebased.State == "previewed" && store.Read(owner).Revision == 4,
                    "Explicit re-preview rebases local revision without a write");
                local.BeforeConfirm(completed.PreviewId!);
                local.Apply(completed);
                Check(store.Read(owner).Revision == 5 && store.Read(owner).Content!.CallSign == "Synthetic imported",
                    "Explicit confirmation recovers onto the re-previewed version");
                return Task.FromResult(0);
            });
            var beforeCorruption = File.ReadAllBytes(profileFile);
            var encrypted = File.ReadAllBytes(journal);
            encrypted[encrypted.Length / 2] ^= 0xff;
            File.WriteAllBytes(journal, encrypted);
            try
            {
                await coordinator.RunAsync(owner, () => true, local => Task.FromResult(local.Apply(completed)));
                throw new InvalidOperationException("Corrupt recovery journal accepted");
            }
            catch (System.Security.Cryptography.CryptographicException) { }
            Check(File.ReadAllBytes(profileFile).SequenceEqual(beforeCorruption), "Corrupt journal never rewrites profile");
            await RuntimeRecovery(Path.Combine(root, "runtime"), preview, completed);
            await RuntimeFirstConfirmation(Path.Combine(root, "first-confirmation"), preview, completed);
            Console.WriteLine("PASS encrypted selected import restart, explicit recovery, conflict and owner isolation");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    private static async Task RuntimeRecovery(string root, LegacyProfileMigrationView preview, LegacyProfileMigrationView completed)
    {
        var endpoint = new Uri("http://127.0.0.1:9/");
        using var handler = new CompletedHandler(completed);
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new NoVault(),
            new ScmOAuthOptions("synthetic", endpoint, endpoint, endpoint, "synthetic", "synthetic", "openid profile.read", "/callback"));
        var session = new ScmOAuthSession("https://authority.invalid", "synthetic-owner", "Synthetic",
            "synthetic-token", DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(root), "test", () => null, session);
        var owner = host.CurrentContext!;
        var store = new LocalPersonalProfileStore(root);
        store.Save(owner, 0, Guid.NewGuid().ToString("N"), new("Before", "Keep", 0, "none", [], []), () => true);
        var protectedFiles = SeedProtectedAccountData(root, owner);
        await new SelectedProfileImportCoordinator(store).RunAsync(owner, () => true, local =>
        { local.Stage(preview); local.BeforeConfirm(preview.PreviewId!); return Task.FromResult(0); });
        using var runtime = new AccountBridgeRuntime(host, localProfile: store);
        BridgeEnvelope Request(string name, object payload) => BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), host.Generation, payload, owner);
        var status = await runtime.DispatchAsync(Request("personalProfile.migrationStatus", new { schemaVersion = 1 }));
        Check(status.Response.Payload.GetProperty("migration").GetProperty("state").GetString() == "localApplyRequired" &&
            store.Read(owner).Revision == 1, "Real runtime status reports local pending without applying");
        var confirm = Request("personalProfile.migrationConfirm", new { schemaVersion = 1,
            previewId = preview.PreviewId, replaceExisting = false });
        handler.Revoked = true;
        var revoked = await runtime.DispatchAsync(confirm);
        Check(revoked.Response.Payload.GetProperty("migration").GetProperty("state").GetString() == "linkRequired" &&
            store.Read(owner).Revision == 1 && revoked.Events.Count == 0,
            "Current link revocation prevents local recovery, remote writes and success invalidation");
        handler.Revoked = false;
        var applied = await runtime.DispatchAsync(confirm);
        Check(applied.Response.Error is null && applied.Response.Payload.GetProperty("migration").GetProperty("state").GetString() == "completed",
            "Real Host completes explicit local recovery");
        Check(store.Read(owner).Revision == 2 && store.Read(owner).Content!.CallSign == "Synthetic imported" && applied.Events.Count == 1,
            "Real runtime saves local name and invalidates displayed profile only after completion");
        await runtime.DispatchAsync(confirm);
        Check(store.Read(owner).Revision == 2 && handler.Reads == 4, "Recovery performs reads only and is idempotent");
        var stale = await runtime.DispatchAsync(confirm with { AccountContext = owner with { Subject = "other" } });
        Check(stale.Response.Error is not null && handler.Reads == 4, "Foreign account rejected before HTTP");
        AssertProtectedAccountData(root, protectedFiles);
    }
    private static async Task RuntimeFirstConfirmation(string root, LegacyProfileMigrationView preview,
        LegacyProfileMigrationView completed)
    {
        var endpoint = new Uri("http://127.0.0.1:9/");
        using var handler = new FirstConfirmationHandler(preview, completed);
        var authorization = new ImportAuthorization();
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new NoVault(),
            new ScmOAuthOptions("synthetic", endpoint, endpoint, endpoint, "synthetic", "synthetic", "openid profile.read", "/callback"));
        var session = new ScmOAuthSession("https://authority.invalid", "synthetic-owner", "Synthetic",
            "synthetic-token", DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(root), "test", () => null,
            session, profileAuthorization: authorization);
        var owner = host.CurrentContext!;
        var store = new LocalPersonalProfileStore(root);
        store.Save(owner, 0, Guid.NewGuid().ToString("N"), new("Before", "Keep", 0, "none", [], []), () => true);
        var protectedFiles = SeedProtectedAccountData(root, owner);
        using var runtime = new AccountBridgeRuntime(host, localProfile: store);
        BridgeEnvelope Request(string name, object payload) => BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), host.Generation, payload, owner);
        var staged = await runtime.DispatchAsync(Request("personalProfile.migrationPreview", new {
            schemaVersion = 1, selection = new { modules = Array.Empty<string>(), replaceModules = Array.Empty<string>(),
                useLegacyCallSign = true, useLegacyAvatar = false } }));
        Check(staged.Response.Error is null && staged.Response.Payload.GetProperty("migration").GetProperty("state").GetString() == "previewed"
            && store.Read(owner).Revision == 1 && authorization.Calls == 0, "Real preview stages without write authorization or local save");
        var confirm = Request("personalProfile.migrationConfirm", new { schemaVersion = 1,
            previewId = preview.PreviewId, replaceExisting = false });
        foreach (var mode in new[] { "denied", "wrong-owner", "missing-scope", "cancelled", "timeout" })
        {
            authorization.Mode = mode;
            var failed = await runtime.DispatchAsync(confirm);
            Check((failed.Response.Error is not null || failed.Response.Payload.GetProperty("migration").GetProperty("state").GetString() == "authorizationRequired")
                && failed.Events.Count == 0 && store.Read(owner).Revision == 1 && handler.Writes == 0,
                "Authorization failure must not mutate either profile: " + mode);
            AssertProtectedAccountData(root, protectedFiles);
            if (mode == "cancelled") Check(failed.Response.Error?.Code == BridgeErrorCodes.Cancelled,
                "User cancellation stays cancellation, not disconnected Host");
            if (mode == "timeout") Check(failed.Response.Error?.Code == AccountBridgeStableErrors.LoginTimeout,
                "Authorization timeout retains its actionable error");
            if (mode == "wrong-owner") Check(failed.Response.Error?.Code == AccountBridgeStableErrors.ReauthorizationRequired,
                "Wrong authorization owner is rejected explicitly");
        }
        authorization.Mode = "granted";
        var lost = await runtime.DispatchAsync(confirm);
        Check(lost.Response.Payload.GetProperty("migration").GetProperty("state").GetString() == "sourceUnavailable"
            && lost.Events.Count == 0 && handler.Writes == 1 && store.Read(owner).Revision == 1,
            "Lost confirmation response does not fabricate local completion or replay remote write");
        var grants = authorization.Calls;
        var recovered = await runtime.DispatchAsync(confirm);
        Check(recovered.Response.Payload.GetProperty("migration").GetProperty("state").GetString() == "completed"
            && recovered.Events.Count == 1 && handler.Writes == 1 && authorization.Calls == grants
            && store.Read(owner).Revision == 2 && store.Read(owner).Content!.CallSign == "Synthetic imported",
            "Retry reads committed receipt then applies approved local content without another grant or POST");
        await runtime.DispatchAsync(confirm);
        Check(handler.Writes == 1 && authorization.Calls == grants && store.Read(owner).Revision == 2,
            "First-confirmation recovery is idempotent");
        AssertProtectedAccountData(root, protectedFiles);
    }
    private static Dictionary<string, byte[]> SeedProtectedAccountData(string root, BridgeAccountContext owner)
    {
        var inventory = new StarBridge.HostRuntime.Hangar.LocalHangarStore(root);
        var privacy = new StarBridge.HostRuntime.Privacy.LocalPrivacyStore(root);
        foreach (var account in new[] { owner, owner with { Subject = "unrelated-owner" } })
        {
            var ships = inventory.Save(account, 0, "synthetic-seed",
                [new("pledge-a", 0, "Synthetic A", "Paint A", "fixture"),
                 new("pledge-b", 0, "Synthetic B", "Paint B", "fixture"),
                 new("pledge-former", 0, "Synthetic former", "Historical paint", "fixture")], false, false);
            ships = inventory.SaveCustomImage(account, ships.Revision, "synthetic-image", ships.Ships[0].Id,
                "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=");
            ships = inventory.SaveCustomImage(account, ships.Revision, "synthetic-former-image", ships.Ships[2].Id,
                "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=");
            ships = inventory.Save(account, ships.Revision, "synthetic-remove",
                [new("pledge-a", 0, "Synthetic A", "Paint A", "fixture"),
                 new("pledge-b", 0, "Synthetic B", "Paint B", "fixture")], false, false);
            ships = inventory.Save(account, ships.Revision, "synthetic-partial",
                [new("pledge-a", 0, "Synthetic A", "Paint A", "fixture")], true, false);
            Check(ships.Partial && ships.Ships.Count == 2 && ships.FormerShips is { Count: 1 } &&
                ships.FormerShips[0].RemovedAt is not null &&
                inventory.ReadCustomImage(account, ships.Revision, ships.FormerShips[0].Id) is not null,
                "Protected fixture includes current ships, retained partial scan state, history and historical image");
            privacy.Save(account, 0, Guid.NewGuid().ToString("N"), new(false,
                new(StarBridge.Core.Presence.PlayerSharedStateFields.None, false, false, ["synthetic-private-group"]),
                new(StarBridge.Core.Presence.PlayerSharedStateFields.None, false)), () => true);
        }
        return ProtectedFiles(root).ToDictionary(path => path, File.ReadAllBytes);
    }
    private static IEnumerable<string> ProtectedFiles(string root) =>
        new[] { "hangar-local-v1", "privacy-local-v1" }.SelectMany(directory =>
            Directory.GetFiles(Path.Combine(root, directory), "*", SearchOption.AllDirectories));
    private static void AssertProtectedAccountData(string root, Dictionary<string, byte[]> expected)
    {
        Check(ProtectedFiles(root).Order().SequenceEqual(expected.Keys.Order()) &&
            expected.All(file => File.ReadAllBytes(file.Key).SequenceEqual(file.Value)),
            "Import cannot alter either owner's real inventory, partial scan state, historical ships/images, privacy fields or sharing consent files");
    }
    private sealed class ImportAuthorization : IProfileWriteAuthorizationClient
    {
        internal string Mode = "granted";
        internal int Calls;
        public Task<ScmOAuthSession> AuthorizeProfileWriteAsync(ScmOAuthSession owner, CancellationToken token,
            Action<string>? reportProgress = null)
        {
            Calls++;
            Check(owner.AccessToken == "synthetic-token", "Temporary write grant never replaces read session");
            return Mode switch {
                "denied" => Task.FromException<ScmOAuthSession>(new ScmApiForbiddenException("Synthetic denial")),
                "cancelled" => Task.FromException<ScmOAuthSession>(new OAuthAuthorizationDeniedException()),
                "timeout" => Task.FromException<ScmOAuthSession>(new TimeoutException()),
                _ => Task.FromResult(owner with { Subject = Mode == "wrong-owner" ? "other" : owner.Subject,
                    AccessToken = "write-token", Capabilities = Mode == "missing-scope" ? [] : ["profile.write"] })
            };
        }
    }
    private sealed class FirstConfirmationHandler(LegacyProfileMigrationView preview,
        LegacyProfileMigrationView completed) : HttpMessageHandler
    {
        internal int Writes;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = request.RequestUri!.AbsolutePath;
            if (request.Method == HttpMethod.Post && path.EndsWith("/selected-confirm", StringComparison.Ordinal))
            {
                Check(request.Headers.Authorization?.Parameter == "write-token", "Confirmation uses temporary grant");
                Writes++;
                return Task.FromException<HttpResponseMessage>(new HttpRequestException("Synthetic response lost after commit"));
            }
            Check(request.Headers.Authorization?.Parameter == "synthetic-token", "Read and preview keep ordinary session");
            Check((request.Method == HttpMethod.Get && path.EndsWith("/legacy-profile-migration", StringComparison.Ordinal)) ||
                (request.Method == HttpMethod.Post && path.EndsWith("/selected-preview", StringComparison.Ordinal)), "Only selected import routes are used");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(Writes == 0 ? preview : completed) });
        }
    }
    private sealed class CompletedHandler(LegacyProfileMigrationView completed) : HttpMessageHandler
    {
        internal int Reads;
        internal bool Revoked;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/legacy-profile-migration",
                "Completed recovery never repeats a remote write or opens authorization");
            Check(request.Headers.Authorization?.Parameter == "synthetic-token", "Recovery status is authenticated");
            Reads++;
            return Task.FromResult(new HttpResponseMessage(Revoked ? HttpStatusCode.Conflict : HttpStatusCode.OK)
                { Content = JsonContent.Create(Revoked ? new LegacyProfileMigrationView("linkRequired") : completed) });
        }
    }
    private sealed class NoVault : ITokenVault
    {
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No token writes");
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string key) { }
    }
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Expect(string code, Func<Task> action)
    {
        try { await action(); } catch (LocalProfileException error) when (error.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }
}
