using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class PublicationValidationDiagnosticTests
{
    internal static readonly (string Name, Func<Task> Test)[] Cases = [
        ("CX-RECEIPT-NAME positive in-game publications accept normalized names on all lanes", NormalizedNames),
        ("CX-HANGARDIAG legacy membership validation failures", Membership),
        ("CX-HANGARDIAG community directory validation failures", DirectoryValidation),
        ("CX-HANGARDIAG member directory validation failures", Members),
        ("CX-HANGARDIAG official context validation failures", Context),
        ("CX-HANGARDIAG official consent read validation failures", ConsentRead),
        ("CX-HANGARDIAG official consent save validation failures", ConsentSave),
        ("CX-HANGARDIAG official consent consistency failures", ConsentConsistency),
        ("CX-HANGARDIAG preflight observers preserve original exceptions and reads", ExceptionIdentity),
        ("CX-HANGARDIAG positive publication successes stay silent", Success)
    ];
    private const string Revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    private const string Operation = "dddddddddddddddddddddddddddddddd";
    private static readonly OfficialFleetRealtimeTarget Target = new("private-authority", 70007, "DIAGTEST", "scm-observed-membership-row-v1:70007");
    private static readonly DateTimeOffset JoinedAt = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
    private static readonly CommunityRealtimeScope Scope = new("private-community", JoinedAt, PlayerSharedStateFields.Ship, false, true, []);
    private static OfficialRealtimeConsentWire Consent => new("private-account", Target, PlayerSharedStateFields.Ship, Revision, Operation);
    private static CommunityMemberDirectoryPage MemberPage => new(3, Scope.Code, JoinedAt, new string('f', 64), 0, 0, []);

    private sealed class Fixture(string lane, string? faultPath = null, HttpMethod? faultMethod = null, string? faultBody = null) : IDisposable
    {
        private readonly string _root = Path.Combine(Path.GetTempPath(), "sb-validationdiag-" + Guid.NewGuid().ToString("N"));
        internal readonly List<string> Calls = [];
        private PrivacyRelayWriter? _active;
        internal bool ThrowObserver;
        internal bool LowercaseReceiptName;
        internal int? MaximumRank;
        internal int MemberOffset;
        internal HttpContent? FaultContent;
        internal long FaultLength => Encoding.UTF8.GetByteCount(faultBody!);

        internal Task Send()
        {
            var journal = new CommunityReadJournal(_root);
            _active = new(new Uri("https://private-relay.invalid"), new Handler(async request =>
            {
                var path = request.RequestUri!.AbsolutePath;
                Calls.Add(request.Method + " " + path);
                if (path == faultPath && request.Method == faultMethod)
                    return new(HttpStatusCode.Created) { Content = FaultContent ?? new StringContent(faultBody!, Encoding.UTF8, "application/json") };
                if (path.EndsWith("/membership", StringComparison.Ordinal)) return Reply(new { fleetCode = (string?)null });
                if (path.EndsWith("/community-scopes", StringComparison.Ordinal))
                    return Reply(new { schemaVersion = 2, primaryFleetCode = Scope.Code,
                        communities = new[] { new { code = Scope.Code, name = "private-community-name", joinedAt = JoinedAt } } });
                if (path.EndsWith("/community-members/read", StringComparison.Ordinal))
                    return Reply(MemberPage with { Offset = MemberOffset, Total = MemberOffset });
                if (path.EndsWith("/context", StringComparison.Ordinal))
                    return Reply(new OfficialRealtimeContextWire(4, "officialFleet:70007", Target, null, "initial", true, true));
                if (path.EndsWith("/consent", StringComparison.Ordinal))
                    return request.Method == HttpMethod.Get ? Reply(new { schemaVersion = 4, consent = (object?)null })
                        : Reply(new { schemaVersion = 4, consent = Consent with { MaximumRankValue = MaximumRank } });
                var sent = await request.Content!.ReadFromJsonAsync<JsonElement>();
                var version = lane == "legacy" ? 1 : lane == "community" ? 3 : 4;
                object receipt = lane switch {
                    "legacy" => sent,
                    "community" => new { schemaVersion = 3, state = sent.GetProperty("state"), communities = sent.GetProperty("communities") },
                    _ => new { schemaVersion = 4, state = sent.GetProperty("state"), communities = sent.GetProperty("communities"),
                        officialAudience = new { target = Target, consentRevision = Revision, withdrawOnly = false } }
                };
                if (LowercaseReceiptName)
                {
                    var changed = JsonSerializer.SerializeToNode(receipt, LocalPrivacyStore.Json)!;
                    var state = (lane == "legacy" ? changed : changed["state"]!).AsObject();
                    Check(state["name"]!.GetValue<string>() == "Mixed_Test_Name", "positive publication retains the in-game mixed-case name");
                    Check(state["online"]!.GetValue<bool>(), "normalized receipt exercises a positive publication");
                    state["name"] = "mixed_test_name";
                    receipt = changed;
                }
                var response = Reply(receipt);
                response.Headers.Add("X-StarBridge-Realtime-Version", version.ToString());
                return response;
            })) { ReceiptDiagnostic = journal.RecordReceipt };
            if (ThrowObserver) _active.ReceiptDiagnostic = (_, _, _, _, _, _) => throw new IOException("private-exception");
            if (lane == "members") return _active.ReadCommunityMembersAsync("private-bearer-token",
                new(3, Scope, MemberOffset, MemberOffset == 0 ? null : MemberPage.Revision), default);
            var input = new PrivacyPublicationInput(new BridgeAccountContext("test", "private-authority.invalid", "private-account"),
                1, LowercaseReceiptName ? "Mixed_Test_Name" : "private-account-name", true, "LIVE", GameLogSessionSnapshot.Empty, AppPresenceConfirmed: true);
            var settings = new LocalPrivacySettings(true,
                new(lane == "legacy" ? PlayerSharedStateFields.Ship : 0, false, lane == "legacy", []), new(0, false),
                lane == "legacy" ? null : lane == "community" ? [Scope] : [],
                OfficialFleet: lane == "official" ? new(Target, PlayerSharedStateFields.Ship, "initial", Operation, MaximumRank) : null);
            return _active.SendAsync("private-bearer-token", PrivacyPublicationPayload.Build(input, settings, false), default, allowOfficialPositive: true);
        }
        internal string[] Lines() => File.Exists(Path.Combine(_root, "community-read-diagnostics.log"))
            ? File.ReadAllLines(Path.Combine(_root, "community-read-diagnostics.log")) : [];
        public void Dispose()
        {
            _active?.Dispose();
            if (System.IO.Directory.Exists(_root)) System.IO.Directory.Delete(_root, true);
        }
    }

    private static async Task NormalizedNames()
    {
        foreach (var lane in new[] { "legacy", "community", "official" })
        {
            using var fixture = new Fixture(lane) { LowercaseReceiptName = true };
            await fixture.Send();
            Check(fixture.Lines().Length == 0, "normalized positive receipts remain silent on " + lane);
        }
    }

    private static Task Membership() => InvalidResponses("legacy", "/api/fleets/membership", HttpMethod.Get,
        "publication-membership", ["{\"fleetCode\":7}", "{\"fleetCode\":\"private-\\naccount\"}"]);
    private static Task DirectoryValidation() => InvalidResponses("community", "/api/privacy/community-scopes", HttpMethod.Get,
        "publication-community-directory", ["{\"schemaVersion\":1,\"primaryFleetCode\":null,\"communities\":[]}",
            "{\"schemaVersion\":2,\"primaryFleetCode\":\"private-missing\",\"communities\":[]}"]);
    private static async Task Members()
    {
        var member = new CommunityMemberSharingTarget("private-account", JoinedAt, "private-name", "private-handle", true, false, 0);
        var invalid = new[] { MemberPage with { SchemaVersion = 2 }, MemberPage with { Code = "private-other" },
            MemberPage with { JoinedAt = JoinedAt.AddDays(1) }, MemberPage with { Offset = 100 },
            MemberPage with { Total = 100001 }, MemberPage with { Revision = "private-invalid" },
            MemberPage with { Members = null! }, MemberPage with { Total = 1 },
            MemberPage with { Total = 1, Members = [member with { Name = "private-\nname" }] },
            MemberPage with { Total = 1, Members = [member with { AccountId = "" }] },
            MemberPage with { Total = 2, Members = [member, member] },
            MemberPage with { Total = 2, Members = [member with { IsSelf = true }, member with { AccountId = "private-other", IsSelf = true }] } };
        await InvalidResponses("members", "/api/privacy/community-members/read", HttpMethod.Post, "publication-member-directory",
            invalid.Select(page => JsonSerializer.Serialize(page, LocalPrivacyStore.Json)).ToArray());
        await InvalidResponses("members", "/api/privacy/community-members/read", HttpMethod.Post, "publication-member-directory",
            [JsonSerializer.Serialize(MemberPage with { Offset = 100, Total = 100, Revision = new string('e', 64) }, LocalPrivacyStore.Json)],
            malformed: false, memberOffset: 100);
        using var fixture = new Fixture("members");
        await fixture.Send();
        Check(fixture.Calls.Count == 1 && fixture.Lines().Length == 0, "successful member read keeps one request and no receipt log");
    }
    private static Task Context() => InvalidResponses("official", "/api/official-fleets/realtime/context", HttpMethod.Get,
        "publication-official-context", [JsonSerializer.Serialize(new OfficialRealtimeContextWire(3, "officialFleet:70007", Target, null, "initial", true), LocalPrivacyStore.Json)], rank: 2);
    private static Task ConsentRead() => InvalidResponses("official", "/api/official-fleets/realtime/consent", HttpMethod.Get,
        "publication-official-consent-read", BadConsents());
    private static Task ConsentSave() => InvalidResponses("official", "/api/official-fleets/realtime/consent", HttpMethod.Put,
        "publication-official-consent-save", BadConsents());
    private static Task ConsentConsistency() => InvalidResponses("official", "/api/official-fleets/realtime/consent", HttpMethod.Put,
        "publication-official-consent-check", new OfficialRealtimeConsentWire?[] {
            null, Consent with { Target = Target with { OrganizationId = 70008 } },
            Consent with { Fields = PlayerSharedStateFields.None }, Consent with { OperationId = new string('e', 32) },
            Consent with { MaximumRankValue = 2 }
        }.Select(value => JsonSerializer.Serialize(new { schemaVersion = 4, consent = value }, LocalPrivacyStore.Json)).ToArray(), malformed: false);
    private static string[] BadConsents() => ["{\"schemaVersion\":3,\"consent\":null}",
        JsonSerializer.Serialize(new { schemaVersion = 4, consent = Consent with { Revision = "private-invalid-revision" } }, LocalPrivacyStore.Json)];

    private static async Task InvalidResponses(string lane, string path, HttpMethod method, string stage, string[] bodies,
        int? rank = null, bool malformed = true, int memberOffset = 0)
    {
        foreach (var body in bodies.Concat(malformed ? ["<html>private-response-body é</html>"] : Array.Empty<string>()))
        foreach (var observerThrows in new[] { false, true })
        {
            using var fixture = new Fixture(lane, path, method, body) { MaximumRank = rank, ThrowObserver = observerThrows, MemberOffset = memberOffset };
            try { await fixture.Send(); throw new InvalidOperationException("Expected validation failure"); }
            catch (JsonException) when (body.StartsWith('<')) { }
            catch (AccountBridgeHostException error) when (!body.StartsWith('<') && error.Code == "privacy_publication.response_invalid") { }
            Check(fixture.Calls.Last() == method + " " + path, "invalid preflight stops publication without another request");
            var lines = fixture.Lines();
            if (observerThrows) Check(lines.Length == 0, "observer failure preserves validation exception");
            else {
                Check(lines.Length == 1 && lines[0].Contains($"stage={stage} code=privacy_publication.response_invalid status=201 ") &&
                    lines[0].Contains($"contentType=json bodyLength={fixture.FaultLength}"), "validation boundary records failure stage and metadata once");
                OfficialHangarDiagnosticTests.AssertPrivate(lines, Operation);
            }
        }
    }

    private static async Task Success()
    {
        foreach (var lane in new[] { "legacy", "community", "official" })
        {
            using var fixture = new Fixture(lane);
            await fixture.Send();
            Check(fixture.Calls.Last().StartsWith("POST ", StringComparison.Ordinal), "positive preflights still reach publication");
            Check(fixture.Lines().Length == 0, "successful validation and publication do not log receipts");
        }
    }
    private static async Task ExceptionIdentity()
    {
        foreach (var error in new Exception[] { new JsonException("private-exception"),
            new AccountBridgeHostException("privacy_publication.response_invalid"),
            new IOException("private-exception"), new OperationCanceledException("private-exception") })
        foreach (var observerThrows in new[] { false, true })
        {
            var content = new FailedContent(error);
            using var fixture = new Fixture("legacy", "/api/fleets/membership", HttpMethod.Get, "")
                { FaultContent = content, ThrowObserver = observerThrows };
            try { await fixture.Send(); throw new InvalidOperationException("Expected original exception"); }
            catch (Exception actual) when (ReferenceEquals(actual, error)) { }
            Check(content.Reads == 1, "diagnostics never attempt another body read");
            var lines = fixture.Lines();
            if (!observerThrows && error is JsonException or AccountBridgeHostException)
                Check(lines.Single().Contains("stage=publication-membership code=privacy_publication.response_invalid status=201 elapsedMs=0 contentType=none bodyLength=none"), "original invalid response uses available metadata without reading body again");
            else Check(lines.Length == 0, "transport and cancellation are not reclassified as invalid receipts");
            OfficialHangarDiagnosticTests.AssertPrivate(lines);
        }
    }
    private static HttpResponseMessage Reply(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value, options: LocalPrivacyStore.Json) };
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => respond(request);
    }
    private sealed class FailedContent(Exception error) : HttpContent
    {
        internal int Reads;
        protected override Task<Stream> CreateContentReadStreamAsync() { Reads++; return Task.FromException<Stream>(error); }
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) { Reads++; return Task.FromException(error); }
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
    }
}
