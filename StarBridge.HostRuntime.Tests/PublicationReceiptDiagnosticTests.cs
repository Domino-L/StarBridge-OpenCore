using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static partial class PublicationReceiptDiagnosticTests
{
    internal static readonly (string Name, Func<Task> Test)[] Cases = [
        ("CX-RECEIPT-NAME case-only names accepted on all three lanes", NameCase),
        .. NameBoundaryCases(),
        ("CX-HANGARDIAG successful publication receipts stay silent on all three lanes", Success),
        ("CX-HANGARDIAG invalid receipts record status type and byte length", Invalid),
        ("CX-HANGARDIAG receipt metadata allowlist and observer isolation", Isolation),
        .. PublicationValidationDiagnosticTests.Cases,
        .. CommunityReadJournalRotationTests.Cases
    ];

    private sealed class Fixture(string lane) : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "sb-receiptdiag-" + Guid.NewGuid().ToString("N"));
        internal PrivacyRelayWriter Writer { get; private set; } = null!;
        internal string? InvalidBody;
        internal string? MediaType = "application/json";
        internal bool MissingVersion, Mismatch, UnknownLength;
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal long BodyLength;
        internal Action<JsonObject>? ChangeReceiptState;
        internal string? PayloadName;
        private readonly OfficialFleetRealtimeTarget _target = new("private-authority", 70007, "DIAGTEST", "scm-observed-membership-row-v1:70007");

        internal Fixture Start()
        {
            Writer = new(new Uri("https://private-relay.invalid"), new Handler(async request =>
            {
                if (request.Method == HttpMethod.Get)
                    return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 4, consent = (object?)null }) };
                var sent = await request.Content!.ReadFromJsonAsync<JsonElement>();
                var version = lane == "legacy" ? 1 : lane == "community" ? 3 : 4;
                object receipt = lane switch {
                    "legacy" => sent,
                    "community" => new { schemaVersion = 3, state = sent.GetProperty("state"), communities = sent.GetProperty("communities") },
                    _ => new { schemaVersion = 4, state = sent.GetProperty("state"), communities = sent.GetProperty("communities"),
                        officialAudience = new { target = _target, consentRevision = "initial", withdrawOnly = true } }
                };
                var text = InvalidBody ?? JsonSerializer.Serialize(receipt, LocalPrivacyStore.Json);
                if (ChangeReceiptState is not null)
                {
                    var changed = JsonNode.Parse(text)!;
                    ChangeReceiptState((lane == "legacy" ? changed : changed["state"]!).AsObject());
                    text = changed.ToJsonString();
                }
                if (Mismatch)
                {
                    var changed = JsonNode.Parse(text)!;
                    (lane == "legacy" ? changed : changed["state"]!)["online"] = true;
                    text = changed.ToJsonString();
                }
                HttpContent content = UnknownLength ? new NoLengthContent(Encoding.UTF8.GetBytes(text)) : new ByteArrayContent(Encoding.UTF8.GetBytes(text));
                if (MediaType is not null) content.Headers.TryAddWithoutValidation("Content-Type", MediaType);
                BodyLength = Encoding.UTF8.GetByteCount(text);
                var response = new HttpResponseMessage(Status) { Content = content };
                if (!MissingVersion) response.Headers.Add("X-StarBridge-Realtime-Version", version.ToString());
                return response;
            })) { ReceiptDiagnostic = new CommunityReadJournal(Root).RecordReceipt };
            return this;
        }
        internal Task Send()
        {
            var owner = new BridgeAccountContext("test", "private-authority.invalid", "private-account");
            var input = new PrivacyPublicationInput(owner, 1, "private-account-name", false, "LIVE",
                new(new("disconnected", null, null), new("unknown", null), new("unknown", null, null)));
            var settings = new LocalPrivacySettings(false, new(PlayerSharedStateFields.None, false, false, []),
                new(PlayerSharedStateFields.None, false), lane == "legacy" ? null : [],
                OfficialFleet: lane == "official" ? new(_target, PlayerSharedStateFields.None, "initial", new string('d', 32)) : null);
            var payload = JsonNode.Parse(PrivacyPublicationPayload.Build(input, settings, true).GetRawText())!.AsObject();
            if (PayloadName is not null)
            {
                payload["name"] = PayloadName;
                if (lane == "official") payload["gameObserved"] = true;
            }
            return Writer.SendAsync("private-bearer-token", JsonSerializer.SerializeToElement(payload), default);
        }
        internal string[] Lines() => File.Exists(Path.Combine(Root, "community-read-diagnostics.log"))
            ? File.ReadAllLines(Path.Combine(Root, "community-read-diagnostics.log")) : [];
        public void Dispose() { Writer?.Dispose(); if (Directory.Exists(Root)) Directory.Delete(Root, true); }
    }

    private static async Task Success()
    {
        foreach (var lane in new[] { "legacy", "community", "official" })
        {
            using var fixture = new Fixture(lane).Start();
            await fixture.Send();
            var lines = fixture.Lines();
            Check(lines.Length == 0, "successful receipts do not overwrite failure evidence");
            OfficialHangarDiagnosticTests.AssertPrivate(lines);
        }
    }

    private static async Task Invalid()
    {
        foreach (var lane in new[] { "legacy", "community", "official" })
        foreach (var (mediaType, category) in new (string?, string)[] {
            ("application/json; charset=utf-8", "json"), ("application/problem+json", "json"), ("TEXT/HTML; charset=utf-8", "html"),
            ("text/plain; private-param=private-header", "text"), ("application/octet-stream", "other"), (null, "none") })
        {
            using var fixture = new Fixture(lane) { InvalidBody = "<html>private-response-body 隔离</html>", MediaType = mediaType,
                Status = HttpStatusCode.Created }.Start();
            await Reject(fixture.Send, json: true);
            AssertInvalid(fixture, category, 201);
        }
        foreach (var lane in new[] { "legacy", "community", "official" })
        {
            using (var fixture = new Fixture(lane) { MissingVersion = true, InvalidBody = "private-response-body" }.Start())
            {
                await Reject(fixture.Send);
                AssertInvalid(fixture, "json", 200);
            }
            using (var fixture = new Fixture(lane) { Mismatch = true }.Start())
            {
                await Reject(fixture.Send);
                AssertInvalid(fixture, "json", 200);
            }
            using (var fixture = new Fixture(lane) { InvalidBody = "", Status = HttpStatusCode.NoContent, MediaType = null }.Start())
            {
                await Reject(fixture.Send, json: true);
                AssertInvalid(fixture, "none", 204);
            }
            using (var fixture = new Fixture(lane) { UnknownLength = true, InvalidBody = "private-response-body 隔离" }.Start())
            {
                await Reject(fixture.Send, json: true);
                AssertInvalid(fixture, "json", 200);
            }
        }
    }

    private static async Task Isolation()
    {
        using (var fixture = new Fixture("community").Start())
        {
            fixture.Writer.ReceiptDiagnostic = (_, _, _, _, _, _) => throw new IOException("private-exception");
            await fixture.Send();
            fixture.MissingVersion = true;
            await Reject(fixture.Send);
        }
        using (var fixture = new Fixture("community").Start())
        {
            var journal = new CommunityReadJournal(fixture.Root);
            journal.RecordReceipt("publication-receipt", "ok", 200, "json", 1);
            journal.RecordReceipt("private-stage\nhttps://private-url.invalid", "privacy_publication.response_invalid", 200, "json", 1);
            Check(fixture.Lines().Length == 0, "receipt successes and untrusted stages are discarded");
            journal.RecordReceipt("publication-receipt", "private-response-body", 999, "private-header\nhttps://private-url.invalid", -7);
            var lines = fixture.Lines();
            Check(lines.Single().Contains("code=unclassified status=none elapsedMs=0 contentType=other bodyLength=none"), "metadata filtered independently");
            OfficialHangarDiagnosticTests.AssertPrivate(lines);
        }
    }

    private static void AssertInvalid(Fixture fixture, string type, int status)
    {
        var lines = fixture.Lines();
        Check(lines.Length == 1 && lines[0].Contains($"stage=publication-receipt code=privacy_publication.response_invalid status={status}") &&
            lines[0].Contains($"contentType={type} bodyLength={fixture.BodyLength}"), "invalid receipt retains bounded metadata only");
        OfficialHangarDiagnosticTests.AssertPrivate(lines);
    }
    private static async Task Reject(Func<Task> send, bool json = false)
    {
        try { await send(); }
        catch (JsonException) when (json) { return; }
        catch (AccountBridgeHostException error) when (!json && error.Code == "privacy_publication.response_invalid") { return; }
        throw new Exception("Expected unchanged receipt failure");
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => respond(request);
    }
    private sealed class NoLengthContent(byte[] bytes) : HttpContent
    {
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) => stream.WriteAsync(bytes).AsTask();
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
    }
}
