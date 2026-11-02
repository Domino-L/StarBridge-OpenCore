using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime;
using StarBridge.NativeBridge;

internal static partial class OfficialFleetReadTests
{
    internal static async Task RuntimeFleetRoutes()
    {
        using var handler = new Handler();
        using var host = Host(handler);
        using var runtime = new AccountBridgeRuntime(host);
        var owner = host.CurrentContext!;
        var members = await runtime.DispatchAsync(BridgeEnvelope.Request("officialFleet.getMembers", "runtime-members", 1, Query(), owner));
        Require(members.Response.Status == "ok", $"Real Runtime blocked the existing member route: {members.Response.Error?.Code}");
        var communication = await runtime.DispatchAsync(BridgeEnvelope.Request("officialFleet.communication", "runtime-communication", 1,
            new {schemaVersion = 1, sourceRef = "officialFleet:7", action = "open"}, owner));
        Require(communication.Response.Error?.Code != BridgeErrorCodes.CapabilityUnavailable, "Real Runtime must deliver communication to its existing owner, even when this fixture has no Relay session");
    }

    internal static async Task DeferredProfile()
    {
        using var handler = new Handler();
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource<HttpResponseMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        handler.Failure = (request, _) => {
            if (!IsProfile(request)) return null;
            Require(request.Headers.Authorization is null, "Detached public read must not send an account token");
            started.TrySetResult();
            return release.Task;
        };
        using var host = Host(handler);
        using var runtime = new AccountBridgeRuntime(host);
        var owner = host.CurrentContext!;
        var identity = await runtime.DispatchAsync(BridgeEnvelope.Request("officialFleet.getIdentity", "identity-first", 1,
            new { schemaVersion = 1 }, owner)).AsTask().WaitAsync(TimeSpan.FromSeconds(3));
        Require(identity.Response.Status == "ok" && identity.Response.Payload.GetProperty("state").GetString() == "member", "Identity must be available without the optional public response");
        Require(!started.Task.IsCompleted, "Identity must not start or wait for optional public work");
        Require(identity.Response.Payload.GetProperty("profileRead").GetProperty("state").GetString() == "deferred", "Identity states explicitly that profile is independently loaded");
        var pending = runtime.DispatchAsync(BridgeEnvelope.Request("officialFleet.getPublicProfile", "public-profile", 1,
            new { schemaVersion = 1, sourceRef = "officialFleet:7" }, owner));
        try {
            await started.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Require(!pending.IsCompleted, "The profile response must still be pending");
            var account = await runtime.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", "account-unblocked", 1,
                new { schemaVersion = 1 })).AsTask().WaitAsync(TimeSpan.FromSeconds(3));
            Require(account.Response.Status == "ok", "Public profile IO must not keep the account dispatch gate");
            var renewed = await runtime.DispatchAsync(BridgeEnvelope.Request("officialFleet.getIdentity", "identity-again", 1,
                new {schemaVersion = 1}, owner)).AsTask().WaitAsync(TimeSpan.FromSeconds(3));
            Require(renewed.Response.Status == "ok", "Another identity confirmation must not wait for public IO");
            var member = await runtime.DispatchAsync(BridgeEnvelope.Request("officialFleet.getMembers", "members-unblocked", 1,
                Query(), owner)).AsTask().WaitAsync(TimeSpan.FromSeconds(3));
            Require(member.Response.Status == "ok", "Members must not wait for optional public IO");
        }
        finally {
            release.TrySetResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) { Content = new StringContent("{}") });
        }
        var result = await pending;
        Require(result.Response.Status == "ok" && result.Response.Payload.GetProperty("profileRead").GetProperty("state").GetString() == "transientFailure", "Deferred failure preserves its independent classification");
        Require(!result.Response.Payload.TryGetProperty("fleet", out _) && !result.Response.Payload.TryGetProperty("officialRankValue", out _), "Public content response cannot become a cached identity or authority response");
    }

    internal static async Task DeferredProfileLifecycle()
    {
        using var handler = new Handler();
        using var host = Host(handler, new PublicReadVault());
        using var runtime = new AccountBridgeRuntime(host);
        var owner = host.CurrentContext!;
        await runtime.DispatchAsync(BridgeEnvelope.Request("officialFleet.getIdentity", "prepare-public-source", 1,
            new {schemaVersion = 1}, owner));
        var forged = await runtime.DispatchAsync(BridgeEnvelope.Request("officialFleet.getPublicProfile", "forged-public-source", 1,
            new {schemaVersion = 1, sourceRef = "officialFleet:99"}, owner));
        Require(forged.Response.Status == "error", "Public request cannot redirect the source published by Native identity");
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource<HttpResponseMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        handler.Failure = (request, _) => {
            if (!IsProfile(request)) return null;
            started.TrySetResult(); return release.Task;
        };
        var pending = runtime.DispatchAsync(BridgeEnvelope.Request("officialFleet.getPublicProfile", "old-public-source", 1,
            new {schemaVersion = 1, sourceRef = "officialFleet:7"}, owner)).AsTask();
        try {
            await started.Task.WaitAsync(TimeSpan.FromSeconds(3));
            var logout = await runtime.DispatchAsync(BridgeEnvelope.Request("account.logout", "logout-not-blocked", 1,
                new {schemaVersion = 1}, owner)).AsTask().WaitAsync(TimeSpan.FromSeconds(3));
            Require(logout.Response.Status == "ok", "Logout must not wait for optional public work");
            Require(logout.Events.Any(e => e.Name == "account.changed"), "The account transition must be delivered with its own response, not held by public work");
        }
        finally { release.TrySetResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) { Content = new StringContent("{}") }); }
        var late = await pending;
        Require(late.Response.Status != "ok", "Retired public work cannot return a successful old projection");
    }

    private sealed class PublicReadVault : StarBridge.HostRuntime.Auth.ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No credential creation permitted");
        public void DeleteRefreshToken(string key) { }
    }

    internal static async Task<string> DeferredProfileWire()
    {
        using var handler = new Handler();
        using var host = Host(handler);
        using var runtime = new AccountBridgeRuntime(host);
        var owner = host.CurrentContext!;
        async Task<BridgeEnvelope> Invoke(string name, string id) => (await runtime.DispatchAsync(BridgeEnvelope.Request(name, id, 1,
            name == "officialFleet.getPublicProfile" ? JsonSerializer.SerializeToElement(new {schemaVersion = 1, sourceRef = "officialFleet:7"}) : JsonSerializer.SerializeToElement(new {schemaVersion = 1}), owner))).Response;
        var identity = await Invoke("officialFleet.getIdentity", "deferred-identity");
        var profileSuccess = await Invoke("officialFleet.getPublicProfile", "profile-success");
        var legacy = await Invoke("officialFleet.getCurrent", "legacy-identity");
        handler.Failure = (request, _) => IsProfile(request) ? Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) {Content = new StringContent("{}")}) : null;
        var profileTransient = await Invoke("officialFleet.getPublicProfile", "profile-transient");
        handler.Failure = (request, _) => IsProfile(request) ? Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden) {Content = new StringContent("{}")}) : null;
        var profileForbidden = await Invoke("officialFleet.getPublicProfile", "profile-forbidden");
        handler.Failure = null; handler.BadProfile = true;
        var profileInvalid = await Invoke("officialFleet.getPublicProfile", "profile-invalid");
        return JsonSerializer.Serialize(new { identity, profileSuccess, legacy, profileTransient, profileForbidden, profileInvalid }, BridgeProtocol.JsonOptions);
    }
}
