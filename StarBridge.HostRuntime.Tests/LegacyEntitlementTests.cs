using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;

internal static class LegacyEntitlementTests
{
    internal static async Task Verify()
    {
        var transport = new Transport();
        using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), transport);
        var credential = new LegacyMigrationCredential("synthetic-owner", "test@example.invalid", "test-bearer", DateTimeOffset.UtcNow);
        Check((await client.RedeemEntitlementsAsync(credential, " ", default)).Outcome == "invalidInput" && transport.Calls == 0);
        var result = await client.RedeemEntitlementsAsync(credential, " synthetic-code ", default);
        Check(result.Outcome == "redeemed" && transport.Calls == 1 && transport.Code == "synthetic-code");
        Check(result.Snapshot!.ResolveActive(DateTimeOffset.UtcNow).SequenceEqual(new[] { "test-permanent" }));
        Check((await client.ReadEntitlementsAsync(credential, default)).Outcome == "ready" && transport.Method == HttpMethod.Get);
        var expiry = DateTimeOffset.Parse("2030-01-08T00:00:00Z");
        transport.Body = "{\"accountId\":\"synthetic-owner\",\"temporaryEntitlements\":[{\"entitlement\":\"overlay.skin.verdict\",\"expiresAt\":\"2030-01-08T00:00:00Z\"}]}";
        var timed = await client.RedeemEntitlementsAsync(credential, "synthetic-timed-code", default);
        Check(timed.Outcome == "redeemed");
        Check(timed.Snapshot!.ResolveActive(expiry.AddTicks(-1)).Contains("overlay.skin.verdict"));
        Check(!timed.Snapshot.ResolveActive(expiry).Contains("overlay.skin.verdict"));
        Check(!timed.Snapshot.ResolveActive(expiry.AddDays(1)).Contains("overlay.skin.verdict"));
        foreach (var body in new[] {
            "{\"accountId\":\"another-owner\"}",
            "{\"accountId\":\"synthetic-owner\",\"entitlements\":true}",
            "{\"accountId\":\"synthetic-owner\",\"accountId\":\"synthetic-owner\"}",
            "{\"accountId\":\"synthetic-owner\",\"temporaryEntitlements\":[{\"entitlement\":\"test\",\"expiresAt\":\"bad\"}]}" })
        {
            transport.Body = body;
            var before = transport.Calls;
            result = await client.RedeemEntitlementsAsync(credential, "synthetic-code", default);
            Check(result.Outcome == "uncertain" && result.Snapshot is null && transport.Calls == before + 1);
        }
        foreach (var pair in new[] { (HttpStatusCode.BadRequest, "rejected"), (HttpStatusCode.Unauthorized, "reauthorizationRequired"),
            (HttpStatusCode.TooManyRequests, "throttled"), (HttpStatusCode.InternalServerError, "uncertain"), (HttpStatusCode.Redirect, "uncertain") })
        {
            transport.Status = pair.Item1;
            var before = transport.Calls;
            Check((await client.RedeemEntitlementsAsync(credential, "synthetic-code", default)).Outcome == pair.Item2 && transport.Calls == before + 1);
        }
        transport.Throw = true;
        var count = transport.Calls;
        Check((await client.RedeemEntitlementsAsync(credential, "synthetic-code", default)).Outcome == "uncertain" && transport.Calls == count + 1);
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        try { await client.ReadEntitlementsAsync(credential, cancelled.Token); throw new Exception("Expected cancellation"); }
        catch (OperationCanceledException) { }
    }

    private static void Check(bool value) { if (!value) throw new Exception("Legacy entitlement boundary failed"); }
    private sealed class Store : ILegacyMigrationCredentialStore
    {
        public void Save(LegacyMigrationCredential value) => throw new Exception("No credential mutation");
        public LegacyMigrationCredential? Load() => throw new Exception("No credential lookup");
        public void Delete() => throw new Exception("No credential mutation");
    }
    private sealed class Transport : HttpMessageHandler
    {
        internal int Calls;
        internal bool Throw;
        internal string? Code;
        internal HttpMethod? Method;
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal string Body = "{\"accountId\":\"synthetic-owner\",\"entitlements\":[\"test-permanent\"],\"temporaryEntitlements\":[{\"entitlement\":\"expired\",\"expiresAt\":\"2000-01-01T00:00:00Z\"}]}";
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            Calls++;
            Check(request.Headers.Authorization?.Parameter == "test-bearer" && request.RequestUri!.Query == "");
            Method = request.Method;
            Check(request.RequestUri!.AbsolutePath == (Method == HttpMethod.Post ? "/api/auth/entitlements/redeem" : "/api/auth/session"));
            if (request.Content is not null)
            {
                using var json = JsonDocument.Parse(await request.Content.ReadAsStringAsync(token));
                Check(json.RootElement.EnumerateObject().Count() == 1);
                Code = json.RootElement.GetProperty("code").GetString();
            }
            if (Throw) throw new HttpRequestException("synthetic transport loss");
            return new(Status) { Content = new StringContent(Body) };
        }
    }
}
