using System.Net;
using System.Reflection;
using System.Security.Authentication;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static class ScmRouteStateTests
{
    private static void Check(bool condition, string label)
    { if (!condition) throw new InvalidOperationException("Route state: " + label); }

    private static ScmEnvironmentSettings Settings => new("production", true, true,
        new Uri("https://region.example.invalid/app-api/region"), new Uri("https://web.example.invalid/"),
        new Uri("https://api.example.invalid/"), new Uri("https://resource.example.invalid/"),
        new Uri("https://relay.example.invalid/"), new HashSet<string>(), TimeSpan.FromSeconds(1), TimeSpan.FromDays(1));
    private static ScmRegionRoute Domestic => new(new Uri("https://flowcld.xyz/"), new Uri("https://flowcld.xyz/"),
        "region-api", DateTimeOffset.UtcNow, new Uri("https://ws.flowcld.xyz/"), true);

    private static Task<ScmRuntimeConfiguration> Configure(string root, string? expected = null, Action? called = null) =>
        ScmRuntimeConfiguration.ResolveAsync(Settings, root, (_, _) =>
        {
            Check(expected is null, "cooldown/preference must bypass discovery and preflight");
            called?.Invoke();
            return Task.FromResult(Domestic);
        }, default, _ => { });

    internal static async Task LoginFailures()
    {
        var root = Directory.CreateTempSubdirectory("sb-route-login-").FullName;
        try
        {
            // Exercise both the actual refresh owner and the code-exchange token hop.
            // Reflection avoids opening a browser or making even a loopback HTTP request.
            foreach (var hop in new[] { "exchange", "refresh" })
            foreach (var failure in new[] { "transport", "timeout", "tls", "503", "html", "400-html", "invalid-grant", "invalid-client", "partial-json" })
            {
                var directory = Path.Combine(root, hop + failure);
                var config = await Configure(directory);
                var path = Path.Combine(directory, "scm-route-state.json");
                var vault = new CountingVault(config.OAuthOptions.AuthorityId + ":route-subject", hop == "refresh");
                using var handler = new TokenHandler(failure, config.OAuthOptions);
                var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, config.OAuthOptions) { RouteState = config.RouteState };
                try
                {
                    if (hop == "refresh") await oauth.TryRestoreSessionAsync(default);
                    else
                    {
                        var method = typeof(OAuthPkceClient).GetMethod("ExchangeCodeAsync", BindingFlags.NonPublic | BindingFlags.Instance)!;
                        await (Task)method.Invoke(oauth, ["route-test", "synthetic-code", new Uri("http://127.0.0.1/oauth/callback"),
                            "synthetic-verifier", CancellationToken.None, true])!;
                    }
                }
                catch (Exception exception) when (exception is HttpRequestException or OperationCanceledException or JsonException or
                    InvalidOperationException or AuthenticationException or IOException) { }
                var network = failure is not ("invalid-grant" or "invalid-client" or "partial-json");
                Check(File.Exists(path) == network, hop + failure + " marker classification");
                Check(vault.Saves == 0 && handler.Calls == 1, hop + failure + " no partial token saves");
                if (network && hop == "refresh") Check(vault.LoadActiveAccountKey() is not null, "network failure retains original credential");
                if (network)
                {
                    using var json = JsonDocument.Parse(File.ReadAllText(path));
                    Check(json.RootElement.GetProperty("domesticLoginFailedAt").GetDateTimeOffset().Offset == TimeSpan.Zero, "UTC marker");
                    var next = await Configure(directory, "fallback-login");
                    Check(next.RouteSource == "fallback-login" && next.OAuthOptions.AuthorizationServerBaseUri == Settings.ApiBaseUri,
                        "next startup selects default overseas endpoints");
                    Check(next.RouteState!.Inspect().Reason == "domesticLoginFailed", "cooldown reason");
                    // Only a complete overseas login clears the marker, using the actual restoration path.
                    using var recovery = new TokenHandler("ok", next.OAuthOptions);
                    var restored = await new OAuthPkceClient(new ScmHttpClient(recovery),
                        new CountingVault(next.OAuthOptions.AuthorityId + ":route-subject", true), next.OAuthOptions)
                        { RouteState = next.RouteState }.TryRestoreSessionAsync(default);
                    Check(restored is not null && !File.Exists(path), "successful overseas login removes marker");
                }
            }
            var expiredRoot = Path.Combine(root, "expired");
            Directory.CreateDirectory(expiredRoot);
            var expiredPath = Path.Combine(expiredRoot, "scm-route-state.json");
            File.WriteAllText(expiredPath, JsonSerializer.Serialize(new { scmRouteMode = "auto", domesticLoginFailedAt = DateTimeOffset.UtcNow.AddHours(-25) }));
            var calls = 0;
            var expired = await Configure(expiredRoot, called: () => calls++);
            Check(calls == 1 && expired.RouteSource == "region-api" && !File.Exists(expiredPath), "expired marker removed before discovery");
            var clock = DateTimeOffset.UtcNow;
            var timed = new ScmRouteState(Path.Combine(root, "clock-state"), () => clock);
            timed.StartupFallback(true); timed.SetActive(Domestic); timed.LoginNetworkFailed();
            clock = clock.AddHours(24);
            Check(timed.StartupFallback(true) is null, "24 hour boundary expires");
            var cancelConfig = await Configure(Path.Combine(root, "cancel"));
            using var cancelled = new CancellationTokenSource();
            cancelled.Cancel();
            var cancelVault = new CountingVault(cancelConfig.OAuthOptions.AuthorityId + ":route-subject", true);
            using var cancelHandler = new TokenHandler("transport", cancelConfig.OAuthOptions);
            try
            {
                await new OAuthPkceClient(new ScmHttpClient(cancelHandler), cancelVault, cancelConfig.OAuthOptions)
                    { RouteState = cancelConfig.RouteState }.TryRestoreSessionAsync(cancelled.Token);
                throw new Exception("Caller cancellation lost");
            }
            catch (OperationCanceledException) { }
            Check(!File.Exists(Path.Combine(root, "cancel", "scm-route-state.json")) && cancelVault.Saves == 0,
                "caller cancellation is not network failure");
            Console.WriteLine("PASS route login failures: 18 token-hop cases, no partial saves, restart cooldown, expiry, overseas recovery");
        }
        finally { Directory.Delete(root, true); }
    }

    internal static async Task PreferencesAndBridge()
    {
        var root = Directory.CreateTempSubdirectory("sb-route-bridge-").FullName;
        try
        {
            var config = await Configure(root);
            using var runtime = new AccountBridgeRuntime(new EnvironmentLockedAccountBridgeHost("production")) { RouteState = config.RouteState };
            async Task<JsonElement> Request(string name, object payload)
            {
                var result = await runtime.DispatchAsync(BridgeEnvelope.Request(name, "route-bridge", runtime.Generation, payload));
                Check(result.Response.Status == BridgeResponseStatuses.Ok, name + " succeeds through account dispatcher");
                var wire = result.Response.Payload.GetRawText();
                Check(!wire.Contains("flowcld") && !wire.Contains("example") && !wire.Contains("https") && !wire.Contains("127.0.0.1"), "bridge excludes hosts and addresses");
                Check(result.Response.Payload.EnumerateObject().Select(p => p.Name).Order().SequenceEqual(
                    new[] { "active", "mode", "reason", "restartRequired" }), "exact bridge fields");
                return result.Response.Payload;
            }
            var initial = await Request("account.scmRouteRead", new { schemaVersion = 1 });
            Check(initial.GetProperty("active").GetString() == "domestic" && initial.GetProperty("reason").ValueKind == JsonValueKind.Null, "initial route projection");
            var changed = await Request("account.scmRouteSave", new { schemaVersion = 1, mode = "overseas" });
            Check(changed.GetProperty("restartRequired").GetBoolean() && changed.GetProperty("active").GetString() == "domestic", "save applies only next startup");
            var readAfterSave = await Request("account.scmRouteRead", new { schemaVersion = 1 });
            Check(readAfterSave.GetProperty("restartRequired").GetBoolean(), "read remembers pending mode");
            var next = await Configure(root, "user-overseas");
            var projected = next.RouteState!.Inspect();
            Check(next.RouteSource == "user-overseas" && projected.Active == "overseas" && projected.Reason == "userOverseas" &&
                !projected.RestartRequired, "overseas startup bypasses discovery");
            config.RouteState!.LoginNetworkFailed();
            next.RouteState.LoginSucceeded();
            using (var policy = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "scm-route-state.json"))))
                Check(policy.RootElement.GetProperty("scmRouteMode").GetString() == "overseas" &&
                    policy.RootElement.GetProperty("domesticLoginFailedAt").ValueKind == JsonValueKind.Null,
                    "clearing cooldown retains user preference in shared state file");
            var disabled = await ScmRuntimeConfiguration.ResolveAsync(Settings with { RegionDiscoveryEnabled = false }, root,
                (_, _) => throw new Exception("disabled user-overseas must not discover"), default, _ => { });
            Check(disabled.RouteSource == "user-overseas", "user preference remains visible when discovery disabled");
            foreach (var boundary in new[] { "explicit", "development", "locked" })
            {
                var routed = false;
                var boundaryConfig = await ScmRuntimeConfiguration.ResolveAsync(Settings with
                {
                    HasExplicitRouteOverride = boundary == "explicit", EnvironmentName = boundary == "development" ? "development" : "production",
                    AccountAccessEnabled = boundary != "locked"
                }, root, (_, _) => { routed = true; return Task.FromResult(Domestic); }, default, _ => { });
                Check(boundary == "locked" ? boundaryConfig.RouteSource == "environment-locked" && !routed : routed,
                    "preference does not supersede " + boundary);
            }
            var reset = await Request("account.scmRouteSave", new { schemaVersion = 1, mode = "auto" });
            Check(!reset.GetProperty("restartRequired").GetBoolean(), "changing back to startup mode clears restart flag");
            foreach (var payload in new object[] { new { schemaVersion = 1, mode = "domestic" }, new { schemaVersion = 2, mode = "overseas" },
                new { schemaVersion = 1, mode = "overseas", address = "forbidden" } })
            {
                var bad = await runtime.DispatchAsync(BridgeEnvelope.Request("account.scmRouteSave", "invalid", runtime.Generation, payload));
                Check(bad.Response.Status == BridgeResponseStatuses.Error && config.RouteState!.Inspect().Mode == "auto", "invalid bridge writes rejected");
            }
            var stale = await runtime.DispatchAsync(BridgeEnvelope.Request("account.scmRouteSave", "stale", runtime.Generation + 1, new { schemaVersion = 1, mode = "overseas" }));
            Check(stale.Response.Status == BridgeResponseStatuses.Error, "stale bridge generation rejected");
            config.RouteState!.SetActive(Domestic with { Source = "fallback-preflight", ApiBaseUri = Settings.ApiBaseUri,
                ResourceBaseUri = Settings.ResourceBaseUri, WebSocketBaseUri = Settings.EffectiveWebSocketBaseUri });
            var fallback = await Request("account.scmRouteRead", new { schemaVersion = 1 });
            Check(fallback.GetProperty("reason").GetString() == "domesticUnavailable" && fallback.GetProperty("active").GetString() == "overseas", "preflight fallback projection");
            var statePath = Path.Combine(root, "scm-route-state.json");
            File.WriteAllText(statePath, "{broken");
            var corrupt = await Configure(root);
            Check(corrupt.RouteState!.Inspect().Mode == "auto" && corrupt.RouteSource == "region-api", "corrupt preferences default auto");
            using (var held = new FileStream(statePath, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
                Check((await Configure(root)).RouteState!.Inspect().Mode == "auto", "unreadable preferences default auto");
            Console.WriteLine("PASS route preferences/bridge: persistence, restart, fallback reasons, exact safe fields, corrupt/unreadable defaults, invalid/stale writes");
        }
        finally { Directory.Delete(root, true); }
    }

    private sealed class CountingVault(string key, bool stored) : ITokenVault
    {
        internal int Saves;
        public void SaveRefreshToken(string accountKey, string refreshToken) { Saves++; stored = true; }
        public string? LoadRefreshToken(string accountKey) => stored ? "synthetic-refresh" : null;
        public string? LoadActiveAccountKey() => stored ? key : null;
        public void DeleteRefreshToken(string accountKey) => stored = false;
    }

    private sealed class TokenHandler(string scenario, ScmOAuthOptions options) : HttpMessageHandler
    {
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            // This fixture is the only transport. No default HTTP handler is ever constructed.
            if (request.RequestUri == options.MeEndpoint)
                return Task.FromResult(Reply(200, """{"subject":"route-subject","displayName":"Route Test","capabilities":[]}"""));
            Check(request.RequestUri == options.TokenEndpoint, "only token/identity fixture endpoints");
            return scenario switch
            {
                "transport" => throw new HttpRequestException("Synthetic connection failure"),
                "timeout" => throw new TaskCanceledException("Synthetic timeout"),
                "tls" => throw new HttpRequestException("Synthetic TLS failure", new AuthenticationException()),
                "503" => Task.FromResult(Reply(503, "{}")),
                "html" => Task.FromResult(Reply(200, "<html>unavailable</html>")),
                "400-html" => Task.FromResult(Reply(400, "<html>unavailable</html>")),
                "invalid-grant" => Task.FromResult(Reply(400, """{"error":"invalid_grant"}""")),
                "invalid-client" => Task.FromResult(Reply(401, """{"error":"invalid_client"}""")),
                "partial-json" => Task.FromResult(Reply(200, """{"access_token":"synthetic-access"}""")),
                _ => Task.FromResult(Reply(200, """{"access_token":"synthetic-access","refresh_token":"synthetic-refresh","expires_in":3600,"token_type":"Bearer"}"""))
            };
        }
        private static HttpResponseMessage Reply(int status, string body) => new((HttpStatusCode)status)
        { Content = new StringContent(body, System.Text.Encoding.UTF8, "application/json") };
    }
}
