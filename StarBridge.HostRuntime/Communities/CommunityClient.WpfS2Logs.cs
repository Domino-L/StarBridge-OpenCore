using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal Task<object> ReadWpfS2LogsAsync(string bearer, JsonElement body, string scope, Action current,
        CancellationToken token) => GuardWorkspace(async () =>
    {
        Validate(body, "targetRef", "type", "query", "offset");
        var epoch = Interlocked.Read(ref _wpfGovernanceEpoch);
        var reference = Text(body, "targetRef", 32);
        var target = ResolveForRead(reference, scope, allowWpfS2: true);
        var type = Text(body, "type", 16);
        var query = Text(body, "query", 128).Trim();
        var offset = Number(body, "offset", 0, 1000000);
        if (!LogFilters.Contains(type)) throw Invalid();
        var fleet = await WpfGovernanceFleet(bearer, target, current, token);
        var owner = await ReadWpfS2Ownership(bearer, fleet, target.WpfS2ViewerId!, token);
        if (!WpfS2HasPermissionId(fleet, target.WpfS2ViewerId!, "audit.view", owner))
            throw new AccountBridgeHostException("communities.notAllowed");
        var canDelete = WpfS2HasPermissionId(fleet, target.WpfS2ViewerId!, "audit.delete", owner);
        var source = WpfS2OptionalRows(fleet, "eventLog", 100000);
        if (source.Select(row => Text(row, "id", 512)).Distinct(StringComparer.OrdinalIgnoreCase).Count() != source.Length) throw Invalid();
        var matched = source.Where(row => (type == "All" || WpfText(row, "type", 128).Equals(type, StringComparison.OrdinalIgnoreCase)) &&
            (query.Length == 0 || new[] { "type", "title", "detail" }.Any(key =>
                WpfText(row, key, 32768, true).Contains(query, StringComparison.OrdinalIgnoreCase))))
            .OrderByDescending(row => WpfTimestamp(row, "timestamp")).ThenBy(row => Text(row, "id", 512), StringComparer.Ordinal).ToArray();
        if (offset > matched.Length) throw Invalid();
        var pending = new Dictionary<string, WpfGovernanceEdit>();
        var version = WpfGovernanceVersion(fleet);
        var items = matched.Skip(offset).Take(20).Select(row =>
        {
            var id = Text(row, "id", 512);
            if (string.IsNullOrWhiteSpace(id)) throw Invalid();
            var timestamp = WpfTimestamp(row, "timestamp");
            var end = WpfTimestamp(row, "endTimestamp");
            if (end is null || end < timestamp) end = timestamp;
            var logRef = Guid.NewGuid().ToString("N");
            if (canDelete) pending[logRef] = new("log", scope, reference, target, null, id,
                version + "\0" + WpfHash(row), _targetClock.GetUtcNow().AddMinutes(5));
            return new { logRef, timestamp, endTimestamp = end, type = WpfText(row, "type", 128),
                title = WpfText(row, "title", 8192, true), detail = WpfText(row, "detail", 32768, true),
                occurrenceCount = row.TryGetProperty("occurrenceCount", out var count) ? Math.Max(1, count.GetInt32()) : 1 };
        }).ToArray();
        current();
        token.ThrowIfCancellationRequested();
        lock (_wpfGovernanceGate)
        {
            if (epoch != _wpfGovernanceEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
            foreach (var old in _wpfGovernanceEdits.Where(row => row.Value.Expires <= _targetClock.GetUtcNow()).ToArray())
                _wpfGovernanceEdits.Remove(old.Key);
            if (_wpfGovernanceEdits.Count + pending.Count > 256) throw new AccountBridgeHostException("communities.refreshRequired");
            foreach (var row in pending) _wpfGovernanceEdits[row.Key] = row.Value;
        }
        RenewTarget(reference, target, token);
        return new { schemaVersion = 1, targetRef = reference, name = Text(fleet, "name", 512), canDelete, type, query, offset,
            next = offset + items.Length < matched.Length ? (int?)(offset + items.Length) : null,
            totalCount = source.Length, matchedCount = matched.Length, items, fetchedAt = _targetClock.GetUtcNow() };
    });
}
