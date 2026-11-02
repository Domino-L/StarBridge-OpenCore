using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static partial class FirstUseModeTests
{
    private const string OfflineAvatar = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";

    internal static Task OfflineAvatarSurvivesColdStart() => OfflineAvatarCore(null);

    internal static async Task<string> OfflineAvatarWire()
    {
        var messages = new Dictionary<string, BridgeEnvelope>();
        await OfflineAvatarCore((name, message) => messages.Add(name, message));
        return JsonSerializer.Serialize(messages, BridgeProtocol.JsonOptions);
    }

    private static async Task OfflineAvatarCore(Action<string, BridgeEnvelope>? observe)
    {
        using var f = RsiAvatarFixture();
        var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var owner = f.Host.CurrentContext!;
        var online = await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(),
            f.Host.Generation, new { schemaVersion = 1 }));
        Require(online.Response.Status == "ok", "Fresh root owner is required before observing display data");
        f.Transport.SelfProfile = new(3, "synthetic-public-profile", true, 3, DateTimeOffset.UtcNow,
            new("Server Pilot", "NeverLive", OfflineAvatar),
            StarBridge.Core.Profiles.PersonalProfileContentContract.Empty with { Introduction = "Authoritative introduction" },
            new("NeverLive", "synthetic", null, "synthetic", "blue"));
        var avatar = await native.DispatchAsync(BridgeEnvelope.Request("account.readAvatar", Op(),
            f.Host.Generation, new { schemaVersion = 1 }, owner));
        Require(avatar.Response.Status == "ok" && avatar.Response.Payload.GetProperty("imageData").GetString() == OfflineAvatar,
            "Only the real authenticated avatar request warms this fixture; no separate personal-profile read");
        Require((await mode.ApplyRootOfflineAsync(0, Op(), f.Host.Generation, native)).State == "offline", "Explicit offline transition");
        var traffic = f.Transport.AllRequests;
        async Task Check(string label, NativeAccountRuntimeBinding binding, FirstUseModeRuntime current)
        {
            using var reader = binding.CreateModeDispatcher()!;
            var result = await reader.DispatchAsync(BridgeEnvelope.Request(FirstUseModeBridgeDispatcher.ReadRequest,
                Op(), current.ControlGeneration, new { schemaVersion = 1 }));
            var display = result.Response.Payload.GetProperty("offlineAccount");
            Require(display.TryGetProperty("avatarImageData", out var image) && image.GetString() == OfflineAvatar,
                "Warm and cold explicit offline chrome must receive original bounded avatar bytes");
            Require(result.Response.AccountContext is null && !display.TryGetProperty("subject", out _) &&
                !display.TryGetProperty("capabilities", out _), "Cached avatar does not restore a signed-in identity or grant");
            Require(display.GetProperty("avatarCachedAtUtc").GetDateTimeOffset() <= DateTimeOffset.UtcNow &&
                display.GetProperty("avatarCachedAtUtc").GetDateTimeOffset() > DateTimeOffset.UnixEpoch,
                "Avatar observation has a real original timestamp");
            observe?.Invoke(label, result.Response);
            var profile = await reader.DispatchAsync(BridgeEnvelope.Request(FirstUseModeBridgeDispatcher.ProfileRequest,
                Op(), current.ControlGeneration, new { schemaVersion = 1, revision = current.Current.Revision }));
            Require(profile.Response.Status == "ok" && profile.Response.Payload.GetProperty("remote").GetProperty("payload")
                .GetProperty("profile").GetProperty("content").GetProperty("introduction").GetString() == "Authoritative introduction",
                "Avatar preparation reuses the actual protected self-profile snapshot without fabricating blank content");
        }
        await Check("warm", native, mode);
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        await using var coldNative = new NativeAccountRuntimeBinding(cold);
        await Check("cold", coldNative, cold.FirstUseMode!);
        Require(f.Transport.AllRequests == traffic && f.Vault.Loads == 0 && f.Vault.Deletions == 0,
            "Offline display does not load credentials, issue network traffic or retire the original session");
    }

    // SCM avatar = RSI image from the cached /me avatarUrl, served by a synthetic downloader.
    private static LocalAccountStopTests.Fixture RsiAvatarFixture(bool preserveRoot = false)
    {
        var rsiBytes = Convert.FromBase64String(OfflineAvatar["data:image/png;base64,".Length..]);
        var f = new LocalAccountStopTests.Fixture(sampling: true, preserveRoot: preserveRoot,
            rsiAvatarDownload: (_, _) => Task.FromResult<byte[]?>(rsiBytes));
        new ScmProfileCacheStore(Path.Combine(f.Root, "profile")).Save(
            AccountRouteIdentity.Create("synthetic-environment", f.Session.AuthorityId, f.Session.Subject, legacyAccountId: null),
            new StarBridge.Core.Profiles.ScmSelfProfileContract(f.Session.Subject, "Server Pilot",
                "https://robertsspaceindustries.com/media/synthetic/heap_infobox/avatar.png", null, null, null), DateTimeOffset.UtcNow);
        return f;
    }

    // Restart during an RSI outage: the stored avatar stays on screen and in the snapshot.
    internal static async Task OfflineAvatarSurvivesDownloadOutage()
    {
        var warm = RsiAvatarFixture(preserveRoot: true);
        var root = warm.Root;
        try
        {
            DateTimeOffset? originalTime;
            using (warm)
            {
                await RootMode(warm);
                await using var warmNative = new NativeAccountRuntimeBinding(warm.Runtime);
                await warmNative.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), warm.Host.Generation, new { schemaVersion = 1 }));
                var owner = warm.Host.CurrentContext!;
                warm.Transport.SelfProfile = new(3, "synthetic-public-profile", true, 3, DateTimeOffset.UtcNow,
                    new("Server Pilot", "NeverLive", OfflineAvatar), StarBridge.Core.Profiles.PersonalProfileContentContract.Empty,
                    new("NeverLive", "synthetic", null, "synthetic", "blue"));
                var saved = await warmNative.DispatchAsync(BridgeEnvelope.Request("account.readAvatar", Op(), warm.Host.Generation,
                    new { schemaVersion = 1 }, owner));
                Require(saved.Response.Payload.GetProperty("imageData").GetString() == OfflineAvatar, "Warm avatar before the outage");
                originalTime = new OfflineAccountStore(root).ReadSelectedDisplay(owner, () => true)?.AvatarCachedAtUtc;
                Require(originalTime is not null, "Warm avatar has an observation time");
            }
            await Task.Delay(20);
            using var f = new LocalAccountStopTests.Fixture(sampling: true, sharedRoot: root, initializeLocalState: false,
                rsiAvatarDownload: (_, _) => throw new HttpRequestException("synthetic outage"));
            await RootMode(f);
            await using var native = new NativeAccountRuntimeBinding(f.Runtime);
            await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), f.Host.Generation, new { schemaVersion = 1 }));
            f.Transport.SelfProfile = new(3, "synthetic-public-profile", true, 3, DateTimeOffset.UtcNow,
                new("Server Pilot", "NeverLive", OfflineAvatar), StarBridge.Core.Profiles.PersonalProfileContentContract.Empty,
                new("NeverLive", "synthetic", null, "synthetic", "blue"));
            var kept = await native.DispatchAsync(BridgeEnvelope.Request("account.readAvatar", Op(), f.Host.Generation,
                new { schemaVersion = 1 }, f.Host.CurrentContext!));
            Require(kept.Response.Status == "ok" && kept.Response.Payload.GetProperty("imageData").GetString() == OfflineAvatar,
                "Download outage after a restart returns the stored avatar");
            var page = await native.DispatchAsync(BridgeEnvelope.Request("personalProfile.getSelf", Op(), f.Host.Generation,
                new { schemaVersion = 1 }, f.Host.CurrentContext!));
            Require(page.Response.Status == "ok" && page.Response.Payload.GetProperty("profile").GetProperty("identity")
                .GetProperty("avatarAssetId").GetString() == OfflineAvatar, "Self profile keeps the stored avatar through the outage");
            var stored = new OfflineAccountStore(root).ReadSelectedDisplay(f.Host.CurrentContext!, () => true);
            Require(stored?.AvatarImageData == OfflineAvatar, "Download outage does not overwrite the stored avatar");
            Require(stored?.AvatarCachedAtUtc == originalTime, "Kept avatar keeps its original observation time");

            // An internal read that is denied drops the stored copy, so the outage cannot bring it back.
            f.Transport.SelfProfileStatus = System.Net.HttpStatusCode.Forbidden;
            try { await f.Host.GetPersonalProfileAsync(f.Host.CurrentContext!, default); Require(false, "Internal denied read throws"); }
            catch (AccountBridgeHostException) { }
            f.Transport.SelfProfileStatus = System.Net.HttpStatusCode.OK;
            Require(new OfflineAccountStore(root).ReadSelectedDisplay(f.Host.CurrentContext!, () => true)?.AvatarImageData is null,
                "Internal denial removes the stored avatar");
            var current = await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), f.Host.Generation, new { schemaVersion = 1 }));
            Require(!current.Response.Payload.TryGetProperty("avatarImageData", out var shown) || shown.ValueKind == JsonValueKind.Null,
                "Account chrome does not bring back the denied avatar");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, recursive: true); }
    }

    // Confirmed no avatar on an internal read drops the stored image but keeps the saved profile.
    internal static async Task OfflineAvatarConfirmedAbsent()
    {
        using var f = RsiAvatarFixture();
        await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), f.Host.Generation, new { schemaVersion = 1 }));
        var owner = f.Host.CurrentContext!;
        f.Transport.SelfProfile = new(3, "synthetic-public-profile", true, 3, DateTimeOffset.UtcNow,
            new("Server Pilot", "NeverLive", OfflineAvatar),
            StarBridge.Core.Profiles.PersonalProfileContentContract.Empty with { Introduction = "Authoritative introduction" },
            new("NeverLive", "synthetic", null, "synthetic", "blue"));
        var saved = await native.DispatchAsync(BridgeEnvelope.Request("account.readAvatar", Op(), f.Host.Generation,
            new { schemaVersion = 1 }, owner));
        Require(saved.Response.Payload.GetProperty("imageData").GetString() == OfflineAvatar, "Warm avatar before it is removed");
        var cache = new OfflineAccountStore(f.Root);
        var savedAt = cache.ReadSelectedDisplay(owner, () => true)?.AvatarCachedAtUtc;
        var profileBefore = cache.ReadSelectedProfile(owner, () => true)!.Remote!;
        new ScmProfileCacheStore(Path.Combine(f.Root, "profile")).Save(
            AccountRouteIdentity.Create("synthetic-environment", f.Session.AuthorityId, f.Session.Subject, legacyAccountId: null),
            new StarBridge.Core.Profiles.ScmSelfProfileContract(f.Session.Subject, "Server Pilot", null, null, null, null), DateTimeOffset.UtcNow);
        await f.Host.GetPersonalProfileAsync(owner, default);
        Require(savedAt is not null && cache.ReadSelectedDisplay(owner, () => true)?.AvatarImageData is null, "Internal read drops the stored image");
        var remote = cache.ReadSelectedProfile(owner, () => true)!.Remote;
        Require(remote?.CachedAtUtc == profileBefore.CachedAtUtc && remote.Payload.GetProperty("profile").GetProperty("content")
            .GetProperty("introduction").GetString() == "Authoritative introduction", "Saved profile text and time stay");
        var current = await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), f.Host.Generation, new { schemaVersion = 1 }));
        Require(!current.Response.Payload.TryGetProperty("avatarImageData", out var shown) || shown.ValueKind == JsonValueKind.Null,
            "Account chrome does not bring back the removed avatar");
    }

    internal static async Task OfflineAvatarReadFailure()
    {
        foreach (var status in new[] { System.Net.HttpStatusCode.Forbidden, System.Net.HttpStatusCode.ServiceUnavailable })
        {
            using var f = RsiAvatarFixture();
            await RootMode(f);
            await using var native = new NativeAccountRuntimeBinding(f.Runtime);
            var owner = f.Host.CurrentContext!;
            await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), f.Host.Generation, new { schemaVersion = 1 }));
            f.Transport.SelfProfile = new(3, "synthetic-public-profile", true, 3, DateTimeOffset.UtcNow,
                new("Server Pilot", "NeverLive", OfflineAvatar), StarBridge.Core.Profiles.PersonalProfileContentContract.Empty,
                new("NeverLive", "synthetic", null, "synthetic", "blue"));
            var saved = await native.DispatchAsync(BridgeEnvelope.Request("account.readAvatar", Op(), f.Host.Generation,
                new { schemaVersion = 1 }, owner));
            Require(saved.Response.Status == "ok", "Warm avatar through the real runtime");
            var cache = new StarBridge.HostRuntime.Account.OfflineAccountStore(f.Root);
            var original = cache.ReadSelectedProfile(owner, () => true)!.Remote;
            Require(original is not null, "Actual profile is protected before injecting a read failure");
            f.Transport.SelfProfileStatus = status;
            var failed = await native.DispatchAsync(BridgeEnvelope.Request("account.readAvatar", Op(), f.Host.Generation,
                new { schemaVersion = 1 }, owner));
            Require(failed.Response.Status == "error", "Real upstream failure must remain visible");
            var retained = cache.ReadSelectedProfile(owner, () => true)!.Remote;
            Require(status == System.Net.HttpStatusCode.Forbidden ? retained is null : retained?.CachedAtUtc == original!.CachedAtUtc,
                "Explicit forbidden removes remote display, transient outage preserves original bytes and time");
            Require((await f.Host.GetCurrentAsync(default)).AvatarImageData ==
                (status == System.Net.HttpStatusCode.Forbidden ? null : OfflineAvatar), "Native chrome memory follows the same field failure policy");
            Require(f.Host.CurrentContext == owner && !f.Vault.Deleted, "Field denial never signs out the root account");
        }
    }

    internal static Task OfflineAvatarCacheGuards()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        var store = new StarBridge.HostRuntime.Account.OfflineAccountStore(f.Root);
        var owner = f.Host.CurrentContext!;
        StarBridge.Core.Profiles.PersonalProfileDocumentContract Profile(string? image) => new(3, "synthetic-public-profile", true,
            3, DateTimeOffset.UtcNow, new("Server Pilot", "NeverLive", image),
            StarBridge.Core.Profiles.PersonalProfileContentContract.Empty, new("NeverLive", "synthetic", null, "synthetic", "blue"));
        store.Observe(owner, "Synthetic Pilot", () => true);
        store.ObserveAvatarProfile(owner, Profile(OfflineAvatar), () => true);
        var data = store.ReadSelectedDisplay(owner, () => true)!;
        Require(data.AvatarImageData == OfflineAvatar && data.AvatarCachedAtUtc is not null, "Same protected self snapshot supplies the display");
        Require(!System.Text.Encoding.UTF8.GetString(File.ReadAllBytes(Path.Combine(f.Root, "offline-account-v1", "snapshot.bin")))
            .Contains(OfflineAvatar, StringComparison.Ordinal), "Avatar bytes are not persisted in plaintext");
        var other = owner with { Subject = owner.Subject.ToUpperInvariant() };
        Require(other != owner && store.ReadSelectedDisplay(other, () => true) is null, "Opaque subject remains case sensitive");
        store.ObserveAvatarProfile(other, Profile(null), () => true);
        store.ObserveAvatarProfile(owner, Profile(null), () => false);
        Require(store.ReadSelectedDisplay(owner, () => true)!.AvatarImageData == OfflineAvatar, "Wrong owner and retired observations cannot clear bytes");
        store.ClearRemoteProfile(other, () => true);
        store.ClearRemoteProfile(owner, () => false);
        Require(store.ReadSelectedDisplay(owner, () => true)!.AvatarImageData == OfflineAvatar, "Clear preserves exact owner and current fence");
        store.ClearRemoteProfile(owner, () => true);
        Require(store.ReadSelectedDisplay(owner, () => true) is { DisplayName: "Synthetic Pilot", AvatarImageData: null },
            "Explicit remote display clear preserves the independent account name");
        foreach (var invalid in new[] { "https://synthetic.invalid/avatar", "data:image/png;base64,bad!",
            "data:image/png;base64," + Convert.ToBase64String(new byte[512 * 1024 + 1]) })
        {
            store.ObserveAvatarProfile(owner, Profile(invalid), () => true);
            Require(store.ReadSelectedDisplay(owner, () => true)!.AvatarImageData is null, "URL, malformed and over-budget data are honest media misses");
        }
        store.ObserveAvatarProfile(owner, Profile(OfflineAvatar), () => true);
        store.Observe(other, "Other Pilot", () => true);
        store.Pin(other, 22, () => true);
        Require(store.ReadDisplay(22) is { DisplayName: "Other Pilot", AvatarImageData: null }, "Account change never inherits prior avatar");
        File.WriteAllBytes(Path.Combine(f.Root, "offline-account-v1", "snapshot.bin"), [1, 2, 3]);
        f.Runtime.InitializeOfflineAccount(f.Root);
        Require(f.Runtime.ReadOfflineAccount(22) is null, "Corrupt protected cache never revives media or identity");
        return Task.CompletedTask;
    }
}
