using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Privacy;

internal static class OfficialChatAuthorDiagnosticTests
{
    private const string Name = "CXCHAT_PRIVATE_NAME", Message = "CXCHAT_PRIVATE_MESSAGE", Reference = "CXCHAT_PRIVATE_REFERENCE";
    private const string Source = "officialFleet:70007", Code = "OFFICIALFLEET:70007";
    private static readonly string Avatar = "data:image/png;base64," + Convert.ToBase64String(CommunityImageFixtures.Png());
    private static string Hash(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();
    private static readonly string AvatarVersion = Hash(Avatar);
    private static readonly string Version = Hash("StarBridge.OfficialFleet.CommunicationAuthor.v1\n" + JsonSerializer.Serialize(new[] { Name, AvatarVersion }));
    private static JsonElement J(object value) => JsonSerializer.SerializeToElement(value);
    private static void Check(bool valid, string message) { if (!valid) throw new InvalidOperationException(message); }

    internal static IEnumerable<(string Name, Func<Task> Test)> Cases()
    {
        yield return ("CX-CHAT-HIDDEN detail hidden replaces cached visible identity", () => HiddenDetail(Version));
        yield return ("CX-CHAT-HIDDEN detail hidden without expected version", () => HiddenDetail(null));
        yield return ("CX-CHAT-HIDDEN detail visible version mismatch remains unavailable", VersionMismatch);
        foreach (var kind in new[] { "page", "renewal", "detail" })
        foreach (var outcome in new[] { "expired", "future", "slow" })
            yield return ($"CX-CHAT-LAPSED {kind} {outcome}", () => Lapsed(kind, outcome));
        foreach (var kind in new[] { "page", "renewal", "preview", "detail" })
            yield return ($"CX-CHAT-LAPSED {kind} delayed publication", () => LapsedPublication(kind));
        foreach (var outcome in new[] { "expired", "future" })
        {
            yield return ($"CX-CHAT-LAPSED preview {outcome} remains unavailable", () => Read("preview", outcome));
            yield return ($"CX-CHAT-LAPSED renewal observed-only {outcome}", () => LapsedUpdates(outcome));
            yield return ($"CX-CHAT-LAPSED detail mismatched {outcome}", () => LapsedMismatch(outcome));
        }
        foreach (var kind in new[] { "page", "detail" })
        foreach (var outcome in new[] { "hidden", "unavailable", "shape", "bad-window" })
            yield return ($"CX-CHAT-LAPSED {kind} {outcome} remains neutral", () => Read(kind, outcome));
        yield return ("CX-CHAT-LAPSED detail bad-avatar remains neutral", () => Read("detail", "bad-avatar"));
        foreach (var kind in new[] { "page", "renewal", "preview", "detail" })
        foreach (var outcome in new[] { "visible", "hidden", "unavailable", "expired", "future", "near-expiry", "http", "json", "shape", "disabled", "cancelled", "unknown", "observer", "disk" })
            yield return ($"CX-CHAT-AUTHOR-DIAG {kind} {outcome}", () => Read(kind, outcome));
        yield return ("CX-CHAT-AUTHOR-DIAG detail version mismatch", VersionMismatch);
        yield return ("CX-CHAT-AUTHOR-DIAG mixed counts and worst times", Mixed);
        yield return ("CX-CHAT-AUTHOR-DIAG renewal observed-only authors", ObservedOnly);
        yield return ("CX-CHAT-AUTHOR-DIAG journal bounds whitelist and rate", Journal);
        yield return ("CX-CHAT-AUTHOR-DIAG diagnostic does not add clock reads", ClockReads);
    }

    private static async Task Lapsed(string kind, string outcome)
    {
        using var f = new Fixture(kind); await f.Prepare();
        f.Handler.Outcome = outcome == "slow" ? "visible" : outcome;
        f.Handler.DelaySeconds = outcome == "slow" ? 6 : 0;
        var calls = f.Handler.Calls;
        var result = J(await f.Read());
        var author = kind == "detail" ? result.GetProperty("author") : result.GetProperty("messages")[0];
        Check(author.GetProperty(kind == "detail" ? "identityState" : "authorIdentityState").GetString() == "visible",
            "Lapsed visible observation must reach Flutter: " + kind + "/" + outcome);
        Check(author.GetProperty(kind == "detail" ? "callsign" : "senderCallsign").GetString() == Name, "Original callsign reaches Flutter");
        Check(author.GetProperty("avatarVersion").GetString() == AvatarVersion &&
            author.GetProperty(kind == "detail" ? "identityVersion" : "authorIdentityVersion").GetString() == Version, "Original versions reach Flutter");
        Check(author.GetProperty("identityObservedAtUtc").GetDateTimeOffset() == f.Handler.Clock.Now.AddSeconds(outcome is "expired" or "slow" ? -6 : 2) &&
            author.GetProperty("identityValidUntilUtc").GetDateTimeOffset() == f.Handler.Clock.Now.AddSeconds(outcome is "expired" or "slow" ? -1 : 7), "Original proof times reach Flutter");
        Check(f.Handler.Calls == calls + (kind == "page" ? 2 : 1), "No extra requests or retries");
        Field(f.Lines().Last(), "invalidVisible", "1");
        if (kind == "detail")
        {
            using var bytes = JsonDocument.Parse(Convert.FromBase64String(result.GetProperty("data").GetString()!));
            Check(bytes.RootElement.GetProperty("avatarImageData").GetString() == Avatar, "Matching lapsed detail returns avatar bytes");
            Check(result.GetProperty("authorRefreshRequired").GetBoolean(), "Lapsed detail still requires fresh proof");
            Check(!author.TryGetProperty("memberRef", out var member) || member.ValueKind == JsonValueKind.Null, "Lapsed detail grants no member reference");
        }
    }

    private static async Task LapsedPublication(string kind)
    {
        using var f = new Fixture(kind); await f.Prepare();
        var pending = await f.Read(); var observed = f.Handler.Clock.Now;
        f.Handler.Clock.Advance(6);
        var result = J(pending);
        var author = kind == "detail" ? result.GetProperty("author") : result.GetProperty("messages")[0];
        Check(author.GetProperty(kind == "detail" ? "identityState" : "authorIdentityState").GetString() ==
            (kind == "preview" ? "unavailable" : "visible"), "Only chat preserves expiry at final publication");
        if (kind != "preview") Check(author.GetProperty("identityObservedAtUtc").GetDateTimeOffset() == observed &&
            author.GetProperty("identityValidUntilUtc").GetDateTimeOffset() == observed.AddSeconds(5), "Publication never extends proof times");
        if (kind == "detail") Check(DetailAvatar(result) == Avatar && result.GetProperty("authorRefreshRequired").GetBoolean() &&
            author.GetProperty("memberRef").ValueKind == JsonValueKind.Null, "Lapsed detail is display-only at publication");
        Field(f.Lines().Last(), "invalidVisible", "0"); // Diagnostic measures arrival, not later serialization.
    }

    private static async Task LapsedUpdates(string outcome)
    {
        using var f = new Fixture("renewal"); await f.Prepare();
        f.Observed = J(await f.Read()).GetProperty("messages")[0].GetProperty("messageRef").GetString();
        f.Handler.EmptyPage = true; f.Handler.Outcome = outcome; f.Clock.Advance(5);
        var result = J(await f.Read()); var update = result.GetProperty("authorUpdates")[0];
        Check(result.GetProperty("messages").GetArrayLength() == 0 && update.GetProperty("authorIdentityState").GetString() == "visible" &&
            update.GetProperty("senderCallsign").GetString() == Name && update.GetProperty("authorIdentityVersion").GetString() == Version,
            "Observed-only chat update carries lapsed display observation");
        Field(f.Lines().Last(), "invalidVisible", "1");
    }

    private static string? DetailAvatar(JsonElement result)
    {
        using var bytes = JsonDocument.Parse(Convert.FromBase64String(result.GetProperty("data").GetString()!));
        return bytes.RootElement.GetProperty("avatarImageData").GetString();
    }

    private static async Task LapsedMismatch(string outcome)
    {
        using var f = new Fixture("detail"); await f.Prepare();
        f.Handler.Outcome = outcome; f.Expected = new string('0', 64);
        var result = J(await f.Read());
        Check(result.GetProperty("author").GetProperty("identityState").GetString() == "unavailable" && DetailAvatar(result) is null,
            "Mismatched lapsed detail never returns avatar bytes");
        Field(f.Lines().Last(), "invalidVisible", "1");
    }

    private static async Task Read(string kind, string outcome)
    {
        using var f = new Fixture(kind); await f.Prepare();
        f.Handler.Outcome = outcome;
        if (outcome == "observer") f.Client.ChatAuthorDiagnostic = _ => throw new ArgumentException(Name);
        if (outcome == "disk")
        {
            Directory.CreateDirectory(f.Root);
            var blocked = Path.Combine(f.Root, "blocked"); File.WriteAllText(blocked, Message);
            f.Client.ChatAuthorDiagnostic = new OfficialChatAuthorReadJournal(blocked).Record;
        }
        var calls = f.Handler.Calls;
        var failure = outcome is "http" or "json" or "cancelled" or "unknown" || outcome == "disabled" && kind != "page";
        if (failure)
        {
            var error = await Failure(f.Read);
            Check(outcome switch
            {
                "http" => error is AccountBridgeHostException { Code: "communities.notAllowed" },
                "json" => error is AccountBridgeHostException { Code: "communities.dataInvalid" },
                "cancelled" => error is OperationCanceledException,
                "unknown" => ReferenceEquals(error, f.Handler.Error),
                _ => error is AccountBridgeHostException { Code: "communities.unavailable" }
            }, "Original failure preserved");
        }
        else
        {
            var result = J(await f.Read());
            var author = kind == "detail" ? result.GetProperty("author") : result.GetProperty("messages")[0];
            var expected = outcome is "shape" or "bad-window" or "disabled" || outcome == "bad-avatar" && kind == "detail" ||
                kind == "preview" && outcome is "expired" or "future" ? "unavailable" : outcome == "hidden" ? "hidden" : outcome == "unavailable" ? "unavailable" : "visible";
            if (outcome != "disabled") Check(author.GetProperty(kind == "detail" ? "identityState" : "authorIdentityState").GetString() == expected, "Original author state preserved");
            if (expected == "visible" && kind != "detail") Check(author.GetProperty("senderCallsign").GetString() == Name, "Original name preserved");
        }
        Check(f.Handler.Calls == calls + (kind == "page" ? outcome == "disabled" ? 3 : 2 : 1), "No additional reads or retries");
        var lines = f.Lines();
        if (outcome is "observer" or "disk") Check(lines.Length == 0, "Failed logging does not replace read result");
        else
        {
            Check(lines.Length == 1, "Exactly one diagnostic line"); var line = lines[0]; Validate(line);
            var expectedCode = outcome switch
            {
                "http" => "http-error", "json" or "shape" or "bad-window" => "parse-failed", "bad-avatar" when kind == "detail" => "parse-failed", "cancelled" => "cancelled", "unknown" => "unclassified",
                "disabled" => kind == "page" ? "disabled" : "http-error", _ => "ok"
            };
            Field(line, "code", expectedCode); Field(line, "kind", kind);
            Field(line, "status", outcome == "http" ? "403" : outcome == "disabled" ? "503" : outcome is "cancelled" or "unknown" ? "none" : "200");
            if (outcome is "visible" or "hidden" or "unavailable" or "expired" or "future" or "near-expiry")
            {
                Field(line, "requested", "1");
                Field(line, "visible", outcome is "hidden" or "unavailable" ? "0" : "1");
                Field(line, "hidden", outcome == "hidden" ? "1" : "0");
                Field(line, "unavailable", outcome == "unavailable" ? "1" : "0");
                Field(line, "invalidVisible", outcome is "expired" or "future" ? "1" : "0");
                Field(line, "arrivalAgeMs", outcome switch { "hidden" or "unavailable" => "none", "expired" => "6000", "future" => "-2000", _ => "0" });
                Field(line, "remainingMs", outcome switch { "hidden" or "unavailable" => "none", "expired" => "-1000", "future" => "7000", "near-expiry" => "1", _ => "5000" });
                if (kind == "detail")
                {
                    Field(line, "avatarData", outcome is "hidden" or "unavailable" ? "0" : "1");
                    Field(line, "versionMatches", outcome is "hidden" or "unavailable" ? "0" : "1");
                }
            }
        }
        Private(f.AllLines());
        if (outcome is "observer" or "disk")
        {
            f.Handler.Outcome = "unknown";
            Check(ReferenceEquals(await Failure(f.Read), f.Handler.Error), "Observer/disk failure preserves original exception instance");
        }
    }

    private static async Task HiddenDetail(string? expected)
    {
        using var f = new Fixture("detail"); await f.Prepare();
        // Prepare observed a visible name and avatar. The next detail response withdraws them.
        f.Handler.Outcome = "hidden"; f.Expected = expected;
        var calls = f.Handler.Calls;
        var result = J(await f.Read());
        var author = result.GetProperty("author");
        var state = author.GetProperty("identityState").GetString();
        Check(state == "hidden", "Flutter detail identityState: expected hidden, got " + state);
        CheckNeutralDetail(result);
        Check(f.Handler.Calls == calls + 1, "Hidden detail adds no requests or retries");
    }

    private static void CheckNeutralDetail(JsonElement result)
    {
        var author = result.GetProperty("author");
        Check(author.GetProperty("callsign").GetString() == "" && !author.GetProperty("hasAvatar").GetBoolean(),
            "Neutral detail contains no name or avatar");
        foreach (var field in new[] { "avatarVersion", "identityVersion", "identityObservedAtUtc", "identityValidUntilUtc", "memberRef" })
            Check(author.GetProperty(field).ValueKind == JsonValueKind.Null, "Neutral detail clears " + field);
        Check(DetailAvatar(result) is null, "Neutral detail contains no avatar bytes");
        Check(result.GetProperty("authorRefreshRequired").GetBoolean(), "Neutral detail preserves refresh requirement");
        var wire = result.GetRawText();
        Check(!wire.Contains(Name, StringComparison.Ordinal) && !wire.Contains(Avatar, StringComparison.Ordinal) &&
            !wire.Contains(AvatarVersion, StringComparison.Ordinal) && !wire.Contains(Version, StringComparison.Ordinal),
            "Flutter detail contains no previous identity values");
    }

    private static async Task VersionMismatch()
    {
        using var f = new Fixture("detail"); await f.Prepare(); f.Expected = new string('0', 64);
        var result = J(await f.Read());
        Check(result.GetProperty("author").GetProperty("identityState").GetString() == "unavailable", "Mismatch still neutral");
        CheckNeutralDetail(result);
        var line = f.Lines().Single(); Field(line, "versionMatches", "0"); Field(line, "avatarData", "1"); Validate(line);
    }

    private static async Task Mixed()
    {
        using var f = new Fixture("preview"); await f.Prepare(); f.Handler.Outcome = "mixed";
        var result = J(await f.Read()); Check(result.GetProperty("messages").GetArrayLength() == 4, "Mixed page unchanged");
        var line = f.Lines().Single();
        foreach (var (key, value) in new[] { ("requested", "4"), ("visible", "2"), ("hidden", "1"), ("unavailable", "1"), ("invalidVisible", "0"), ("arrivalAgeMs", "3000"), ("remainingMs", "500") }) Field(line, key, value);
        Validate(line); Private(f.AllLines());
    }

    private static async Task ObservedOnly()
    {
        using var f = new Fixture("renewal"); await f.Prepare();
        var first = J(await f.Read()); f.Observed = first.GetProperty("messages")[0].GetProperty("messageRef").GetString();
        f.Handler.EmptyPage = true; f.Clock.Advance(5);
        var result = J(await f.Read());
        Check(result.GetProperty("messages").GetArrayLength() == 0 && result.GetProperty("authorUpdates")[0].GetProperty("authorIdentityState").GetString() == "visible", "Observed-only author preserved");
        Field(f.Lines().Last(), "requested", "1"); Field(f.Lines().Last(), "visible", "1");
    }

    private static Task Journal()
    {
        using var f = new Fixture("preview");
        var record = new OfficialChatAuthorReadDiagnostic("page", "ok", 200, 1, 1, 1, 0, 0, 0, -2000, 7000, true, true);
        f.Journal.Record(record); f.Journal.Record(record);
        f.Journal.Record(record with { Kind = "renewal", ElapsedMs = 2 });
        Check(f.AllLines().Length == 1, "Same stage limited even when numeric metadata/kind changes");
        f.Journal.Record(record with { Kind = "detail" }); Check(f.AllLines().Length == 2, "Detail has separate stage quota");
        f.Clock.Advance(4.999); f.Journal.Record(record); Check(f.AllLines().Length == 2, "No early repeat");
        f.Clock.Advance(.001); f.Journal.Record(record); Check(f.AllLines().Length == 3, "Repeat after exactly five seconds");
        f.Clock.Advance(5); f.Journal.Record(record with { Code = Name + "\n" + Message, Status = -1 });
        Field(f.AllLines().Last(), "code", "unclassified"); Field(f.AllLines().Last(), "status", "none");
        f.Journal.Record(record with { Kind = Reference }); Check(f.AllLines().Length == 4, "Unknown kinds are dropped");
        Directory.CreateDirectory(f.Root);
        var unrelated = Path.Combine(f.Root, "community-read-diagnostics.log"); File.WriteAllText(unrelated, Message);
        var path = Path.Combine(f.Root, OfficialChatAuthorReadJournal.FileName); File.WriteAllText(path, new string('x', 128 * 1024));
        f.Clock.Advance(5); f.Journal.Record(record);
        Check(File.Exists(path + ".1") && new FileInfo(path).Length < 2048 && File.ReadAllText(unrelated) == Message, "Rotation cannot evict other diagnostics");
        foreach (var line in f.AllLines()) Validate(line); Private(f.AllLines());
        return Task.CompletedTask;
    }

    private static async Task ClockReads()
    {
        using var f = new Fixture("preview"); await f.Prepare();
        // Journal uses an independent clock; instrumentation must not call the proof clock again.
        f.Client.ChatAuthorDiagnostic = _ => { };
        var start = f.Handler.Clock.Reads; await f.Read(); var enabled = f.Handler.Clock.Reads - start;
        f.Client.ChatAuthorDiagnostic = null;
        start = f.Handler.Clock.Reads; await f.Read();
        Check(f.Handler.Clock.Reads - start == enabled, "Observation adds no proof-clock reads");
    }

    private static void Field(string line, string key, string expected) => Check(Regex.IsMatch(line, $@"(?:^| ){key}={Regex.Escape(expected)}(?: |$)"), key + "=" + expected);
    private static void Validate(string line) => Check(Regex.IsMatch(line,
        @"^\S+ \[DEBUG-community-read\] stage=official-chat-authors?(-detail)? code=(ok|http-error|parse-failed|disabled|cancelled|unclassified) status=(none|\d{3}) elapsedMs=\d+ kind=(page|renewal|preview|detail) requested=\d+ visible=\d+ hidden=\d+ unavailable=\d+ invalidVisible=\d+ arrivalAgeMs=(none|-?\d+) remainingMs=(none|-?\d+)( avatarData=[01] versionMatches=[01])?$"), "Only closed vocabulary and numeric metadata");
    private static void Private(IEnumerable<string> lines)
    {
        var text = string.Join("\n", lines);
        foreach (var forbidden in new[] { Name, Message, Reference, Source, Code, Avatar, AvatarVersion, Version, "scm-v1:", "businessSubjectId", "identityObservedAtUtc", "https://", "identities", "avatarImageData" })
            Check(!text.Contains(forbidden, StringComparison.Ordinal), "Private payload absent: " + forbidden[..Math.Min(forbidden.Length, 24)]);
    }
    private static async Task<Exception> Failure(Func<Task<object>> read)
    {
        try { await read(); } catch (Exception error) { return error; }
        throw new InvalidOperationException("Expected failure");
    }

    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = new(2026, 10, 31, 0, 0, 0, TimeSpan.Zero);
        internal int Reads;
        private long _stamp;
        public override DateTimeOffset GetUtcNow() { Reads++; return Now; }
        public override long TimestampFrequency => 1000;
        public override long GetTimestamp() => _stamp;
        internal void Advance(double seconds) { Now += TimeSpan.FromSeconds(seconds); _stamp += (long)Math.Round(seconds * 1000); }
    }

    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "StarBridge-ChatAuthorTests", Guid.NewGuid().ToString("N")));
        internal readonly Handler Handler = new();
        internal readonly Clock Clock = new();
        internal readonly CommunityClient Client;
        internal readonly OfficialChatAuthorReadJournal Journal;
        private readonly string _kind;
        private string _target = "", _message = "";
        internal string? Expected = Version;
        internal string? Observed;
        internal Fixture(string kind)
        {
            _kind = kind; Journal = new(Root, Clock);
            Client = new(new("https://chat-diag.invalid/"), Handler, Handler.Clock) { ChatAuthorDiagnostic = Journal.Record };
        }
        internal async Task Prepare()
        {
            var open = J(await Client.OpenOfficialFleetAsync("synthetic", Source, "synthetic-scope", () => { }, default));
            _target = open.GetProperty("targetRef").GetString()!;
            if (_kind == "detail")
            {
                var page = J(await Client.ReadChatAuthorRenewalAsync("synthetic", Renewal("preview"), "synthetic-scope", () => { }, default));
                _message = page.GetProperty("messages")[0].GetProperty("messageRef").GetString()!;
            }
        }
        private JsonElement Renewal(string surface) => J(new { schemaVersion = 1, targetRef = _target, after = Observed is null ? 0 : 1, limit = 8, surface,
            observeMessageRefs = Observed is null ? Array.Empty<string>() : [Observed] });
        internal Task<object> Read() => _kind switch
        {
            "page" => Client.ReadChatAsync("synthetic", J(new { schemaVersion = 1, targetRef = _target, after = 0, before = 0, authorIdentitySchemaVersion = 1,
                observeMessageRefs = Array.Empty<string>() }), "synthetic-scope", () => { }, default),
            "detail" => Client.ReadChatDetailAsync("synthetic", J(new { schemaVersion = 1, targetRef = _target, messageRef = _message, offset = 0,
                authorIdentitySchemaVersion = 1, expectedAuthorIdentityVersion = Expected }), "synthetic-scope", () => { }, default),
            _ => Client.ReadChatAuthorRenewalAsync("synthetic", Renewal(_kind == "preview" ? "preview" : "chat"), "synthetic-scope", () => { }, default)
        };
        internal string[] AllLines() => File.Exists(Path.Combine(Root, OfficialChatAuthorReadJournal.FileName)) ? File.ReadAllLines(Path.Combine(Root, OfficialChatAuthorReadJournal.FileName)) : [];
        internal string[] Lines() => AllLines().Where(l => l.Contains(" stage=" + (_kind == "detail" ? "official-chat-author-detail" : "official-chat-authors") + " ")).ToArray();
        public void Dispose()
        {
            Client.Dispose();
            var parent = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "StarBridge-ChatAuthorTests")) + Path.DirectorySeparatorChar;
            if (Root.StartsWith(parent, StringComparison.OrdinalIgnoreCase) && Directory.Exists(Root)) Directory.Delete(Root, true);
        }
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal readonly Clock Clock = new();
        internal string Outcome = "visible";
        internal bool EmptyPage;
        internal double DelaySeconds;
        internal int Calls;
        internal readonly Exception Error = new Exception(Reference);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/api/official-fleets/context") return Json(new { schemaVersion = 1, sourceRef = Source, fleetCode = Code, name = Name,
                announcementsAvailable = true, chatAvailable = true, canSend = false, readReceiptsAvailable = false, canManageAnnouncements = false,
                authorIdentitySchemaVersion = 1, previewAuthorsAvailable = true });
            if (path == "/api/official-fleets/chat/channels") return Json(new { totalUnread = 0, channels = new[] { new { channelId = "fleet:" + Code, type = "fleet", unreadCount = 0, canSend = false } } });
            var body = request.Content is null ? default : JsonDocument.Parse(await request.Content.ReadAsStringAsync(cancellationToken)).RootElement.Clone();
            var detail = body.ValueKind == JsonValueKind.Object && body.GetProperty("mode").GetString() == "detail";
            var count = Outcome == "mixed" ? 4 : 1;
            static string Subject(int index) => "scm-v1:" + new string((char)('a' + index), 64);
            object MessageRow(int i) => new { sequence = i + 1, messageId = Reference + i, channelId = "fleet:" + Code, senderAccountId = Subject(i), senderCallsign = Name,
                senderGameId = Name, senderRoleTitle = Name, senderRoleColor = "#9DAAB3", text = Message, createdAt = Clock.Now.ToString("O"), isSelf = true,
                hasAvatar = true, avatarVersion = AvatarVersion, hasAttachment = false };
            object Page() => new { schemaVersion = 1, channelId = "fleet:" + Code, latestSequence = count, oldestSequence = EmptyPage ? 0 : 1,
                hasOlder = false, canSend = false, serverTime = Clock.Now.ToString("O"), messages = EmptyPage ? [] : Enumerable.Range(0, count).Select(MessageRow).ToArray() };
            if (path == "/api/official-fleets/chat/messages") return Json(Page());
            Check(path is "/api/official-fleets/chat/messages/read" or "/api/official-fleets/chat/messages/read-preview", "No external handler fallback");
            switch (Outcome)
            {
                case "http": return new(HttpStatusCode.Forbidden) { Content = new StringContent(Message) };
                case "disabled": return new(HttpStatusCode.ServiceUnavailable) { Content = JsonContent.Create(new { reason = "chatAuthorsDisabled" }) };
                case "json": return new(HttpStatusCode.OK) { Content = new StringContent("{" + Message) };
                case "cancelled": throw new OperationCanceledException(Reference);
                case "unknown": throw Error;
            }
            object Identity(int i)
            {
                var state = Outcome == "mixed" ? i == 2 ? "hidden" : i == 3 ? "unavailable" : "visible" : Outcome is "hidden" or "unavailable" ? Outcome : "visible";
                if (state != "visible") return new { businessSubjectId = Subject(i), state };
                var observed = Clock.Now.AddSeconds(Outcome == "expired" ? -6 : Outcome == "future" ? 2 : Outcome == "mixed" ? i == 0 ? -3 : -1 : 0);
                var until = Outcome == "mixed" ? Clock.Now.AddMilliseconds(i == 0 ? 1000 : 500) : Outcome == "near-expiry" ? Clock.Now.AddMilliseconds(1) : observed.AddSeconds(Outcome == "bad-window" ? 6 : 5);
                var row = JsonSerializer.SerializeToNode(new { businessSubjectId = Subject(i), state, callsign = Name, hasAvatar = true,
                    avatarVersion = AvatarVersion, identityVersion = Outcome == "shape" ? new string('0', 64) : Version,
                    identityObservedAtUtc = observed, identityValidUntilUtc = until })!.AsObject();
                if (detail) row["avatarImageData"] = Outcome == "bad-avatar" ? "invalid" : Avatar;
                return row;
            }
            var observedRows = detail ? [] : body.GetProperty("observedMessages").EnumerateArray().Select(row => new
                { messageId = row.GetProperty("messageId").GetString(), sequence = row.GetProperty("sequence").GetInt64(), recordState = "found", senderAccountId = Subject(0) }).ToArray();
            var response = Json(new { schemaVersion = 2, sourceRef = Source, page = detail ? MessageRow(0) : Page(), observedMessages = observedRows,
                identities = Enumerable.Range(0, count).Select(Identity).ToArray(), authorRefreshRequired = false });
            // Buffer the response before advancing the Host clock, simulating slow IO without sleeping.
            await response.Content!.LoadIntoBufferAsync(); Clock.Advance(DelaySeconds);
            return response;
        }
        private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    }
}
