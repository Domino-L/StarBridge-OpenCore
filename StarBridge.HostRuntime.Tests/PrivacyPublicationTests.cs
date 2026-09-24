using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class PrivacyPublicationTests
{
    private static readonly BridgeAccountContext Owner = new("test", "privacy.invalid", "OwnerMixed");
    private static PrivacyPublicationInput Input => new(Owner, 1, "Handle_Mixed", true, "EPTU",
        new(new("connected", "US", "pub_use1b_00000_001"), new("confirmed", "Orison"),
            new("confirmed", "ANVL_Test", "Test Ship")));
    private static LocalPrivacySettings Settings => new(true,
        new(PlayerSharedStateFields.Presence, false, true, []),
        new(PlayerSharedStateFields.Ship | PlayerSharedStateFields.Location | PlayerSharedStateFields.Server, true));
    public static Task Projection()
    {
        foreach (var state in new[] { "confirmed", "likely", "possible", "unknown" })
        {
            var input = Input with { Game = Input.Game with { Location = new(state, "Test Location") } };
            foreach (bool? hide in new bool?[] { null, true, false })
            {
                var choices = Settings with { HideLowConfidenceLocation = hide };
                var projected = PrivacyPublicationPayload.Build(input, choices, false);
                var allowed = state == "confirmed" || (hide == false && state is "likely" or "possible");
                Require(projected.GetProperty("location").GetString() == (allowed ? "Test Location" : "Unknown"),
                    "Absent policy stays high-only; explicit off permits inferred locations only.");
                Require(projected.GetProperty("locationConfidence").GetString() == (!allowed ? "None" :
                    state == "confirmed" ? "High" : state == "likely" ? "Medium" : "Low"), "Preserve evidence confidence.");
                Require(PrivacyPublicationPayload.Build(input, choices, true).GetProperty("location").GetString() == "Unknown",
                    "Withdrawal overrides confidence preference.");
                Require(PrivacyPublicationPayload.Build(input, choices, false, PlayerPresenceVisibilityMode.Invisible)
                    .GetProperty("location").GetString() == "Unknown", "Invisible overrides confidence preference.");
                var transient = input with { Game = input.Game with { Location = input.Game.Location with { CanSynchronize = false } } };
                Require(PrivacyPublicationPayload.Build(transient, choices, false).GetProperty("location").GetString() == "Unknown",
                    "Display-only locations cannot be synchronized.");
                var noLocationAudience = choices with {
                    Room = choices.Room with { AllMembersCanView = false },
                    Fleet = choices.Fleet with { AllMembersCanView = false, AdministratorsCanView = false }
                };
                Require(PrivacyPublicationPayload.Build(input, noLocationAudience, false).GetProperty("location").GetString() == "Unknown",
                    "Disabling the confidence filter cannot grant an audience.");
                var disconnected = input with { Game = input.Game with { Server = new("unknown") } };
                Require(PrivacyPublicationPayload.Build(disconnected, choices, false).GetProperty("location").GetString() == "Unknown",
                    "Inferred evidence cannot survive loss of the connected session.");
            }
        }
        Require(!JsonSerializer.SerializeToElement(Settings, LocalPrivacyStore.Json).TryGetProperty("hideLowConfidenceLocation", out _),
            "Absent optional policy preserves legacy integrity serialization.");
        var savedPolicy = Settings with { HideLowConfidenceLocation = false };
        using (var fixture = new Fixture())
        {
            var store = new LocalPrivacyStore(fixture.Root);
            store.Save(Owner, 0, Guid.NewGuid().ToString("N"), savedPolicy, () => true);
            Require(new LocalPrivacyStore(fixture.Root).Read(Owner).Settings?.HideLowConfidenceLocation == false,
                "Explicit inferred-location choice survives account-scoped storage reload.");
        }
        var payload = PrivacyPublicationPayload.Build(Input, Settings, false);
        Require(payload.GetProperty("name").GetString() == "Handle_Mixed", "Preserve Handle case.");
        Require(payload.GetProperty("fleetSharedStateFields").GetInt32() == 1 &&
            payload.GetProperty("roomSharedStateFields").GetInt32() == 14, "Independent axes.");
        Require(payload.GetProperty("ship").GetString() == "Test Ship" && payload.GetProperty("location").GetString() == "Orison",
            "Current confirmed source only.");
        Require(!payload.TryGetProperty("ownedShips", out _) && !payload.TryGetProperty("accountId", out _),
            "No inventory erase, local files, credentials or client-authored account IDs.");
        Require(!payload.TryGetProperty("personalHangarSharedWithFleet", out _) &&
            !payload.TryGetProperty("sharedEvents", out _) && !payload.TryGetProperty("sharedEventTypes", out _),
            "Realtime publication cannot revoke inventory sharing or event consent.");
        foreach (var input in new[] { Input with { GameVersion = null }, Input with { Game = GameLogSessionSnapshot.Empty } })
        {
            var stale = PrivacyPublicationPayload.Build(input, Settings, false);
            Require(stale.GetProperty("location").GetString() == "Unknown" && stale.GetProperty("serverShard").ValueKind == JsonValueKind.Null,
                "Lost session evidence strips stale server/location.");
        }
        var noAudience = Settings with { Fleet = Settings.Fleet with { AllMembersCanView = false }, Room = Settings.Room with { AllMembersCanView = false } };
        Require(!PrivacyPublicationPayload.Build(Input, noAudience, false).GetProperty("online").GetBoolean(), "No audience means no live content.");
        var clear = PrivacyPublicationPayload.Build(Input, Settings, true);
        Require(!clear.TryGetProperty("personalHangarSharedWithFleet", out _) &&
            !clear.TryGetProperty("sharedEvents", out _), "Withdrawal also leaves other publication domains untouched.");
        Require(clear.GetProperty("roomSharedStateFields").GetInt32() == 0 && clear.GetProperty("fleetSharedStateFields").GetInt32() == 0 &&
            !clear.GetProperty("online").GetBoolean() && clear.GetProperty("liveStatus").GetString() == "Offline" &&
            clear.GetProperty("serverShard").ValueKind == JsonValueKind.Null, "Clear removes both axes and stale values.");
        return Task.CompletedTask;
    }

    public static async Task Lifecycle()
    {
        using var fixture = new Fixture();
        var store = new LocalPrivacyStore(fixture.Root);
        var current = Input;
        var sent = new List<JsonElement>();
        bool fail = false;
        using var publisher = new PrivacyPublication(store, () => current, (_, data, _) => {
            sent.Add(data.Clone());
            return fail ? Task.FromException(new HttpRequestException()) : Task.CompletedTask;
        }, startTimer: false);
        store.Save(Owner, 0, Guid.NewGuid().ToString("N"), Settings, () => true);
        await publisher.TickAsync();
        Require(sent.Count == 0, "Existing local save is not consent to publish.");
        current = current with { IdentityConfirmed = false };
        Require((await publisher.ApplyAsync(Owner, 1, 1, default)).State == "identityRequired" && sent.Count == 0,
            "Unconfirmed identity cannot begin sharing.");
        current = Input;
        Require((await publisher.ApplyAsync(Owner, 1, 1, default)).State == "applied", "Explicit apply acknowledges revision.");
        store.Save(Owner, 1, Guid.NewGuid().ToString("N"), Settings with { PublicationEnabled = false }, () => true);
        await publisher.TickAsync();
        Require(publisher.Status.State == "withdrawn" && !sent[^1].GetProperty("online").GetBoolean(), "Saved off clears live state.");
        store.Save(Owner, 2, Guid.NewGuid().ToString("N"), Settings, () => true);
        await publisher.TickAsync();
        Require(!sent[^1].GetProperty("online").GetBoolean(), "Turning off revokes consent; merely saving on does not reauthorize.");
        await publisher.ApplyAsync(Owner, 1, 3, default);
        Require(publisher.Status.AppliedRevision == 3, "Explicit confirmation restores the current saved revision.");
        fail = true;
        Require(!await publisher.StopAsync(default) && publisher.Status.State == "withdrawalPending", "Failed withdrawal is not success.");
        fail = false;
        await publisher.TickAsync();
        Require(publisher.Status.State == "withdrawn" && !sent[^1].GetProperty("online").GetBoolean(), "Reconnect retries only withdrawal.");
        var count = sent.Count;
        await publisher.TickAsync();
        Require(sent.Count == count, "Stopped sharing is not restored by timer.");
        await publisher.ApplyAsync(Owner, 1, 3, default);
        current = Input with { Owner = Owner with { Subject = "Other" }, Generation = 2 };
        publisher.Invalidate();
        Require(publisher.Status.State == "inactive", "Account event clears status before the next timer tick.");
        count = sent.Count;
        await publisher.TickAsync();
        Require(sent.Count == count && publisher.Status.State == "inactive", "New account never inherits consent.");
    }

    public static async Task Ordering()
    {
        using var fixture = new Fixture();
        var store = new LocalPrivacyStore(fixture.Root);
        var current = Input;
        var entered = new TaskCompletionSource();
        var release = new TaskCompletionSource();
        var sent = new List<JsonElement>();
        using var publisher = new PrivacyPublication(store, () => current, async (_, data, token) => {
            sent.Add(data.Clone());
            if (sent.Count == 1) { entered.SetResult(); await release.Task.WaitAsync(token); }
        }, startTimer: false);
        store.Save(Owner, 0, Guid.NewGuid().ToString("N"), Settings, () => true);
        var apply = publisher.ApplyAsync(Owner, 1, 1, default);
        await entered.Task;
        var stop = publisher.StopAsync(default);
        Require(!stop.IsCompleted, "Withdrawal queues behind in-flight publication.");
        release.SetResult();
        await apply; await stop;
        Require(sent.Count == 2 && !sent[^1].GetProperty("online").GetBoolean(), "Clear is the final write, not a racing old publish.");
        current = current with { Generation = 2 };
        try { await publisher.ApplyAsync(Owner, 1, 1, default); throw new Exception("Expected stale rejection"); }
        catch (LocalPrivacyException e) when (e.Code == "privacy_publication.account_changed") { }
    }

    public static async Task FailClosed()
    {
        using var fixture = new Fixture();
        var store = new LocalPrivacyStore(fixture.Root);
        var sent = new List<JsonElement>();
        bool rejectOnline = false;
        bool rejectClear = false;
        using var publisher = new PrivacyPublication(store, () => Input, (_, data, _) => {
            sent.Add(data.Clone());
            var online = data.GetProperty("online").GetBoolean();
            return (online && rejectOnline) || (!online && rejectClear)
                ? Task.FromException(new AccountBridgeHostException("privacy_publication.response_invalid"))
                : Task.CompletedTask;
        }, startTimer: false);
        await publisher.StopAsync(default);
        Require(sent.Count == 0, "Inactive shutdown cannot write remote state.");
        await publisher.StopAsync(default, explicitRequest: true);
        Require(sent.Count == 1 && !sent[0].GetProperty("online").GetBoolean(), "Explicit stop can withdraw a previous client's state.");
        store.Save(Owner, 0, Guid.NewGuid().ToString("N"), Settings, () => true);
        rejectOnline = rejectClear = true;
        await publisher.ApplyAsync(Owner, 1, 1, default);
        Require(sent.Count == 3 && publisher.Status.State == "withdrawalPending", "Uncertain acknowledgement triggers a compensating clear.");
        rejectOnline = rejectClear = false;
        await publisher.TickAsync();
        Require(!sent[^1].GetProperty("online").GetBoolean() && publisher.Status.State == "withdrawn", "Reconnect never restores uncertain publication.");
        var count = sent.Count;
        await publisher.TickAsync();
        Require(sent.Count == count, "Explicit apply is required after failed publication.");
        await publisher.ApplyAsync(Owner, 1, 1, default);
        var file = Directory.GetFiles(Path.Combine(fixture.Root, "privacy-local-v1"), "*.json").Single();
        File.WriteAllText(file, "invalid fixture policy");
        await publisher.TickAsync();
        Require(!sent[^1].GetProperty("online").GetBoolean() && publisher.Status.State == "failed", "Unreadable policy clears previously published state.");
        File.Delete(file);
        store.Save(Owner, 0, Guid.NewGuid().ToString("N"), Settings, () => true);
        await publisher.ApplyAsync(Owner, 1, 1, default);
        File.Delete(file);
        await publisher.TickAsync();
        Require(!sent[^1].GetProperty("online").GetBoolean() && publisher.Status.State == "failed", "Missing policy also clears previously published state.");
    }

    public static async Task Wire()
    {
        var calls = new List<string>();
        bool dropFields = false;
        string? sharingContext = "VERIFIED-FLEET";
        using var handler = new Handler(async (request, token) => {
            calls.Add(request.Method + " " + request.RequestUri!.AbsolutePath);
            Require(request.Headers.Authorization?.Scheme == "Bearer", "SCM bearer only.");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/membership")
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new
                    { fleetCode = sharingContext, fleetCodes = new[] { "OTHER-COMMUNITY", "VERIFIED-FLEET" } }) };
            if (request.Method == HttpMethod.Get)
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new[] { new { groupId = "owned" } }) };
            var body = await request.Content!.ReadFromJsonAsync<JsonElement>(token);
            Require(body.GetProperty("fleetVisibilityGroupIds").GetArrayLength() == 0 &&
                body.GetProperty("roomVisibilityGroupIds").GetArrayLength() == 0, "Retired group references never reach publication.");
            if (body.GetProperty("online").GetBoolean())
                Require(body.GetProperty("fleet").GetString() == (sharingContext ?? "No Fleet"),
                    "Fleet uses the explicit sharing context, never the first item of multiple memberships.");
            var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = dropFields ? JsonContent.Create(new { name = "Handle_Mixed" }) :
                new StringContent(JsonSerializer.Serialize(body, new JsonSerializerOptions { WriteIndented = true })) };
            response.Headers.Add("X-StarBridge-Realtime-Version", "1");
            return response;
        });
        using var writer = new PrivacyRelayWriter(new Uri("https://privacy.invalid"), handler);
        var settings = Settings with { Fleet = Settings.Fleet with { VisibilityGroupIds = ["owned"] } };
        await writer.SendAsync("fixture-bearer", PrivacyPublicationPayload.Build(Input, settings, false), default);
        Require(calls.SequenceEqual(new[] { "GET /api/fleets/membership", "POST /api/players/realtime" }), "Membership checked without querying retired groups.");
        sharingContext = null;
        await writer.SendAsync("fixture-bearer", PrivacyPublicationPayload.Build(Input, settings, false), default);
        sharingContext = "VERIFIED-FLEET";
        calls.Clear();
        await writer.SendAsync("fixture-bearer", PrivacyPublicationPayload.Build(Input,
            settings with { Fleet = settings.Fleet with { VisibilityGroupIds = ["foreign"] } }, false), default);
        Require(calls.SequenceEqual(new[] { "GET /api/fleets/membership", "POST /api/players/realtime" }),
            "Legacy references do not block unrelated audiences or authorize any group.");
        dropFields = true;
        try { await writer.SendAsync("fixture-bearer", PrivacyPublicationPayload.Build(Input, Settings, true), default); throw new Exception("Expected echo rejection"); }
        catch (AccountBridgeHostException e) when (e.Code == "privacy_publication.response_invalid") { }
        foreach (var code in new[] { HttpStatusCode.Redirect, HttpStatusCode.Unauthorized, HttpStatusCode.Forbidden,
            HttpStatusCode.Gone, HttpStatusCode.NotFound, HttpStatusCode.MethodNotAllowed })
        {
            var attempts = new List<string>();
            using var denied = new PrivacyRelayWriter(new Uri("https://privacy.invalid"), new Handler((request, _) => {
                attempts.Add(request.Method + " " + request.RequestUri!.AbsolutePath);
                return Task.FromResult(new HttpResponseMessage(code));
            }));
            try { await denied.SendAsync("fixture-bearer", PrivacyPublicationPayload.Build(Input, Settings, true), default); throw new Exception("Expected denied route"); }
            catch (AccountBridgeHostException) { }
            Require(attempts.SequenceEqual(new[] { "POST /api/players/realtime" }),
                "Unsupported service never falls back to destructive legacy full publication.");
        }
        foreach (var version in new[] { "", "2" })
        {
            using var incompatible = new PrivacyRelayWriter(new Uri("https://privacy.invalid"), new Handler(async (request, token) => {
                var response = new HttpResponseMessage(HttpStatusCode.OK) { Content =
                    new StringContent(await request.Content!.ReadAsStringAsync(token)) };
                if (version.Length > 0) response.Headers.Add("X-StarBridge-Realtime-Version", version);
                return response;
            }));
            try { await incompatible.SendAsync("fixture-bearer", PrivacyPublicationPayload.Build(Input, Settings, true), default); throw new Exception("Expected version rejection"); }
            catch (AccountBridgeHostException e) when (e.Code == "privacy_publication.response_invalid") { }
        }
        foreach (var status in new[] { HttpStatusCode.RequestTimeout, HttpStatusCode.TooManyRequests,
            HttpStatusCode.InternalServerError, HttpStatusCode.BadGateway, HttpStatusCode.ServiceUnavailable, HttpStatusCode.GatewayTimeout })
        {
            using var unavailable = new PrivacyRelayWriter(new Uri("https://privacy.invalid"),
                new Handler((_, _) => Task.FromResult(new HttpResponseMessage(status))));
            try { await unavailable.SendAsync("fixture-bearer", PrivacyPublicationPayload.Build(Input, Settings, true), default); throw new Exception("Expected transient failure"); }
            catch (AccountBridgeHostException e) when (e.Code == "privacy_publication.temporarily_unavailable") { }
        }
    }

    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => send(request, cancellationToken); }
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Fixture : IDisposable
    {
        public string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-privacy-publication-test-" + Guid.NewGuid().ToString("N"));
        public void Dispose() { if (Directory.Exists(Root)) Directory.Delete(Root, true); }
    }
}
