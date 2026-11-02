using System.Net;
using System.Net.Http.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class PersonalProfileReadFailureTests
{
    internal static async Task Run()
    {
        var failures = new List<string>();
        foreach (var legacy in new[] { true, false })
        {
            foreach (var (status, code, retryable) in new[] {
                (HttpStatusCode.Unauthorized, "account.reauthorization_required", false),
                (HttpStatusCode.Forbidden, "personal_profile.read_forbidden", false),
                (HttpStatusCode.NotFound, "personal_profile.read_unavailable", false),
                (HttpStatusCode.Redirect, "personal_profile.read_unavailable", false),
                ((HttpStatusCode)799, "personal_profile.read_unavailable", false),
                (HttpStatusCode.RequestTimeout, "personal_profile.read_transient", true),
                (HttpStatusCode.TooManyRequests, "personal_profile.read_transient", true),
                (HttpStatusCode.InternalServerError, "personal_profile.read_transient", true),
                (HttpStatusCode.ServiceUnavailable, "personal_profile.read_transient", true) })
            {
                await Verify(legacy, $"http-{(int)status}", (_, _) => Task.FromResult(
                    new HttpResponseMessage(status) { Content = new StringContent("{}") }),
                    !legacy && status == HttpStatusCode.Unauthorized ? "personal_profile.read_transient" : code,
                    !legacy && status == HttpStatusCode.Unauthorized || retryable, failures);
            }
            await Verify(legacy, "transport", (_, _) => throw new HttpRequestException("synthetic transport"),
                "personal_profile.read_transient", true, failures);
            await Verify(legacy, "deadline", (_, _) => throw new OperationCanceledException("synthetic deadline"),
                "personal_profile.read_transient", true, failures);
            await Verify(legacy, "broken-stream", (_, _) => throw new IOException("synthetic stream disconnect"),
                "personal_profile.read_transient", true, failures);
            await Verify(legacy, "invalid-data", (_, _) => throw new InvalidDataException("synthetic invalid content"),
                "personal_profile.data_invalid", false, failures);
            await Verify(legacy, "bad-json", (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                { Content = new StringContent("{invalid") }), "personal_profile.data_invalid", false, failures);
            await Verify(legacy, "bad-schema", (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                { Content = JsonContent.Create(Document with { SchemaVersion = 999 }) }),
                "personal_profile.data_invalid", false, failures);
            foreach (var (name, invalid) in new[] {
                ("missing-content", Document with { Content = null! }),
                ("missing-identity", Document with { Identity = null! }),
                ("empty-id", Document with { PublicId = "" }),
                ("negative-revision", Document with { Revision = -1 }) })
                await Verify(legacy, name, (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                    { Content = JsonContent.Create(invalid) }), "personal_profile.data_invalid", false, failures);
            if (legacy)
                await Verify(true, "wrong-owner", (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                    { Content = JsonContent.Create(Document with { PublicId = "other-owner" }) }),
                    "personal_profile.data_invalid", false, failures);
            await VerifyCancellation(legacy);
        }
        await VerifyGeneration();
        if (failures.Count != 0) throw new InvalidOperationException(string.Join(Environment.NewLine, failures));
        Console.WriteLine("PASS personal profile Relay and SCM read failures preserve transport, authorization, schema and cancellation boundaries");
    }

    private static readonly PersonalProfileDocumentContract Document = new(
        3, "synthetic-owner", true, 1, DateTimeOffset.UnixEpoch,
        new("Synthetic pilot", ""), PersonalProfileContentContract.Empty, null);

    private static async Task Verify(bool legacy, string name,
        Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> reply,
        string code, bool retryable, List<string> failures)
    {
        var calls = 0;
        using var transport = new Handler((request, token) => { calls++; return reply(request, token); });
        using var login = new LegacyPasswordLoginClient(new("https://relay.example.invalid/"), new Store(), transport);
        using var host = CreateScm(transport);
        try
        {
            if (legacy) await login.ReadOwnProfileAsync(Credential, default);
            else await host.GetPersonalProfileAsync(host.CurrentContext!, default);
            failures.Add($"{legacy}/{name}: expected failure, got success");
        }
        catch (AccountBridgeHostException error)
        {
            if (error.Code != code || error.Retryable != retryable)
                failures.Add($"{legacy}/{name}: expected {code}/{retryable}, got {error.Code}/{error.Retryable}");
        }
        catch (Exception error) { failures.Add($"{legacy}/{name}: unexpected {error.GetType().Name}"); }
        if (calls != 1) failures.Add($"{legacy}/{name}: read made {calls} requests");
    }

    private static async Task VerifyCancellation(bool legacy)
    {
        using var cancellation = new CancellationTokenSource();
        using var transport = new Handler((_, _) => {
            cancellation.Cancel();
            throw new OperationCanceledException(cancellation.Token);
        });
        using var login = new LegacyPasswordLoginClient(new("https://relay.example.invalid/"), new Store(), transport);
        using var host = CreateScm(transport);
        try
        {
            if (legacy) await login.ReadOwnProfileAsync(Credential, cancellation.Token);
            else await host.GetPersonalProfileAsync(host.CurrentContext!, cancellation.Token);
            throw new InvalidOperationException("Caller cancellation was converted to a result");
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
    }

    private static async Task VerifyGeneration()
    {
        var calls = 0;
        using var transport = new Handler((_, _) => {
            calls++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(Document) });
        });
        using var host = CreateScm(transport);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var result = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.getSelf", "old-generation",
            host.Generation + 1, new { schemaVersion = 1 }, host.CurrentContext));
        if (result.Response.Error?.Code != "bridge.stale_generation" || result.Response.Error.Retryable || calls != 0)
            throw new InvalidOperationException("A wrong generation reached the profile endpoint or became a transient read");
    }

    private static readonly LegacyMigrationCredential Credential = new(
        "synthetic-owner", "synthetic@example.invalid", "synthetic-token", DateTimeOffset.UtcNow);

    private static ScmAccountBridgeHost CreateScm(HttpMessageHandler handler)
    {
        var options = new ScmOAuthOptions("synthetic", new("https://web.example.invalid/"),
            new("https://auth.example.invalid/"), new("https://resource.example.invalid/"),
            "synthetic-client", "starbridge-api", "openid profile.read", "/oauth/callback");
        return new(new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options),
            new ScmProfileCacheStore(), "synthetic", () => null,
            initialSession: new("synthetic", "synthetic-owner", "Synthetic", "synthetic-access",
                DateTimeOffset.MaxValue, ["profile.read"]));
    }

    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> reply) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => reply(request, token); }
    private sealed class Store : ILegacyMigrationCredentialStore
    {
        public LegacyMigrationCredential? Load() => throw new InvalidOperationException("No credential read allowed");
        public void Save(LegacyMigrationCredential credential) => throw new InvalidOperationException("No credential write allowed");
        public void Delete() => throw new InvalidOperationException("No credential delete allowed");
    }
    private sealed class Vault : ITokenVault
    {
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No token write allowed");
        public void DeleteRefreshToken(string key) { }
    }
}
