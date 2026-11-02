using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;

internal static class OfficialFleetAnnouncementManagementClientTests
{
    internal static async Task RunAsync()
    {
        using (var scene = new Driver())
        {
            var editor = await scene.Open(); var id = new string('a', 32); var body = scene.Intent(editor, id);
            var saved = await scene.Send(body);
            Check(Status(saved) == "accepted" && saved.GetProperty("revision").GetInt64() == 2 && scene.Handler.Posts == 1,
                "Synthetic codec verifies timeline2 independently of policy4 and one normalized official POST");
            var posted = scene.Handler.Last ?? throw new InvalidOperationException("Missing recorded POST");
            Check(posted.GetProperty("title").GetString() == "Title" &&
                posted.GetProperty("content").GetString() == "Body\ntext", "Original announcement normalization is reused");
            Check(Status(await scene.Send(body)) == "accepted" && scene.Handler.Posts == 1, "Confirmed same-ID bridge delivery does not POST again");
            var changed = scene.Intent(editor, id, title: "Different");
            Check((await scene.Send(changed)).GetProperty("error").GetString() == "intentConflict" && scene.Handler.Posts == 1,
                "The original bridge fingerprint cannot silently change even after editor retirement");
        }
        foreach (var mode in new[] { "bare-400", "bare-401", "bare-403", "bare-409", "bare-429", "auth-throw", "lost",
                     "malformed", "wrong-op", "wrong-policy", "wrong-timeline", "unknown-reason", "duplicate-keys", "oversized" })
        {
            using var scene = new Driver(); var body = scene.Intent(await scene.Open(), Guid.NewGuid().ToString("N"));
            scene.Handler.PostMode = mode;
            Check(Status(await scene.Send(body)) == "unknown" && scene.Handler.Posts == 1, mode + " never becomes a false definite rejection or success");
            Check(Status(await scene.Send(body)) == "unknown" && scene.Handler.Posts == 1, mode + " cannot be replayed by callback redelivery");
            scene.Handler.NotFound = true;
            Check(Status(await scene.Query(body.GetProperty("requestId").GetString()!)) == "unknown" && scene.Handler.Posts == 1,
                "notFound preserves original uncertainty without replacement ID or mutation POST");
        }
        foreach (var (status, state, error) in new[] { (400, "invalid", "dataInvalid"), (403, "notAllowed", "notAllowed"),
                     (409, "conflict", "announcementsChanged"), (503, "storageLimitReached", "unavailable") })
        {
            using var scene = new Driver(); var body = scene.Intent(await scene.Open(), Guid.NewGuid().ToString("N"));
            scene.Handler.Rejection = (status, state);
            var result = await scene.Send(body);
            Check(Status(result) == "rejected" && result.GetProperty("error").GetString() == error,
                "Only strict correlated original endpoint " + state + " is a definite rejection");
        }
        using (var scene = new Driver())
        {
            var editor = await scene.Open(); scene.Handler.GetMode = "unavailable";
            await Failure(() => scene.Open());
            scene.Handler.GetMode = "";
            Check(Status(await scene.Send(scene.Intent(editor, Guid.NewGuid().ToString("N")))) == "rejected" && scene.Handler.Posts == 0,
                "A failed fresh read permanently retires the old positive editor");
            editor = await scene.Open(); scene.Handler.Binding = new string('b', 64);
            Check((await scene.Send(scene.Intent(editor, Guid.NewGuid().ToString("N")))).GetProperty("error").GetString() == "announcementsChanged" &&
                scene.Handler.Posts == 0, "Same org/source with a different incarnation binding cannot reuse old intent");
        }
        await RetiredEditorDuringPreflightAsync();
        await LateEditorAsync();
        foreach (var mode in new[] { "schema1", "missing-binding", "bad-binding", "extra-key", "duplicate-key" })
        {
            using var scene = new Driver(); scene.Handler.GetMode = mode;
            await Failure(() => scene.Open());
            Check(scene.Handler.Posts == 0, "Strict editor " + mode + " cannot create a fallback management reference");
        }
        using (var scene = new Driver())
        {
            var editor = await scene.Open();
            foreach (var body in new[] {
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, sourceRef = "officialFleet:7", editRef = editor.GetProperty("editRef").GetString(),
                    requestId = new string('a',32), action = "withdraw", announcementRef = editor.GetProperty("current").GetProperty("announcementRef").GetString(), title = (string?)null }),
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, sourceRef = "officialFleet:7", editRef = editor.GetProperty("editRef").GetString(),
                    requestId = new string('a',32), action = "edit", announcementRef = editor.GetProperty("current").GetProperty("announcementRef").GetString(),
                    title = "Title", content = "Body", expectedPolicyRevision = 3 }) })
                await Failure(() => scene.Send(body));
            Check(scene.Handler.Posts == 0, "Strict union and native-only CAS reject malformed intent before HTTP");
        }
    }
    private static async Task RetiredEditorDuringPreflightAsync()
    {
        using var scene = new Driver();
        var editor = await scene.Open();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        scene.Handler.BeforeEditor = () => { entered.SetResult(); return release.Task; };
        var sending = scene.Send(scene.Intent(editor, Guid.NewGuid().ToString("N")));
        await entered.Task;
        scene.Handler.BeforeEditor = null; scene.Handler.GetMode = "unavailable";
        try { await Failure(() => scene.Open()); }
        finally { scene.Handler.GetMode = ""; release.SetResult(); }
        Check(Status(await sending) == "rejected" && scene.Handler.Posts == 0,
            "A failed concurrent fresh read retires an in-flight old editor before its positive POST");
    }
    private static async Task LateEditorAsync()
    {
        using var scene = new Driver();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        scene.Handler.BeforeEditor = () => { entered.SetResult(); return release.Task; };
        var late = scene.Open(); await entered.Task;
        scene.Handler.BeforeEditor = null; scene.Handler.GetMode = "unavailable";
        try { await Failure(() => scene.Open()); }
        finally { scene.Handler.GetMode = ""; release.SetResult(); }
        await Failure(() => late);
        Check((await scene.Open()).GetProperty("state").GetString() == "available" && scene.Handler.Posts == 0,
            "Late old editor completion cannot revive a retired reference or displace the next current read");
        var editor = await scene.Open();
        var changed = scene.Intent(editor, Guid.NewGuid().ToString("N"));
        var wrongGeneration = JsonSerializer.SerializeToElement(await scene.Client.ManageOfficialAnnouncementsAsync(
            "synthetic", changed, Driver.Account, "synthetic-generation-2", () => { }, default));
        Check(Status(wrongGeneration) == "rejected" && scene.Handler.Posts == 0,
            "The same account's old opaque editor is not restored into another generation");
    }
    internal static string Status(JsonElement value) => value.GetProperty("status").GetString()!;
    internal static void Check(bool value, string message)
    {
        if (!value) throw new InvalidOperationException(message);
        Console.WriteLine("PASS " + message);
    }
    internal static async Task Failure(Func<Task<JsonElement>> action)
    {
        try { await action(); throw new Exception("Expected a closed native failure"); }
        catch (AccountBridgeHostException) { }
    }
    internal sealed class Clock(DateTimeOffset now) : TimeProvider { public override DateTimeOffset GetUtcNow() => now; }
    internal sealed class Driver : IDisposable
    {
        internal readonly Clock Clock = new(DateTimeOffset.UtcNow);
        internal readonly Handler Handler = new();
        internal readonly string Root;
        internal readonly CommunityClient Client;
        internal const string Account = "synthetic-account", Scope = "synthetic-generation-1";
        internal static readonly Uri Origin = new("https://announcement.invalid/");
        internal Driver(Action<string>? fault = null, string? root = null)
        {
            Root = root ?? Path.Combine(Path.GetTempPath(), "a4b-native-" + Guid.NewGuid().ToString("N"));
            Client = new(Origin, Handler, Clock, announcementJournal: new(Root, Clock, fault));
        }
        internal async Task<JsonElement> Open() => JsonSerializer.SerializeToElement(await Client.ReadOfficialAnnouncementEditorAsync(
            "synthetic", JsonSerializer.SerializeToElement(new { schemaVersion = 1, sourceRef = "officialFleet:7" }), Scope, () => { }, default));
        internal JsonElement Intent(JsonElement editor, string id, string action = "edit", string title = " Title ", string content = " Body\r\ntext ")
        {
            var body = new Dictionary<string, object?>
            {
                ["schemaVersion"] = 1,
                ["sourceRef"] = "officialFleet:7",
                ["editRef"] = editor.GetProperty("editRef").GetString(),
                ["requestId"] = id,
                ["action"] = action
            };
            if (action != "publish") body["announcementRef"] = editor.GetProperty("current").GetProperty("announcementRef").GetString();
            if (action != "withdraw") { body["title"] = title; body["content"] = content; }
            return JsonSerializer.SerializeToElement(body);
        }
        internal async Task<JsonElement> Send(JsonElement body) => JsonSerializer.SerializeToElement(await Client.ManageOfficialAnnouncementsAsync(
            "synthetic", body, Account, Scope, () => { }, default));
        internal async Task<JsonElement> Query(string id) => JsonSerializer.SerializeToElement(await Client.ReadOfficialAnnouncementOutcomeAsync(
            "synthetic", JsonSerializer.SerializeToElement(new { schemaVersion = 1, kind = "query", requestId = id }), Account, () => { }, default));
        public void Dispose() => Client.Dispose();
    }
    internal sealed class Handler : HttpMessageHandler
    {
        internal int Posts, Queries, Policy = 3, Timeline = 1, Item = 1;
        internal string Binding = new('a', 64), GetMode = "", PostMode = "", Title = "Before", Content = "Body";
        internal bool NotFound;
        internal (int Status, string State)? Rejection;
        internal JsonElement? Last;
        internal Func<Task>? BeforeEditor;
        private readonly Dictionary<string, JsonElement> _receipts = new();
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = request.RequestUri!.AbsolutePath;
            if (request.Method == HttpMethod.Get)
            {
                Check(path == "/api/official-fleets/governance/announcements/editor" &&
                    request.Headers.GetValues("X-StarBridge-Announcement-Editor-Version").Single() == "2", "Exact editor2 route/header; no G4 or community authority request");
                if (BeforeEditor is { } before) await before();
                token.ThrowIfCancellationRequested();
                if (GetMode == "unavailable") return new(HttpStatusCode.ServiceUnavailable);
                var data = new Dictionary<string, object?>
                {
                    ["schemaVersion"] = GetMode == "schema1" ? 1 : 2,
                    ["state"] = "available",
                    ["sourceRef"] = "officialFleet:7",
                    ["scopeKey"] = new string('1', 64),
                    ["authorityBinding"] = GetMode == "bad-binding" ? "bad" : Binding,
                    ["policyRevision"] = Policy,
                    ["timelineRevision"] = Timeline,
                    ["current"] = new { announcementId = "private-item", itemRevision = Item, title = Title, content = Content },
                    ["allowedActions"] = new[] { "publish", "edit", "withdraw" }
                };
                if (GetMode is "schema1" or "missing-binding") data.Remove("authorityBinding");
                if (GetMode == "extra-key") data["privateUnexpected"] = true;
                if (GetMode == "duplicate-key") return new(HttpStatusCode.OK) { Content = new StringContent("{\"schemaVersion\":2,\"schemaVersion\":2}") };
                return Json(data);
            }
            using var document = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            var body = document.RootElement;
            if (path == "/api/official-fleets/governance/receipt-query")
            {
                Queries++;
                var operation = body.GetProperty("operationId").GetString()!;
                if (NotFound || !_receipts.TryGetValue(operation, out var receipt)) return new(HttpStatusCode.NotFound);
                return Json(receipt);
            }
            Check(path.StartsWith("/api/official-fleets/announcements/", StringComparison.Ordinal), "Official writes never fall back to community URLs");
            Posts++; Last = body.Clone();
            var op = body.GetProperty("operationId").GetString()!;
            if (Rejection is { } rejection) return new((HttpStatusCode)rejection.Status)
            { Content = JsonContent.Create(new { schemaVersion = 1, state = rejection.State, operationId = op }) };
            Policy++; Timeline++; Item++;
            if (body.TryGetProperty("title", out var title)) { Title = title.GetString()!; Content = body.GetProperty("content").GetString()!; }
            _receipts[op] = JsonSerializer.SerializeToElement(new
            {
                schemaVersion = 1,
                state = "found",
                operationId = op,
                kind = "announcements." + path.Split('/').Last(),
                expectedRevision = Policy - 1,
                resultRevision = Policy,
                auditSequence = Policy,
                timelineRevision = Timeline
            });
            if (PostMode == "auth-throw") throw new ScmApiAuthenticationException("Synthetic post-commit authentication exception");
            if (PostMode == "lost") throw new HttpRequestException("Synthetic lost response");
            if (PostMode.StartsWith("bare-", StringComparison.Ordinal)) return new((HttpStatusCode)int.Parse(PostMode[5..]));
            if (PostMode == "malformed") return new(HttpStatusCode.OK) { Content = new StringContent("{") };
            if (PostMode == "oversized") return new(HttpStatusCode.OK) { Content = new StringContent(new string('x', 4097)) };
            if (PostMode == "unknown-reason") return new(HttpStatusCode.Forbidden)
            { Content = JsonContent.Create(new { schemaVersion = 1, state = "differentReason", operationId = op }) };
            if (PostMode == "duplicate-keys") return new(HttpStatusCode.OK) { Content = new StringContent("{\"schemaVersion\":1,\"schemaVersion\":1}") };
            return Json(new
            {
                schemaVersion = 1,
                state = "accepted",
                operationId = PostMode == "wrong-op" ? "other" : op,
                policyRevision = PostMode == "wrong-policy" ? Policy + 1 : Policy,
                timelineRevision = PostMode == "wrong-timeline" ? Policy : Timeline,
                auditSequence = Policy
            });
        }
        private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    }
}
