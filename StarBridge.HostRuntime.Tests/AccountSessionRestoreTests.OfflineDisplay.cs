using StarBridge.HostRuntime.Auth;
using System.Net;

internal static partial class AccountSessionRestoreTests
{
    internal static Task NetworkOutageRetainsDisplayThroughBridge() => RetainedDisplayRenewalWire();

    internal static async Task<string> RetainedDisplayRenewalWire()
    {
        var root = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "StarBridge-retained-display-bridge-" + Guid.NewGuid().ToString("N"));
        System.IO.Directory.CreateDirectory(root);
        try
        {
            var settings = CreateEnvironmentSettings();
            var options = ScmOAuthOptions.Create(settings);
            var key = options.AuthorityId + ":synthetic-owner";
            var vault = new WindowsTokenVault(System.IO.Path.Combine(root, "vault.json"));
            vault.SaveRefreshToken(key, "synthetic-private-refresh");
            var bytes = System.IO.File.ReadAllBytes(System.IO.Path.Combine(root, "vault.json"));
            var owner = new StarBridge.NativeBridge.BridgeAccountContext(settings.EnvironmentName, options.AuthorityId, "synthetic-owner");
            var cache = new StarBridge.HostRuntime.Account.OfflineAccountStore(root);
            cache.Observe(owner, "Retained Pilot", () => true, owner);
            new StarBridge.HostRuntime.Profiles.LocalPersonalProfileStore(root).Save(owner, 0, Guid.NewGuid().ToString("N"),
                new("Retained Pilot", "Retained own introduction", 0, "none", [], []), () => true);
            new StarBridge.HostRuntime.Hangar.LocalHangarStore(root).Save(owner, 0, "synthetic-own-inventory",
                [new StarBridge.Core.Hangar.CollectedHangarShip("synthetic-pledge", 0, "Synthetic Own Ship", null, null)], false, false);
            cache.ObserveAchievements(owner, new(1, new() { ["first-entry"] = DateTimeOffset.UtcNow.AddDays(-1) }), () => true);
            var rejected = false;
            var handler = new ScriptedHandler(_ => rejected
                ? JsonResponse(HttpStatusCode.BadRequest, "{\"error\":\"invalid_grant\"}")
                : throw new HttpRequestException("Synthetic network outage"));
            using var account = new StarBridge.HostRuntime.AccountBridgeRuntime(new StarBridge.HostRuntime.Account.ScmAccountBridgeHost(
                new OAuthPkceClient(new ScmHttpClient(handler), vault, options),
                new ScmProfileCacheStore(System.IO.Path.Combine(root, "profile")), settings.EnvironmentName, () => null));
            account.InitializeOfflineAccount(root);
            await using var native = new StarBridge.HostRuntime.NativeAccountRuntimeBinding(account);
            var response = (await ReadCurrent(account, "synthetic-retained-display")).Response;
            AssertEqual("credentialTemporarilyUnavailable", response.Payload.GetProperty("state").GetString(), "cached name must not authenticate");
            AssertEqual<StarBridge.NativeBridge.BridgeAccountContext?>(null, response.AccountContext, "display must not carry a business owner");
            var display = response.Payload.GetProperty("retainedDisplay");
            var first = response;
            var firstId = display.GetProperty("readId").GetString();
            AssertEqual(3, display.EnumerateObject().Count(), "display contains only name, timestamp and opaque read selection");
            const string image = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
            cache.ObserveAvatarProfile(owner, new(3, "synthetic-public-profile", true, 3, DateTimeOffset.UtcNow,
                new("Retained Pilot", "NotLive", image), StarBridge.Core.Profiles.PersonalProfileContentContract.Empty,
                new("NotLive", "synthetic", null, "synthetic", "blue")), () => true);
            response = (await ReadCurrent(account, "synthetic-retained-avatar")).Response;
            display = response.Payload.GetProperty("retainedDisplay");
            var second = response;
            AssertEqual(firstId, display.GetProperty("previousReadId").GetString(), "only the exact previous display owner may retain presentation");
            AssertEqual(6, display.EnumerateObject().Count(), "optional avatar and presentation continuity add no authority");
            AssertEqual(image, display.GetProperty("avatarImageData").GetString(), "network outage retains exact-owner real avatar bytes");
            AssertEqual("Retained Pilot", display.GetProperty("displayName").GetString(), "cold network outage retains exact owner name");
            AssertEqual(true, display.GetProperty("cachedAtUtc").GetDateTimeOffset() > DateTimeOffset.UnixEpoch, "display confirmation time");
            AssertEqual(false, response.Payload.GetRawText().Contains("synthetic-private-refresh"), "credential leaked to Bridge");
            AssertEqual(true, bytes.SequenceEqual(System.IO.File.ReadAllBytes(System.IO.Path.Combine(root, "vault.json"))), "display read changed credential vault");
            var readId = display.GetProperty("readId").GetString()!;
            async Task<StarBridge.NativeBridge.BridgeEnvelope> ReadData(string kind, string? selected = null,
                StarBridge.NativeBridge.BridgeAccountContext? injected = null, Dictionary<string, object?>? extra = null)
            {
                var payload = new Dictionary<string, object?> { ["schemaVersion"] = 1, ["readId"] = selected ?? readId, ["kind"] = kind };
                if (extra is not null) foreach (var pair in extra) payload[pair.Key] = pair.Value;
                return (await native.DispatchAsync(StarBridge.NativeBridge.BridgeEnvelope.Request("account.offlineData.read",
                    Guid.NewGuid().ToString("N"), account.Generation, payload, injected))).Response;
            }
            var traffic = handler.RequestCount;
            foreach (var kind in new[] { "profile", "hangar", "achievements" })
            {
                var data = await ReadData(kind);
                AssertEqual("ok", data.Status, "retained data route: " + kind);
                AssertEqual<StarBridge.NativeBridge.BridgeAccountContext?>(null, data.AccountContext, "cache read context");
                AssertEqual(false, data.Payload.GetRawText().Contains("synthetic-private-refresh"), "cache read secret leak");
                var retainedValue = kind switch { "profile" => "Retained own introduction", "hangar" => "Synthetic Own Ship", _ => "first-entry" };
                AssertEqual(true, data.Payload.GetRawText().Contains(retainedValue), "cache route must return original content, not empty success: " + kind);
            }
            AssertEqual(traffic, handler.RequestCount, "cached reads must not call network or award achievements");
            AssertEqual("offlineAccount.invalid_request", (await ReadData("profile", injected: owner)).Error?.Code, "caller cannot choose account");
            AssertEqual("offlineAccount.invalid_request", (await ReadData("profile", extra: new() { ["subject"] = "synthetic-other" })).Error?.Code, "extra owner field rejected");
            AssertEqual("offlineAccount.invalid_request", (await ReadData("save")).Error?.Code, "writes unavailable");
            AssertEqual("offlineAccount.context_changed", (await ReadData("hangar", Guid.NewGuid().ToString("N"))).Error?.Code, "unknown selection rejected");
            AssertEqual("hangar.revision_conflict", (await ReadData("hangar", extra: new() { ["inventoryRevision"] = 999 })).Error?.Code, "inventory pagination revision guard");
            var renewed = (await ReadCurrent(account, "synthetic-renew-selection")).Response;
            AssertEqual(readId, renewed.Payload.GetProperty("retainedDisplay").GetProperty("previousReadId").GetString(), "same credential renewal identifies only its immediate predecessor");
            var retired = await ReadData("profile");
            AssertEqual("offlineAccount.context_changed", retired.Error?.Code, "new account observation retires old read selection");
            AssertEqual("offlineAccount.invalid_request", (await ReadData("profile", extra: new() { ["previousReadId"] = readId })).Error?.Code,
                "display continuity cannot be submitted as cache-read authority");
            vault.SaveRefreshToken(key, "synthetic-replacement-refresh");
            var replaced = (await ReadCurrent(account, "synthetic-replaced-credential")).Response;
            AssertEqual(false, replaced.Payload.GetProperty("retainedDisplay").TryGetProperty("previousReadId", out _), "even same-account credential replacement cannot claim display continuity");
            foreach (var other in new[] {
                owner with { Subject = "synthetic-other" },
                owner with { Environment = "different-environment" },
                owner with { Authority = "different-authority" } })
            {
                cache.Observe(other, "Must Not Show", () => true);
                AssertEqual(false, (await ReadCurrent(account, Guid.NewGuid().ToString("N"))).Response.Payload.TryGetProperty("retainedDisplay", out _), "mismatched cache owner leaked");
            }
            cache.Observe(owner, "Retained Pilot", () => true);
            cache.Pin(owner, 42, () => true);
            AssertEqual(false, (await ReadCurrent(account, "synthetic-manual-offline")).Response.Payload.TryGetProperty("retainedDisplay", out _), "network route adopted a manual-offline revision");
            cache.Observe(owner, "Retained Pilot", () => true);
            rejected = true;
            response = (await ReadCurrent(account, "synthetic-rejected")).Response;
            AssertEqual("reauthorizationRequired", response.Payload.GetProperty("state").GetString(), "rejection state");
            AssertEqual(false, response.Payload.TryGetProperty("retainedDisplay", out _), "rejected credential inherited display");
            return System.Text.Json.JsonSerializer.Serialize(new { first, second, renewed, retired, replaced }, StarBridge.NativeBridge.BridgeProtocol.JsonOptions);
        }
        finally { System.IO.Directory.Delete(root, recursive: true); }
    }

    internal static async Task RestoreCannotReplaceConcurrentLogin()
    {
        foreach (var stage in new[] { "token", "identity" })
        foreach (var result in new[] { "success", "reject", "outage", "mismatch", "unauthorized" })
        foreach (var change in new[] { "other", "same", "logout" })
            await RestoreRace(stage, result, change);
        Console.WriteLine("PASS 30 stale refresh races preserve concurrent login/logout without selecting old display data");
    }

    private static async Task RestoreRace(string stage, string result, string change)
    {
        var root = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "StarBridge-restore-race-" + Guid.NewGuid().ToString("N"));
        System.IO.Directory.CreateDirectory(root);
        try
        {
            var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
            var key = options.AuthorityId + ":synthetic-original";
            var replacement = change == "same" ? key : options.AuthorityId + ":synthetic-replacement";
            var path = System.IO.Path.Combine(root, "vault.json");
            var vault = new WindowsTokenVault(path);
            vault.SaveRefreshToken(key, "synthetic-original-refresh");
            byte[]? replacementBytes = null;
            var handler = new ScriptedHandler(request =>
            {
                var currentStage = request.RequestUri == options.TokenEndpoint ? "token" : "identity";
                if (currentStage == stage)
                {
                    // A different login completes while the old HTTP request is outstanding.
                    var otherWriter = new WindowsTokenVault(path);
                    if (change == "logout") otherWriter.DeleteRefreshToken(key);
                    else otherWriter.SaveRefreshToken(replacement, "synthetic-new-login");
                    replacementBytes = System.IO.File.ReadAllBytes(path);
                    if (result == "outage") throw new HttpRequestException("Synthetic outage");
                    if (result == "reject") return JsonResponse(HttpStatusCode.BadRequest, "{\"error\":\"invalid_grant\"}");
                    if (result == "unauthorized" && currentStage == "identity")
                        return JsonResponse(HttpStatusCode.Unauthorized, "{\"message\":\"Synthetic authentication denied\"}");
                }
                if (currentStage == "token")
                    return JsonResponse(HttpStatusCode.OK,
                        "{\"access_token\":\"synthetic-old-access\",\"refresh_token\":\"synthetic-old-rotation\",\"token_type\":\"Bearer\",\"expires_in\":3600}");
                return JsonResponse(HttpStatusCode.OK, result == "mismatch"
                    ? "{\"subject\":\"synthetic-wrong\",\"displayName\":\"Synthetic\",\"capabilities\":[\"profile.read\"]}"
                    : "{\"subject\":\"synthetic-original\",\"displayName\":\"Synthetic\",\"capabilities\":[\"profile.read\"]}");
            });
            var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
            var rejectedCredentials = new List<(string Authority, string Subject)>();
            oauth.StoredCredentialRejected += (authority, subject) => rejectedCredentials.Add((authority, subject));
            ScmOAuthSession? restored = null;
            try { restored = await oauth.TryRestoreSessionAsync(default); }
            catch (HttpRequestException) { }
            catch (InvalidOperationException) when (oauth.LastSessionRestoreOutcome == ScmSessionRestoreOutcome.ReauthorizationRequired) { }
            AssertEqual<ScmOAuthSession?>(null, restored, "late response admitted old online session");
            AssertEqual(change == "logout" ? null : replacement, vault.LoadActiveAccountKey(), "late old refresh changed selected account");
            if (change != "logout") AssertEqual("synthetic-new-login", vault.LoadRefreshToken(replacement), "late old refresh changed new credential");
            AssertEqual(true, replacementBytes is not null && replacementBytes.SequenceEqual(System.IO.File.ReadAllBytes(path)),
                $"late response changed committed vault bytes: {stage}/{result}/{change}");
            AssertEqual<ScmOfflineDisplayOwner?>(null, oauth.ReadOfflineDisplayOwner(), "old refresh selected stale display data");
            if (change != "logout")
                AssertEqual(0, rejectedCredentials.Count, $"late response retired a concurrent login's authorization: {stage}/{result}/{change}");
            else
                AssertEqual(true, rejectedCredentials.All(value => value == (options.AuthorityId, "synthetic-original")),
                    "completed original logout must not retire another owner");
        }
        finally { System.IO.Directory.Delete(root, recursive: true); }
    }

    internal static async Task OfflineDisplaySelection()
    {
        var root = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "StarBridge-display-selection-" + Guid.NewGuid().ToString("N"));
        System.IO.Directory.CreateDirectory(root);
        try
        {
            var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
            var key = options.AuthorityId + ":synthetic-owner";
            var vault = new WindowsTokenVault(System.IO.Path.Combine(root, "vault.json"));
            vault.SaveRefreshToken(key, "synthetic-refresh");
            var phase = "outage";
            using var cancellation = new CancellationTokenSource();
            OAuthPkceClient? oauth = null;
            var handler = new ScriptedHandler(request =>
            {
                AssertEqual<ScmOfflineDisplayOwner?>(null, oauth!.ReadOfflineDisplayOwner(), "in-flight restore is not a completed outage");
                if (phase == "cancel")
                {
                    cancellation.Cancel();
                    throw new TaskCanceledException("Synthetic caller cancellation");
                }
                if (phase == "reject") return JsonResponse(HttpStatusCode.BadRequest, "{\"error\":\"invalid_grant\"}");
                if (phase == "rotate" && request.RequestUri == options.TokenEndpoint)
                    return JsonResponse(HttpStatusCode.OK,
                        "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-rotated\",\"token_type\":\"Bearer\",\"expires_in\":3600}");
                throw new HttpRequestException("Synthetic outage");
            });
            oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
            var rejectedCredentials = new List<(string Authority, string Subject)>();
            oauth.StoredCredentialRejected += (authority, subject) => rejectedCredentials.Add((authority, subject));
            AssertEqual<ScmOfflineDisplayOwner?>(null, oauth.ReadOfflineDisplayOwner(), "no attempted restore must select a cached account");
            async Task Outage()
            {
                try { await oauth.TryRestoreSessionAsync(default); throw new Exception("Expected simulated network failure"); }
                catch (HttpRequestException) { }
            }
            await Outage();
            var original = oauth.ReadOfflineDisplayOwner();
            AssertEqual("synthetic-owner", original?.Subject, "outage must retain exact selected subject");
            AssertEqual(options.AuthorityId, original?.Authority, "outage authority");
            AssertEqual("synthetic-refresh", vault.LoadRefreshToken(key), "display selection must not modify credentials");
            vault.SaveRefreshToken(key, "synthetic-replacement");
            AssertEqual<ScmOfflineDisplayOwner?>(null, oauth.ReadOfflineDisplayOwner(), "same-account replacement invalidates old selection");
            await Outage();
            AssertEqual("synthetic-owner", oauth.ReadOfflineDisplayOwner()?.Subject, "new attempt may select current original owner");
            vault.SaveRefreshToken(options.AuthorityId + ":synthetic-other", "synthetic-other-refresh");
            AssertEqual<ScmOfflineDisplayOwner?>(null, oauth.ReadOfflineDisplayOwner(), "account switch invalidates selection");
            vault.SaveRefreshToken(key, "synthetic-next");
            phase = "rotate";
            await Outage();
            AssertEqual("synthetic-owner", oauth.ReadOfflineDisplayOwner()?.Subject, "profile outage after token rotation retains original owner");
            AssertEqual("synthetic-rotated", vault.LoadRefreshToken(key), "rotation uses actual committed credential");
            phase = "cancel";
            try { await oauth.TryRestoreSessionAsync(cancellation.Token); throw new Exception("Expected cancellation"); }
            catch (OperationCanceledException) { }
            AssertEqual<ScmOfflineDisplayOwner?>(null, oauth.ReadOfflineDisplayOwner(), "caller cancellation is not a completed network outage");
            AssertEqual(0, rejectedCredentials.Count, "outage, rotation or cancellation retired authorization");
            // The rotated refresh is retained while identity is unavailable
            // (2026-10-21); a replaced credential drops it, so the rejection
            // below still comes from the token endpoint.
            vault.SaveRefreshToken(key, "synthetic-after-outage");
            phase = "reject";
            await oauth.TryRestoreSessionAsync(default);
            AssertEqual<ScmOfflineDisplayOwner?>(null, oauth.ReadOfflineDisplayOwner(), "explicit rejection cannot select offline display by credential");
            AssertEqual<string?>(null, vault.LoadActiveAccountKey(), "rejection preserves existing revocation behavior");
            AssertEqual(true, rejectedCredentials.SequenceEqual([(options.AuthorityId, "synthetic-owner")]),
                "explicit rejection must retire only its original credential owner");
            phase = "outage";
            await oauth.TryRestoreSessionAsync(default);
            AssertEqual<ScmOfflineDisplayOwner?>(null, oauth.ReadOfflineDisplayOwner(), "missing credential cannot select old cache");
            AssertEqual(1, rejectedCredentials.Count, "missing credential manufactured another rejection");
            Console.WriteLine("PASS offline display selection: outage, rotation, same-account replacement, switch, rejection and missing credential");
        }
        finally { System.IO.Directory.Delete(root, recursive: true); }
    }
}
