using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record LogTarget(string Id, string Version, string Code, string Scope, DateTimeOffset Expires);
    private readonly ConcurrentDictionary<string, LogTarget> _logTargets = new();
    private static readonly string[] LogFilters = ["All", "成员", "公告", "舰队"];

    internal Task<object> ReadLogsAsync(string bearer, JsonElement body, string scope, CancellationToken token) =>
        GuardWorkspace(() => ReadLogsCore(bearer, body, scope, token));

    private async Task<object> ReadLogsCore(string bearer, JsonElement body, string scope, CancellationToken token)
    {
        Validate(body, "targetRef", "type", "query", "offset");
        var reference = Text(body, "targetRef", 32);
        var target = ResolveForRead(reference, scope);
        var type = Text(body, "type", 16);
        var query = Text(body, "query", 128).Trim();
        var offset = Number(body, "offset", 0, 1000000);
        if (!LogFilters.Contains(type)) throw Invalid();
        var root = await WorkspaceJson(bearer, $"/api/fleets/logs?code={Uri.EscapeDataString(target.Code)}&type={Uri.EscapeDataString(type)}&q={Uri.EscapeDataString(query)}&offset={offset}", token);
        if (Number(root, "schemaVersion", 1, 1) != 1 || Number(root, "membershipModelVersion", 2, 2) != 2 ||
            Text(root, "code", 256) != target.Code || Text(root, "type", 16) != type ||
            Text(root, "query", 128) != query || Number(root, "offset", 0, 1000000) != offset) throw Invalid();
        var name = Text(root, "name", 512);
        var canDelete = root.GetProperty("canDelete").GetBoolean();
        var total = Number(root, "totalCount", 0, 100000);
        var matched = Number(root, "matchedCount", 0, 100000);
        int? next = root.GetProperty("next").ValueKind == JsonValueKind.Null ? null : Number(root, "next", 0, 100000);
        var fetchedAt = Timestamp(root, "fetchedAt") ?? throw Invalid();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var pending = new Dictionary<string, LogTarget>();
        var items = Rows(root, "items", 20).Select(row =>
        {
            var id = Text(row, "id", 512);
            var version = Text(row, "version", 64);
            if (string.IsNullOrWhiteSpace(id) || !seen.Add(id) || version.Length != 64 ||
                version.Any(c => !char.IsAsciiHexDigit(c) || char.IsUpper(c))) throw Invalid();
            var timestamp = Timestamp(row, "timestamp");
            var end = Timestamp(row, "endTimestamp");
            if (timestamp is not null && (end is null || DateTimeOffset.Parse(end) < DateTimeOffset.Parse(timestamp))) throw Invalid();
            var rowType = Text(row, "type", 128);
            if (type != "All" && !string.Equals(type, rowType, StringComparison.OrdinalIgnoreCase)) throw Invalid();
            var logRef = Guid.NewGuid().ToString("N");
            if (canDelete) pending[logRef] = new(id, version, target.Code, scope, DateTimeOffset.UtcNow.AddMinutes(5));
            return new
            {
                logRef, timestamp, endTimestamp = end, type = rowType,
                title = Text(row, "title", 8192, true), detail = Text(row, "detail", 32768, true),
                occurrenceCount = Number(row, "occurrenceCount", 1, int.MaxValue)
            };
        }).ToArray();
        if (matched > total || offset > matched || items.Length != Math.Min(20, matched - offset) ||
            next != (offset + items.Length < matched ? offset + items.Length : null)) throw Invalid();
        token.ThrowIfCancellationRequested();
        // Publish action references only after validating the entire response.
        foreach (var old in _logTargets.Where(p => p.Value.Expires <= DateTimeOffset.UtcNow ||
                     !canDelete && p.Value.Scope == scope && p.Value.Code == target.Code).ToArray())
            _logTargets.TryRemove(old.Key, out _);
        if (_logTargets.Count + pending.Count > 4000) _logTargets.Clear();
        foreach (var pair in pending) _logTargets[pair.Key] = pair.Value;
        RenewTarget(reference, target, token);
        return new { schemaVersion = 1, targetRef = reference, name, canDelete, type, query, offset, next,
            totalCount = total, matchedCount = matched, items, fetchedAt };
    }

    internal async Task<object> DeleteLogAsync(string bearer, JsonElement body, string scope, Action current, CancellationToken token)
    {
        Validate(body, "targetRef", "logRef");
        var reference = Text(body, "targetRef", 32);
        var logRef = Text(body, "logRef", 32);
        var target = Resolve(reference, scope);
        if (!_logTargets.TryGetValue(logRef, out var entry) || entry.Scope != scope || entry.Code != target.Code ||
            entry.Expires <= DateTimeOffset.UtcNow) return new CommunityCommand("rejected", "refreshRequired");
        if (!await _write.WaitAsync(0, token)) return new CommunityCommand("rejected", "busy");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        var sent = false;
        try
        {
            current();
            token.ThrowIfCancellationRequested();
            // A displayed reference authorizes at most one attempt. An uncertain reply is never replayed.
            if (!_logTargets.TryRemove(logRef, out _)) return new CommunityCommand("rejected", "refreshRequired");
            using var request = new HttpRequestMessage(HttpMethod.Post,
                new Uri(_origin, "/api/fleets/logs/delete?projection=logs&version=" + entry.Version))
            { Content = JsonContent.Create(new { fleetCode = target.Code, logId = entry.Id }) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden or HttpStatusCode.NotFound or
                HttpStatusCode.BadRequest or HttpStatusCode.Conflict)
                return new CommunityCommand("rejected", response.StatusCode == HttpStatusCode.Unauthorized ? "identityUnavailable" : "refreshRequired");
            if (!response.IsSuccessStatusCode) return new CommunityCommand("unknown", "outcomeUnknown");
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            var bytes = new byte[1025];
            var length = 0;
            int count;
            while (length < bytes.Length && (count = await stream.ReadAsync(bytes.AsMemory(length), deadline.Token)) > 0) length += count;
            if (length > 1024) return new CommunityCommand("unknown", "outcomeUnknown");
            using var receipt = JsonDocument.Parse(bytes.AsMemory(0, length));
            var root = receipt.RootElement;
            if (root.EnumerateObject().Count() != 2 || Number(root, "schemaVersion", 1, 1) != 1 ||
                Text(root, "status", 16) != "accepted") return new CommunityCommand("unknown", "outcomeUnknown");
            current();
            return new CommunityCommand("accepted");
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or
            JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or
            AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException)
        { return new CommunityCommand(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired"); }
        finally { _write.Release(); }
    }
}
