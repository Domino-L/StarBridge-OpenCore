using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static partial class CommunityWpfS2DiscoveryTests
{
    internal static async Task ImageMaintenanceReferences()
    {
        var calls = 0;
        using var handler = new Handler(request =>
        {
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "test-token",
                "Synthetic directory fixture only uses the original authenticated GETs");
            calls++;
            return request.RequestUri!.AbsolutePath switch
            {
                "/api/fleets/membership" => Json(new { fleetCode = "MEMBER" }),
                "/api/fleets/applications/mine" => Json(Array.Empty<object>()),
                "/api/fleets" => Json(new[] { Fleet("PUBLIC", 5, true) }),
                _ => throw new InvalidOperationException("Unexpected fixture route")
            };
        });
        using var client = new CommunityClient(new Uri("https://relay.invalid"), handler);
        const string scope = "synthetic-directory-maintenance";
        Task<CommunityPage> Read() => client.ReadWpfS2Async("test-token", new("discover", "", null, null), scope, "self", default);
        var before = await Read();
        Check(before.Items.Length == 1 && before.Items[0].LogoDeferred && before.Items[0].LogoImageData is null,
            "Actual Native producer defers directory media without discarding metadata");
        JsonElement Body(string target) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target, kind = "logo", offset = 0 });
        var beforeMedia = JsonSerializer.SerializeToElement(await client.ReadMediaAsync("test-token", Body(before.Items[0].TargetRef), scope, default));
        var beforeCalls = calls;
        var root = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "StarBridge-directory-maintenance-" + Guid.NewGuid().ToString("N")));
        Directory.CreateDirectory(root);
        try
        {
            using var support = new ApplicationSupportBridgeDispatcher(root, null,
                clearImageReadCaches: client.ClearDownloadableImageReadCaches);
            var clear = await support.DispatchAsync(BridgeEnvelope.Request("diagnostics.clearImageCache",
                Guid.NewGuid().ToString("N"), 0, new { schemaVersion = 1 }));
            Check(clear.Response.Status == "ok" && clear.Response.Payload.GetProperty("count").GetInt32() == 0,
                "The original zero-file maintenance route still purges Native directory RAM");
            await Error(() => client.ReadMediaAsync("test-token", Body(before.Items[0].TargetRef), scope, default), "communities.refreshRequired");
            Check(calls == beforeCalls, "Purge and stale image lookup do not fetch private workspace data or use a fallback");
            var after = await Read();
            var afterMedia = JsonSerializer.SerializeToElement(await client.ReadMediaAsync("test-token", Body(after.Items[0].TargetRef), scope, default));
            Check(after.Items[0].TargetRef != before.Items[0].TargetRef && after.Items[0].OrganizationRef == before.Items[0].OrganizationRef,
                "A fresh public directory read rebinds media while preserving the stable organization identity");
            Check(afterMedia.GetProperty("data").GetString() == beforeMedia.GetProperty("data").GetString() && calls == beforeCalls + 3,
                "New opaque media reference works through the actual Native producer; no extra bulk download per image");
            await Error(() => client.ReadMediaAsync("test-token", Body(after.Items[0].TargetRef), "different-account-scope", default), "communities.refreshRequired");
            var output = Environment.GetEnvironmentVariable("STARBRIDGE_DIRECTORY_IMAGE_MAINTENANCE_FIXTURE");
            if (!string.IsNullOrEmpty(output))
            {
                var source = Environment.GetEnvironmentVariable("STARBRIDGE_HOST_TEST_SOURCE_ROOT") ?? throw new InvalidOperationException("Missing fixture source root");
                var allowed = Path.GetFullPath(Path.Combine(source, ".artifacts")) + Path.DirectorySeparatorChar;
                output = Path.GetFullPath(output);
                if (!output.StartsWith(allowed, StringComparison.OrdinalIgnoreCase) || Path.GetExtension(output) != ".json")
                    throw new InvalidOperationException("Fixture output must remain in the local test artifacts");
                var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
                File.WriteAllText(output, JsonSerializer.Serialize(new { schemaVersion = 1, producer = "CommunityClient.WpfS2Discovery + original diagnostics dispatcher",
                    before, beforeMedia, clear = clear.Response.Payload, retiredError = "communities.refreshRequired", after, afterMedia }, options));
            }
        }
        finally
        {
            var name = Path.GetFileName(root);
            const string prefix = "StarBridge-directory-maintenance-";
            if (!string.Equals(Path.GetDirectoryName(root), Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())), StringComparison.OrdinalIgnoreCase) ||
                !name.StartsWith(prefix, StringComparison.Ordinal) || !Guid.TryParseExact(name[prefix.Length..], "N", out _))
                throw new InvalidOperationException("Unsafe fixture cleanup");
            Directory.Delete(root, true);
        }
    }
}
