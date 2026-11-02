using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using D = OfficialFleetDiagnosticFixture;

internal static class OfficialAnnouncementDiagnosticTests
{
    internal static IEnumerable<(string Name, Func<Task> Test)> Cases()
    {
        foreach (var route in new[] { "page", "history", "detail", "author-page", "author-detail", "editor" })
        foreach (var outcome in new[] { "ok", "403", "json", "shape", "business", "network", "unknown", "observer", "disk" })
            yield return ($"CX-ANN-DIAG {route} {outcome}", () => Read(route, outcome));
        foreach (var route in new[] { "page", "detail", "editor" })
            yield return ($"CX-ANN-DIAG {route} no session", () => NoSession(route));
        yield return ("CX-ANN-DIAG fixed journal codes", FixedCodes);
    }

    private static async Task Read(string route, string outcome)
    {
        using var f = new Fixture(route);
        await f.Prepare();
        var calls = f.Data.Relay.Calls;
        var baseline = f.Data.Lines(f.Stage).Length;
        var original = new AccountBridgeHostException("communities.notAllowed", httpStatus: HttpStatusCode.OK);
        switch (outcome)
        {
            case "403": f.Data.Relay.Status = HttpStatusCode.Forbidden; break;
            case "json": f.Data.Relay.Body = "{CXDIAG_BODY_SENTINEL"; break;
            case "shape": f.Data.Relay.Body = "{\"state\":\"CXDIAG_BODY_SENTINEL\"}"; break;
            // Inject a business-layer rejection independently of an HTTP denial.
            case "business": f.Data.Relay.Error = original; break;
            case "network": f.Data.Relay.Error = new HttpRequestException(D.Name); break;
            case "unknown": f.Data.Relay.Error = new Exception(D.Reference); break;
            case "observer":
                f.Data.Host.OfficialFleetDiagnostic = (_, _, _, _) => throw new ArgumentException(D.Name);
                break;
            case "disk":
                Directory.CreateDirectory(f.Data.Root);
                var blocked = Path.Combine(f.Data.Root, "blocked");
                File.WriteAllText(blocked, "synthetic file, not directory");
                f.Data.Host.OfficialFleetDiagnostic = new CommunityReadJournal(blocked).Record;
                break;
        }
        var succeeds = outcome is "ok" or "observer" or "disk";
        if (succeeds)
        {
            var result = D.J(await f.Read());
            if (route == "editor")
                D.Check(result.GetProperty("current").GetProperty("content").GetString() == D.Name, "Editor result preserved");
            else if (!route.Contains("detail"))
                D.Check(result.GetProperty("current").GetProperty("content").GetString() == D.Name, "Page result preserved");
            else D.Check(result.GetProperty("data").GetString()!.Length > 0, "Detail result preserved");
        }
        else
        {
            var error = await D.Failure(f.Read);
            if (outcome is "json" or "shape")
                D.Check(error is AccountBridgeHostException { Code: "communities.dataInvalid" }, "Original parse error preserved");
            if (outcome == "403")
                D.Check(error is AccountBridgeHostException { Code: "communities.notAllowed" }, "Original 403 error preserved");
            if (outcome == "business") D.Check(ReferenceEquals(error, original), "Business exception instance preserved");
            if (outcome == "unknown") D.Check(error.GetType() == typeof(Exception), "Unknown exception type preserved");
        }
        D.Check(f.Data.Relay.Calls == calls + 1, "Diagnostics do not add reads or retries");
        var added = f.Data.Lines(f.Stage).Skip(baseline).ToArray();
        if (outcome is "observer" or "disk")
            D.Check(added.Length == 0, "Failed logging does not alter read result");
        else
        {
            var (code, status) = outcome switch
            {
                "403" => ("http-error", "403"),
                "json" or "shape" => ("parse-failed", "200"),
                "business" => ("notAllowed", "200"),
                "network" => (route == "editor" ? "network" : "unavailable", "none"),
                "unknown" => ("unclassified", "none"),
                _ => ("ok", "200")
            };
            D.Check(added.Length == 1 && Regex.IsMatch(added[0],
                $@"^\S+ \[DEBUG-community-read\] stage={f.Stage} code={code} status={status} elapsedMs=\d+$"),
                "Exactly one bounded line with correct stage, code, HTTP status and elapsed time");
        }
        D.Private(f.AllLines());

        // A throwing diagnostic must also preserve a failed read's exception instance.
        if (outcome is "observer" or "disk")
        {
            f.Data.Relay.Error = original;
            D.Check(ReferenceEquals(await D.Failure(f.Read), original), "Throwing diagnostic preserves original failure");
            D.Check(f.Data.Relay.Calls == calls + 2, "Failure observation sends once");
        }
    }

    private static async Task NoSession(string route)
    {
        using var f = new D(session: false);
        var body = D.J(new { schemaVersion = 1, sourceRef = D.Source,
            action = route == "detail" ? "announcementDetail" : "announcements" });
        var error = await D.Failure(() => route == "editor"
            ? f.Host.ReadOfficialFleetAnnouncementEditorAsync(f.Owner, D.Open, default)
            : f.Host.OfficialFleetCommunicationAsync(f.Owner, body, default));
        D.Check(error is AccountBridgeHostException { Code: AccountBridgeStableErrors.ReauthorizationRequired }, "Entry guard preserved");
        var stage = Stage(route);
        D.Check(f.Lines(stage) is [var line] && line.Contains(" code=reauthorization-required status=none elapsedMs="), "Pre-HTTP failure recorded once");
        D.Check(f.Relay.Calls == 0, "Entry diagnostic never sends");
        D.Private(f.Lines(stage));
    }

    private static Task FixedCodes()
    {
        using var f = new D();
        foreach (var stage in new[] { "official-announcements", "official-announcement-detail", "official-announcement-editor" })
        {
            f.Journal.Record(stage, D.Name + "\n" + D.Reference, 200, 1);
            D.Check(f.Lines(stage) is [var line] && line.Contains(" code=unclassified status=200 "), "Journal never writes arbitrary result codes");
            D.Private(f.Lines(stage));
        }
        return Task.CompletedTask;
    }

    private static string Stage(string route) => route == "editor" ? "official-announcement-editor"
        : route.Contains("detail") ? "official-announcement-detail" : "official-announcements";

    // Random temporary workspace directory and an in-memory handler; never resolves a configured data root.
    private sealed class Fixture(string route) : IDisposable
    {
        internal readonly D Data = new();
        private string? _target, _announcement;
        internal string Stage => OfficialAnnouncementDiagnosticTests.Stage(route);
        private bool Authors => route.StartsWith("author-", StringComparison.Ordinal);
        private const string Stamp = "2026-10-30T00:00:00Z";
        private static object Person => new { accountId = "legacy", callsign = D.Name, gameId = "", roleTitle = D.Name,
            roleColor = "#112233", avatarImageData = (string?)null };
        private static object Entry(bool history = false) => new
        {
            authorHasAvatar = false, lastEditorHasAvatar = false,
            announcement = new { id = history ? D.Reference + "history" : D.Reference, fleetCode = "OFFICIALFLEET:70007",
                title = "Synthetic title", content = D.Name, state = history ? "archived" : "published", revision = 1,
                publishedAt = Stamp, updatedAt = Stamp, archivedAt = history ? Stamp : null, withdrawnAt = (string?)null,
                author = Person, lastEditor = Person }
        };
        private static JsonElement Page(bool detail = false, bool history = false) => detail
            ? D.J(new { schemaVersion = 1, membershipModelVersion = 2, fleetCode = "OFFICIALFLEET:70007", revision = 1, entry = Entry() })
            : D.J(new { schemaVersion = 1, membershipModelVersion = 2, fleetCode = "OFFICIALFLEET:70007", revision = 1,
                current = Entry(), history = history ? new[] { Entry(true) } : [], offset = 0, next = (int?)null,
                totalHistoryCount = history ? 1 : 0, refreshedAt = Stamp });
        private void SetBody(bool detail = false)
        {
            object body = route == "editor" ? new
            {
                schemaVersion = 2, state = "available", sourceRef = D.Source, scopeKey = new string('1', 64),
                authorityBinding = new string('a', 64), policyRevision = 1, timelineRevision = 1,
                current = new { announcementId = D.Reference, itemRevision = 1, title = "Synthetic title", content = D.Name },
                allowedActions = new[] { "publish", "edit", "withdraw" }
            } : Authors ? new
            {
                schemaVersion = 2, sourceRef = D.Source, page = Page(detail), observedAnnouncements = Array.Empty<object>(),
                identities = Array.Empty<object>(), authorRefreshRequired = false
            } : Page(detail, route == "history");
            Data.Relay.Body = JsonSerializer.Serialize(body);
        }
        internal async Task Prepare()
        {
            if (route != "editor")
            {
                Data.Relay.Body = JsonSerializer.Serialize(new { schemaVersion = 1, sourceRef = D.Source,
                    fleetCode = "OFFICIALFLEET:70007", name = D.Name, announcementsAvailable = true, chatAvailable = true,
                    canSend = false, readReceiptsAvailable = false, canManageAnnouncements = false, authorIdentitySchemaVersion = 1 });
                var opened = D.J(await Data.Host.OfficialFleetCommunicationAsync(Data.Owner,
                    D.J(new { schemaVersion = 1, sourceRef = D.Source, action = "open" }), default));
                _target = opened.GetProperty("targetRef").GetString();
                SetBody();
                if (route.Contains("detail"))
                {
                    var page = D.J(await Data.Host.OfficialFleetCommunicationAsync(Data.Owner, Body(detail: false), default));
                    _announcement = page.GetProperty("current").GetProperty("announcementRef").GetString();
                }
            }
            SetBody(route.Contains("detail"));
        }
        private JsonElement Body(bool detail)
        {
            var body = new Dictionary<string, object?> { ["schemaVersion"] = 1, ["sourceRef"] = D.Source,
                ["action"] = detail ? "announcementDetail" : "announcements", ["targetRef"] = _target, ["offset"] = 0 };
            if (detail) body["announcementRef"] = _announcement;
            if (Authors)
            {
                body["authorIdentitySchemaVersion"] = 1;
                if (!detail) body["observeAnnouncementRefs"] = Array.Empty<string>();
            }
            return D.J(body);
        }
        internal Task<object> Read() => route == "editor"
            ? Data.Host.ReadOfficialFleetAnnouncementEditorAsync(Data.Owner, D.Open, default)
            : Data.Host.OfficialFleetCommunicationAsync(Data.Owner, Body(route.Contains("detail")), default);
        internal string[] AllLines() => File.Exists(Path.Combine(Data.Root, "community-read-diagnostics.log"))
            ? File.ReadAllLines(Path.Combine(Data.Root, "community-read-diagnostics.log")) : [];
        public void Dispose() => Data.Dispose();
    }
}
