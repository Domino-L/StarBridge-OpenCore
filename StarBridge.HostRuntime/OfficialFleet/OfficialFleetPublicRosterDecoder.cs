using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.OfficialFleet;

// Public source facts only. Decoding grants no membership, identity linkage or profile authority.
internal static class OfficialFleetPublicRosterDecoder
{
    internal enum ReadState { Available, Unavailable, Invalid }
    internal enum Freshness { Fresh, Stale }
    internal enum Visibility { Visible, Redacted, Hidden }
    internal sealed record Pin(string Generation, string Revision);
    // The caller supplies the already-verified fleet/source pair; JSON cannot create this scope.
    internal sealed record Request(string SourceRef, string Sid, string Search, int PageNumber, int PageSize,
        Pin? SnapshotPin = null);
    internal sealed record Query(string SourceRef, string Search, int PageNumber, int PageSize, Pin? SnapshotPin = null);
    internal sealed record Counts(int Total, int Visible, int Redacted, int Hidden);
    // Preserves the wire's precision (milliseconds for current numeric Jackson output). Never a permission lease.
    internal readonly record struct SourceInstant(long UnixSeconds, int Nanosecond, int QuantumNanoseconds = 1)
        : IComparable<SourceInstant>
    {
        public int CompareTo(SourceInstant other) => UnixSeconds != other.UnixSeconds
            ? UnixSeconds.CompareTo(other.UnixSeconds) : Nanosecond.CompareTo(other.Nanosecond);
    }
    internal sealed record Snapshot(string Sid, Pin Pin, Freshness Freshness, SourceInstant StartedAtUtc,
        SourceInstant CompletedAtUtc, SourceInstant FirstSourceObservedAtUtc, SourceInstant LastSourceObservedAtUtc,
        int PagesRead, Counts Counts, long ReportedTotalStart, long ReportedTotalEnd,
        bool ReportedTotalStable, string CountRelation, bool TraversalComplete);
    internal sealed record Row(int SourceOrder, string SourceEntryRef, int SourceOrdinalInPage,
        Visibility Visibility, bool HasMainClass, string? Handle, string? PublicDisplayName,
        string? RankName, IReadOnlyList<string>? RoleLabels)
    {
        internal int? RankValue => null;
    }
    internal sealed record Page(Request Query, Snapshot Snapshot, IReadOnlyList<Row> Members,
        int TotalCount, int TotalPages);
    internal sealed record Response(ReadState State, Page? Page, string? Reason)
    {
        internal string? StableErrorCode => State switch {
            ReadState.Invalid => AccountBridgeStableErrors.OfficialFleetDataInvalid,
            ReadState.Unavailable => AccountBridgeStableErrors.OfficialFleetReadUnavailable,
            _ => null
        };
    }

    private static readonly string[] UnavailableReasons = ["disabled", "queryBusy", "configurationUnavailable",
        "cacheUnavailable", "queryBudgetExceeded", "expired", "conflict", "corrupt"];
    private const long MaximumSafeInteger = 9_007_199_254_740_991;
    private const long MinimumEpochSecond = -62_167_219_200, MaximumEpochSecondExclusive = 253_402_300_800;

    /// <summary>
    /// Consumes the existing public SCM helper's unwrapped data. HTTP/envelope/byte budgets stay there.
    /// A missing/unavailable/malformed page never becomes an empty roster or a registered-member fallback.
    /// </summary>
    internal static Response Decode(JsonElement data, Request expected)
    {
        try { return DecodeCore(data, Normalize(expected)); }
        catch (AccountBridgeHostException error) when (error.Code == AccountBridgeStableErrors.OfficialFleetDataInvalid)
        { return Invalid(); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException
            or FormatException or OverflowException or ArgumentException)
        { return Invalid(); }
    }

    private static Response DecodeCore(JsonElement data, Request expected)
    {
        Shape(data, ["schemaVersion", "state", "coverage", "order"],
            ["query", "reason", "snapshot", "members", "totalCount", "totalPages"]);
        Require(Integer(data.GetProperty("schemaVersion"), 1, 1) == 1
            && Text(data.GetProperty("coverage"), 64) == "publicRsiRosterSnapshot"
            && Text(data.GetProperty("order"), 16) == "source");
        string state = Text(data.GetProperty("state"), 32);
        if (state == "invalid") {
            // Query.read's internal invalid DTO is not a successful controller response: HTTP maps it to 400.
            Require(NullableText(data, "reason", 64) == "invalidQuery" && Null(data, "query"));
            RequireNoPage(data);
            return new(ReadState.Invalid, null, "invalidQuery");
        }
        ReadEcho(data.GetProperty("query"), expected);
        if (state == "unavailable") {
            string? reason = NullableText(data, "reason", 64);
            Require(reason is not null && UnavailableReasons.Contains(reason, StringComparer.Ordinal));
            RequireNoPage(data);
            return new(ReadState.Unavailable, null, reason);
        }
        Require(state == "available" && Null(data, "reason"));
        Snapshot snapshot = ReadSnapshot(data.GetProperty("snapshot"), expected);
        int total = Integer(data.GetProperty("totalCount"), 0, 100_000);
        int pages = Integer(data.GetProperty("totalPages"), 0, 4_000);
        bool search = expected.Search.Length != 0;
        Require(pages == (total + expected.PageSize - 1) / expected.PageSize
            && (search ? total <= snapshot.Counts.Visible : total == snapshot.Counts.Total));
        JsonElement values = data.GetProperty("members");
        Require(values.ValueKind == JsonValueKind.Array);
        int start = (expected.PageNumber - 1) * expected.PageSize;
        int count = Math.Min(expected.PageSize, Math.Max(0, total - start));
        Require(values.GetArrayLength() == count);
        var rows = new List<Row>(count);
        var references = new HashSet<string>(StringComparer.Ordinal);
        var handles = new HashSet<string>(StringComparer.Ordinal);
        int priorOrder = -1, priorSourcePage = 0, priorOrdinal = -1;
        int visible = 0, hidden = 0, redacted = 0;
        foreach (JsonElement value in values.EnumerateArray()) {
            Row row = ReadRow(value, snapshot, out int sourcePage);
            Require(references.Add(row.SourceEntryRef) && row.SourceOrder > priorOrder
                && sourcePage >= priorSourcePage && (!search || row.Visibility == Visibility.Visible));
            if (!search) Require(row.SourceOrder == start + rows.Count);
            if (sourcePage == priorSourcePage)
                Require(row.SourceOrder - priorOrder == row.SourceOrdinalInPage - priorOrdinal);
            if (row.Visibility == Visibility.Visible) { Require(handles.Add(row.Handle!)); visible++; }
            else if (row.Visibility == Visibility.Hidden) hidden++;
            else redacted++;
            priorOrder = row.SourceOrder; priorSourcePage = sourcePage; priorOrdinal = row.SourceOrdinalInPage;
            rows.Add(row);
        }
        Require(visible <= snapshot.Counts.Visible && hidden <= snapshot.Counts.Hidden
            && redacted <= snapshot.Counts.Redacted);
        return new(ReadState.Available, new(expected, snapshot, rows.AsReadOnly(), total, pages), null);
    }

    private static Request Normalize(Request expected)
    {
        if (expected is null) throw OfficialFleetReadModel.Invalid();
        Require(Match(expected.Sid, @"\A[A-Z0-9-]{2,32}\z"));
        Query query = ValidateQuery(new(expected.SourceRef, expected.Search, expected.PageNumber,
            expected.PageSize, expected.SnapshotPin));
        return expected with { Search = query.Search };
    }

    // Shared preflight has no invented SID, IO or authority. Bind uses the actual bootstrap SID afterwards.
    internal static Query ValidateQuery(Query query)
    {
        if (query is null) throw OfficialFleetReadModel.Invalid();
        Require(Match(query.SourceRef, @"\AofficialFleet:[1-9][0-9]{0,18}\z")
            && long.TryParse(query.SourceRef[14..], NumberStyles.None, CultureInfo.InvariantCulture, out _)
            && query.Search is not null && query.Search.Length <= 128 && !SourceControl(query.Search)
            && query.PageNumber is >= 1 and <= 4_000 && query.PageSize is 25 or 50 or 100);
        if (query.SnapshotPin is { } pin) Require(Hex(pin.Generation, 32) && Hex(pin.Revision, 64));
        // Java String.trim: admission already rejects every <=U+001F character; only U+0020 remains.
        return query with { Search = query.Search.Trim(' ') };
    }

    internal static Request Bind(Query query, string sid) => Normalize(new(query.SourceRef, sid,
        query.Search, query.PageNumber, query.PageSize, query.SnapshotPin));

    private static void ReadEcho(JsonElement echo, Request expected)
    {
        Shape(echo, ["sid", "query", "page", "pageSize"], ["generation", "revision"]);
        string? generation = NullableText(echo, "generation", 32), revision = NullableText(echo, "revision", 64);
        Require(Text(echo.GetProperty("sid"), 32) == expected.Sid
            && SearchText(echo.GetProperty("query")) == expected.Search
            && Integer(echo.GetProperty("page"), 1, 4_000) == expected.PageNumber
            && Integer(echo.GetProperty("pageSize"), 25, 100) == expected.PageSize
            && (generation is null) == (revision is null));
        if (expected.SnapshotPin is { } pin) Require(generation == pin.Generation && revision == pin.Revision);
        else Require(generation is null && revision is null);
    }

    private static Snapshot ReadSnapshot(JsonElement value, Request expected)
    {
        Shape(value, ["sid", "generation", "revision", "freshness", "startedAtUtc", "completedAtUtc",
            "firstSourceObservedAtUtc", "lastSourceObservedAtUtc", "pagesRead", "counts", "reportedTotalStart",
            "reportedTotalEnd", "reportedTotalStable", "countRelation", "traversalComplete"]);
        string sid = Text(value.GetProperty("sid"), 32), generation = Text(value.GetProperty("generation"), 32);
        string revision = Text(value.GetProperty("revision"), 64), freshness = Text(value.GetProperty("freshness"), 16);
        Require(sid == expected.Sid && Hex(generation, 32) && Hex(revision, 64));
        var pin = new Pin(generation, revision);
        if (expected.SnapshotPin is not null) Require(pin == expected.SnapshotPin);
        Require(freshness is "fresh" or "stale");
        SourceInstant started = Instant(value.GetProperty("startedAtUtc")), completed = Instant(value.GetProperty("completedAtUtc"));
        SourceInstant first = Instant(value.GetProperty("firstSourceObservedAtUtc")), last = Instant(value.GetProperty("lastSourceObservedAtUtc"));
        // Millisecond output loses sub-ms writer precision. Validate possible source intervals;
        // a quantized boundary is not evidence that the writer exceeded its strict four-hour limit.
        decimal difference = ((decimal)completed.UnixSeconds - started.UnixSeconds) * 1_000_000_000
            + completed.Nanosecond - started.Nanosecond;
        Require(difference + completed.QuantumNanoseconds - 1 >= 0
            && difference - (started.QuantumNanoseconds - 1) < 14_400_000_000_000m);
        int pages = Integer(value.GetProperty("pagesRead"), 1, 100_000);
        JsonElement count = value.GetProperty("counts"); Shape(count, ["total", "visible", "redacted", "hidden"]);
        var counts = new Counts(Integer(count.GetProperty("total"), 0, 100_000), Integer(count.GetProperty("visible"), 0, 100_000),
            Integer(count.GetProperty("redacted"), 0, 100_000), Integer(count.GetProperty("hidden"), 0, 100_000));
        long reportedStart = Long(value.GetProperty("reportedTotalStart"), 0, MaximumSafeInteger);
        long reportedEnd = Long(value.GetProperty("reportedTotalEnd"), 0, MaximumSafeInteger);
        bool stable = Boolean(value.GetProperty("reportedTotalStable")), traversal = Boolean(value.GetProperty("traversalComplete"));
        string relation = Text(value.GetProperty("countRelation"), 32);
        // Only COMPLETE is queryable. PARTIAL manifests are never an available page.
        Require((long)counts.Visible + counts.Redacted + counts.Hidden == counts.Total
            && counts.Total >= pages - 1 && counts.Total <= 32L * (pages - 1)
            && stable && reportedStart == reportedEnd && reportedEnd == counts.Total && relation == "equal" && traversal);
        // Source observation clocks are independent. Builder does not impose first<=last or source<=completed.
        return new(sid, pin, freshness == "fresh" ? Freshness.Fresh : Freshness.Stale,
            started, completed, first, last, pages, counts, reportedStart, reportedEnd, stable, relation, traversal);
    }

    private static Row ReadRow(JsonElement value, Snapshot snapshot, out int sourcePage)
    {
        Shape(value, ["sourceOrder", "sourceEntryRef", "sourceOrdinalInPage", "visibility", "hasMainClass"],
            ["handle", "publicDisplayName", "rankName", "rankValue", "roleLabels"]);
        int order = Integer(value.GetProperty("sourceOrder"), 0, 99_999);
        int ordinal = Integer(value.GetProperty("sourceOrdinalInPage"), 0, 31);
        string reference = Text(value.GetProperty("sourceEntryRef"), 64), visibility = Text(value.GetProperty("visibility"), 16);
        Match match = Regex.Match(reference, @"\Apage:([1-9][0-9]{0,5}):row:([0-9]|[12][0-9]|3[01])\z", RegexOptions.CultureInvariant);
        Require(match.Success && int.Parse(match.Groups[2].Value, CultureInfo.InvariantCulture) == ordinal);
        sourcePage = int.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture);
        Require(order < snapshot.Counts.Total && sourcePage < snapshot.PagesRead
            && order >= sourcePage - 1 + ordinal && order <= 32L * (sourcePage - 1) + ordinal
            && (visibility is "visible" or "redacted" or "hidden") && Null(value, "rankValue"));
        bool main = Boolean(value.GetProperty("hasMainClass"));
        string? handle = NullableText(value, "handle", 256), name = NullableText(value, "publicDisplayName", 256);
        string? rank = NullableText(value, "rankName", 256);
        IReadOnlyList<string>? roles = null;
        if (!Null(value, "roleLabels")) {
            JsonElement labels = value.GetProperty("roleLabels");
            Require(labels.ValueKind == JsonValueKind.Array && labels.GetArrayLength() is >= 1 and <= 16);
            var selected = new List<string>();
            foreach (JsonElement label in labels.EnumerateArray()) {
                // Matches Query.row exactly: role labels have a length bound, not identity-text semantics.
                Require(label.ValueKind == JsonValueKind.String && label.GetString()!.Length <= 256);
                selected.Add(label.GetString()!);
            }
            roles = selected.AsReadOnly();
        }
        Require(visibility == "visible" ? handle is not null : handle is null && name is null && rank is null && roles is null);
        return new(order, reference, ordinal, visibility == "visible" ? Visibility.Visible
            : visibility == "hidden" ? Visibility.Hidden : Visibility.Redacted, main, handle, name, rank, roles);
    }

    private static SourceInstant Instant(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Number) {
            // Canonical Jackson enables timestamps and DISABLES timestamp nanoseconds: epoch milliseconds.
            // No magnitude-based seconds/milliseconds guessing or floating-point rounding.
            long millis = Long(value, MinimumEpochSecond * 1_000, MaximumEpochSecondExclusive * 1_000 - 1);
            long seconds = Math.DivRem(millis, 1_000, out long remainder);
            if (remainder < 0) { seconds--; remainder += 1_000; }
            return new(seconds, (int)remainder * 1_000_000, 1_000_000);
        }
        string text = Text(value, 40);
        Match iso = Regex.Match(text, @"\A([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,9}))?(?:Z|\+00:00)\z", RegexOptions.CultureInvariant);
        Require(iso.Success);
        int Part(int index) => int.Parse(iso.Groups[index].Value, CultureInfo.InvariantCulture);
        int year = Part(1), month = Part(2), day = Part(3), hour = Part(4), minute = Part(5), second = Part(6);
        bool leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
        int[] days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        Require(month is >= 1 and <= 12 && day >= 1 && day <= days[month - 1] && hour < 24 && minute < 60 && second < 60);
        long date = 365L * year + (year + 3) / 4 - (year + 99) / 100 + (year + 399) / 400 - 719_528;
        for (int i = 0; i < month - 1; i++) date += days[i];
        long epoch = (date + day - 1) * 86_400 + hour * 3_600 + minute * 60 + second;
        Require(epoch >= MinimumEpochSecond && epoch < MaximumEpochSecondExclusive);
        int nanosecond = iso.Groups[7].Success ? int.Parse(iso.Groups[7].Value.PadRight(9, '0'), CultureInfo.InvariantCulture) : 0;
        return new(epoch, nanosecond);
    }

    private static void Shape(JsonElement value, string[] required, string[]? optional = null)
    {
        Require(value.ValueKind == JsonValueKind.Object);
        var names = new HashSet<string>(StringComparer.Ordinal);
        foreach (JsonProperty property in value.EnumerateObject())
            Require(names.Add(property.Name) && (required.Contains(property.Name, StringComparer.Ordinal)
                || optional?.Contains(property.Name, StringComparer.Ordinal) == true));
        Require(required.All(names.Contains));
    }
    private static bool Null(JsonElement value, string name) => !value.TryGetProperty(name, out JsonElement field)
        || field.ValueKind == JsonValueKind.Null;
    private static void RequireNoPage(JsonElement value) => Require(Null(value, "snapshot") && Null(value, "members")
        && Null(value, "totalCount") && Null(value, "totalPages"));
    private static string? NullableText(JsonElement value, string name, int max) => Null(value, name) ? null : Text(value.GetProperty(name), max);
    private static string Text(JsonElement value, int max)
    {
        Require(value.ValueKind == JsonValueKind.String);
        string text = value.GetString()!; Require(text.Length is > 0 && text.Length <= max && !SourceControl(text)); return text;
    }
    private static string SearchText(JsonElement value)
    {
        Require(value.ValueKind == JsonValueKind.String);
        string text = value.GetString()!; Require(text.Length <= 128 && !SourceControl(text)); return text;
    }
    private static bool SourceControl(string value) => value.Any(c => c < 32 || c == 127);
    private static bool Boolean(JsonElement value)
    {
        Require(value.ValueKind is JsonValueKind.True or JsonValueKind.False); return value.GetBoolean();
    }
    private static int Integer(JsonElement value, int min, int max) => checked((int)Long(value, min, max));
    private static long Long(JsonElement value, long min, long max)
    {
        Require(value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out _));
        long result = value.GetInt64(); Require(result >= min && result <= max); return result;
    }
    private static bool Hex(string? value, int count) => value is not null && value.Length == count
        && value.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');
    private static bool Match(string? value, string expression) => value is not null && Regex.IsMatch(value, expression, RegexOptions.CultureInvariant);
    private static Response Invalid() => new(ReadState.Invalid, null, null);
    private static void Require([System.Diagnostics.CodeAnalysis.DoesNotReturnIf(false)] bool value) { if (!value) throw OfficialFleetReadModel.Invalid(); }
}
