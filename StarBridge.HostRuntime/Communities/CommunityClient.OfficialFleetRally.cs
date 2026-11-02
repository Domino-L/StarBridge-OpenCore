using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

/// Main-fleet rally ("come now"). The relay decides who may start or end it
/// (the fleet owner) and keeps counts only; this client re-validates every
/// reply and never forwards anything beyond the rally projection.
internal sealed partial class CommunityClient
{
    private const string OfficialRallyRoute = "/api/official-fleets/rally";

    internal Task<object> OfficialRallyAsync(string bearer, JsonElement body, Action current, CancellationToken token) =>
        GuardWorkspace(async () =>
    {
        var action = body.ValueKind == JsonValueKind.Object && body.TryGetProperty("action", out var name) &&
            name.ValueKind == JsonValueKind.String ? name.GetString() : null;
        string[] fields = action switch
        {
            "read" => ["action", "sourceRef", "online"],
            "eligibility" => ["action", "sourceRef"],
            "start" => ["action", "sourceRef", "operationId", "text", "minutes"],
            "respond" => ["action", "sourceRef", "rallyId", "response"],
            "end" => ["action", "sourceRef", "rallyId"],
            _ => throw Invalid()
        };
        Validate(body, [.. fields, "include"]);
        var includeStarter = OfficialFleetProjectionRequested(body, "starter");
        if (body.EnumerateObject().Count() != fields.Length + 1 + (body.TryGetProperty("include", out _) ? 1 : 0)) throw Invalid();
        var sourceRef = Text(body, "sourceRef", 64);
        if (!OfficialAnnouncementSource(sourceRef)) throw Invalid();
        using var request = action switch
        {
            // online=0 for an invisible viewer: it may read the rally but is never counted.
            "read" => new HttpRequestMessage(HttpMethod.Get, new Uri(_origin, OfficialRallyRoute + "?sourceRef=" + Uri.EscapeDataString(sourceRef) +
                "&online=" + (body.GetProperty("online").GetBoolean() ? "1" : "0"))),
            "eligibility" => new HttpRequestMessage(HttpMethod.Get,
                new Uri(_origin, OfficialRallyRoute + "/eligibility?sourceRef=" + Uri.EscapeDataString(sourceRef))),
            _ => new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, OfficialRallyRoute + "/" + action))
            {
                Content = JsonContent.Create(Command(action!, body, sourceRef))
            }
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        request.Headers.Add("X-StarBridge-Rally-Starter", "1");
        current(); token.ThrowIfCancellationRequested();
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        current(); token.ThrowIfCancellationRequested();
        if (response.StatusCode != HttpStatusCode.OK) throw new AccountBridgeHostException(response.StatusCode switch
        {
            HttpStatusCode.Unauthorized => "communities.identityUnavailable",
            HttpStatusCode.Forbidden => "communities.notAllowed",
            HttpStatusCode.NotFound => "communities.upgradeRequired",
            HttpStatusCode.Conflict => "officialFleet.rallyConflict",
            HttpStatusCode.TooManyRequests => "officialFleet.rallyRateLimited",
            HttpStatusCode.BadRequest => "communities.dataInvalid",
            _ => "communities.unavailable"
        });
        var row = await ReadOfficialHangarJson(response, token, 4096);
        object projection = action == "eligibility" ? OfficialRallyEligibility(row, sourceRef) : OfficialRallyState(row, sourceRef, action!, includeStarter);
        current(); token.ThrowIfCancellationRequested();
        return (object)JsonSerializer.SerializeToElement(projection);
    });

    private static object Command(string action, JsonElement body, string sourceRef)
    {
        string Id(string key) => Guid.TryParseExact(Text(body, key, 32), "N", out var id) ? id.ToString("N") : throw Invalid();
        return action switch
        {
            "start" => new
            {
                schemaVersion = 1, sourceRef, operationId = Id("operationId"),
                text = OfficialRallyText(Text(body, "text", 256).Trim()),
                minutes = Number(body, "minutes", 15, 60) is var minutes && minutes is 15 or 30 or 60 ? minutes : throw Invalid()
            },
            "respond" => new
            {
                schemaVersion = 1, sourceRef, rallyId = Id("rallyId"),
                response = Text(body, "response", 16) is "coming" or "cannot" ? body.GetProperty("response").GetString() : throw Invalid()
            },
            _ => (object)new { schemaVersion = 1, sourceRef, rallyId = Id("rallyId") }
        };
    }

    private static string OfficialRallyText(string text) =>
        text.Length > 0 && new System.Globalization.StringInfo(text).LengthInTextElements <= 40 ? text : throw Invalid();

    private static object OfficialRallyEligibility(JsonElement row, string sourceRef)
    {
        RequireOfficialAnnouncementObject(row, "schemaVersion", "sourceRef", "canStart", "onlineCount", "remainingThisHour",
            "durations", "maximumText");
        if (Number(row, "schemaVersion", 1, 1) != 1 || Text(row, "sourceRef", 64) != sourceRef) throw Invalid();
        var durations = Rows(row, "durations", 3).Select(v => v.GetInt32()).ToArray();
        if (!durations.SequenceEqual([15, 30, 60]) || Number(row, "maximumText", 40, 40) != 40) throw Invalid();
        var canStart = row.GetProperty("canStart").GetBoolean();
        var remaining = Number(row, "remainingThisHour", 0, 3);
        if (!canStart && remaining != 0) throw Invalid();
        return new
        {
            schemaVersion = 1, sourceRef, canStart, onlineCount = Number(row, "onlineCount", 0, 100000),
            remainingThisHour = remaining, durations, maximumText = 40
        };
    }

    private static object OfficialRallyState(JsonElement row, string sourceRef, string action, bool includeStarter)
    {
        RequireOfficialAnnouncementObject(row, "schemaVersion", "sourceRef", "state", "onlineCount", "rally");
        if (Number(row, "schemaVersion", 1, 1) != 1 || Text(row, "sourceRef", 64) != sourceRef) throw Invalid();
        var state = row.GetProperty("state");
        string? outcome = state.ValueKind == JsonValueKind.Null ? null : state.GetString();
        var expected = action switch
        {
            "read" => outcome is null,
            "start" => outcome is "started" or "duplicate",
            "respond" => outcome is "accepted" or "duplicate",
            _ => outcome is "ended"
        };
        if (!expected) throw Invalid();
        var value = row.GetProperty("rally");
        object? rally = null;
        if (value.ValueKind != JsonValueKind.Null)
        {
            string[] fields = ["rallyId", "text", "minutes", "startedAt", "expiresAt", "state", "coming", "cannot", "pending", "response"];
            var hasStarter = value.TryGetProperty("starter", out var starter);
            RequireOfficialAnnouncementObject(value, hasStarter ? [.. fields, "starter"] : fields);
            var id = Text(value, "rallyId", 32);
            var started = value.GetProperty("startedAt").GetDateTimeOffset();
            var expires = value.GetProperty("expiresAt").GetDateTimeOffset();
            var minutes = Number(value, "minutes", 15, 60);
            var rallyState = Text(value, "state", 16);
            var answer = value.GetProperty("response");
            string? mine = answer.ValueKind == JsonValueKind.Null ? null : answer.GetString();
            if (!Guid.TryParseExact(id, "N", out _) || minutes is not (15 or 30 or 60) || expires != started.AddMinutes(minutes) ||
                rallyState is not ("active" or "ended" or "expired") || mine is not (null or "coming" or "cannot")) throw Invalid();
            var projected = new Dictionary<string, object?>
            {
                ["rallyId"] = id, ["text"] = OfficialRallyText(Text(value, "text", 256)), ["minutes"] = minutes,
                ["startedAt"] = started, ["expiresAt"] = expires, ["state"] = rallyState,
                ["coming"] = Number(value, "coming", 0, 100000), ["cannot"] = Number(value, "cannot", 0, 100000),
                ["pending"] = Number(value, "pending", 0, 100000), ["response"] = mine
            };
            if (hasStarter)
            {
                RequireOfficialAnnouncementObject(starter, "displayName", "isSelf");
                var display = Optional(starter, "displayName", 128);
                if (display is not null && string.IsNullOrWhiteSpace(display)) throw Invalid();
                var isSelf = starter.GetProperty("isSelf").GetBoolean();
                if (includeStarter) projected["starter"] = new { displayName = display, isSelf };
            }
            rally = projected;
        }
        if (action != "read" && rally is null) throw Invalid();
        return new { schemaVersion = 1, sourceRef, state = outcome, onlineCount = Number(row, "onlineCount", 0, 100000), rally };
    }
}
