using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Updates;
using StarBridge.NativeBridge;

internal static class FlutterInstallerUpdateTests
{
    internal static async Task Verify()
    {
        using var rsa = RSA.Create(2048);
        var keys = new Dictionary<string, string> { ["fixture"] = rsa.ToXmlString(false) };
        using (var buildVersionSource = new FlutterInstallerUpdateSource(new Uri("https://example.invalid/manifest.json"),
            "windows-x64", "0.7.0+1", keys, new ResponseHandler())) { }
        var manifest = new FlutterInstallerUpdateSource.Manifest("flutter", "windows-x64", "inno-setup",
            "0.7.1", "https://example.invalid/installer.exe", new string('a', 64), "New release", "fixture", "");
        FlutterInstallerUpdateSource.Manifest Sign(FlutterInstallerUpdateSource.Manifest value) => value with
        {
            // Independent literal mirrors the existing online-installer signing contract.
            Signature = Convert.ToBase64String(rsa.SignData(Encoding.UTF8.GetBytes(string.Join('\n',
                "starbridge-flutter-installer-manifest-v1", value.ClientKind, value.Platform, value.PackageKind,
                value.Version, value.DownloadUrl, value.DownloadSha256.ToLowerInvariant(),
                Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value.Notes))).ToLowerInvariant())),
                HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1))
        };
        var json = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var transport = new ResponseHandler();
        void Serve(FlutterInstallerUpdateSource.Manifest value) => transport.Body = JsonSerializer.Serialize(value, json);
        Serve(Sign(manifest));
        using var source = new FlutterInstallerUpdateSource(new Uri("https://example.invalid/manifest.json"),
            "windows-x64", "0.7.0+1", keys, transport);
        var result = await source.CheckForUpdateAsync();
        Require(result.Status == "available" && result.Version == "0.7.1" && result.Notes == "New release", "Signed installer not recognized.");
        foreach (var version in new[] { "0.7.0", "0.7.0.0", "0.6.9" })
        {
            Serve(Sign(manifest with { Version = version }));
            result = await source.CheckForUpdateAsync();
            Require(result.Status == "up-to-date" && result.Version is null && result.Notes is null, "Equal/older release offered.");
        }
        Serve(Sign(manifest with { Version = "0.7.0.1" }));
        Require((await source.CheckForUpdateAsync()).Status == "available", "Real fourth-part update missed.");

        using var bridge = new FlutterUpdateBridgeDispatcher(source, () => "0.7.0", () => 1);
        var request = BridgeEnvelope.Request(FlutterUpdateBridgeDispatcher.RequestName, "fixture", 1, new { schemaVersion = 1 });
        async Task RequireRejected()
        {
            var response = (await bridge.DispatchAsync(request)).Response;
            Require(response.Status == "ok" && response.Payload.GetProperty("state").GetString() == "verification-failed" &&
                response.Payload.GetProperty("availableVersion").ValueKind == JsonValueKind.Null &&
                response.Payload.GetProperty("notes").ValueKind == JsonValueKind.Null, "Untrusted metadata leaked or became retryable/latest.");
        }
        foreach (var invalid in new[]
        {
            Sign(manifest) with { Notes = "tampered" }, Sign(manifest) with { Version = "0.6.0" },
            Sign(manifest with { ClientKind = "wpf" }), Sign(manifest with { Platform = "windows-arm64" }),
            Sign(manifest with { PackageKind = "portable-zip" }), Sign(manifest) with { SignatureKeyId = "unknown" },
            Sign(manifest) with { Signature = "invalid" }, Sign(manifest with { Version = "0.7" }),
            Sign(manifest with { Version = "0.7.1+2" }),
            Sign(manifest with { DownloadUrl = "http://example.invalid/untrusted" }),
            Sign(manifest with { DownloadUrl = "https://user:secret@example.invalid/untrusted" }),
            Sign(manifest with { DownloadSha256 = new string('z', 64) })
        }) { Serve(invalid); await RequireRejected(); }
        var validJson = JsonSerializer.Serialize(Sign(manifest), json);
        foreach (var invalid in new[] { "null", "[]", "{}", new string('x', 65537),
            validJson[..^1] + ",\"version\":\"0.7.1\"}",
            validJson[..^1] + ",\"publicKey\":\"attacker\"}",
            validJson.Replace("\"notes\":", "\"Notes\":", StringComparison.Ordinal) })
        { transport.Body = invalid; await RequireRejected(); }
        transport.Body = validJson;
        foreach (var status in new[] { HttpStatusCode.NotFound, HttpStatusCode.Redirect, HttpStatusCode.Forbidden })
        {
            transport.Status = status;
            Require((await source.CheckForUpdateAsync()).Status == "channel-unavailable", "Unavailable channel misreported.");
        }
        foreach (var status in new[] { HttpStatusCode.BadGateway, HttpStatusCode.RequestTimeout, HttpStatusCode.TooManyRequests })
        {
            transport.Status = status;
            var response = (await bridge.DispatchAsync(request)).Response;
            Require(response.Status == "error", "Transient service failure not retryable.");
        }
        transport.Status = HttpStatusCode.OK;
        Require((await bridge.DispatchAsync(request, new CancellationToken(true))).Response.Status == "cancelled", "Cancellation ignored.");
        Require((await bridge.DispatchAsync(request with { SessionGeneration = 2 })).Response.Status == "error", "Stale generation accepted.");
        Require((await bridge.DispatchAsync(request with { AccountContext = new("fixture", "fixture", "fixture") })).Response.Status == "error",
            "Account context accepted by device update.");
        Require((await bridge.DispatchAsync(BridgeEnvelope.Request(FlutterUpdateBridgeDispatcher.PrepareRequestName,
            "prepare", 1, new { schemaVersion = 1, version = "0.7.1" }))).Response.Status == "error", "Check-only source enabled installation.");
        Require(transport.Requests > 0 && !transport.SentCredentials, "Unexpected update credentials.");

        foreach (var url in new string?[] { null, "", " " })
        {
            using var unconfigured = FlutterReleaseUpdateSource.Create(url, "0.7.0", "windows-x64");
            Require((await unconfigured.CheckForUpdateAsync()).Status == "channel-unconfigured", "Missing configuration became latest.");
        }
        foreach (var url in new[] { "http://example.invalid/update", "https://localhost/update", "https://127.0.0.1/update",
            "https://[::1]/update", "https://user:secret@example.invalid/update", "https://example.invalid/update#fragment" })
        {
            using var invalid = FlutterReleaseUpdateSource.Create(url, "0.7.0", "windows-x64");
            Require((await invalid.CheckForUpdateAsync()).Status == "configuration-invalid", "Unsafe build configuration accepted.");
        }
        using var unsupported = FlutterReleaseUpdateSource.Create("https://example.invalid/update", "0.7.0", "windows-arm64");
        Require((await unsupported.CheckForUpdateAsync()).Status == "configuration-invalid", "Unsupported platform silently used x64.");
        using var malformed = FlutterReleaseUpdateSource.Create("https://example.invalid/update", null, "windows-x64");
        Require((await malformed.CheckForUpdateAsync()).Status == "configuration-invalid", "Unknown current version accepted.");
        foreach (var version in new[] { "0.7.0+", "0.7.0++1", "0.7.0+preview", "0.7.0-preview+1" })
        {
            using var invalid = FlutterReleaseUpdateSource.Create("https://example.invalid/update", version, "windows-x64");
            Require((await invalid.CheckForUpdateAsync()).Status == "configuration-invalid", "Malformed/unsupported installed version accepted.");
        }
        var embeddedKeys = FlutterReleaseUpdateSource.ReadTrustedKeys();
        Require(embeddedKeys.Count == 2 && embeddedKeys.ContainsKey("73bfc5146228b248") && embeddedKeys.ContainsKey("facbafaec567677a"),
            "Embedded public key IDs drifted from the existing installer signing contract.");
    }

    private static void Require(bool value, string error) { if (!value) throw new Exception(error); }
    private sealed class ResponseHandler : HttpMessageHandler
    {
        internal string Body = "";
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal int Requests;
        internal bool SentCredentials;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellation)
        {
            Requests++;
            SentCredentials |= request.Headers.Authorization is not null || request.Headers.Contains("Cookie");
            Require(request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/manifest.json", "Unexpected artifact download/write.");
            return Task.FromResult(new HttpResponseMessage(Status) { Content = new StringContent(Body, Encoding.UTF8, "application/json") });
        }
    }
}
