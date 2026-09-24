using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // No cached authority: every continuation/detail read rebuilds a coherent authorized snapshot.
    // Server filtering/sorting remains authoritative; only WPF's local text predicate is added.
    private async Task<JsonElement> ReadLoanerSearchPage(string bearer, string code, ShipQuery query,
        int requestedOffset, string? expected, Action current, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(30));
        var remote = query with { Text = "" };
        var offset = 0;
        string? revision = null;
        int? total = null, filtered = null;
        var bytes = 0;
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var matches = new List<JsonElement>();
        using var digest = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        void Hash(string value) => digest.AppendData(Encoding.UTF8.GetBytes(value + "\n"));
        Hash("loaner-search-v1"); Hash(code); Hash(JsonSerializer.Serialize(query.View));
        try
        {
            while (true)
            {
                current(); deadline.Token.ThrowIfCancellationRequested();
                var path = "/api/fleets/ships?code=" + Uri.EscapeDataString(code)
                    + "&offset=" + offset.ToString(CultureInfo.InvariantCulture)
                    + (revision is null ? "" : "&revision=" + revision) + remote.Url;
                var page = await WorkspaceJson(bearer, path, deadline.Token, 400 * 1024);
                current(); deadline.Token.ThrowIfCancellationRequested();
                ShipObject(page);
                if (!page.TryGetProperty("queryVersion", out var version) || version.GetInt32() != 2)
                    throw new AccountBridgeHostException("communities.upgradeRequired");
                var actualRevision = Text(page, "revision", 64);
                var actualTotal = Number(page, "totalCount", 0, 1000000);
                var actualFiltered = Number(page, "matchedCount", 0, actualTotal);
                if (!ShipHash(actualRevision) || Number(page, "schemaVersion", 1, 1) != 1 ||
                    Text(page, "code", 256) != code || ParseShipQuery(page.GetProperty("query")) != remote ||
                    Number(page, "offset", 0, 1000000) != offset) throw Invalid();
                if (revision is not null && (actualRevision != revision || actualTotal != total || actualFiltered != filtered))
                    throw new AccountBridgeHostException("communities.shipsChanged");
                revision = actualRevision; total = actualTotal; filtered = actualFiltered;
                var rows = Rows(page, "ships", 20);
                var next = page.GetProperty("next").ValueKind == JsonValueKind.Null ? (int?)null : Number(page, "next", 0, actualFiltered);
                if (offset > filtered || rows.Length != Math.Min(20, actualFiltered - offset) ||
                    next != (offset + rows.Length < filtered ? offset + rows.Length : null)) throw Invalid();
                bytes += Encoding.UTF8.GetByteCount(page.GetRawText());
                if (actualFiltered > 10000 || bytes > 8 * 1024 * 1024)
                    throw new AccountBridgeHostException("communities.unavailable", true);
                Hash(revision);
                foreach (var row in rows)
                {
                    deadline.Token.ThrowIfCancellationRequested();
                    ShipObject(row);
                    var id = Text(row, "id", 64);
                    if (!ShipHash(id) || !seen.Add(id)) throw Invalid();
                    var sourceCode = Text(row, "code", 256);
                    if (sourceCode.Length == 0) throw Invalid();
                    foreach (var field in new[] { "displayName", "ownerCallsign", "ownerGameName" }) Text(row, field, 512);
                    foreach (var field in new[] { "catalogSpec", "catalogRole", "catalogStatus", "catalogPriceUsd" }) Optional(row, field, 512);
                    var loaners = JsonSerializer.SerializeToElement(_shipLoaners(sourceCode,
                        Optional(row, "catalogStatus", 256), query.Culture));
                    Hash(loaners.GetRawText());
                    if (MatchesShipSearch(row, loaners, query.Text)) matches.Add(row.Clone());
                }
                if (next is null) break;
                offset = next.Value;
            }
            var projectedRevision = Convert.ToHexString(digest.GetHashAndReset()).ToLowerInvariant();
            if (expected is not null && projectedRevision != expected)
                throw new AccountBridgeHostException("communities.shipsChanged");
            if (requestedOffset > matches.Count) throw new AccountBridgeHostException("communities.shipsChanged");
            current(); deadline.Token.ThrowIfCancellationRequested();
            var selected = matches.Skip(requestedOffset).Take(20).ToArray();
            return JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, queryVersion = 2, code, query = query.View,
                revision = projectedRevision, offset = requestedOffset,
                next = requestedOffset + selected.Length < matches.Count ? (int?)(requestedOffset + selected.Length) : null,
                totalCount = total, matchedCount = matches.Count, ships = selected
            });
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        { throw new AccountBridgeHostException("communities.unavailable", true); }
    }

    internal static bool MatchesShipSearch(JsonElement source, JsonElement loaners, string query)
    {
        // Explicit public-field whitelist: never search instance IDs, account IDs or hidden fields.
        bool Match(JsonElement row, params string[] fields) => fields.Any(field =>
            row.TryGetProperty(field, out var value) && value.ValueKind == JsonValueKind.String &&
            (value.GetString() ?? "").Contains(query, StringComparison.OrdinalIgnoreCase));
        if (Match(source, "code", "displayName", "ownerCallsign", "ownerGameName", "catalogSpec", "catalogRole",
            "catalogStatus", "catalogPriceUsd")) return true;
        if (loaners.ValueKind != JsonValueKind.Array) return false;
        return loaners.EnumerateArray().Any(row => Match(row, "code", "displayName", "catalogSpec",
            "catalogRole", "catalogStatus", "catalogPriceUsd") || LoanerLabels(row).Any(label =>
                label.Contains(query, StringComparison.OrdinalIgnoreCase)));
    }

    private static IEnumerable<string> LoanerLabels(JsonElement row)
    {
        foreach (var field in new[] { "catalogSpec", "catalogRole", "catalogStatus" })
        {
            if (!row.TryGetProperty(field, out var value) || value.ValueKind != JsonValueKind.String) continue;
            yield return value.GetString()?.ToLowerInvariant() switch {
                "capital" => "旗舰级 旗艦級", "large" => "大型", "medium" => "中型", "small" => "小型",
                "flyable" => "可飞 可飛", "concept" => "概念", "combat" => "战斗 戰鬥",
                "transport" => "运输 運輸", "industrial" => "工业 工業",
                "exploration" => "探索", "support" => "支援", "utility" => "其他", _ => ""
            };
        }
        if (row.TryGetProperty("catalogPriceUsd", out var price) && price.ValueKind == JsonValueKind.String &&
            decimal.TryParse(price.GetString(), NumberStyles.Number, CultureInfo.InvariantCulture, out var amount) && amount >= 0)
        {
            yield return "$" + price.GetString();
            yield return "$" + amount.ToString("#,0.##", CultureInfo.InvariantCulture);
        }
    }
}
