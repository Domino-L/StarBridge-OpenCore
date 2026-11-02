using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.LegacyRelay;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task RestoreDisplayBoundaries()
    {
        foreach (var stage in new[] { "token", "identity" })
        foreach (var change in new[] { "cancel", "retire", "same", "other", "remove" })
        {
            await using var f = await RestoreDisplayFixture.Create();
            var originalVersion = f.Vault.CaptureRetirement(f.Key);
            f.Start(stage, ignoreCancellation: true);
            await f.Transport!.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            var heldVersion = f.Vault.CaptureRetirement(f.Key);
            AssertEqual(stage == "token", heldVersion == originalVersion, "only identity stage has already committed rotation");
            AssertEqual("ok", (await f.Read()).Status, "actual Native binding must read only its pending root's cache");
            Task? retiring = null;
            if (change == "cancel") f.Cancellation.Cancel();
            else if (change == "retire") retiring = f.Native!.DisposeAsync().AsTask();
            else if (change == "remove") f.Vault.DeleteRefreshToken(f.Key);
            else f.Vault.SaveRefreshToken(change == "same" ? f.Key : f.Options.AuthorityId + ":synthetic-other", "synthetic-new-credential");
            var bytes = File.ReadAllBytes(f.VaultPath);
            AssertEqual(false, f.Pending!.IsCompleted, "original held HTTP must still be pending during retirement check");
            var after = await f.Read(direct: true);
            AssertEqual(false, after.Status == "ok", "cancel/retire/replacement must invalidate display before the late HTTP reply");
            f.Transport.Release.TrySetResult();
            var final = (await f.Pending.WaitAsync(TimeSpan.FromSeconds(3))).Response;
            if (retiring is not null) await retiring.WaitAsync(TimeSpan.FromSeconds(3));
            AssertEqual(false, final.Payload.TryGetProperty("restoreDisplayReadId", out _), "invalidated scope cannot claim live continuity");
            AssertEqual(false, final.Payload.TryGetProperty("retainedDisplay", out _), "original restore cannot adopt replacement credentials");
            if (change is "cancel" or "retire")
            {
                // Join the independent flight: a cancelled display waiter may
                // return before its token/identity work has actually drained.
                await f.OAuth!.TryRestoreSessionAsync(default);
                AssertEqual(f.Key, f.Vault.LoadActiveAccountKey(), "waiter retirement leaves the independent flight's committed credential selected");
                AssertEqual("synthetic-cold-rotated", f.Vault.LoadRefreshToken(f.Key), "independent flight preserves its actual committed synthetic credential");
                var committed = f.Vault.CaptureRetirement(f.Key);
                AssertEqual(false, committed == originalVersion, "exact encrypted version advances once from the seed");
                AssertEqual(stage == "identity", committed == heldVersion, "identity reply cannot rotate a second time; token reply must commit");
                AssertEqual(1, f.Transport.Kinds.Count(kind => kind == "token"), "display retirement leaves exactly one token rotation");
            }
            else
                AssertEqual(true, bytes.SequenceEqual(File.ReadAllBytes(f.VaultPath)), "late original reply must preserve actual replacement/removed vault bytes");
        }
    }

    internal static async Task RestoreDisplayOwnerPreparation()
    {
        foreach (var logout in new[] { false, true })
        {
            await using var f = await RestoreDisplayFixture.Create();
            var coordinator = new RestoreOwnerCoordinator();
            using var reader = new S2CompatibilityReader(coordinator, UnavailableLegacyRelayAccountPort.Instance);
            f.Start("none", reader: reader);
            await coordinator.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            try
            {
                AssertEqual(1L, f.Runtime!.Generation, "real authentication, not cache, advances generation");
                AssertEqual(false, f.Pending!.IsCompleted, "root still awaits original local-owner verification");
                AssertEqual("ok", (await f.Read()).Status, "only the original pending root's display child crosses its own authenticated transition");
                AssertEqual("offlineAccount.context_changed", (await f.Read(generation: 1)).Error?.Code,
                    "current-generation requests cannot impersonate the original display transaction");
                AssertEqual("offlineAccount.invalid_request", (await f.Read(context: f.Owner)).Error?.Code,
                    "display ID must not carry account authority");
                var unavailable = false;
                try { f.Host!.ResolveLocalDataOwner(f.Owner); }
                catch (StarBridge.HostRuntime.Privacy.LocalPrivacyOwnerUnavailableException) { unavailable = true; }
                AssertEqual(true, unavailable, "cached historical storage must not satisfy current writable local ownership");
                if (logout)
                {
                    await f.Host!.LogoutAsync(f.Owner, default);
                    AssertEqual(2L, f.Runtime.Generation, "a separate actual logout has its own generation");
                    AssertEqual(false, (await f.Read()).Status == "ok", "unrelated account transition retires pending display immediately");
                }
                coordinator.Release.TrySetResult();
                var final = await f.Pending.WaitAsync(TimeSpan.FromSeconds(3));
                if (!logout)
                {
                    AssertEqual("signedIn", final.Response.Payload.GetProperty("state").GetString(), "original owner finishes normally");
                    AssertEqual(f.ReadId, final.Response.Payload.GetProperty("restoreDisplayReadId").GetString(), "explicit continuity belongs only to the original display");
                    AssertEqual(0L, final.Response.SessionGeneration, "wire response preserves original root generation");
                    AssertEqual(true, final.Events.Any(e => e.Name == "account.changed" && e.SessionGeneration == 1 &&
                        e.Sequence > f.Prepared!.Sequence), "original generation event remains after the progress sequence");
                }
                else AssertEqual(false, final.Response.Payload.TryGetProperty("restoreDisplayReadId", out _), "logout cannot prove continuity");
                AssertEqual(false, (await f.Read(direct: true)).Status == "ok", "display read ID retires when original root returns");
            }
            finally { coordinator.Release.TrySetResult(); }
        }
    }

    internal static async Task RestoreDisplayAdmission()
    {
        foreach (var boundary in new[] { "freshSignIn", "ownerMismatch", "unprotectedVault", "notRequested" })
        {
            await using var f = await RestoreDisplayFixture.Create();
            if (boundary == "ownerMismatch") new OfflineAccountStore(f.Root).Observe(
                f.Owner with { Subject = "synthetic-other" }, "Other cached pilot", () => true);
            var memory = boundary == "unprotectedVault" ? new MemoryTokenVault() : null;
            memory?.SaveRefreshToken(f.Key, "synthetic-memory-refresh");
            f.Start("token", requireFresh: boundary == "freshSignIn", memory: memory, requestProgress: boundary != "notRequested");
            if (boundary != "freshSignIn") await f.Transport!.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            AssertEqual<BridgeEnvelope?>(null, f.Prepared, "unproven/other selected owner must not publish any preparing display");
            if (boundary == "freshSignIn") AssertEqual(0, f.Transport!.Requests, "fresh-sign-in owner must not restore existing credentials");
            f.Transport!.Release.TrySetResult();
            await f.Pending!.WaitAsync(TimeSpan.FromSeconds(3));
        }
    }

    internal static async Task RestoreDisplayOutcomes()
    {
        foreach (var stage in new[] { "token", "identity" })
        foreach (var outcome in new[] { "outage", "reject" })
        {
            await using var f = await RestoreDisplayFixture.Create();
            f.Start(stage);
            f.Transport!.AfterHold = outcome;
            await f.Transport.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            var requests = f.Transport.Requests;
            AssertEqual("ok", (await f.Read()).Status, "cache is readable before the actual network outcome");
            AssertEqual(requests, f.Transport.Requests, "cached display must not send HTTP or register business identity");
            f.Transport.Release.TrySetResult();
            var final = (await f.Pending!.WaitAsync(TimeSpan.FromSeconds(3))).Response;
            AssertEqual(false, (await f.Read()).Status == "ok", "completed original read cannot keep its display capability");
            if (outcome == "outage" || stage == "identity")
            {
                AssertEqual("credentialTemporarilyUnavailable", final.Payload.GetProperty("state").GetString(), "actual outage remains unauthenticated");
                AssertEqual(f.ReadId, final.Payload.GetProperty("restoreDisplayReadId").GetString(), "outage continuation proves exact original presentation");
                var nextId = final.Payload.GetProperty("retainedDisplay").GetProperty("readId").GetString();
                var next = await f.Native!.DispatchAsync(BridgeEnvelope.Request("account.offlineData.read",
                    Guid.NewGuid().ToString("N"), 0, new { schemaVersion = 1, readId = nextId, kind = "profile" }));
                AssertEqual("ok", next.Response.Status, "normal strict retained read takes over after root completion");
            }
            else
            {
                AssertEqual("reauthorizationRequired", final.Payload.GetProperty("state").GetString(), "rejection cannot retain preparing display");
                AssertEqual(false, final.Payload.TryGetProperty("restoreDisplayReadId", out _), "rejection has no continuity proof");
                AssertEqual(false, final.Payload.TryGetProperty("retainedDisplay", out _), "rejection has no display selection");
            }
        }
    }

    internal static async Task RestoreDisplayStorageOwnerChange()
    {
        await using var f = await RestoreDisplayFixture.Create();
        var historical = f.Owner with { Authority = "synthetic-past-storage", Subject = "synthetic-past-owner" };
        new OfflineAccountStore(f.Root).Observe(f.Owner, "Historical display", () => true, historical);
        new StarBridge.HostRuntime.Profiles.LocalPersonalProfileStore(f.Root).Save(historical, 0,
            Guid.NewGuid().ToString("N"), new("Historical pilot", "Historical storage content", 0, "none", [], []), () => true);
        var coordinator = new RestoreOwnerCoordinator();
        using var reader = new S2CompatibilityReader(coordinator, UnavailableLegacyRelayAccountPort.Instance);
        f.Start("businessIdentity", reader: reader);
        await coordinator.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        try
        {
            AssertEqual("Historical storage content", (await f.Read()).Payload.GetProperty("content").GetProperty("introduction").GetString(),
                "prior verified storage is presentation only while current ownership is unknown");
            coordinator.Release.TrySetResult();
            await f.Transport!.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            AssertEqual(f.Owner, f.Host!.ResolveLocalDataOwner(f.Owner), "actual new unlinked mapping selects the current SCM storage");
            AssertEqual(false, f.Pending!.IsCompleted, "hold optional discovery after actual owner confirmation");
            var stillReadable = (await f.Read()).Status == "ok";
            f.Transport.Release.TrySetResult();
            var final = (await f.Pending.WaitAsync(TimeSpan.FromSeconds(3))).Response;
            AssertEqual(false, stillReadable, "confirmed storage replacement must retire the historical display scope before root completion");
            AssertEqual(false, final.Payload.TryGetProperty("restoreDisplayReadId", out _), "different storage cannot prove presentation continuity");
        }
        finally { coordinator.Release.TrySetResult(); f.Transport!.Release.TrySetResult(); }
    }

    internal static async Task RestoreDisplayOptionValidation()
    {
        await using var f = await RestoreDisplayFixture.Create();
        f.Start("none", requireFresh: true);
        await f.Pending!.WaitAsync(TimeSpan.FromSeconds(3));
        object[] malformed = [
            new { schemaVersion = 1, restoreDisplayProgress = "true" },
            new { schemaVersion = 1, restoreDisplayProgress = 1 },
            new { schemaVersion = 1, restoreDisplayProgress = true, owner = "synthetic-forged-owner" },
            System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(
                "{\"schemaVersion\":1,\"restoreDisplayProgress\":true,\"restoreDisplayProgress\":false}")
        ];
        foreach (var body in malformed)
        {
            var response = await f.Native!.DispatchAsync(BridgeEnvelope.Request("account.getCurrent",
                Guid.NewGuid().ToString("N"), 0, body));
            AssertEqual(BridgeErrorCodes.InvalidEnvelope, response.Response.Error?.Code, "optional display request schema must fail closed");
        }
        var authority = await f.Native!.DispatchAsync(BridgeEnvelope.Request("account.getCurrent",
            Guid.NewGuid().ToString("N"), 0, new { schemaVersion = 1, restoreDisplayProgress = true }, f.Owner));
        AssertEqual(BridgeErrorCodes.InvalidEnvelope, authority.Response.Error?.Code, "display opt-in must not select an account context");
        var declined = await f.Native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent",
            Guid.NewGuid().ToString("N"), 0, new { schemaVersion = 1, restoreDisplayProgress = false }));
        AssertEqual("signedOut", declined.Response.Payload.GetProperty("state").GetString(), "false opt-in preserves original fresh sign-in state");
        AssertEqual(0, f.Transport!.Requests, "schema rejection or declined display must not restore an unselected account");
        AssertEqual<BridgeEnvelope?>(null, f.Prepared, "invalid or declined requests emit no cached display");
    }

    private sealed class RestoreOwnerCoordinator : IAccountCompatibilityCoordinator
    {
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public async Task<AccountBridgeCompatibilityProjection> ReadAsync(ScmOAuthSession session, CancellationToken token)
        {
            Entered.TrySetResult();
            await Release.Task.WaitAsync(token);
            return new("unlinked", "notApplicable", false, false, [], null);
        }
        public Task<AccountBridgeCompatibilityProjection> LinkExistingAsync(ScmOAuthSession s,
            LegacyIdentityLinkPasswordCredential? credential, CancellationToken token) => throw new InvalidOperationException("Unexpected link");
        public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(ScmOAuthSession s,
            CancellationToken token) => throw new InvalidOperationException("Unexpected provisioning");
    }

    private sealed class RestoreDisplayFixture : IAsyncDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "StarBridge-restore-display-" + Guid.NewGuid().ToString("N"));
        internal readonly ScmEnvironmentSettings Settings = CreateEnvironmentSettings();
        internal ScmOAuthOptions Options => ScmOAuthOptions.Create(Settings);
        internal string VaultPath => Path.Combine(Root, "vault.json");
        internal WindowsTokenVault Vault => new(VaultPath);
        internal string Key => Options.AuthorityId + ":synthetic-cold-owner";
        internal BridgeAccountContext Owner => new(Settings.EnvironmentName, Options.AuthorityId, "synthetic-cold-owner");
        internal readonly CancellationTokenSource Cancellation = new();
        internal ColdContentHandler? Transport;
        internal ScmAccountBridgeHost? Host;
        internal OAuthPkceClient? OAuth;
        internal AccountBridgeRuntime? Runtime;
        internal NativeAccountRuntimeBinding? Native;
        internal Task<BridgeDispatchBatch>? Pending;
        internal BridgeEnvelope? Prepared;
        internal string ReadId => Prepared!.Payload.GetProperty("retainedDisplay").GetProperty("readId").GetString()!;
        internal static async Task<RestoreDisplayFixture> Create(StarBridge.HostRuntime.Friends.FriendsReader? friends = null,
            Func<AccountBridgeRuntime, BridgeEnvelope, string, Task>? afterFriendsRead = null)
        {
            var f = new RestoreDisplayFixture();
            Directory.CreateDirectory(f.Root);
            f.Vault.SaveRefreshToken(f.Key, "synthetic-original-refresh");
            using var transport = new ColdContentHandler(f.Options, "none");
            using var runtime = new AccountBridgeRuntime(new ScmAccountBridgeHost(
                new OAuthPkceClient(new ScmHttpClient(transport), f.Vault, f.Options),
                new ScmProfileCacheStore(Path.Combine(f.Root, "profile")), f.Settings.EnvironmentName, () => null, friends: friends));
            runtime.InitializeOfflineAccount(f.Root);
            AssertEqual("signedIn", (await ReadCurrent(runtime, "synthetic-restore-seed")).Response.Payload.GetProperty("state").GetString(), "seed actual authenticated root");
            if (friends is not null)
            {
                var directory = (await runtime.DispatchAsync(BridgeEnvelope.Request("friends.read", "synthetic-friends-seed",
                    runtime.Generation, new { schemaVersion = 1 }, f.Owner))).Response;
                AssertEqual("ok", directory.Status, "seed through actual authenticated friends route");
                if (afterFriendsRead is not null) await afterFriendsRead(runtime, directory, f.Root);
            }
            new StarBridge.HostRuntime.Profiles.LocalPersonalProfileStore(f.Root).Save(f.Owner, 0,
                Guid.NewGuid().ToString("N"), new("Stored Pilot", "Stored introduction", 0, "none", [], []), () => true);
            return f;
        }
        internal void Start(string stage, S2CompatibilityReader? reader = null, bool requireFresh = false,
            MemoryTokenVault? memory = null, bool ignoreCancellation = false, bool requestProgress = true)
        {
            Transport = new(Options, stage) { IgnoreCancellation = ignoreCancellation };
            OAuth = new(new ScmHttpClient(Transport), memory is null ? Vault : memory, Options);
            Host = new(OAuth,
                new ScmProfileCacheStore(Path.Combine(Root, "profile")), Settings.EnvironmentName, () => null,
                compatibilityReader: reader, requireFreshSignIn: requireFresh);
            Runtime = new(Host);
            Runtime.InitializeOfflineAccount(Root);
            Native = new(Runtime);
            Native.EventReady += e => { if (e.Name == "account.restoreDisplay") Prepared = e; };
            var payload = new Dictionary<string, object?> { ["schemaVersion"] = 1 };
            if (requestProgress) payload["restoreDisplayProgress"] = true;
            Pending = Native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", "synthetic-restore-pending", Native.Generation,
                payload), Cancellation.Token).AsTask();
        }
        internal async Task<BridgeEnvelope> Read(long generation = 0, BridgeAccountContext? context = null, bool direct = false)
        {
            var request = BridgeEnvelope.Request("account.offlineData.read", Guid.NewGuid().ToString("N"), generation,
                new { schemaVersion = 1, readId = ReadId, kind = "profile" }, context);
            return (direct ? await Runtime!.DispatchAsync(request) : await Native!.DispatchAsync(request)).Response;
        }
        public async ValueTask DisposeAsync()
        {
            Cancellation.Cancel();
            Transport?.Release.TrySetResult();
            if (Pending is not null) await Pending.WaitAsync(TimeSpan.FromSeconds(3));
            if (Native is not null) await Native.DisposeAsync();
            Runtime?.Dispose();
            Transport?.Dispose();
            Cancellation.Dispose();
            Directory.Delete(Root, recursive: true);
        }
    }
}
