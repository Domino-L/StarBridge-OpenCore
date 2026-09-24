using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class CommunitySharingTests
{
    internal static async Task Verify()
    {
        await CommunityMemberSharingTests.Verify();
        var owner = new BridgeAccountContext("test", "privacy.invalid", "fixture-owner");
        var joined = DateTimeOffset.UtcNow;
        var scopes = new[] { new CommunityRealtimeScope("A", joined, PlayerSharedStateFields.Location, false, true, []),
            new CommunityRealtimeScope("B", joined, PlayerSharedStateFields.Ship, false, true, []) };
        var settings = LocalPrivacySettings.EditorDefaults with { Communities = scopes,
            Room = new(PlayerSharedStateFields.None, false) };
        var input = new PrivacyPublicationInput(owner, 1, "Fixture_Handle", true, "EPTU",
            new(new("connected", "US", "fixture-server"), new("confirmed", "Orison"), new("confirmed", "fixture", "Fixture Ship")));
        var root = Path.Combine(Path.GetTempPath(), "starbridge-community-sharing-test-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new LocalPrivacyStore(root);
            Check(!JsonSerializer.Serialize(LocalPrivacySettings.EditorDefaults, LocalPrivacyStore.Json).Contains("communities"),
                "legacy serialization and integrity unchanged for unmigrated settings");
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
            var reopened = new LocalPrivacyStore(root).Read(owner).Settings!;
            Check(reopened.Communities!.Length == 2 && reopened.Communities[1].JoinedAt == joined,
                "independent grants and exact membership instance survive restart");
            Check(!store.HasPublicationConsent(owner), "saving grants alone does not activate sharing");
            Check(store.Read(owner with { Subject = "other" }).Settings is null, "account isolation");
            var payload = PrivacyPublicationPayload.Build(input, reopened, false);
            Check(payload.GetProperty("fleetSharedStateFields").GetInt32() == 0 &&
                payload.GetProperty("ship").GetString() == "Fixture Ship", "scoped fields replace the legacy fleet live axis");
            var hidden = PrivacyPublicationPayload.Build(input, reopened, false, PlayerPresenceVisibilityMode.Invisible);
            Check(hidden.GetProperty("communities").GetArrayLength() == 0 && !hidden.GetProperty("online").GetBoolean(),
                "invisibility removes every organization grant from the outgoing snapshot");
            var calls = new List<string>();
            var drop = false;
            using var writer = new PrivacyRelayWriter(new Uri("https://privacy.invalid"), new Handler(async (request, token) => {
                calls.Add(request.Method + " " + request.RequestUri!.AbsolutePath);
                if (request.Method == HttpMethod.Get)
                    return new(HttpStatusCode.OK) { Content = JsonContent.Create(new CommunitySharingTargets(2, "B", [
                        new("A", "Organization A", joined.AddSeconds(1)), new("B", "Organization B", joined)]), options: LocalPrivacyStore.Json) };
                var body = JsonNode.Parse(await request.Content!.ReadAsStringAsync(token))!.AsObject();
                var entries = body["communities"]!.AsArray();
                Check(entries.Count == 1 && entries[0]!["code"]!.GetValue<string>() == "B", "stale A grant removed without rebinding membership");
                Check(body["state"]!["location"]!.GetValue<string>() == "Unknown" &&
                    body["state"]!["ship"]!.GetValue<string>() == "Fixture Ship", "lost audience strips its fields before upload, B continues");
                if (drop) body["communities"] = new JsonArray();
                var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
                response.Headers.Add("X-StarBridge-Realtime-Version", "3");
                return response;
            }));
            await writer.SendAsync("fixture-bearer", payload, default);
            Check(calls.SequenceEqual(new[] { "GET /api/privacy/community-scopes", "POST /api/players/realtime-scoped" }), "versioned scoped path only");
            drop = true;
            await Reject(() => writer.SendAsync("fixture-bearer", payload, default), "privacy_publication.response_invalid");
            calls.Clear();
            using var unavailable = new PrivacyRelayWriter(new Uri("https://privacy.invalid"), new Handler((request, _) => {
                calls.Add(request.Method + " " + request.RequestUri!.AbsolutePath);
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
            }));
            await Reject(() => unavailable.SendAsync("fixture-bearer", payload, default), "privacy_publication.community_scopes_unavailable");
            Check(calls.Count == 1 && calls[0].StartsWith("GET "), "unsupported server cannot trigger writes or broad legacy fallback");
            var departed = false;
            var writes = 0;
            using var racing = new PrivacyRelayWriter(new Uri("https://privacy.invalid"), new Handler(async (request, token) => {
                if (request.Method == HttpMethod.Get)
                    return new(HttpStatusCode.OK) { Content = JsonContent.Create(new CommunitySharingTargets(2, "B",
                        departed ? [new("B", "B", joined)] : [new("A", "A", joined), new("B", "B", joined)]), options: LocalPrivacyStore.Json) };
                writes++;
                if (!departed) { departed = true; return new(HttpStatusCode.Forbidden); }
                var body = await request.Content!.ReadFromJsonAsync<JsonElement>(token);
                Check(body.GetProperty("communities").GetArrayLength() == 1 &&
                    body.GetProperty("communities")[0].GetProperty("code").GetString() == "B", "racing departure retries only remaining grant");
                var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
                response.Headers.Add("X-StarBridge-Realtime-Version", "3");
                return response;
            }));
            await racing.SendAsync("fixture-bearer", payload, default);
            Check(writes == 2, "one membership reconciliation avoids withdrawing unrelated organizations");
            var current = (Context: (BridgeAccountContext?)owner, Generation: 1L);
            var reads = 0;
            var bridge = new CommunitySharingDispatcher(() => current, (_, _, _) => {
                reads++; return Task.FromResult(new CommunitySharingTargets(2, "B", [new("B", "B", joined)]));
            });
            var request = BridgeEnvelope.Request("privacy.communityTargets", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1 }, owner);
            Check((await bridge.DispatchAsync(request, default)).Response.Error is null && reads == 1, "target read bridge is wired");
            current = (owner with { Subject = "other" }, 2);
            Check((await bridge.DispatchAsync(request, default)).Response.Error?.Code == "privacy_publication.account_changed" && reads == 1,
                "stale target read never crosses account boundary");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    private static async Task Reject(Func<Task> action, string code)
    { try { await action(); } catch (AccountBridgeHostException error) when (error.Code == code) { return; } throw new Exception("Expected " + code); }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request, token); }
}
