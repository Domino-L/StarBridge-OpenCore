using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record OfficialObservedAnnouncement(string Reference, AnnouncementTarget Address, bool Found);
    private sealed record OfficialAnnouncementRead(JsonElement Page, IReadOnlyDictionary<string, OfficialAuthorObservation> Identities,
        OfficialObservedAnnouncement[] Updates, bool RefreshRequired, IReadOnlySet<string>? ProvenOffpage = null);
    private static AnnouncementRecord NeutralOfficialAnnouncement(AnnouncementRecord item) => item with
    {
        Author = item.Author with { Callsign = "", GameId = "", RoleTitle = "", RoleColor = "#9DAAB3", HasAvatar = false, Avatar = null },
        Editor = item.Editor with { Callsign = "", GameId = "", RoleTitle = "", RoleColor = "#9DAAB3", HasAvatar = false, Avatar = null }
    };
    private async Task<OfficialAnnouncementRead> ReadOfficialAnnouncementAuthors(string bearer, Target target, JsonElement body, string scope, int offset, long? expectedRevision, CancellationToken token)
    {
        var known = new List<(string Reference, AnnouncementTarget Address)>(); var refresh = false;
        foreach (var value in body.GetProperty("observeAnnouncementRefs").EnumerateArray())
        {
            var reference = value.GetString()!;
            if (!_announcementTargets.TryGetValue(reference, out var address)) { refresh = true; continue; }
            if (address.Code != target.Code || address.Scope != scope || !address.OfficialFleet) throw Invalid(); known.Add((reference, address));
        }
        var source = "officialFleet:" + target.Code["OFFICIALFLEET:".Length..];
        var root = await OfficialAuthorJson(bearer, "/api/official-fleets/announcements/read", new
        {
            schemaVersion = 2,
            sourceRef = source,
            fleetCode = target.Code,
            mode = "page",
            offset,
            expectedRevision,
            observedAnnouncements = known.Select(row => new { announcementId = row.Address.Record.Id, revision = row.Address.Record.Revision }).ToArray()
        }, 400 * 1024, token);
        if (root.ValueKind != JsonValueKind.Object || Number(root, "schemaVersion", 2, 2) != 2 || Text(root, "sourceRef", 64) != source) throw Invalid();
        var page = root.GetProperty("page"); var wrappers = Rows(page, "history", 20).ToList();
        if (page.GetProperty("current").ValueKind != JsonValueKind.Null) wrappers.Add(page.GetProperty("current"));
        var expected = new HashSet<string>(StringComparer.Ordinal);
        foreach (var wrapper in wrappers) foreach (var key in new[] { "author", "lastEditor" })
            {
                var id = Text(wrapper.GetProperty("announcement").GetProperty(key), "accountId", 256); if (OfficialBid(id)) expected.Add(id);
            }
        var updates = known.Select(row => new OfficialObservedAnnouncement(row.Reference, row.Address, false)).ToArray();
        var hintValid = TryAuthorRefresh(root, out var upstreamRefresh); refresh |= upstreamRefresh;
        var valid = hintValid && AuthorKeys(root, ["schemaVersion", "sourceRef", "page", "observedAnnouncements", "identities", "authorRefreshRequired"]);
        try
        {
            var rows = Rows(root, "observedAnnouncements", 21); if (rows.Length != known.Count) throw Invalid();
            for (int i = 0; i < rows.Length; i++)
            {
                var row = rows[i]; var address = known[i].Address; var state = Text(row, "recordState", 16);
                if (Text(row, "announcementId", 128) != address.Record.Id || Number(row, "revision", 1, int.MaxValue) != address.Record.Revision) throw Invalid();
                if (state == "found")
                {
                    if (!AuthorKeys(row, ["announcementId", "revision", "recordState", "authorAccountId", "editorAccountId"]) ||
                        Text(row, "authorAccountId", 256) != address.Record.Author.AccountId || Text(row, "editorAccountId", 256) != address.Record.Editor.AccountId) throw Invalid();
                    foreach (var id in new[] { address.Record.Author.AccountId, address.Record.Editor.AccountId }) if (OfficialBid(id)) expected.Add(id);
                    updates[i] = updates[i] with { Found = true };
                }
                else if (state != "notRetained" || !AuthorKeys(row, ["announcementId", "revision", "recordState"])) throw Invalid();
            }
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or AccountBridgeHostException) { valid = false; refresh = true; }
        var identities = valid ? AuthorIdentities(root, expected) : new Dictionary<string, OfficialAuthorObservation>();
        if (!valid) { refresh = true; updates = updates.Select(row => row with { Found = false }).ToArray(); }
        var read = new OfficialAnnouncementRead(page, identities, updates, refresh);
        return await ReauthorizeOfficialAnnouncement(bearer, target, read, token);
    }
    private void ApplyOfficialPerson(JsonObject person, OfficialAuthorObservation? observation, bool preserveLapsedVisible = false)
    {
        var visible = observation?.Current(_targetClock.GetUtcNow()) == true;
        if (!visible) person["memberRef"] = null;
        // Chat detail may carry a lapsed display observation, never a member permission.
        visible |= preserveLapsedVisible && observation?.State == "visible";
        person["callsign"] = visible ? observation!.Callsign : ""; person["gameId"] = ""; person["roleTitle"] = ""; person["roleColor"] = "#9DAAB3";
        person["hasAvatar"] = visible && observation!.AvatarVersion is not null; person["avatarVersion"] = visible ? observation!.AvatarVersion : null;
        person["identityState"] = visible ? "visible" : observation?.State == "hidden" ? "hidden" : "unavailable";
        person["identityVersion"] = visible ? observation!.IdentityVersion : null;
        person["identityObservedAtUtc"] = visible ? JsonValue.Create(observation!.Observed) : null;
        person["identityValidUntilUtc"] = visible ? JsonValue.Create(observation!.Until) : null;
    }
    private object CompleteOfficialAnnouncementAuthors(object result, OfficialAnnouncementRead read, Dictionary<string, AnnouncementTarget> pending, string scope, Action current, CancellationToken token, long operationStarted, string targetRef)
    {
        var refresh = read.RefreshRequired; var revision = AnnouncementRevision(read.Page, "revision");
        token.ThrowIfCancellationRequested(); current();
        foreach (var observed in read.Updates)
        {
            bool unchanged = observed.Found && (observed.Address.TimelineRevision == revision || pending.Values.Any(row => row.Record == observed.Address.Record) || read.ProvenOffpage?.Contains(observed.Reference) == true);
            if (unchanged) _announcementTargets.TryUpdate(observed.Reference, observed.Address with { Expires = _targetClock.GetUtcNow().AddMinutes(5), TimelineRevision = revision }, observed.Address);
            else refresh = true;
        }
        return OfficialAuthorProjectionResult(read.Identities, retired =>
        {
            OfficialAuthorObservation? Author(string id) => retired.Contains(id) ? null : read.Identities.GetValueOrDefault(id);
            var node = JsonSerializer.SerializeToNode(result, AnnouncementJson)!.AsObject();
            var entries = node["history"]!.AsArray().ToList(); if (node["current"] is { } active) entries.Add(active);
            foreach (var entry in entries)
            {
                var view = entry!.AsObject(); var record = pending[view["announcementRef"]!.GetValue<string>()].Record;
                ApplyOfficialPerson(view["author"]!.AsObject(), Author(record.Author.AccountId)); ApplyOfficialPerson(view["editor"]!.AsObject(), Author(record.Editor.AccountId));
            }
            JsonObject Person(AnnouncementPerson value, string code, bool found)
            {
                var observation = found ? Author(value.AccountId) : null;
                var memberRef = observation?.Current(_targetClock.GetUtcNow()) == true
                    ? MemberReferenceFor("account:" + value.AccountId, code, scope, create: false) : null;
                var person = new JsonObject { ["memberRef"] = memberRef }; ApplyOfficialPerson(person, observation); return person;
            }
            var updates = new JsonArray();
            foreach (var observed in read.Updates)
            {
                var record = observed.Address.Record;
                updates.Add(new JsonObject
                {
                    ["announcementRef"] = observed.Reference,
                    ["revision"] = record.Revision,
                    ["recordState"] = observed.Found ? "found" : "notRetained",
                    ["author"] = Person(record.Author, observed.Address.Code, observed.Found),
                    ["editor"] = Person(record.Editor, observed.Address.Code, observed.Found)
                });
            }
            if (JsonSerializer.SerializeToUtf8Bytes(updates, AnnouncementJson).Length > 64 * 1024) throw Invalid();
            node["authorUpdates"] = updates; node["authorRefreshRequired"] = refresh || retired.Count > 0; node["authorIdentitySchemaVersion"] = 1; return node;
        }, current, token, operationStarted, targetRef);
    }
    private void TrimOfficialAnnouncementAddresses(Target target, string scope, HashSet<string> pending)
    {
        var added = pending.Count(reference => !_announcementTargets.ContainsKey(reference));
        var existing = _announcementTargets.Where(pair => pair.Value.OfficialFleet && pair.Value.Code == target.Code && pair.Value.Scope == scope).ToArray();
        foreach (var old in existing.Where(pair => !pending.Contains(pair.Key)).OrderBy(pair => pair.Value.Record.UpdatedAt, StringComparer.Ordinal)
            .Take(Math.Max(0, existing.Length + added - 100))) _announcementTargets.TryRemove(old.Key, out _);
        foreach (var old in _announcementTargets.Where(pair => pair.Value.OfficialFleet && !pending.Contains(pair.Key)).OrderBy(pair => pair.Value.Expires)
            .Take(Math.Max(0, _announcementTargets.Count + added - 4000)).ToArray()) _announcementTargets.TryRemove(old.Key, out _);
    }
}
