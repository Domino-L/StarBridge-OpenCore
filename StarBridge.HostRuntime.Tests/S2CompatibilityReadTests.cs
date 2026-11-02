using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.LegacyRelay;
using StarBridge.Core.Profiles;
using StarBridge.Core.Identity;
using StarBridge.NativeBridge;

internal static class S2CompatibilityReadTests
{
    internal static async Task VerifyLocalPrivacyInheritance()
    {
        var root = Directory.CreateTempSubdirectory("sb-linked-privacy-").FullName;
        try
        {
            using var legacy = new LegacyPasswordLoginClient(new Uri("https://fixture-relay.invalid/"), new NoCredentials());
            var legacyOwner = new BridgeAccountContext("development", legacy.AuthorityId, "synthetic-legacy");
            var store = new StarBridge.HostRuntime.Privacy.LocalPrivacyStore(root);
            var joinedAt = new DateTimeOffset(2026, 9, 1, 0, 0, 0, TimeSpan.Zero);
            var settings = StarBridge.HostRuntime.Privacy.LocalPrivacySettings.EditorDefaults with {
                PublicationEnabled = false,
                Communities = [new("synthetic-community", joinedAt,
                    StarBridge.Core.Presence.PlayerSharedStateFields.None, false, false, [])]
            };
            var saved = store.Save(legacyOwner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
            var profileStore = new StarBridge.HostRuntime.Profiles.LocalPersonalProfileStore(root);
            var profileContent = new StarBridge.HostRuntime.Profiles.LocalProfileContent("Original callsign", "Original introduction", 1, "none",
                [new("favorite-ships", 3, true, 0), new("hangar-summary", 3, true, 1)], null);
            var oldProfile = profileStore.Save(legacyOwner, 0, Guid.NewGuid().ToString("N"), profileContent, () => true);
            var hangarStore = new StarBridge.HostRuntime.Hangar.LocalHangarStore(root);
            var observations = new StarBridge.Core.Hangar.CollectedHangarShip[] { new("synthetic-pledge", 0, "Aurora MR", null, null) };
            var oldHangar = hangarStore.Save(legacyOwner, 0, "original-inventory", observations, false, false);
            const string image = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM7sAAAAASUVORK5CYII=";
            var originalShipId = oldHangar.Ships.Single().Id;
            oldHangar = hangarStore.SaveCustomImage(legacyOwner, oldHangar.Revision, "original-image", originalShipId, image);
            var visibilityStore = new StarBridge.HostRuntime.Settings.PresenceVisibilityStore(root);
            visibilityStore.Save(StarBridge.Core.Presence.PlayerPresenceVisibilityMode.Invisible, visibilityStore.Read().Revision, () => { });
            var logStore = new StarBridge.HostRuntime.Presence.GameLogSettingsStore(root);
            using (var legacyLog = logStore.Open(legacyOwner))
                legacyLog.Save(legacyLog.Read(), new(Enabled: false, Channel: "PTU"), () => true);
            var timeStore = new StarBridge.HostRuntime.Presence.GameplayTimeStore(root);
            using (var legacyTime = timeStore.Open(legacyOwner))
            {
                var emptyTime = legacyTime.Read();
                legacyTime.Save(emptyTime, emptyTime with { Consent = StarBridge.HostRuntime.Presence.GameplayRecordingConsent.Declined,
                    Seconds = 3600, ShowOnProfile = false }, () => true);
            }
            var before = Directory.GetFiles(root, "*.json", SearchOption.AllDirectories)
                .ToDictionary(path => path, File.ReadAllBytes);
            var session = new ScmOAuthSession("fixture-scm", "fixture-subject", "Fixture", "synthetic-token",
                DateTimeOffset.UtcNow.AddMinutes(5), [], GameIdentityHandle: "FixturePilot", GameIdentityStatus: ScmGameIdentityStatus.Verified);
            var coordinator = new Coordinator();
            var ownershipClock = new OwnershipClock();
            using var reader = new S2CompatibilityReader(coordinator, new Relay());
            using var host = new ScmAccountBridgeHost(new OAuthPkceClient(new ScmHttpClient(new OfflineScm()), new Vault(), ScmOAuthOptions.CreateDefault()),
                new ScmProfileCacheStore(), "development", () => null, initialSession: session,
                compatibilityReader: reader, legacyPasswordLogin: legacy) { LocalDataOwnerClock = ownershipClock };
            using var runtime = new AccountBridgeRuntime(host,
                localHangar: hangarStore, localProfile: profileStore, privacy: store, visibility: visibilityStore);
            await host.GetCurrentAsync(default);
            timeStore.ResolveOwner = host.ResolveLocalDataOwner;
            using var timeRuntime = new StarBridge.HostRuntime.Presence.GameplayTimeRuntime(timeStore,
                () => (host.CurrentContext, host.Generation), () => new(1, "notRunning"), startTimer: false);
            var timeRead = timeRuntime.Dispatch(BridgeEnvelope.Request("gameplayTime.read", "inherit-time", host.Generation,
                new { schemaVersion = 1 }, host.CurrentContext)).Response;
            Check(timeRead.Error is null && timeRead.Payload.GetProperty("seconds").GetInt64() == 3600 &&
                timeRead.Payload.GetProperty("consent").GetString() == "declined" && !timeRead.Payload.GetProperty("showOnProfile").GetBoolean(),
                "Actual verified SCM linkage must retain original time, decline and hidden profile");
            logStore.ResolveOwner = host.ResolveLocalDataOwner;
            using var logRuntime = new StarBridge.HostRuntime.Presence.GameLogRuntime(logStore,
                () => (host.CurrentContext, host.Generation), () => "FixturePilot", probe: () => new("notRunning"),
                startTimer: false, locator: new(() => []));
            var logRead = logRuntime.Dispatch(BridgeEnvelope.Request("gameLog.read", "inherit-log-stop", host.Generation,
                new { schemaVersion = 1 }, host.CurrentContext));
            Check(logRead.Response.Error is null && !logRead.Response.Payload.GetProperty("enabled").GetBoolean() &&
                logRead.Response.Payload.GetProperty("channel").GetString() == "PTU",
                "SCM login must retain stopped log recognition and the original selected channel");
            Check(host.ResolveLocalDataOwner(host.CurrentContext!) == legacyOwner,
                "Startup must resolve the original business owner without visiting compatibility settings");
            var presenceRead = await runtime.DispatchAsync(BridgeEnvelope.Request("presence.read", "inherit-invisible", host.Generation,
                new { schemaVersion = 1 }, host.CurrentContext));
            Check(presenceRead.Response.Error is null && presenceRead.Response.Payload.GetProperty("mode").GetString() == "invisible",
                "Switching authentication must preserve the existing device invisibility choice without a remote presence write");
            var inventoryRead = await runtime.DispatchAsync(BridgeEnvelope.Request("hangarReader.inventory", "inherit-hangar", host.Generation,
                new { schemaVersion = 1 }, host.CurrentContext));
            Check(inventoryRead.Response.Error is null && inventoryRead.Response.Payload.GetProperty("revision").GetInt64() == oldHangar.Revision,
                "SCM login must expose the original saved inventory, not an empty parallel hangar");
            Check(hangarStore.Read(host.CurrentContext!).Ships.Single().Id == originalShipId &&
                hangarStore.ReadCustomImage(host.CurrentContext!, oldHangar.Revision, originalShipId) == image,
                "Original ship instance IDs and custom images must survive the authentication switch");
            var profileRead = await runtime.DispatchAsync(BridgeEnvelope.Request("personalProfile.localRead", "inherit-profile", host.Generation,
                new { schemaVersion = 1 }, host.CurrentContext));
            Check(profileRead.Response.Error is null && profileRead.Response.Payload.GetProperty("revision").GetInt64() == oldProfile.Revision &&
                profileRead.Response.Payload.GetProperty("content").GetProperty("callSign").GetString() == profileContent.CallSign,
                "SCM login must retain the original local callsign, profile and layout instead of returning a new profile");
            var result = await runtime.DispatchAsync(BridgeEnvelope.Request("privacy.localRead", "inherit-privacy", host.Generation,
                new { schemaVersion = 1 }, host.CurrentContext));
            Check(result.Response.Error is null, "Verified compatible login must read the old privacy choices");
            Check(result.Response.Payload.GetProperty("revision").GetInt64() == saved.Revision,
                "Switching authentication must retain the old privacy revision rather than returning a new-account record");
            Check(!result.Response.Payload.GetProperty("settings").GetProperty("publicationEnabled").GetBoolean(),
                "The old account's explicit sharing-off choice must survive SCM login");
            var inheritedScope = store.Read(host.CurrentContext!).Settings!.Communities!.Single();
            Check(inheritedScope.Code == "synthetic-community" && inheritedScope.JoinedAt == joinedAt &&
                inheritedScope.Fields == StarBridge.Core.Presence.PlayerSharedStateFields.None &&
                !inheritedScope.AllMembersCanView && !inheritedScope.AdministratorsCanView,
                "Original membership confirmation and organization refusal must survive without broadening recipients");
            Check(before.Count == Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).Length &&
                before.All(pair => pair.Value.SequenceEqual(File.ReadAllBytes(pair.Key))),
                "Inheritance reads must not migrate, duplicate or rewrite files");
            var updatedHangar = hangarStore.Save(host.CurrentContext!, oldHangar.Revision, "scm-inventory-save", observations, false, false);
            Check(new StarBridge.HostRuntime.Hangar.LocalHangarStore(root).Read(legacyOwner).Revision == updatedHangar.Revision &&
                updatedHangar.Ships.Single().Id == originalShipId &&
                hangarStore.ReadCustomImage(host.CurrentContext!, updatedHangar.Revision, originalShipId) == image,
                "SCM inventory save updates the same file while retaining original instance and image");
            try
            {
                hangarStore.Save(host.CurrentContext!, updatedHangar.Revision, "revoked-during-save", observations, false, false, () => {
                    coordinator.Linked = false;
                    host.GetCompatibilityStateAsync(host.CurrentContext!, default).GetAwaiter().GetResult();
                    return true;
                });
                throw new Exception("An in-flight save survived a changed business owner");
            }
            catch (StarBridge.HostRuntime.Hangar.LocalHangarStoreException error) when (error.Code == "hangar.account_changed") { }
            Check(new StarBridge.HostRuntime.Hangar.LocalHangarStore(root).Read(legacyOwner).Revision == updatedHangar.Revision,
                "Revocation at the commit guard must leave the original inventory unchanged");
            coordinator.Linked = true;
            await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
            var profileSave = await runtime.DispatchAsync(BridgeEnvelope.Request("personalProfile.localSave", "save-inherited-profile", host.Generation,
                new { schemaVersion = 1, expectedRevision = oldProfile.Revision, operationId = Guid.NewGuid().ToString("N"),
                    content = profileContent with { Introduction = "Updated through SCM" } }, host.CurrentContext));
            Check(profileSave.Response.Error is null &&
                new StarBridge.HostRuntime.Profiles.LocalPersonalProfileStore(root).Read(legacyOwner).Content!.Introduction == "Updated through SCM" &&
                Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).Length == before.Count,
                "Editing the linked local profile must update the original file without creating a parallel profile");
            Check(!store.NeedsFirstChoice(host.CurrentContext!) && !store.HasPublicationConsent(host.CurrentContext!),
                "An inherited refusal is a completed choice, not a new onboarding prompt or publication consent");
            var updated = store.Save(host.CurrentContext!, saved.Revision, Guid.NewGuid().ToString("N"), settings, () => true);
            Check(new StarBridge.HostRuntime.Privacy.LocalPrivacyStore(root).Read(legacyOwner).Revision == updated.Revision &&
                Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).Length == before.Count,
                "Saving through SCM must update the original file, not create a parallel account");
            var pendingProjection = new TaskCompletionSource<AccountBridgeCompatibilityProjection>(TaskCreationOptions.RunContinuationsAsynchronously);
            coordinator.Pending = pendingProjection;
            var oldRead = host.GetCompatibilityStateAsync(host.CurrentContext!, default);
            coordinator.Pending = null;
            coordinator.Linked = false;
            await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
            pendingProjection.SetResult(Coordinator.LinkedProjection);
            try { await oldRead; } catch (AccountBridgeHostException) { }
            Check(host.ResolveLocalDataOwner(host.CurrentContext!) == host.CurrentContext,
                "A late linked response must not restore old-account access after a newer unlink observation");
            coordinator.Failure = true;
            try { await host.GetCompatibilityStateAsync(host.CurrentContext!, default); }
            catch (AccountBridgeHostException) { }
            try { store.Read(host.CurrentContext!); throw new Exception("Unavailable ownership returned new-account defaults"); }
            catch (StarBridge.HostRuntime.Privacy.LocalPrivacyException) { }
            var unavailableLog = logRuntime.Dispatch(BridgeEnvelope.Request("gameLog.read", "unavailable-log", host.Generation,
                new { schemaVersion = 1 }, host.CurrentContext));
            Check(unavailableLog.Response.Error is not null, "A cached log lease must stop serving settings after ownership becomes unverified");
            var unavailableProfile = await runtime.DispatchAsync(BridgeEnvelope.Request("personalProfile.localRead", "unavailable-profile", host.Generation,
                new { schemaVersion = 1 }, host.CurrentContext));
            Check(unavailableProfile.Response.Error is not null, "Unverified ownership must not expose the old profile or present an empty new profile");
            var unavailableHangar = await runtime.DispatchAsync(BridgeEnvelope.Request("hangarReader.inventory", "unavailable-hangar", host.Generation,
                new { schemaVersion = 1 }, host.CurrentContext));
            Check(unavailableHangar.Response.Error is not null, "Unverified ownership must not expose the old inventory or offer empty defaults");
            coordinator.Failure = false;
            coordinator.Linked = true;
            await host.GetCurrentAsync(default);
            Check(store.Read(host.CurrentContext!).Revision == updated.Revision,
                "Recovery must reconnect the same original file without resetting choices");
            var recoveredLog = logRuntime.Dispatch(BridgeEnvelope.Request("gameLog.read", "recovered-log", host.Generation,
                new { schemaVersion = 1 }, host.CurrentContext));
            Check(recoveredLog.Response.Error is null && !recoveredLog.Response.Payload.GetProperty("enabled").GetBoolean() &&
                recoveredLog.Response.Payload.GetProperty("channel").GetString() == "PTU",
                "The old log lease must be released on failure and reopened safely after ownership recovery");
            var stranger = new BridgeAccountContext("development", "fixture-scm", "another-subject");
            try { store.Read(stranger); throw new Exception("Another account read inherited choices"); }
            catch (StarBridge.HostRuntime.Privacy.LocalPrivacyException) { }
            ownershipClock.Advance(TimeSpan.FromMinutes(4));
            try { host.ResolveLocalDataOwner(host.CurrentContext!); throw new Exception("Old account ownership was cached indefinitely without revalidation"); }
            catch (StarBridge.HostRuntime.Privacy.LocalPrivacyException) { }
            await host.GetCurrentAsync(default);
            Check(host.ResolveLocalDataOwner(host.CurrentContext!) == legacyOwner,
                "Expired verified ownership must recover automatically through current SCM and Relay validation");
            var backgroundRead = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            coordinator.OnRead = () => backgroundRead.TrySetResult();
            coordinator.Linked = false;
            ownershipClock.Advance(TimeSpan.FromMinutes(1));
            host.EnableParticipantSynchronization(TimeSpan.FromMilliseconds(10));
            await backgroundRead.Task.WaitAsync(TimeSpan.FromSeconds(3));
            for (var retry = 0; retry < 200 && host.ResolveLocalDataOwner(host.CurrentContext!) != host.CurrentContext; retry++)
                await Task.Delay(10);
            Check(host.ResolveLocalDataOwner(host.CurrentContext!) == host.CurrentContext,
                "The production background lifecycle must observe unlinking without opening the settings page");
            // DL-129: the queue-free current read only repeats a recent full read.
            var projector = (IAccountBridgeCurrentProjection)host;
            await host.GetCurrentAsync(default);
            var fast = projector.TryProjectCurrent();
            Check(fast is not null && fast.Context == host.CurrentContext && fast.Generation == host.Generation,
                "A repeated current read after a full read must be answered from memory");
            ownershipClock.Advance(TimeSpan.FromSeconds(31));
            Check(projector.TryProjectCurrent() is null, "An old full read must send current back through the ordinary queue");
            await host.GetCurrentAsync(default);
            Check(projector.TryProjectCurrent() is not null, "A new full read re-opens the in-memory answer");
            // DL-129 option 3: a healthy SCM session shares resource reads; a
            // disposed host serializes them again.
            var resources = (IAccountBridgeConcurrentResourceReads)host;
            Check(resources.SupportsConcurrentResourceReads && !host.SupportsConcurrentReads,
                "A healthy SCM session may overlap resource reads but not every independent read");
            host.Dispose();
            Check(projector.TryProjectCurrent() is null, "A disposed host never answers current from memory");
            Check(!resources.SupportsConcurrentResourceReads, "A disposed host never overlaps resource reads");
            await host.ParticipantLoopCompletion.WaitAsync(TimeSpan.FromSeconds(3));
        }
        finally { Directory.Delete(root, true); }
    }

    internal static async Task VerifySharingAfterOwnerRecovery()
    {
        foreach (var scenario in new[] { "confirmed", "declined", "disabled", "unlinked", "manual-stop" })
        {
            var root = Directory.CreateTempSubdirectory("sb-owner-sharing-recovery-").FullName;
            try
            {
                using var legacy = new LegacyPasswordLoginClient(new Uri("https://fixture-relay.invalid/"), new NoCredentials());
                var legacyOwner = new BridgeAccountContext("development", legacy.AuthorityId, "synthetic-legacy");
                var store = new StarBridge.HostRuntime.Privacy.LocalPrivacyStore(root);
                var settings = new StarBridge.HostRuntime.Privacy.LocalPrivacySettings(scenario != "disabled",
                    new(StarBridge.Core.Presence.PlayerSharedStateFields.Presence, false, true, []),
                    new(StarBridge.Core.Presence.PlayerSharedStateFields.None, false));
                var saved = store.Save(legacyOwner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
                store.SetPublicationConsent(legacyOwner, saved.Revision, scenario is "confirmed" or "unlinked" or "manual-stop", () => true);
                var originalFiles = Directory.GetFiles(root, "*.json", SearchOption.AllDirectories)
                    .ToDictionary(path => path, File.ReadAllBytes);
                var session = new ScmOAuthSession("fixture-scm", "fixture-subject", "Fixture", "synthetic-token",
                    DateTimeOffset.UtcNow.AddMinutes(5), [], GameIdentityHandle: "FixturePilot",
                    GameIdentityStatus: ScmGameIdentityStatus.Verified);
                var coordinator = new Coordinator { Failure = true };
                using var reader = new S2CompatibilityReader(coordinator, new Relay());
                using var host = new ScmAccountBridgeHost(new OAuthPkceClient(new ScmHttpClient(new OfflineScm()),
                    new Vault(), ScmOAuthOptions.CreateDefault()), new ScmProfileCacheStore(), "development", () => null,
                    initialSession: session, compatibilityReader: reader, legacyPasswordLogin: legacy);
                store.ResolveOwner = host.ResolveLocalDataOwner;
                var sent = new List<System.Text.Json.JsonElement>();
                using var publication = new StarBridge.HostRuntime.Privacy.PrivacyPublication(store,
                    () => new(host.CurrentContext!, host.Generation, "FixturePilot", true, null,
                        StarBridge.HostRuntime.Presence.GameLogSessionSnapshot.Empty),
                    (_, payload, _) => { sent.Add(payload.Clone()); return Task.CompletedTask; }, startTimer: false);
                // Same account invalidation wiring as AccountBridgeRuntime. A
                // compatibility refresh alone does not change SCM generation.
                host.AccountChanged += _ => publication.Invalidate();
                await host.GetCurrentAsync(default);
                await publication.TickAsync();
                Check(sent.Count == 0, "Unverified ownership must not publish or silently use SCM defaults");
                if (scenario == "manual-stop")
                {
                    await publication.StopAsync(default, explicitRequest: true);
                    // A pending compensating clear must not erase the explicit
                    // stop just because its owner lookup is still unavailable.
                    await publication.TickAsync();
                }
                var generation = host.Generation;
                coordinator.Failure = false;
                coordinator.Linked = scenario != "unlinked";
                await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
                Check(host.Generation == generation, "Ownership recovery is not another login/account event");
                if (scenario == "confirmed")
                    Check(host.ResolveLocalDataOwner(host.CurrentContext!) == legacyOwner &&
                        store.Read(host.CurrentContext!).Revision == saved.Revision && store.HasPublicationConsent(host.CurrentContext!),
                        "Recovery control must verify the same old owner, policy revision and remembered consent before the tick");
                await publication.TickAsync();
                await publication.TickAsync();
                if (scenario == "confirmed")
                    Check(publication.Status.State == "applied" && sent.Count > 0 && sent.All(payload => payload.GetProperty("online").GetBoolean()),
                        "Recovered verified old-account ownership must resume remembered sharing without Apply, login or client restart");
                else
                    Check(sent.All(payload => !payload.GetProperty("online").GetBoolean()),
                        "Ownership recovery cannot promote a refusal, disabled policy or unlinked account into consent");
                Check(originalFiles.All(pair => File.ReadAllBytes(pair.Key).SequenceEqual(pair.Value)) &&
                    Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).Length == originalFiles.Count,
                    "Recovery must preserve original policies/consent and avoid parallel account files");
                Check(coordinator.Writes == 0, "Read-side recovery must never create or change a binding");
            }
            finally { Directory.Delete(root, true); }
        }
        Console.WriteLine("PASS sharing resumes only verified remembered consent after ownership recovery");
    }

    private sealed class NoCredentials : ILegacyMigrationCredentialStore
    {
        public LegacyMigrationCredential? Load() => throw new Exception("Unexpected legacy credential read");
        public void Save(LegacyMigrationCredential credential) => throw new Exception("Unexpected credential write");
        public void Delete() => throw new Exception("Unexpected credential delete");
    }

    private sealed class OwnershipClock : TimeProvider
    {
        private long _ticks;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => Interlocked.Read(ref _ticks);
        internal void Advance(TimeSpan duration) => Interlocked.Add(ref _ticks, duration.Ticks);
    }

    private sealed class OfflineScm : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.ServiceUnavailable));
    }

    internal static async Task Verify()
    {
        var session = new ScmOAuthSession("scm-development", "synthetic", "Synthetic",
            "synthetic-bearer", DateTimeOffset.UtcNow.AddMinutes(5), []);
        foreach (var state in new[] { LegacyRelayAccessState.Ready, LegacyRelayAccessState.AccountMismatch,
                     LegacyRelayAccessState.AuthorizationRequired, LegacyRelayAccessState.Unavailable })
        {
            var coordinator = new Coordinator(); var relay = new Relay { State = state };
            using var reader = new S2CompatibilityReader(coordinator, relay);
            using var host = Host(session, reader);
            var result = await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
            Check(result.LegacyFeaturesAvailable == (state == LegacyRelayAccessState.Ready), "lease state");
            Check(ReferenceEquals(relay.Session, session), "same SCM session must reach Relay");
            Check(!result.AvailableActions.Contains("createCompatibilityIdentity"), "no provisioning");
            Check(coordinator.Writes == 0, "read must not mutate identity");
        }
        {
            var coordinator = new Coordinator { Linked = false }; var relay = new Relay();
            using var reader = new S2CompatibilityReader(coordinator, relay);
            using var host = Host(session, reader);
            using var runtime = new AccountBridgeRuntime(host);
            var result = await runtime.DispatchAsync(BridgeEnvelope.Request("account.getCompatibilityState",
                "s2-read", host.Generation, new { schemaVersion = 1 }, host.CurrentContext));
            Check(result.Response.Status == BridgeResponseStatuses.Ok, "runtime read route");
            Check(relay.Calls == 0, "unlinked account cannot establish Relay identity");
            Check(!result.Response.Payload.TryGetProperty("legacyAccountId", out _), "internal ID stays in Host");
            Check(result.Response.Payload.GetProperty("availableActions").GetArrayLength() == 1, "existing-account action only");
            foreach (var name in new[] { "account.createCompatibilityIdentity" })
            {
                var denied = await runtime.DispatchAsync(BridgeEnvelope.Request(name, name,
                    host.Generation, new { schemaVersion = 1 }, host.CurrentContext));
                Check(denied.Response.Error?.Code == BridgeErrorCodes.CapabilityUnavailable, "writes stay closed");
            }
        }
        {
            var coordinator = new Coordinator { Failure = true };
            using var reader = new S2CompatibilityReader(coordinator, new Relay());
            using var host = Host(session, reader);
            try { await host.GetCompatibilityStateAsync(host.CurrentContext!, default); throw new Exception("Missing failure"); }
            catch (AccountBridgeHostException e) { Check(e.Code == AccountBridgeStableErrors.CompatibilityReadUnavailable, "local failure"); }
            Check(host.CurrentContext is not null, "SCM context survives compatibility outage");
        }
        {
            var coordinator = new Coordinator { Pending = new(TaskCreationOptions.RunContinuationsAsynchronously) };
            using var reader = new S2CompatibilityReader(coordinator, new Relay());
            using var host = Host(session, reader);
            var pending = host.GetCompatibilityStateAsync(host.CurrentContext!, default);
            host.Dispose();
            coordinator.Pending.SetResult(Coordinator.LinkedProjection);
            try { await pending; throw new Exception("Late response escaped"); }
            catch (AccountBridgeHostException) { }
        }
    }
    private static ScmAccountBridgeHost Host(ScmOAuthSession session, S2CompatibilityReader reader) => new(
        new OAuthPkceClient(new ScmHttpClient(), new Vault(), ScmOAuthOptions.CreateDefault()),
        new ScmProfileCacheStore(), "development", () => null, initialSession: session, compatibilityReader: reader);
    private static void Check(bool ok, string message) { if (!ok) throw new Exception(message); }
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected delete");
    }
    private sealed class Coordinator : IAccountCompatibilityCoordinator
    {
        internal static AccountBridgeCompatibilityProjection LinkedProjection => new("linked", "notEstablished", false, false, [], "synthetic-legacy");
        internal bool Linked = true, Failure;
        internal int Writes;
        internal Action? OnRead;
        internal TaskCompletionSource<AccountBridgeCompatibilityProjection>? Pending;
        public Task<AccountBridgeCompatibilityProjection> ReadAsync(ScmOAuthSession s, CancellationToken t)
        {
            OnRead?.Invoke();
            return Failure ? Task.FromException<AccountBridgeCompatibilityProjection>(new HttpRequestException()) :
            Pending?.Task ?? Task.FromResult(Linked ? LinkedProjection : new("unlinked", "notApplicable", false, false,
                ["linkExistingAccount", "createCompatibilityIdentity"], null));
        }
        public Task<AccountBridgeCompatibilityProjection> LinkExistingAsync(ScmOAuthSession s, LegacyIdentityLinkPasswordCredential? c, CancellationToken t)
        { Writes++; throw new Exception("Unexpected link"); }
        public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(ScmOAuthSession s, CancellationToken t)
        { Writes++; throw new Exception("Unexpected provision"); }
    }
    private sealed class Relay : ILegacyRelayAccountPort
    {
        internal LegacyRelayAccessState State = LegacyRelayAccessState.Ready;
        internal int Calls; internal ScmOAuthSession? Session;
        public Task<LegacyRelayAccessState> EstablishAsync(ScmOAuthSession s, string id, CancellationToken t)
        { t.ThrowIfCancellationRequested(); Calls++; Session = s; return Task.FromResult(State); }
        public Task<LegacyRelayProfileReadResult> ReadOwnProfileAsync(ScmOAuthSession s, string id, CancellationToken t) => throw new Exception("Unexpected profile read");
        public void Reset() { }
    }
}
