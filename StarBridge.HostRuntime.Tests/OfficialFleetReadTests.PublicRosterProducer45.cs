using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using Roster = StarBridge.HostRuntime.OfficialFleet.OfficialFleetPublicRosterDecoder;

internal static partial class OfficialFleetReadTests
{
    private const string Producer45RootVariable = "STARBRIDGE_ROSTER_PRODUCER45_ROOT";
    private const string Producer45ManifestSha = "a951c86d073b955b1c3ebdfb707fd53e50c875b5f0f6655741c1d3eeeafcb40d";
    private static readonly (string File, string Sha, int Length)[] Producer45Pins = [
        ("manifest.json", "a951c86d073b955b1c3ebdfb707fd53e50c875b5f0f6655741c1d3eeeafcb40d", 3652),
        ("production-mapper-probe.json", "fd178e36a1375273043a79c607f27a67b8eb06c42926ad91eaefe4641059ae60", 116),
        ("mixed-visible-redacted-hidden.json", "999feb2e132d8e9ad3e13c16114bff0cef98351e7d2ac846913575f975db6b05", 16418),
        ("pinned-page-three.json", "91795f1c2af04aceedff516f60a654950a54066d57a62368e8018bdc24e3969d", 4323),
        ("search-no-match.json", "ea95f88f759f718893ab69f02c9f7f2f4780fb7bc97036aaae17f846dbaa0f13", 889),
        ("complete-empty-roster.json", "4e6a3479953d1cef4dc06b9f4a63a92e377acea40ea2e694b992a18a79f4f9c1", 782),
        ("stale-complete.json", "a507ea68735d3457d01273cb052ca37566de5f0b86a10413d0085442696a71fe", 16510),
        ("cache-unavailable.json", "9ea0790f1c11be974590681d80a133e9c7a843fc2db34b194a40d179e7343c01", 312),
        ("read-disabled.json", "b47c5a2419ab0deb62729305aac16ffbe0affb9497045c57f89535d71297e709", 303),
    ];

    // Optional in the original general Run. The dedicated interoperability plan requires
    // this environment variable and all seven PASS lines; an absent fixture is never evidence.
    private static async Task RunPublicRosterProducer45Async()
    {
        string? root = Environment.GetEnvironmentVariable(Producer45RootVariable);
        if (string.IsNullOrEmpty(root))
        {
            Console.WriteLine("SKIP actual producer45 roster interoperability: explicit frozen fixture root required");
            return;
        }
        Dictionary<string, byte[]> bytes = ReadProducer45Bytes(root);
        using JsonDocument manifest = JsonDocument.Parse(bytes["manifest.json"]);
        JsonElement metadata = manifest.RootElement;
        Require(metadata.GetProperty("schemaVersion").GetInt32() == 1 && metadata.GetProperty("fixture").GetString() == "45"
            && metadata.GetProperty("syntheticData").GetBoolean() && !metadata.GetProperty("responseBodyBytesWereParsedAndReserialized").GetBoolean()
            && metadata.GetProperty("testMethod").GetString() == "exportProductionJacksonRosterControllerEnvelopes",
            "Only the frozen actual-controller synthetic export is accepted, without rewriting response bytes");
        using (JsonDocument probe = JsonDocument.Parse(bytes["production-mapper-probe.json"]))
        {
            JsonElement value = probe.RootElement;
            Require(value.EnumerateObject().Count() == 5 && value.GetProperty("safeLong").GetInt64() == 42
                && value.GetProperty("largeLong").GetString() == "9007199254740993"
                && value.GetProperty("instant").GetInt64() == 1700000000123
                && value.GetProperty("localDateTime").GetInt64() == 1699970400000
                && value.GetProperty("nullable").ValueKind == JsonValueKind.Null,
                "The pinned real Boot/Yudao mapper probe preserves numeric milliseconds, Long string policy and explicit null");
        }
        JsonElement[] exports = metadata.GetProperty("exports").EnumerateArray().ToArray();
        Require(exports.Length == 7 && exports.Select(row => row.GetProperty("file").GetString()).Distinct().Count() == 7,
            "Every frozen producer scenario has exactly one manifest row");
        Roster.Pin? mixedPin = null;
        foreach (JsonElement exported in exports)
        {
            string file = exported.GetProperty("file").GetString()!;
            Require(Producer45Pins.Any(pin => pin.File == file) && file is not ("manifest.json" or "production-mapper-probe.json")
                && exported.GetProperty("method").GetString() == "GET" && exported.GetProperty("httpStatus").GetInt32() == 200,
                "The original seven producer envelopes are successful HTTP GET responses, including typed unavailable");
            var target = new Uri("http://producer-fixture.invalid" + exported.GetProperty("requestTarget").GetString());
            Require(target.AbsolutePath == "/member/organization/roster/page", "Producer target is the existing public roster route");
            Dictionary<string, string> query = PublicRosterParameters(target);
            Require(query.Keys.All(key => key is "sid" or "query" or "page" or "pageSize" or "generation" or "revision")
                && query.ContainsKey("sid") && query.ContainsKey("page") && query.ContainsKey("pageSize")
                && query.ContainsKey("generation") == query.ContainsKey("revision"), "Typed request comes only from the pinned producer query");
            int page = int.Parse(query["page"], CultureInfo.InvariantCulture), size = int.Parse(query["pageSize"], CultureInfo.InvariantCulture);
            string search = query.GetValueOrDefault("query") ?? "";
            string? generation = query.GetValueOrDefault("generation"), revision = query.GetValueOrDefault("revision");
            if (generation is not null)
                Require(generation == metadata.GetProperty("snapshotGeneration").GetString()
                    && revision == metadata.GetProperty("snapshotRevision").GetString(), "Every producer continuation pins both original snapshot fields");
            byte[] body = bytes[file];
            using var handler = new RosterHttpHandler { Sid = query["sid"], RawBody = uri => {
                Dictionary<string, string> actual = PublicRosterParameters(uri);
                var expected = new Dictionary<string, string>(query, StringComparer.Ordinal) { ["query"] = search };
                Require(actual.Count == expected.Count && expected.All(pair => actual.TryGetValue(pair.Key, out string? value) && value == pair.Value),
                    "Host sends exactly the producer query including empty search, both pin fields and page size");
                return body; // ByteArrayContent receives the untouched accepted response body.
            } };
            var vault = new RosterMemoryVault();
            using var host = PublicRosterHost(handler, vault);
            Roster.Response result = await host.ReadOfficialFleetPublicRosterAsync(host.CurrentContext!,
                PublicRosterPayload(search: search, page: page, generation: generation, revision: revision, pageSize: size), default);
            Require(handler.BootstrapReads == 1 && handler.PublicReads == 1 && vault.Writes == 0,
                "Actual Host/OAuth helper/decoder uses one synthetic bootstrap plus one raw public response, without G1 or writes");
            string expectedState = exported.GetProperty("expectedState").GetString()!;
            if (expectedState == "unavailable")
            {
                Require(result.State == Roster.ReadState.Unavailable && result.Page is null
                    && result.Reason == exported.GetProperty("expectedReason").GetString()
                    && result.Reason == (file == "cache-unavailable.json" ? "cacheUnavailable" : "disabled"),
                    "Actual producer unavailable remains typed and cannot become an empty roster");
            }
            else
            {
                Require(expectedState == "available" && result.State == Roster.ReadState.Available && result.Page is not null && result.Reason is null,
                    "An actual available producer envelope must survive the existing bounded helper and strict decoder");
                Roster.Page decoded = result.Page!;
                Require(decoded.Query.Sid == query["sid"] && decoded.Query.Search == search && decoded.Query.PageNumber == page
                    && decoded.Query.PageSize == size && decoded.TotalCount == exported.GetProperty("expectedTotal").GetInt32()
                    && decoded.Members.Count == exported.GetProperty("expectedRows").GetInt32()
                    && decoded.Snapshot.Freshness == (exported.GetProperty("expectedFreshness").GetString() == "stale" ? Roster.Freshness.Stale : Roster.Freshness.Fresh),
                    "Real response query, totals, rows and fresh/stale fact retain the producer contract");
                using JsonDocument rawBody = JsonDocument.Parse(body);
                JsonElement snapshot = rawBody.RootElement.GetProperty("data").GetProperty("snapshot");
                Producer45Millis(snapshot.GetProperty("startedAtUtc"), decoded.Snapshot.StartedAtUtc);
                Producer45Millis(snapshot.GetProperty("completedAtUtc"), decoded.Snapshot.CompletedAtUtc);
                Producer45Millis(snapshot.GetProperty("firstSourceObservedAtUtc"), decoded.Snapshot.FirstSourceObservedAtUtc);
                Producer45Millis(snapshot.GetProperty("lastSourceObservedAtUtc"), decoded.Snapshot.LastSourceObservedAtUtc);
                Require(decoded.Members.Where(row => row.Visibility != Roster.Visibility.Visible).All(row => row.Handle is null
                    && row.PublicDisplayName is null && row.RankName is null && row.RoleLabels is null && row.RankValue is null),
                    "Redacted/hidden public facts never gain identity or an invented rank");
                switch (file)
                {
                    case "mixed-visible-redacted-hidden.json":
                        Require(decoded.Snapshot.Counts == new Roster.Counts(64, 62, 1, 1) && decoded.Members.Count == 64
                            && decoded.Members.Count(row => row.Visibility == Roster.Visibility.Visible) == 62
                            && decoded.Members.Count(row => row.Visibility == Roster.Visibility.Redacted) == 1
                            && decoded.Members.Count(row => row.Visibility == Roster.Visibility.Hidden) == 1,
                            "Actual mixed64 retains 62 visible plus one redacted and one hidden public placeholder");
                        mixedPin = decoded.Snapshot.Pin;
                        Require(mixedPin.Generation == metadata.GetProperty("snapshotGeneration").GetString()
                            && mixedPin.Revision == metadata.GetProperty("snapshotRevision").GetString(), "First actual page supplies the producer snapshot pin");
                        break;
                    case "pinned-page-three.json":
                        Require(mixedPin is not null && decoded.Snapshot.Pin == mixedPin && decoded.Query.SnapshotPin == mixedPin
                            && decoded.Members.Select(row => row.SourceOrder).SequenceEqual(Enumerable.Range(50, 14)),
                            "Pinned page3 keeps the original revision and exact source positions50..63");
                        break;
                    case "search-no-match.json":
                        Require(decoded.Snapshot.Pin == mixedPin && decoded.TotalCount == 0 && decoded.TotalPages == 0
                            && decoded.Snapshot.Counts.Total == 64, "No-match search does not erase the complete64 source roster");
                        break;
                    case "complete-empty-roster.json":
                        Require(decoded.TotalCount == 0 && decoded.TotalPages == 0 && decoded.Snapshot.Counts == new Roster.Counts(0, 0, 0, 0)
                            && decoded.Snapshot.TraversalComplete, "True completed empty snapshot remains distinct from no-match and unavailable");
                        break;
                    case "stale-complete.json":
                        Require(decoded.Snapshot.Pin == mixedPin && decoded.Snapshot.Freshness == Roster.Freshness.Stale && decoded.Members.Count == 64,
                            "Actual stale public snapshot stays stale, without renewing a permission or identity deadline");
                        break;
                    default:
                        throw new InvalidOperationException("Unexpected available producer scenario");
                }
            }
            Require(Convert.ToHexString(SHA256.HashData(body)).ToLowerInvariant() == exported.GetProperty("sha256").GetString(),
                "No raw producer response was mutated while passing through the helper");
            Console.WriteLine("PASS actual producer45 Host roster interoperability " + file);
        }
        Require(ReadProducer45Bytes(root).All(pair => bytes[pair.Key].SequenceEqual(pair.Value)), "All nine frozen files remain unchanged after consumption");
        Console.WriteLine("PASS actual producer45 original7 bodies plus production mapper probe and manifest integrity");
    }

    private static Dictionary<string, byte[]> ReadProducer45Bytes(string root)
    {
        var result = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (var pin in Producer45Pins)
        {
            byte[] body = File.ReadAllBytes(Path.Combine(root, pin.File));
            Require(body.Length == pin.Length && Convert.ToHexString(SHA256.HashData(body)).ToLowerInvariant() == pin.Sha,
                "Declared producer45 fixture file must equal its accepted original bytes");
            result.Add(pin.File, body);
        }
        Require(Producer45Pins.Single(pin => pin.File == "manifest.json").Sha == Producer45ManifestSha,
            "Producer manifest uses its independently accepted pin");
        return result;
    }

    private static void Producer45Millis(JsonElement original, Roster.SourceInstant decoded)
    {
        Require(original.ValueKind == JsonValueKind.Number, "Production Jackson timestamps are numeric milliseconds");
        long value = original.GetInt64();
        Require(value >= 0 && decoded.UnixSeconds == value / 1000 && decoded.Nanosecond == value % 1000 * 1_000_000
            && decoded.QuantumNanoseconds == 1_000_000, "Decoder preserves exact original millisecond instant and source precision");
    }
}
