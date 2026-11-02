using System.Net;
using System.Text.Json;
using StarBridge.Core.Ships;
using StarBridge.HostRuntime.Ships;

// Explicit diagnostic entry only. Enumerates client-owned catalogues, never account inventory.
internal static class ShipSpecificationCoverageAudit
{
    private sealed record Input(string Scope, string Model, string Chinese, string Delivery);
    private sealed record Result(string Scope, string Model, string Chinese, string Delivery,
        string State, int Groups, int Components, string? Version, string? Error, string? PaintBaseModel = null);

    internal static async Task Run(string catalogPath, string namesPath, string outputPath)
    {
        var lines = File.ReadAllLines(catalogPath);
        var header = lines[0].TrimStart('\uFEFF').Split('\t');
        var english = Array.IndexOf(header, "英文飞船名");
        var chinese = Array.IndexOf(header, "中文飞船名");
        var delivery = Array.IndexOf(header, "官网状态");
        if (english < 0 || chinese < 0 || delivery < 0) throw new InvalidDataException("Client catalogue columns missing.");
        var inputs = lines.Skip(1).Select(line => line.Split('\t'))
            .Where(row => row.Length > Math.Max(delivery, Math.Max(english, chinese)) && !string.IsNullOrWhiteSpace(row[english]))
            .Select(row => new Input("clientCatalog", row[english].Trim(), row[chinese].Trim(), row[delivery].Trim())).ToList();
        using var names = JsonDocument.Parse(File.ReadAllText(namesPath));
        inputs.AddRange(names.RootElement.GetProperty("entries").EnumerateArray().Select(row => new Input("runtimeNames",
            row.GetProperty("runtimeId").GetString()!, row.GetProperty("chineseName").GetString()!, "")));
        // Adjacent aliases share the product cache. No bulk parallel detail requests.
        inputs = inputs.OrderBy(input => ShipNameIndex.Bundled.Find(input.Model)?.RuntimeId ?? "name:" + input.Model,
            StringComparer.OrdinalIgnoreCase).ToList();
        using var reader = new ScmShipSpecificationReader(new("https://scmk.flowcld.com/"), names:
            ShipNameIndex.Parse(File.ReadAllText(namesPath), File.ReadAllText(catalogPath)));
        var results = new List<Result>();
        foreach (var input in inputs)
        {
            try
            {
                var result = await reader.ReadAsync(input.Model, false, default);
                results.Add(new(input.Scope, input.Model, input.Chinese, input.Delivery, result.State,
                    result.Groups?.Count ?? 0, result.Components?.Count ?? 0, result.DataVersion, null, result.PaintBaseModel));
            }
            catch (HttpRequestException error)
            {
                results.Add(new(input.Scope, input.Model, input.Chinese, input.Delivery, "failed", 0, 0, null,
                    error.InnerException?.GetType().Name ?? error.GetType().Name));
            }
            if (results.Count % 25 == 0 || results.Count == inputs.Count)
            {
                File.WriteAllText(outputPath, JsonSerializer.Serialize(new {
                    completed = results.Count == inputs.Count, processed = results.Count, total = inputs.Count,
                    summary = results.GroupBy(row => new { row.Scope, row.State }).Select(group => new { group.Key.Scope, group.Key.State, count = group.Count() }),
                    rows = results
                }, new JsonSerializerOptions { WriteIndented = true }));
                Console.WriteLine($"COVERAGE {results.Count}/{inputs.Count}: ready={results.Count(row => row.State == "ready")}, failed={results.Count(row => row.State == "failed")}");
            }
        }
        foreach (var scope in results.GroupBy(row => row.Scope))
            Console.WriteLine($"SUMMARY {scope.Key}: total={scope.Count()}, " + string.Join(", ", scope.GroupBy(row => row.State).Select(group => $"{group.Key}={group.Count()}")));
    }
}
