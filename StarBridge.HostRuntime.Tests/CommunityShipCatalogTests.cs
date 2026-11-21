using System.Text.Json;
using StarBridge.Core.Ships;
using StarBridge.HostRuntime.Communities;

namespace StarBridge.HostRuntime.Tests;
internal static class CommunityShipCatalogTests
{
    internal static void Verify()
    {
        var names = new ShipPresentation("测试舰船", "測試艦船", null, EnglishName: "Test Ship");
        Check(CommunityShipCatalog.DisplayName(names, "original", "zh-CN") == "测试舰船" &&
            CommunityShipCatalog.DisplayName(names, "original", "zh-TW") == "測試艦船" &&
            CommunityShipCatalog.DisplayName(names, "original", "en-US") == "Test Ship" &&
            CommunityShipCatalog.DisplayName(null, "Unlisted Variant", "zh-CN") == "Unlisted Variant",
            "Organization names follow language and keep unknown variants unchanged");
        var bundled = StarBridge.HostRuntime.Hangar.HangarShipNames.Resource("StarBridge.ShipLoanerMatrix.tsv");
        if (bundled is not null) Check(new ShipLoanerCatalog(bundled).Available, "existing private WPF matrix is recognized including comment header");
        var matrix = new ShipLoanerCatalog("源英文飞船名\t中文\t规格\t替代\t规则\t标签\n" +
            "Source Test\t测试\t大型\tArgo Replacement Test\tOnlyWhenSourceIsConcept\t\n");
        ShipPresentation Lookup(string value) => value switch {
            "source-code" => new("源船", "源船", null, EnglishName: "Source Test"),
            "Replacement Test" => new("替代测试", "替代測試", null, Category: "transport",
                SizeClass: "large", DeliveryStatus: "flyable", PriceUsd: 100, EnglishName: "Replacement Test"),
            _ => new(null, null, null)
        };
        var rows = CommunityShipCatalog.Loaners("source-code", "Concept", "zh-TW", matrix, Lookup)!;
        var json = JsonSerializer.SerializeToElement(rows);
        Check(json.GetArrayLength() == 1 && json[0].GetProperty("displayName").GetString() == "替代測試", "local matrix and exact catalog alias");
        Check(json[0].GetProperty("catalogStatus").GetString() == "flyable", "catalog status not invented");
        Check(!json[0].TryGetProperty("ownerMemberRef", out _) && !json[0].TryGetProperty("shipRef", out _), "no synthetic owned instance or authority");
        Check(CommunityShipCatalog.Loaners("source-code", "Flyable", "en-US", matrix, Lookup)!.Length == 0, "flyable source hides concept-only loaners");
        Check(CommunityShipCatalog.Loaners("source-code", "Concept", "en-US", new(null), Lookup) is null, "missing optional matrix is unknown");
        Check(CommunityShipCatalog.Loaners("unknown", "Concept", "en-US", matrix, Lookup) is null, "unknown source is not guessed");
        foreach (var development in new[] { "开发中", "開發中", "In Development", "in-production" })
            Check(CommunityShipCatalog.Loaners("source-code", development, "en-US", matrix, Lookup)!.Length == 1,
                "in-development counts as concept: " + development);
        Check(CommunityShipCatalog.Loaners("source-code", "可飞", "zh-CN", matrix, Lookup)!.Length == 0, "flight-ready source never shows loaners");
        BundledMatrixMatchesCatalog();
    }

    // 2026-11-05: the bundled matrix may only name ships the RSI Ship Matrix still lists as
    // in-concept (the catalog's 官网状态), and every loaner must resolve to a catalog model.
    private static void BundledMatrixMatchesCatalog()
    {
        var data = Path.Combine(HostTestSource.Root, "StarBridge.Desktop", "Data");
        string catalog;
        string matrixBody;
        try
        {
            catalog = RestrictedSamples.ReadFile(Path.Combine(data, "ship-catalog.tsv"), "ship-catalog.tsv");
            matrixBody = RestrictedSamples.ReadFile(Path.Combine(data, "ship-loaner-matrix.tsv"), "ship-loaner-matrix.tsv");
        }
        catch (RestrictedSampleAbsentException error)
        {
            error.Report("community ship loaner matrix comparison");
            return;
        }

        var catalogRows = catalog.Split('\n').Select(line => line.TrimEnd('\r'))
            .Where(line => !string.IsNullOrWhiteSpace(line) && !line.StartsWith('#'))
            .Select(line => line.Split('\t')).ToArray();
        var header = catalogRows[0];
        int nameColumn = Array.IndexOf(header, "英文飞船名"), statusColumn = Array.IndexOf(header, "官网状态");
        Check(nameColumn >= 0 && statusColumn >= 0, "catalog header has name and status");
        var status = catalogRows.Skip(1).Where(row => row.Length > Math.Max(nameColumn, statusColumn))
            .GroupBy(row => row[nameColumn].Trim(), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First()[statusColumn].Trim(), StringComparer.OrdinalIgnoreCase);
        var tsv = matrixBody;
        var matrix = new ShipLoanerCatalog(tsv);
        Check(matrix.Available, "bundled matrix is recognized");
        var rows = tsv.Split('\n').Where(line => !string.IsNullOrWhiteSpace(line) && !line.StartsWith('#') &&
            !line.StartsWith("源英文飞船名", StringComparison.Ordinal)).Select(line => line.TrimEnd('\r').Split('\t')).ToArray();
        Check(rows.Length > 0 && rows.All(row => row.Length >= 4), "bundled matrix rows are complete");
        foreach (var row in rows)
        {
            Check(status.TryGetValue(row[0].Trim(), out var value) && value is "概念" or "开发中",
                "loaner source is still concept in the catalog: " + row[0]);
            Check(ShipLoanerCatalog.FindLoanerCatalog(row[3].Trim(), candidate => status.ContainsKey(candidate) ? candidate : null) is not null,
                "loaner resolves to a catalog model: " + row[3]);
        }
        string[] Loaners(string source) => matrix.FindForConceptSource(source).Select(entry => entry.LoanerEnglishName).Order().ToArray();
        Check(Loaners("Kraken").SequenceEqual(["Drake Buccaneer", "Drake Ironclad Assault", "RSI Polaris"]), "Kraken has the three official loaners");
        Check(Loaners("Kraken Privateer").SequenceEqual(["Drake Buccaneer", "Drake Ironclad", "RSI Polaris"]), "Kraken Privateer has the three official loaners");
        Check(Loaners("Merchantman").SequenceEqual(["Banu Defender", "Crusader C2 Hercules Starlifter", "MISC Hull C"]), "Merchantman has the three official loaners");
        Check(Loaners("Javelin").SequenceEqual(["Aegis Idris-P", "Argo MPUV Cargo"]), "Javelin has the two official loaners");
    }

    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
