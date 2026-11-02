using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using Roster = StarBridge.HostRuntime.OfficialFleet.OfficialFleetPublicRosterDecoder;

internal static partial class OfficialFleetReadTests
{
    // Synthetic typed-contract fixtures only; these are not exported Java producer bytes.
    private static readonly string RosterGeneration = new('a', 32), RosterRevision = new('b', 64);
    private static Roster.Request RosterRequest(string search = "", int page = 1, Roster.Pin? pin = null) =>
        new("officialFleet:7", "ASTER", search, page, 25, pin);

    private static void RunPublicRosterDecoder()
    {
        PublicRosterAvailableFacts();
        PublicRosterPaginationAndScope();
        PublicRosterUnavailableIsNotEmpty();
        PublicRosterRejectsCorruptionAndDisclosure();
        PublicRosterTimestampContract();
        PublicRosterQueryPreflightContract();
    }

    private static void PublicRosterQueryPreflightContract()
    {
        const string nullSearchJson = """
            {"SourceRef":"officialFleet:7","Search":null,"PageNumber":1,"PageSize":25,"SnapshotPin":null}
            """;
        Roster.Query nullSearch = JsonSerializer.Deserialize<Roster.Query>(nullSearchJson)
            ?? throw new InvalidOperationException("The synthetic null-search query must deserialize");
        Require(nullSearch.Search is null, "Real JSON deserialization preserves the malformed null search");
        bool rejected = false;
        try { Roster.ValidateQuery(nullSearch); }
        catch (AccountBridgeHostException error) when (error.Code == AccountBridgeStableErrors.OfficialFleetDataInvalid)
        { rejected = true; }
        Require(rejected, "ValidateQuery rejects a deserialized null search with the exact data_invalid code");

        foreach ((string search, string expected) in new[] { ("", ""), ("   ", ""), ("  Wing  ", "Wing") })
        {
            string json = JsonSerializer.Serialize(new { SourceRef = "officialFleet:7", Search = search,
                PageNumber = 1, PageSize = 25, SnapshotPin = (object?)null });
            Roster.Query query = JsonSerializer.Deserialize<Roster.Query>(json)
                ?? throw new InvalidOperationException("The synthetic valid query must deserialize");
            Require(Roster.ValidateQuery(query).Search == expected,
                "Empty search and Java-compatible space trimming retain their exact admitted result");
        }
    }

    private static void PublicRosterAvailableFacts()
    {
        Roster.Response decoded = DecodeRoster(RosterFixture());
        Require(decoded.State == Roster.ReadState.Available && decoded.StableErrorCode is null,
            "A complete public snapshot is available without claiming any membership permission");
        Roster.Page page = decoded.Page!;
        Require(page.TotalCount == 3 && page.TotalPages == 1 && page.Snapshot.PagesRead == 3
            && page.Snapshot.Counts == new Roster.Counts(3, 1, 1, 1), "Source counts include anonymous rows");
        Require(page.Members.Select(row => row.SourceEntryRef).SequenceEqual(
            ["page:1:row:0", "page:2:row:0", "page:2:row:1"]),
            "Short nonempty source pages remain valid; source order is not page-times-32 arithmetic");
        Require(page.Members[0].Handle == "Pilot-Wing" && page.Members[0].RankValue is null
            && page.Members[0].RoleLabels!.SequenceEqual(["", "role\nlabel"]),
            "Actual Query role-label rules and absent normalized rank remain intact");
        Require(page.Members.Skip(1).All(row => row.Handle is null && row.PublicDisplayName is null
            && row.RankName is null && row.RoleLabels is null && row.RankValue is null),
            "Hidden and redacted rows contain no author/linkage fallback");
        JsonObject stale = RosterFixture(); RosterSnapshot(stale)["freshness"] = "stale";
        Require(DecodeRoster(stale).Page!.Snapshot.Freshness == Roster.Freshness.Stale,
            "Stale complete source facts remain distinct from unavailable or realtime presence");
        JsonObject empty = RosterFixture();
        RosterSnapshot(empty)["pagesRead"] = 1; SetRosterCounts(empty, 0, 0, 0, 0);
        empty["members"] = new JsonArray(); empty["totalCount"] = 0; empty["totalPages"] = 0;
        Require(DecodeRoster(empty).Page is { TotalCount: 0, TotalPages: 0, Members.Count: 0 },
            "A genuinely available empty traversal has zero total pages, not a fabricated page one");
    }

    private static void PublicRosterPaginationAndScope()
    {
        var pin = new Roster.Pin(RosterGeneration, RosterRevision);
        JsonObject second = RosterFixture(); SetRosterCounts(second, 26, 26, 0, 0);
        second["query"]!["page"] = 2; second["query"]!["generation"] = RosterGeneration;
        second["query"]!["revision"] = RosterRevision;
        second["members"] = new JsonArray(RosterRow(25, 2, 0)); second["totalCount"] = 26; second["totalPages"] = 2;
        Require(DecodeRoster(second, RosterRequest(page: 2, pin: pin)).Page!.Members.Single().SourceOrder == 25,
            "Subsequent pages use the caller's exact generation/revision pair and source offset");
        RejectRoster(second, "A pinned response cannot be treated as an unpinned request");
        JsonObject mismatch = (JsonObject)second.DeepClone(); RosterSnapshot(mismatch)["revision"] = new string('c', 64);
        RejectRoster(mismatch, "Snapshot pin cannot drift after a correct request echo", RosterRequest(page: 2, pin: pin));
        JsonObject beyond = RosterFixture(); beyond["query"]!["page"] = 2; beyond["members"] = new JsonArray();
        Require(DecodeRoster(beyond, RosterRequest(page: 2)).Page!.Members.Count == 0,
            "A requested page after the end does not replace the authoritative total");
        JsonObject highSourcePage = RosterFixture(); SetRosterCounts(highSourcePage, 99_999, 99_999, 0, 0);
        RosterSnapshot(highSourcePage)["pagesRead"] = 100_000; highSourcePage["query"]!["page"] = 4_000;
        highSourcePage["totalCount"] = 99_999; highSourcePage["totalPages"] = 4_000;
        highSourcePage["members"] = new JsonArray(Enumerable.Range(99_975, 24)
            .Select(order => (JsonNode)RosterRow(order, order + 1, 0)).ToArray());
        Require(DecodeRoster(highSourcePage, RosterRequest(page: 4_000)).Page!.Members.Count == 24,
            "Source page limit 100000 is independent of the public query page limit 4000");

        JsonObject searched = RosterFixture(); searched["query"]!["query"] = "Wing";
        searched["members"] = new JsonArray(RosterRow(0, 1, 0)); searched["totalCount"] = 1;
        Require(DecodeRoster(searched, RosterRequest(" Wing ")).Page!.Query.Search == "Wing",
            "Only the existing Java query-space trim is mirrored; SID is never normalized");
        JsonObject noMatch = RosterFixture(); noMatch["query"]!["query"] = "none";
        noMatch["members"] = new JsonArray(); noMatch["totalCount"] = 0; noMatch["totalPages"] = 0;
        Require(DecodeRoster(noMatch, RosterRequest("none")).Page!.Snapshot.Counts.Total == 3,
            "Zero search matches do not erase the whole snapshot count");
        foreach (string sid in new[] { "A-", new string('Z', 32) }) {
            JsonObject candidateSid = RosterFixture(); candidateSid["query"]!["sid"] = sid;
            RosterSnapshot(candidateSid)["sid"] = sid;
            Require(DecodeRoster(candidateSid, RosterRequest() with { Sid = sid }).State == Roster.ReadState.Available,
                "Source-owner SID contract is 2..32 uppercase alphanumeric/hyphen; Query alignment is a separate pending delta");
        }
        foreach (string sid in new[] { "A", "aster", " ASTER", "ASTER ", new string('Z', 33), "AS_TER" })
            RejectRoster(RosterFixture(), "SID admission never guesses or silently normalizes", RosterRequest() with { Sid = sid });
        foreach (string source in new[] { "officialFleet:0", "officialFleet:07", "community:7", "officialFleet:9223372036854775808" })
            RejectRoster(RosterFixture(), "Only a valid caller-supplied verified fleet/source locator is admitted",
                RosterRequest() with { SourceRef = source });
        foreach (string field in new[] { "sid", "query", "page", "pageSize" }) {
            JsonObject changed = RosterFixture();
            changed["query"]![field] = field switch { "page" => JsonValue.Create(2), "pageSize" => JsonValue.Create(50),
                "sid" => JsonValue.Create("OTHER"), _ => JsonValue.Create("other") };
            RejectRoster(changed, "Every echoed request field is bound to the caller");
        }
    }

    private static void PublicRosterUnavailableIsNotEmpty()
    {
        foreach (string reason in new[] { "disabled", "queryBusy", "configurationUnavailable", "cacheUnavailable",
            "queryBudgetExceeded", "expired", "conflict", "corrupt" }) {
            JsonObject unavailable = UnavailableRoster(reason); Roster.Response result = DecodeRoster(unavailable);
            Require(result.State == Roster.ReadState.Unavailable && result.Page is null && result.Reason == reason
                && result.StableErrorCode == AccountBridgeStableErrors.OfficialFleetReadUnavailable,
                "A well-formed unavailable response remains explicit and cannot become an empty/registered roster");
            unavailable["members"] = new JsonArray(); RejectRoster(unavailable, "Unavailable cannot carry a page, even an empty one");
        }
        RejectRoster(UnavailableRoster("futureReason"), "An unknown unavailable reason is a protocol mismatch");
        RejectRoster(new JsonObject { ["code"] = 0, ["data"] = RosterFixture(), ["msg"] = "" },
            "The decoder consumes only data; public HTTP envelope validation remains in its existing owner");
    }

    private static void PublicRosterRejectsCorruptionAndDisclosure()
    {
        Action<JsonObject>[] corruptions = [
            value => value["schemaVersion"] = 2,
            value => value["coverage"] = "registeredMembers",
            value => value["order"] = "name",
            value => value["memberId"] = 42,
            value => value["totalPages"] = 2,
            value => value["totalCount"] = 2,
            value => RosterSnapshot(value)["traversalComplete"] = false,
            value => RosterSnapshot(value)["reportedTotalStable"] = false,
            value => RosterSnapshot(value)["countRelation"] = "below_reported",
            value => RosterSnapshot(value)["reportedTotalEnd"] = 4,
            value => RosterSnapshot(value)["counts"]!["visible"] = 2,
            value => RosterSnapshot(value)["pagesRead"] = 1,
            value => value["members"]![0]!["rankValue"] = 5,
            value => value["members"]![0]!["visibility"] = "unknown",
            value => value["members"]![0]!["sourceEntryRef"] = "page:100001:row:0",
            value => value["members"]![0]!["sourceEntryRef"] = "page:1:row:1",
            value => value["members"]![0]!["sourceOrder"] = 1,
            value => value["members"]![0]!["userId"] = 42,
            value => value["members"]![1]!["handle"] = "SCM fallback",
            value => value["members"]![2]!["publicDisplayName"] = "Hidden fallback",
            value => value["members"]![2]!["roleLabels"] = new JsonArray("Owner"),
            value => value["members"]![0]!["roleLabels"] = new JsonArray(),
            value => value["members"]![0]!["roleLabels"] = new JsonArray(JsonValue.Create(42)),
            value => value["members"]![0]!["handle"] = "control\nname"
        ];
        foreach (Action<JsonObject> corrupt in corruptions) {
            JsonObject fixture = RosterFixture(); corrupt(fixture); RejectRoster(fixture, "Corrupt or identity-leaking source facts fail closed");
        }
        string duplicate = RosterFixture().ToJsonString().Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1", StringComparison.Ordinal);
        using JsonDocument parsed = JsonDocument.Parse(duplicate);
        Require(Roster.Decode(parsed.RootElement, RosterRequest()).State == Roster.ReadState.Invalid,
            "Duplicate JSON properties are rejected even when values agree");
        JsonObject anonymousSearch = RosterFixture(); anonymousSearch["query"]!["query"] = "x";
        anonymousSearch["totalCount"] = 1; anonymousSearch["members"] = new JsonArray(RosterRow(2, 2, 1, "hidden"));
        RejectRoster(anonymousSearch, "Search cannot reveal anonymous rows", RosterRequest("x"));
    }

    private static void PublicRosterTimestampContract()
    {
        Roster.Snapshot normal = DecodeRoster(RosterFixture()).Page!.Snapshot;
        Require(normal.StartedAtUtc == new Roster.SourceInstant(1_700_000_000, 0, 1_000_000),
            "Current numeric Jackson timestamps are explicit epoch milliseconds, not guessed seconds");
        JsonObject beforeEpoch = RosterFixture(); RosterSnapshot(beforeEpoch)["startedAtUtc"] = -1;
        RosterSnapshot(beforeEpoch)["completedAtUtc"] = 0;
        Require(DecodeRoster(beforeEpoch).Page!.Snapshot.StartedAtUtc == new Roster.SourceInstant(-1, 999_000_000, 1_000_000),
            "Negative epoch milliseconds use floor division without changing the instant");
        JsonObject exact = RosterFixture(); RosterSnapshot(exact)["startedAtUtc"] = "0000-01-01T00:00:00.000000001Z";
        RosterSnapshot(exact)["completedAtUtc"] = "0000-01-01T00:00:00.000000002+00:00";
        Require(DecodeRoster(exact).Page!.Snapshot.StartedAtUtc == new Roster.SourceInstant(-62_167_219_200, 1),
            "Explicit UTC text retains Java nanoseconds and year zero without DateTimeOffset truncation");
        JsonObject sourceClock = RosterFixture(); RosterSnapshot(sourceClock)["firstSourceObservedAtUtc"] = 1_800_000_000_000L;
        RosterSnapshot(sourceClock)["lastSourceObservedAtUtc"] = 1_600_000_000_000L;
        Require(DecodeRoster(sourceClock).State == Roster.ReadState.Available,
            "Independent source clock ordering is not invented beyond Builder's actual contract");
        foreach (JsonNode timestamp in new JsonNode[] { JsonValue.Create(1.5m)!, JsonValue.Create("1700000000000")!,
            JsonValue.Create("2026-10-18T12:00:00+01:00")!, JsonValue.Create("2026-10-18T12:00:60Z")!,
            JsonValue.Create("2026-02-29T12:00:00Z")!, JsonValue.Create("2026-10-18T12:00:00.0000000001Z")! }) {
            JsonObject invalid = RosterFixture(); RosterSnapshot(invalid)["firstSourceObservedAtUtc"] = timestamp;
            RejectRoster(invalid, "Timestamp units, precision and UTC offset are explicit");
        }
        JsonObject boundary = RosterFixture(); RosterSnapshot(boundary)["completedAtUtc"] = 1_700_014_400_000L;
        Require(DecodeRoster(boundary).State == Roster.ReadState.Available,
            "A legal source window of four hours minus one nanosecond can quantize to exactly four hours");
        JsonObject tooLong = RosterFixture(); RosterSnapshot(tooLong)["completedAtUtc"] = 1_700_014_400_001L;
        RejectRoster(tooLong, "A quantized window beyond four hours plus the lost fraction is impossible");
        RosterSnapshot(tooLong)["completedAtUtc"] = 1_700_014_399_999L;
        Require(DecodeRoster(tooLong).State == Roster.ReadState.Available, "The last millisecond inside the source build window remains valid");
        JsonObject exactLimit = RosterFixture(); RosterSnapshot(exactLimit)["startedAtUtc"] = "1970-01-01T00:00:00Z";
        RosterSnapshot(exactLimit)["completedAtUtc"] = "1970-01-01T04:00:00Z";
        RejectRoster(exactLimit, "Exact ISO instants at four hours cannot hide sub-millisecond writer precision");
    }

    private static Roster.Response DecodeRoster(JsonNode fixture, Roster.Request? request = null) =>
        Roster.Decode(JsonSerializer.SerializeToElement(fixture), request ?? RosterRequest());
    private static void RejectRoster(JsonNode fixture, string reason, Roster.Request? request = null)
    {
        Roster.Response result = DecodeRoster(fixture, request);
        Require(result.State == Roster.ReadState.Invalid && result.Page is null
            && result.StableErrorCode == AccountBridgeStableErrors.OfficialFleetDataInvalid, reason);
    }
    private static JsonObject RosterSnapshot(JsonObject value) => (JsonObject)value["snapshot"]!;
    private static void SetRosterCounts(JsonObject value, int total, int visible, int redacted, int hidden)
    {
        JsonObject snapshot = RosterSnapshot(value);
        snapshot["counts"] = new JsonObject { ["total"] = total, ["visible"] = visible, ["redacted"] = redacted, ["hidden"] = hidden };
        snapshot["reportedTotalStart"] = total; snapshot["reportedTotalEnd"] = total;
    }
    private static JsonObject RosterRow(int order, int sourcePage, int ordinal, string visibility = "visible") => new() {
        ["sourceOrder"] = order, ["sourceEntryRef"] = $"page:{sourcePage}:row:{ordinal}", ["sourceOrdinalInPage"] = ordinal,
        ["visibility"] = visibility, ["hasMainClass"] = false, ["handle"] = visibility == "visible" ? $"Pilot-{order}" : null,
        ["publicDisplayName"] = null, ["rankName"] = null, ["rankValue"] = null, ["roleLabels"] = null
    };
    private static JsonObject UnavailableRoster(string reason) => new() {
        ["schemaVersion"] = 1, ["state"] = "unavailable", ["reason"] = reason,
        ["coverage"] = "publicRsiRosterSnapshot", ["order"] = "source", ["query"] = RosterFixture()["query"]!.DeepClone()
    };
    private static JsonObject RosterFixture() => new() {
        ["schemaVersion"] = 1, ["state"] = "available", ["reason"] = null,
        ["coverage"] = "publicRsiRosterSnapshot", ["order"] = "source",
        ["query"] = new JsonObject { ["sid"] = "ASTER", ["query"] = "", ["page"] = 1, ["pageSize"] = 25,
            ["generation"] = null, ["revision"] = null },
        ["snapshot"] = new JsonObject { ["sid"] = "ASTER", ["generation"] = RosterGeneration, ["revision"] = RosterRevision,
            ["freshness"] = "fresh", ["startedAtUtc"] = 1_700_000_000_000L, ["completedAtUtc"] = 1_700_000_001_000L,
            ["firstSourceObservedAtUtc"] = 1_700_000_002_000L, ["lastSourceObservedAtUtc"] = 1_699_999_995_000L,
            ["pagesRead"] = 3, ["counts"] = new JsonObject { ["total"] = 3, ["visible"] = 1, ["redacted"] = 1, ["hidden"] = 1 },
            ["reportedTotalStart"] = 3, ["reportedTotalEnd"] = 3, ["reportedTotalStable"] = true,
            ["countRelation"] = "equal", ["traversalComplete"] = true },
        ["members"] = new JsonArray(
            new JsonObject { ["sourceOrder"] = 0, ["sourceEntryRef"] = "page:1:row:0", ["sourceOrdinalInPage"] = 0,
                ["visibility"] = "visible", ["hasMainClass"] = true, ["handle"] = "Pilot-Wing", ["publicDisplayName"] = "Synthetic Pilot",
                ["rankName"] = "Member", ["rankValue"] = null, ["roleLabels"] = new JsonArray("", "role\nlabel") },
            RosterRow(1, 2, 0, "redacted"), RosterRow(2, 2, 1, "hidden")),
        ["totalCount"] = 3, ["totalPages"] = 1
    };
}
