using System.Net;
using System.Net.Http.Json;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;
using Roster = StarBridge.HostRuntime.OfficialFleet.OfficialFleetPublicRosterDecoder;

internal static partial class OfficialFleetReadTests
{
    private sealed class RosterMemoryVault : ITokenVault
    {
        internal int Writes;
        public void SaveRefreshToken(string key, string value) => Writes++;
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string key) => Writes++;
    }

    private sealed class RosterHttpHandler : HttpMessageHandler
    {
        internal int BootstrapReads, PublicReads;
        internal long FleetId = 7;
        internal string Sid = "ASTER", Subject = "fixture-owner";
        internal bool NoFleet, BadEnvelope, OversizedBody;
        internal TaskCompletionSource? PublicStarted, PublicRelease, BootstrapStarted, BootstrapRelease;
        internal readonly List<Uri> PublicUris = [];
        internal Func<JsonObject, JsonObject>? EditData;
        internal Func<Uri, byte[]>? RawBody;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Uri uri = request.RequestUri!;
            if (uri.AbsolutePath == "/app-api/starbridge/v1/bootstrap") {
                BootstrapReads++;
                Require(uri.Port == 18082 && request.Headers.Authorization?.Parameter == "synthetic-access",
                    "Only the existing bootstrap resource receives the account bearer");
                var fleet = new ScmBootstrapFleet(FleetId, Sid, "Synthetic Fleet", null, true, "Member", 0, []);
                var snapshot = new ScmBootstrapSnapshot(new(Subject, "Synthetic Pilot", null, false), new(false, null),
                    NoFleet ? [] : [fleet], NoFleet ? null : fleet, 0, 1, new() { ["fleets"] = 1 },
                    DateTimeOffset.UtcNow, ["profile.read", "organizations.read"]);
                TaskCompletionSource? bootstrapGate = BootstrapRelease;
                BootstrapStarted?.TrySetResult();
                if (bootstrapGate is not null) await bootstrapGate.Task; // Deliberately ignores cancellation for final-owner tests.
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(snapshot, options: Json) };
            }
            Require(uri.AbsolutePath == "/app-api/member/organization/roster/page" && uri.Port == 18080,
                "The public roster uses its exact existing public route, never registered members or G1");
            Require(request.Method == HttpMethod.Get && request.Headers.Authorization is null,
                "Public core receives neither a resource token nor a write");
            PublicReads++; PublicUris.Add(uri);
            if (RawBody is { } bytes)
            {
                var content = new ByteArrayContent(bytes(uri));
                content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
                return new(HttpStatusCode.OK) { Content = content };
            }
            JsonObject data = BuildRosterHttpData(uri);
            if (EditData is not null) data = EditData(data);
            PublicStarted?.TrySetResult();
            if (PublicRelease is { } gate) await gate.Task; // A late transport success must not bypass completion fences.
            if (OversizedBody) return new(HttpStatusCode.OK) { Content = new StringContent(new string(' ', 1024 * 1024 + 1)) };
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { code = BadEnvelope ? 7 : 0, data, msg = "" }, options: Json) };
        }
    }

    private static ScmAccountBridgeHost PublicRosterHost(RosterHttpHandler handler, RosterMemoryVault? vault = null)
    {
        var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"),
            new("http://127.0.0.1:18080/"), new("http://127.0.0.1:18082/"),
            "starbridge-desktop", "starbridge-api", "organizations.read", "/oauth/callback");
        var session = new ScmOAuthSession("fixture-scm", "fixture-owner", "Synthetic Pilot", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["organizations.read", "profile.read"]);
        return new(new OAuthPkceClient(new ScmHttpClient(handler), vault ?? new RosterMemoryVault(), options),
            new ScmProfileCacheStore(Path.GetTempPath()), "fixture", () => null, initialSession: session, initialGeneration: 1);
    }

    private static JsonElement PublicRosterPayload(string source = "officialFleet:7", string search = "", int page = 1,
        string? generation = null, string? revision = null, int pageSize = 25) => JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, sourceRef = source, search, filter = "all", pageNumber = page, pageSize, generation, revision });

    private static Dictionary<string, string> PublicRosterParameters(Uri uri) => uri.Query.TrimStart('?').Split('&')
        .Select(pair => pair.Split('=', 2)).ToDictionary(pair => Uri.UnescapeDataString(pair[0]),
            pair => Uri.UnescapeDataString(pair[1]), StringComparer.Ordinal);

    private static JsonObject BuildRosterHttpData(Uri uri)
    {
        Dictionary<string, string> query = PublicRosterParameters(uri);
        JsonObject data = RosterFixture();
        data["query"]!["sid"] = query["sid"]; data["snapshot"]!["sid"] = query["sid"];
        data["query"]!["query"] = query["query"]; data["query"]!["page"] = int.Parse(query["page"], System.Globalization.CultureInfo.InvariantCulture);
        data["query"]!["pageSize"] = int.Parse(query["pageSize"], System.Globalization.CultureInfo.InvariantCulture);
        data["query"]!["generation"] = query.GetValueOrDefault("generation");
        data["query"]!["revision"] = query.GetValueOrDefault("revision");
        if (query["query"].Length != 0) {
            JsonObject row = (JsonObject)data["members"]![0]!.DeepClone(); row["handle"] = query["query"];
            data["members"] = new JsonArray(row); data["totalCount"] = 1;
        }
        if (query["page"] != "1") data["members"] = new JsonArray();
        return data;
    }

    private static async Task RunPublicRosterHttpReaderAsync()
    {
        await PublicRosterHttpAndPins();
        await PublicRosterPreflightHasNoIo();
        await PublicRosterScopeAndUnavailable();
        await PublicRosterLateOwnersAndCancellation();
        await PublicRosterForgedSourceDoesNotRetireVerifiedSource();
        await PublicRosterSourceChangedDuringBootstrap();
        await RunPublicRosterProducer45Async();
    }

    private static async Task PublicRosterHttpAndPins()
    {
        using var handler = new RosterHttpHandler(); var vault = new RosterMemoryVault();
        using var host = PublicRosterHost(handler, vault); BridgeAccountContext owner = host.CurrentContext!;
        const string keyword = "Pilot & Wing /é?+";
        Roster.Response result = await host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload(search: " " + keyword + " "), default);
        Require(result.State == Roster.ReadState.Available && result.Page!.Query.Search == keyword
            && result.Page.Query.SourceRef == "officialFleet:7" && result.Page.Query.Sid == "ASTER",
            "The actual Host->OAuth public helper->decoder chain returns only verified-scoped source facts");
        Uri first = handler.PublicUris.Single();
        Require(PublicRosterParameters(first)["query"] == keyword && first.Query.Contains("%26", StringComparison.Ordinal)
            && first.Query.Contains("%2B", StringComparison.OrdinalIgnoreCase) && first.Query.Contains("%2F", StringComparison.OrdinalIgnoreCase),
            "Search is URI encoded rather than becoming another query parameter");
        Roster.Pin pin = result.Page!.Snapshot.Pin;
        Roster.Response second = await host.ReadOfficialFleetPublicRosterAsync(owner,
            PublicRosterPayload(page: 2, generation: pin.Generation, revision: pin.Revision), default);
        Dictionary<string, string> secondQuery = PublicRosterParameters(handler.PublicUris[1]);
        Require(second.State == Roster.ReadState.Available && second.Page!.Snapshot.Pin == pin
            && secondQuery["generation"] == pin.Generation && secondQuery["revision"] == pin.Revision
            && secondQuery["page"] == "2", "Both snapshot pin fields survive the actual public URL and response echo");
        Require(handler.BootstrapReads == 2 && handler.PublicReads == 2 && vault.Writes == 0,
            "There is one bootstrap and one public read per operation, no G1/nickname lookup or persistence");
    }

    private static async Task PublicRosterPreflightHasNoIo()
    {
        using var handler = new RosterHttpHandler(); using var host = PublicRosterHost(handler);
        BridgeAccountContext owner = host.CurrentContext!;
        Action<JsonObject>[] invalid = [
            value => value["schemaVersion"] = 2, value => value["filter"] = "online", value => value["sourceRef"] = "officialFleet:0",
            value => value["sid"] = "CALLER-SID", value => value["search"] = "control\ntext", value => value["search"] = new string('x', 129),
            value => value["pageNumber"] = 0, value => value["pageNumber"] = 4001, value => value["pageSize"] = 32,
            value => value["generation"] = RosterGeneration, value => value["revision"] = RosterRevision,
            value => { value["generation"] = RosterGeneration.ToUpperInvariant(); value["revision"] = RosterRevision; },
            value => value.Remove("sourceRef"), value => value["sourceRef"] = null
        ];
        foreach (Action<JsonObject> mutate in invalid) {
            JsonObject payload = JsonNode.Parse(PublicRosterPayload().GetRawText())!.AsObject(); mutate(payload);
            await RejectPublicRoster(async () => { await host.ReadOfficialFleetPublicRosterAsync(owner,
                JsonSerializer.SerializeToElement(payload), default); }, AccountBridgeStableErrors.OfficialFleetDataInvalid);
        }
        string duplicate = PublicRosterPayload().GetRawText().Replace("\"schemaVersion\":1",
            "\"schemaVersion\":1,\"schemaVersion\":1", StringComparison.Ordinal);
        using var duplicateJson = JsonDocument.Parse(duplicate);
        await RejectPublicRoster(async () => { await host.ReadOfficialFleetPublicRosterAsync(owner, duplicateJson.RootElement, default); },
            AccountBridgeStableErrors.OfficialFleetDataInvalid);
        await RejectPublicRoster(async () => { await host.ReadOfficialFleetPublicRosterAsync(
            owner with { Subject = "other-fixture-account" }, PublicRosterPayload(), default); }, AccountBridgeStableErrors.ReauthorizationRequired);
        Require(handler.BootstrapReads == 0 && handler.PublicReads == 0, "Malformed/foreign-owner payloads have zero HTTP reads");
    }

    private static async Task PublicRosterScopeAndUnavailable()
    {
        using var handler = new RosterHttpHandler(); using var host = PublicRosterHost(handler);
        BridgeAccountContext owner = host.CurrentContext!;
        await RejectPublicRoster(async () => { await host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload("officialFleet:99"), default); },
            AccountBridgeStableErrors.OfficialFleetDataInvalid);
        Require(handler.PublicReads == 0, "Syntactically valid forged source fails authenticated bootstrap before public IO");
        handler.NoFleet = true;
        await RejectPublicRoster(async () => { await host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload(), default); },
            AccountBridgeStableErrors.OfficialFleetDataInvalid);
        handler.NoFleet = false;
        foreach (string sid in new[] { " ASTER", "aster", "A" }) {
            handler.Sid = sid;
            await RejectPublicRoster(async () => { await host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload(), default); },
                AccountBridgeStableErrors.OfficialFleetDataInvalid);
        }
        Require(handler.PublicReads == 0, "Bootstrap SID is not silently trimmed, uppercased or replaced from a caller field");
        handler.Sid = "ASTER";
        handler.Subject = "other-fixture-account";
        await RejectPublicRoster(async () => { await host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload(), default); },
            AccountBridgeStableErrors.OfficialFleetDataInvalid);
        Require(handler.PublicReads == 0, "The original OAuth bootstrap owner check rejects another account before public IO");
        handler.Subject = "fixture-owner";
        handler.EditData = data => { var value = UnavailableRoster("disabled"); value["query"] = data["query"]!.DeepClone(); return value; };
        Roster.Response unavailable = await host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload(), default);
        Require(unavailable.State == Roster.ReadState.Unavailable && unavailable.Page is null && unavailable.Reason == "disabled",
            "A real helper response with typed unavailable does not become an empty list or registered fallback");
        handler.EditData = data => { data["snapshot"]!["revision"] = new string('c', 64); return data; };
        Roster.Response invalid = await host.ReadOfficialFleetPublicRosterAsync(owner,
            PublicRosterPayload(generation: RosterGeneration, revision: RosterRevision), default);
        Require(invalid.State == Roster.ReadState.Invalid && invalid.Page is null, "Response pin mismatch remains typed invalid");
        handler.EditData = null; handler.BadEnvelope = true;
        await RejectPublicRoster(async () => { await host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload(), default); },
            AccountBridgeStableErrors.OfficialFleetDataInvalid);
        handler.BadEnvelope = false; handler.OversizedBody = true;
        await RejectPublicRoster(async () => { await host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload(), default); },
            AccountBridgeStableErrors.OfficialFleetDataInvalid);
    }

    private static async Task PublicRosterLateOwnersAndCancellation()
    {
        foreach (string scenario in new[] { "account", "source", "same-reader-source", "departure", "cancel", "dispose" }) {
            using var handler = new RosterHttpHandler { PublicStarted = new(TaskCreationOptions.RunContinuationsAsynchronously),
                PublicRelease = new(TaskCreationOptions.RunContinuationsAsynchronously) };
            using var host = PublicRosterHost(handler); using var cancelled = new CancellationTokenSource();
            BridgeAccountContext owner = host.CurrentContext!;
            Task<Roster.Response> pending = host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload(), cancelled.Token);
            try {
                await handler.PublicStarted!.Task.WaitAsync(TimeSpan.FromSeconds(3));
                if (scenario == "source") {
                    handler.FleetId = 8; handler.Sid = "OTHER";
                    Require((await host.GetOfficialFleetIdentityAsync(owner, default)).Fleet!.SourceRef == "officialFleet:8",
                        "Source replacement is observed through the original identity read owner");
                }
                else if (scenario == "same-reader-source") {
                    handler.FleetId = 8; handler.Sid = "OTHER";
                    await RejectPublicRoster(async () => { await host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload(), default); },
                        AccountBridgeStableErrors.OfficialFleetDataInvalid);
                    Require(handler.BootstrapReads == 2 && handler.PublicReads == 1,
                        "Same-reader verified source replacement rejects the old requested source without another public request");
                }
                else if (scenario == "departure") {
                    handler.NoFleet = true;
                    await RejectPublicRoster(async () => { await host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload(), default); },
                        AccountBridgeStableErrors.OfficialFleetDataInvalid);
                }
                else if (scenario == "account") {
                    // Fixture-only publication through the existing lifecycle; this is not an authentication proof.
                    MethodInfo publish = typeof(ScmAccountBridgeHost).GetMethod("PublishSession", BindingFlags.Instance | BindingFlags.NonPublic)!;
                    var replacement = new ScmOAuthSession("fixture-scm", "other-fixture-account", "Synthetic replacement", "synthetic-access",
                        DateTimeOffset.UtcNow.AddHours(1), ["organizations.read", "profile.read"]);
                    publish.Invoke(host, [replacement, false, null, false, null, null, null, null]);
                    Require(host.Generation == 2 && host.CurrentContext!.Subject == replacement.Subject,
                        "The original account publisher retires the old generation and installs a different fixture owner");
                }
                else if (scenario == "cancel") cancelled.Cancel();
                else host.Dispose();
                handler.PublicRelease!.TrySetResult();
                if (scenario == "cancel") {
                    bool rejected = false;
                    try { await pending; } catch (OperationCanceledException) when (cancelled.IsCancellationRequested) { rejected = true; }
                    Require(rejected, "Caller cancellation survives a late cancellation-ignoring transport");
                }
                else await RejectPublicRoster(async () => { await pending; }, scenario is "source" or "same-reader-source" or "departure"
                    ? AccountBridgeStableErrors.OfficialFleetDataInvalid : AccountBridgeStableErrors.ReauthorizationRequired);
                if (scenario == "same-reader-source") {
                    Roster.Response fresh = await host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload("officialFleet:8"), default);
                    Require(fresh.State == Roster.ReadState.Available && fresh.Page!.Query.SourceRef == "officialFleet:8"
                        && fresh.Page.Query.Sid == "OTHER", "Only the actually verified new source can be read afterwards");
                }
            }
            finally { handler.PublicRelease!.TrySetResult(); try { await pending; } catch { } }
        }
    }

    private static async Task PublicRosterForgedSourceDoesNotRetireVerifiedSource()
    {
        using var handler = new RosterHttpHandler { PublicStarted = new(TaskCreationOptions.RunContinuationsAsynchronously),
            PublicRelease = new(TaskCreationOptions.RunContinuationsAsynchronously) };
        using var host = PublicRosterHost(handler); BridgeAccountContext owner = host.CurrentContext!;
        Task<Roster.Response> pending = host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload(), default);
        try {
            await handler.PublicStarted!.Task.WaitAsync(TimeSpan.FromSeconds(3));
            await RejectPublicRoster(async () => { await host.ReadOfficialFleetPublicRosterAsync(owner,
                PublicRosterPayload("officialFleet:99"), default); }, AccountBridgeStableErrors.OfficialFleetDataInvalid);
            Require(handler.BootstrapReads == 2 && handler.PublicReads == 1,
                "A forged requested source cannot select a different public route");
            handler.PublicRelease!.TrySetResult();
            Roster.Response original = await pending;
            Require(original.State == Roster.ReadState.Available && original.Page!.Query.SourceRef == "officialFleet:7",
                "A forged source does not retire the still-verified real source or poison its in-flight response");
        }
        finally { handler.PublicRelease!.TrySetResult(); try { await pending; } catch { } }
    }

    private static async Task PublicRosterSourceChangedDuringBootstrap()
    {
        using var handler = new RosterHttpHandler { BootstrapStarted = new(TaskCreationOptions.RunContinuationsAsynchronously),
            BootstrapRelease = new(TaskCreationOptions.RunContinuationsAsynchronously) };
        using var host = PublicRosterHost(handler); BridgeAccountContext owner = host.CurrentContext!;
        TaskCompletionSource heldBootstrap = handler.BootstrapRelease!;
        Task<Roster.Response> pending = host.ReadOfficialFleetPublicRosterAsync(owner, PublicRosterPayload(), default);
        try {
            await handler.BootstrapStarted!.Task.WaitAsync(TimeSpan.FromSeconds(3));
            handler.FleetId = 8; handler.Sid = "OTHER";
            handler.BootstrapRelease = null;
            await host.GetOfficialFleetIdentityAsync(owner, default);
            heldBootstrap.TrySetResult();
            await RejectPublicRoster(async () => { await pending; }, AccountBridgeStableErrors.OfficialFleetDataInvalid);
            Require(handler.PublicReads == 0, "A late old bootstrap cannot replace an already-observed new fleet routing descriptor");
        }
        finally { heldBootstrap.TrySetResult(); host.Dispose(); try { await pending; } catch { } }
    }

    private static async Task RejectPublicRoster(Func<Task> operation, string expected)
    {
        try { await operation(); }
        catch (AccountBridgeHostException failure) { Require(failure.Code == expected, "Read failure keeps its exact existing stable error category"); return; }
        throw new InvalidOperationException("Expected public roster read rejection: " + expected);
    }
}
