using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static class OfflineCommunityPaginationTests
{
    internal static string Wire()
    {
        OfflineOrganizationDirectory Directory(int count, bool changed) => new(new string(changed ? 'c' : 'a', 32),
            new DateTimeOffset(2026, 10, 14, 12, 0, 0, TimeSpan.Zero), !(changed && count == 256),
            Enumerable.Range(0, count).Select(i => new OfflineOrganizationRow((i + 1).ToString("x").PadLeft(64, '0'),
                (changed ? "New " : "Old ") + i, null, null)).ToArray());
        object Read(OfflineOrganizationDirectory value, int offset, string? version) =>
            OfflineOrganizationProjection.Read(value, JsonSerializer.SerializeToElement(new { offset, directoryVersion = version }), false);
        string Error(OfflineOrganizationDirectory value, int offset, string version)
        {
            try { Read(value, offset, version); throw new Exception("Expected rejected cursor"); }
            catch (AccountBridgeHostException error) { return error.Code; }
        }
        var snapshots = new Dictionary<string, object[]>();
        foreach (var (count, changed) in new[] { (61, false), (256, false), (61, true), (25, true), (5, true), (0, true), (256, true) })
        {
            var value = Directory(count, changed);
            snapshots[(changed ? "new" : "old") + count] = Enumerable.Range(0, Math.Max(1, (count + 19) / 20))
                .Select(page => Read(value, page * 20, page == 0 ? null : value.Version)).ToArray();
        }
        return JsonSerializer.Serialize(new { snapshots,
            directoryChanged = Error(Directory(61, true), 20, new string('a', 32)),
            missingPage = Error(Directory(5, true), 20, new string('c', 32)) }, BridgeProtocol.JsonOptions);
    }

    internal static Task Run()
    {
        using var json = JsonDocument.Parse(Wire());
        if (json.RootElement.GetProperty("directoryChanged").GetString() != "offlineAccount.directory_changed" ||
            json.RootElement.GetProperty("missingPage").GetString() != "offlineAccount.invalid_request")
            throw new Exception("Snapshot changes and unavailable offsets must retain exact failure semantics");
        var pages = json.RootElement.GetProperty("snapshots");
        if (pages.GetProperty("new61")[1].GetProperty("items")[0].GetProperty("name").GetString() != "New 20" ||
            pages.GetProperty("new256")[12].GetProperty("items").GetArrayLength() != 16 ||
            pages.GetProperty("new256")[12].GetProperty("complete").GetBoolean() ||
            pages.GetProperty("new0")[0].GetProperty("items").GetArrayLength() != 0)
            throw new Exception("Actual Native pagination did not preserve bounded rows and empty snapshots");
        return Task.CompletedTask;
    }
}
