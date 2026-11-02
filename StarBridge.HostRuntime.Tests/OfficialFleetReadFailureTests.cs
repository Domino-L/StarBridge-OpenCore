using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class OfficialFleetReadTests
{
    internal static async Task Failures()
    {
        foreach (var members in new[] { false, true })
        foreach (var (status, code, retryable) in new[] {
            (HttpStatusCode.Forbidden, "official_fleet.read_forbidden", false),
            (HttpStatusCode.RequestTimeout, "official_fleet.read_transient", true),
            (HttpStatusCode.TooManyRequests, "official_fleet.read_transient", true),
            (HttpStatusCode.ServiceUnavailable, "official_fleet.read_transient", true),
            ((HttpStatusCode)599, "official_fleet.read_transient", true),
            ((HttpStatusCode)799, "official_fleet.read_unavailable", false),
            (HttpStatusCode.BadRequest, "official_fleet.read_unavailable", false) })
        {
            using var handler = new Handler();
            handler.Failure = (request, _) => IsTarget(request, members)
                ? Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent("{}") }) : null;
            using var host = Host(handler);
            using var dispatcher = new AccountBridgeDispatcher(host);
            var result = await Read(dispatcher, host, members, "http-matrix");
            Check(result, code, retryable, $"{members}/{(int)status}");
        }
        foreach (var members in new[] { false, true })
        foreach (var (error, code, retryable) in new (Exception, string, bool)[] {
            (new HttpRequestException(), "official_fleet.read_transient", true),
            (new IOException(), "official_fleet.read_transient", true),
            (new OperationCanceledException(), "official_fleet.read_transient", true),
            (new InvalidDataException(), "official_fleet.data_invalid", false),
            (new FormatException(), "official_fleet.data_invalid", false),
            (new InvalidOperationException(), "official_fleet.data_invalid", false),
            (new Exception("private-fault-detail"), "bridge.host_error", false) })
        {
            using var handler = new Handler();
            handler.Failure = (request, _) => IsTarget(request, members) ? throw error : null;
            using var host = Host(handler);
            using var dispatcher = new AccountBridgeDispatcher(host);
            var result = await Read(dispatcher, host, members, "exception-matrix");
            Check(result, code, retryable, $"{members}/{error.GetType().Name}");
            Require(!JsonSerializer.Serialize(result, BridgeProtocol.JsonOptions).Contains("private-fault-detail"), "Private exception detail must not reach the wire");
        }
        Console.WriteLine("PASS Schema1 official fleet read failure matrices retain stable codes and private error isolation");
        await RuntimePublicPageFailure();
        await RuntimeFailureControls();
        using var cancelledHandler = new Handler();
        using var cancelledHost = Host(cancelledHandler);
        using var cancellation = new CancellationTokenSource();
        cancelledHandler.Failure = (request, _) => {
            if (!IsTarget(request, true)) return null;
            cancellation.Cancel();
            return Task.FromCanceled<HttpResponseMessage>(cancellation.Token);
        };
        try { await cancelledHost.GetOfficialFleetMembersAsync(cancelledHost.CurrentContext!, Query(), cancellation.Token); }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { return; }
        throw new InvalidOperationException("Caller cancellation was reclassified");
    }

    private static async Task RuntimePublicPageFailure()
    {
        using var handler = new Handler();
        var pageReads = 0;
        var identityReads = 0;
        handler.Failure = (request, _) => {
            if (request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/official-fleet/member-identities")
                Interlocked.Increment(ref identityReads);
            if (!IsTarget(request, true)) return null;
            Interlocked.Increment(ref pageReads);
            Require(request.Method == HttpMethod.Get && request.RequestUri.Port == 18080 &&
                request.Headers.Authorization is null, "Runtime page failure uses the existing public SCM directory without a resource token");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) {
                Content = new StringContent("runtime-503-private-detail")
            });
        };
        using var host = Host(handler);
        host.ConfigureOfficialRealtime(true);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var query = JsonSerializer.SerializeToElement(new {
            schemaVersion = 2, sourceRef = "officialFleet:7", search = "Pilot & Wing",
            filter = "all", pageNumber = 1, pageSize = 50
        });
        var result = (await dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.getRuntimeMembers",
            "runtime-public-page-503", host.Generation, query, host.CurrentContext))).Response;
        Require(pageReads == 1 && identityReads == 0,
            "The runtime request reaches exactly one public page and fails before G1 or the unconfigured privacy writer");
        Require(!JsonSerializer.Serialize(result, BridgeProtocol.JsonOptions).Contains("runtime-503-private-detail"),
            "The upstream private error body must not reach the runtime Bridge response");
        Console.WriteLine($"OBSERVED runtime public-page HTTP503: code={result.Error?.Code}, retryable={result.Error?.Retryable}, pages={pageReads}, G1={identityReads}");
        Check(result, "official_fleet.read_transient", true, "runtime/HTTP503");
    }

    private static async Task RuntimeFailureControls()
    {
        foreach (var (name, response, error, code, retryable) in new (string, Func<HttpResponseMessage>?, Exception?, string, bool)[] {
            ("HTTP401", () => RuntimeResponse(HttpStatusCode.Unauthorized, "{}"), null, AccountBridgeStableErrors.ReauthorizationRequired, false),
            ("HTTP403", () => RuntimeResponse(HttpStatusCode.Forbidden, "{}"), null, "official_fleet.read_forbidden", false),
            ("HTTP408", () => RuntimeResponse(HttpStatusCode.RequestTimeout, "{}"), null, "official_fleet.read_transient", true),
            ("HTTP429", () => RuntimeResponse(HttpStatusCode.TooManyRequests, "{}"), null, "official_fleet.read_transient", true),
            ("invalid JSON", () => RuntimeResponse(HttpStatusCode.OK, "{"), null, "official_fleet.data_invalid", false),
            ("invalid page", () => RuntimeResponse(HttpStatusCode.OK, "{\"code\":0,\"data\":{\"total\":1,\"list\":[{\"userId\":\"invalid\"}]}}"), null, "official_fleet.data_invalid", false),
            ("synthetic timeout", null, new TimeoutException("runtime-private-detail"), "official_fleet.read_transient", true),
            ("synthetic transport cancellation", null, new OperationCanceledException("runtime-private-detail"), "official_fleet.read_transient", true),
            ("synthetic IO", null, new IOException("runtime-private-detail"), "official_fleet.read_transient", true),
            ("synthetic overflow", null, new OverflowException("runtime-private-detail"), "official_fleet.data_invalid", false),
            ("typed failure", null, new AccountBridgeHostException("official_fleet.read_forbidden"), "official_fleet.read_forbidden", false),
            ("unknown failure", null, new Exception("runtime-private-detail"), "bridge.host_error", false) })
        {
            using var handler = new Handler();
            var pages = 0;
            var identities = 0;
            handler.Failure = (request, _) => {
                if (request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/official-fleet/member-identities") identities++;
                if (!IsTarget(request, true)) return null;
                pages++;
                return error is not null ? Task.FromException<HttpResponseMessage>(error) : Task.FromResult(response!());
            };
            using var host = Host(handler);
            host.ConfigureOfficialRealtime(true);
            using var dispatcher = new AccountBridgeDispatcher(host);
            var result = (await dispatcher.DispatchAsync(RuntimeRequest(host, "runtime-control"))).Response;
            Require(pages == 1 && identities == 0, name + ": failure must precede G1 and the unconfigured privacy writer");
            Check(result, code, retryable, "runtime/" + name);
            Require(!JsonSerializer.Serialize(result, BridgeProtocol.JsonOptions).Contains("runtime-private-detail"),
                name + ": private exception detail must not reach the wire");
            Console.WriteLine("PASS runtime failure classification " + name);
        }
        await RuntimeCancellationControl(false);
        await RuntimeCancellationControl(true);
        using (var handler = new Handler())
        using (var host = Host(handler))
        using (var dispatcher = new AccountBridgeDispatcher(host))
        {
            var requests = 0;
            handler.Failure = (_, _) => { requests++; return null; };
            var result = (await dispatcher.DispatchAsync(RuntimeRequest(host, "runtime-disabled"))).Response;
            Check(result, "official_fleet.runtime_unavailable", false, "runtime/default off");
            Require(requests == 0, "Default-off runtime must perform no upstream IO");
            Console.WriteLine("PASS runtime default-off performs zero upstream IO");
        }
        using (var handler = new Handler())
        using (var host = Host(handler))
        {
            host.ConfigureOfficialRealtime(true);
            var owner = host.CurrentContext!;
            var identities = 0;
            handler.Failure = (request, _) => {
                if (request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/official-fleet/member-identities") identities++;
                return null;
            };
            handler.PublicStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
            handler.PublicRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var delayed = host.GetOfficialFleetRuntimeMembersAsync(owner, RuntimeQuery(), default);
            await handler.PublicStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            host.Dispose();
            handler.PublicRelease.SetResult();
            AccountBridgeHostException? failure = null;
            try { await delayed; } catch (AccountBridgeHostException caught) { failure = caught; }
            Require(failure?.Code == AccountBridgeStableErrors.ReauthorizationRequired && identities == 0,
                "Retired runtime owner must reject the late valid public page before G1 or any publication");
            Console.WriteLine("PASS runtime late public page cannot cross owner retirement");
        }
    }

    private static async Task RuntimeCancellationControl(bool throughDispatcher)
    {
        using var handler = new Handler();
        using var host = Host(handler);
        host.ConfigureOfficialRealtime(true);
        using var cancellation = new CancellationTokenSource();
        var pages = 0;
        var identities = 0;
        handler.Failure = (request, _) => {
            if (request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/official-fleet/member-identities") identities++;
            if (!IsTarget(request, true)) return null;
            pages++;
            cancellation.Cancel();
            return Task.FromCanceled<HttpResponseMessage>(cancellation.Token);
        };
        if (throughDispatcher)
        {
            using var dispatcher = new AccountBridgeDispatcher(host);
            var result = (await dispatcher.DispatchAsync(RuntimeRequest(host, "runtime-cancel"), cancellation.Token)).Response;
            Require(result.Status == "cancelled" && result.Error?.Code == BridgeErrorCodes.Cancelled,
                "Dispatcher must preserve the original cancelled response rather than a transient error");
        }
        else
        {
            var cancelled = false;
            try { await host.GetOfficialFleetRuntimeMembersAsync(host.CurrentContext!, RuntimeQuery(), cancellation.Token); }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { cancelled = true; }
            Require(cancelled, "Runtime Host must preserve the original caller cancellation");
        }
        Require(pages == 1 && identities == 0, "Caller cancellation must precede G1 and the unconfigured writer");
        Console.WriteLine("PASS runtime caller cancellation " + (throughDispatcher ? "Dispatcher" : "Host"));
    }

#if STARBRIDGE_SESSION_PROBE || STARBRIDGE_MEMBER_READ_PROBE
    // Actual Dispatcher -> SCM Host -> existing HTTP-handler fixture. No real service or account.
    internal static async Task MemberCheckpointFailures()
    {
        foreach (var scenario in new[] { "bootstrap", "g1-read", "g1-deadline", "relay", "materialize" })
        {
            var path = Path.Combine(StarBridge.HostRuntime.HostDataRoot.CurrentRoot, "scm-auth-diagnostics.log");
            var offset = File.Exists(path) ? File.ReadAllText(path).Length : 0;
            using var handler = new Handler();
            var bootstrapReads = 0; var pageReads = 0; var identityReads = 0; var relayReads = 0;
            handler.Failure = (request, _) => {
                if (request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/bootstrap")
                {
                    bootstrapReads++;
                    if (scenario == "bootstrap") return Task.FromResult(RuntimeResponse(HttpStatusCode.ServiceUnavailable, "stage-private-sentinel"));
                }
                if (IsTarget(request, true)) pageReads++;
                if (request.RequestUri.AbsolutePath != "/app-api/starbridge/v1/official-fleet/member-identities") return null;
                identityReads++;
                if (scenario == "g1-read") return Task.FromResult(RuntimeResponse(HttpStatusCode.OK, "{"));
                var observed = DateTimeOffset.UtcNow.AddSeconds(scenario == "g1-deadline" ? -10 : 0);
                var body = JsonSerializer.Serialize(new { schemaVersion = 2, sourceRef = "officialFleet:7", members = new[] { 101L, 102L }.Select(id => new {
                    memberId = id, state = "unlinked", identityObservedAtUtc = observed.ToString("O"), identityValidUntilUtc = observed.AddSeconds(5).ToString("O")
                }) });
                return Task.FromResult(RuntimeResponse(HttpStatusCode.OK, body));
            };
            using var relay = new MemberStageRelayHandler(request => {
                relayReads++;
                Require(request.Method == HttpMethod.Post && request.RequestUri!.AbsolutePath == "/api/official-fleets/realtime/read",
                    "Stage fixture uses only the existing runtime read route");
                if (scenario == "relay") return RuntimeResponse(HttpStatusCode.Forbidden, "stage-private-sentinel");
                return RuntimeResponse(HttpStatusCode.OK, JsonSerializer.Serialize(new {
                    schemaVersion = 4, sourceRef = "officialFleet:7", coverage = "requestedOwners", requestedOwnerCount = 0,
                    supportedFilters = new[] { "all" }, runtimeCapabilities = new {
                        presence = true, server = true, ship = true, location = true, onlineCount = false, inGameCount = false },
                    members = Array.Empty<object>()
                }));
            });
            using var host = Host(handler);
            host.ConfigureOfficialRealtime(true);
            host.ConfigurePrivacyWriter(new StarBridge.HostRuntime.Privacy.PrivacyRelayWriter(new Uri("https://stage-fixture.invalid/"), relay));
            using var dispatcher = new AccountBridgeDispatcher(host);
            var result = (await dispatcher.DispatchAsync(RuntimeRequest(host, "member-stage-fixture"))).Response;
            var expected = scenario switch {
                "bootstrap" => "official_fleet.read_transient",
                "g1-read" or "g1-deadline" => "official_fleet.identity_unavailable",
                "relay" => "privacy_publication.forbidden",
                _ => "none"
            };
            Require((expected == "none" ? result.Status == "ok" : result.Error?.Code == expected) && bootstrapReads == 1 &&
                pageReads == (scenario == "bootstrap" ? 0 : 1) && identityReads == (scenario == "bootstrap" ? 0 : 1) &&
                relayReads == (scenario is "relay" or "materialize" ? 1 : 0), "Stage observation does not add requests or bypass earlier failures");
            var rows = File.ReadAllText(path)[offset..].Split('\n').Where(line => line.Contains("[DEBUG-account-wait-20261017]")).ToArray();
            var g1 = scenario is "g1-read" or "g1-deadline" ? "contract" : "none";
            Require(rows.Length == 4 && rows.Count(line => line.Contains("phase=dispatch-work event=" +
                (expected == "none" ? "returned" : "interrupted")) &&
                line.Contains("code=" + expected + " checkpoint=" + scenario + " g1=" + g1)) == 1,
                "Actual member terminal must retain the last reached closed stage and original code: " + scenario);
            Require(rows.All(line => !line.Contains("stage-private-sentinel") && !line.Contains("fixture-owner") &&
                !line.Contains("synthetic-access") && !line.Contains("stage-fixture.invalid")), "Stage evidence is payload/account/endpoint free");
            Console.WriteLine("PASS actual member checkpoint " + scenario + " original code and exact IO counts");
        }
        {
            var path = Path.Combine(StarBridge.HostRuntime.HostDataRoot.CurrentRoot, "scm-auth-diagnostics.log");
            var offset = File.ReadAllText(path).Length;
            using var handler = new Handler { PublicStarted = new(TaskCreationOptions.RunContinuationsAsynchronously),
                PublicRelease = new(TaskCreationOptions.RunContinuationsAsynchronously) };
            using var host = Host(handler); host.ConfigureOfficialRealtime(true);
            using var dispatcher = new AccountBridgeDispatcher(host);
            var delayed = dispatcher.DispatchAsync(RuntimeRequest(host, "stage-retired-owner"));
            await handler.PublicStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            host.Dispose(); handler.PublicRelease.SetResult();
            var result = (await delayed).Response;
            var rows = File.ReadAllText(path)[offset..].Split('\n').Where(line => line.Contains("[DEBUG-account-wait-20261017]")).ToArray();
            Require(result.Error?.Code == AccountBridgeStableErrors.ReauthorizationRequired && rows.Any(line =>
                line.Contains("phase=dispatch-work event=interrupted") && line.Contains("code=account.reauthorization_required checkpoint=owner-fence")),
                "Late page keeps the existing owner rejection and identifies only its last owner checkpoint");
            Console.WriteLine("PASS actual member owner-fence checkpoint after late page");
        }
        // Schema1 directory (the visible member page) keeps one fail-closed code; only the
        // probe names the G1 HTTP family so a live 503/403/contract failure is distinguishable.
        foreach (var (scenario, status, g1) in new[] {
            ("g1-503", HttpStatusCode.ServiceUnavailable, "status-5xx"), ("g1-403", HttpStatusCode.Forbidden, "status-403"),
            ("g1-400", HttpStatusCode.BadRequest, "status-400"), ("g1-contract", HttpStatusCode.OK, "contract") })
        {
            var path = Path.Combine(StarBridge.HostRuntime.HostDataRoot.CurrentRoot, "scm-auth-diagnostics.log");
            var offset = File.Exists(path) ? File.ReadAllText(path).Length : 0;
            using var handler = new Handler();
            var identityReads = 0;
            handler.Failure = (request, _) => {
                if (request.RequestUri!.AbsolutePath != "/app-api/starbridge/v1/official-fleet/member-identities") return null;
                identityReads++;
                return Task.FromResult(RuntimeResponse(status, status == HttpStatusCode.OK ? "{" : "stage-private-sentinel"));
            };
            using var host = Host(handler);
            using var dispatcher = new AccountBridgeDispatcher(host);
            var result = await Read(dispatcher, host, true, "member-g1-" + scenario);
            var rows = File.ReadAllText(path)[offset..].Split('\n').Where(line => line.Contains("[DEBUG-account-wait-20261017]")).ToArray();
            Require(result.Error?.Code == "official_fleet.identity_unavailable" && identityReads == 1 &&
                rows.Count(line => line.Contains("command=officialFleet.getMembers schema=1") &&
                    line.Contains("phase=dispatch-work event=interrupted") &&
                    line.Contains("code=official_fleet.identity_unavailable checkpoint=g1-read g1=" + g1)) == 1 &&
                rows.All(line => !line.Contains("stage-private-sentinel") && !line.Contains("fixture-owner") && !line.Contains("synthetic-access")),
                "Schema1 G1 failure keeps its stable code and adds only the fixed failure class: " + scenario);
            Console.WriteLine("PASS schema1 member G1 failure class " + scenario + " -> " + g1);
        }
    }

    private sealed class MemberStageRelayHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        { token.ThrowIfCancellationRequested(); return Task.FromResult(respond(request)); }
    }
#endif

    private static HttpResponseMessage RuntimeResponse(HttpStatusCode status, string body) => new(status) { Content = new StringContent(body) };
    private static JsonElement RuntimeQuery() => JsonSerializer.SerializeToElement(new {
        schemaVersion = 2, sourceRef = "officialFleet:7", search = "Pilot & Wing", filter = "all", pageNumber = 1, pageSize = 50
    });
    private static BridgeEnvelope RuntimeRequest(ScmAccountBridgeHost host, string correlation) =>
        BridgeEnvelope.Request("officialFleet.getRuntimeMembers", correlation, host.Generation, RuntimeQuery(), host.CurrentContext);

    internal static async Task<string> FailureWire()
    {
        using var handler = new Handler();
        using var host = Host(handler);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var identitySuccess = await Read(dispatcher, host, false, "identity-success");
        var membersSuccess = await Read(dispatcher, host, true, "members-success");
        handler.Failure = (request, _) => IsTarget(request, false) || IsTarget(request, true)
            ? Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) { Content = new StringContent("{}") }) : null;
        var identityTransient = await Read(dispatcher, host, false, "identity-transient");
        // Members verify the bootstrap first, so this also tests that boundary.
        var membersTransient = await Read(dispatcher, host, true, "members-transient");
        handler.Failure = (request, _) => IsTarget(request, false) || IsTarget(request, true)
            ? Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden) { Content = new StringContent("{}") }) : null;
        var identityForbidden = await Read(dispatcher, host, false, "identity-forbidden");
        var membersForbidden = await Read(dispatcher, host, true, "members-forbidden");
        return JsonSerializer.Serialize(new { identitySuccess, membersSuccess, identityTransient, membersTransient, identityForbidden, membersForbidden }, BridgeProtocol.JsonOptions);
    }

    private static bool IsTarget(HttpRequestMessage request, bool members) => request.RequestUri!.AbsolutePath ==
        (members ? "/app-api/member/organization/member/page" : "/app-api/starbridge/v1/bootstrap");
    private static async Task<BridgeEnvelope> Read(AccountBridgeDispatcher dispatcher, ScmAccountBridgeHost host, bool members, string correlation) =>
        (await dispatcher.DispatchAsync(BridgeEnvelope.Request(members ? "officialFleet.getMembers" : "officialFleet.getCurrent", correlation,
            host.Generation, members ? Query() : JsonSerializer.SerializeToElement(new { schemaVersion = 1 }), host.CurrentContext))).Response;
    private static void Check(BridgeEnvelope result, string code, bool retryable, string scenario) =>
        Require(result.Error?.Code == code && result.Error.Retryable == retryable,
            $"{scenario}: expected {code}/{retryable}, got {result.Error?.Code}/{result.Error?.Retryable}");
}
