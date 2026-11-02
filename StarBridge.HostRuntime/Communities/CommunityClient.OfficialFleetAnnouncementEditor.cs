using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.Core.FleetAnnouncements;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private const string OfficialAnnouncementEditorPath = "/api/official-fleets/governance/announcements/editor";
    private const string OfficialAnnouncementEditorVersionHeader = "X-StarBridge-Announcement-Editor-Version";
    private sealed record OfficialAnnouncementItem(string Id, int Revision, string Title, string Content);
    private sealed record OfficialAnnouncementEdit(string AccountScope, string SourceRef, string ScopeKey, string AuthorityBinding,
        long PolicyRevision, long TimelineRevision, OfficialAnnouncementItem? Item, string? ItemRef, DateTimeOffset Expires);
    private readonly ConcurrentDictionary<string, OfficialAnnouncementEdit> _officialAnnouncementEdits = new(StringComparer.Ordinal);
    private long _officialAnnouncementEditorEpoch;

    internal Task<object> ReadOfficialAnnouncementEditorAsync(string bearer, JsonElement body, string accountScope,
        Action current, CancellationToken token) => GuardWorkspace(async () =>
    {
        Validate(body, "sourceRef");
        var sourceRef = Text(body, "sourceRef", 64);
        if (!OfficialAnnouncementSource(sourceRef)) throw Invalid();
        current(); token.ThrowIfCancellationRequested();
        var epoch = Interlocked.Increment(ref _officialAnnouncementEditorEpoch);
        foreach (var pair in _officialAnnouncementEdits.Where(p => p.Value.AccountScope == accountScope ||
                     p.Value.Expires <= _targetClock.GetUtcNow()).ToArray()) _officialAnnouncementEdits.TryRemove(pair.Key, out _);
        // Failed/unknown fresh reads never keep an old positive reference alive.
        var edit = await FetchOfficialAnnouncementEditorAsync(bearer, sourceRef, accountScope, current, token);
        current(); token.ThrowIfCancellationRequested();
        if (epoch != Interlocked.Read(ref _officialAnnouncementEditorEpoch))
            throw new AccountBridgeHostException("communities.refreshRequired");
        if (_officialAnnouncementEdits.Count >= 128) throw new AccountBridgeHostException("communities.refreshRequired");
        var reference = Guid.NewGuid().ToString("N");
        if (!_officialAnnouncementEdits.TryAdd(reference, edit)) throw Invalid();
        try
        {
            current(); token.ThrowIfCancellationRequested();
            if (epoch != Interlocked.Read(ref _officialAnnouncementEditorEpoch))
                throw new AccountBridgeHostException("communities.refreshRequired");
        }
        catch { _officialAnnouncementEdits.TryRemove(reference, out _); throw; }
        return JsonSerializer.SerializeToElement(new
        {
            schemaVersion = 1,
            state = "available",
            sourceRef,
            editRef = reference,
            revision = edit.TimelineRevision,
            allowedActions = edit.Item is null ? new[] { "publish" } : new[] { "publish", "edit", "withdraw" },
            current = edit.Item is null ? null : new { announcementRef = edit.ItemRef, title = edit.Item.Title, content = edit.Item.Content }
        });
    });

    private async Task<OfficialAnnouncementEdit> FetchOfficialAnnouncementEditorAsync(string bearer, string sourceRef,
        string accountScope, Action current, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var request = new HttpRequestMessage(HttpMethod.Get,
            new Uri(_origin, OfficialAnnouncementEditorPath + "?sourceRef=" + Uri.EscapeDataString(sourceRef)));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        request.Headers.Add(OfficialAnnouncementEditorVersionHeader, "2");
        current(); deadline.Token.ThrowIfCancellationRequested();
        Privacy.OfficialAnnouncementReadObservation.Sending();
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
        Privacy.OfficialAnnouncementReadObservation.Response(response.StatusCode);
        current(); deadline.Token.ThrowIfCancellationRequested();
        if (response.StatusCode != HttpStatusCode.OK) throw new AccountBridgeHostException(
            response.StatusCode == HttpStatusCode.Forbidden ? "communities.notAllowed" : "communities.unavailable");
        // Reuse the existing bounded JSON byte reader, not the hangar authority/target.
        var root = await ReadOfficialHangarJson(response, deadline.Token, 16 * 1024);
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("schemaVersion", out var schema) &&
            schema.ValueKind == JsonValueKind.Number && schema.TryGetInt32(out var version) && version == 1)
        {
            RequireOfficialAnnouncementObject(root, "schemaVersion", "state", "sourceRef", "scopeKey",
                "policyRevision", "timelineRevision", "current", "allowedActions");
            throw new AccountBridgeHostException("communities.upgradeRequired");
        }
        RequireOfficialAnnouncementObject(root, "schemaVersion", "state", "sourceRef", "scopeKey", "authorityBinding",
            "policyRevision", "timelineRevision", "current", "allowedActions");
        if (Number(root, "schemaVersion", 2, 2) != 2 || Text(root, "state", 16) != "available" ||
            Text(root, "sourceRef", 64) != sourceRef) throw Invalid();
        var scopeKey = Text(root, "scopeKey", 64); var binding = Text(root, "authorityBinding", 64);
        if (!LowerHex(scopeKey, 64) || !LowerHex(binding, 64)) throw Invalid();
        var policy = OfficialAnnouncementRevision(root, "policyRevision");
        var timeline = OfficialAnnouncementRevision(root, "timelineRevision");
        OfficialAnnouncementItem? item = null;
        var value = root.GetProperty("current");
        if (value.ValueKind != JsonValueKind.Null)
        {
            RequireOfficialAnnouncementObject(value, "announcementId", "itemRevision", "title", "content");
            var id = Text(value, "announcementId", 128);
            var title = Text(value, "title", 48); var content = Text(value, "content", 1200, true);
            var normalized = FleetAnnouncementPolicy.Normalize(title, content);
            if (string.IsNullOrWhiteSpace(id) || normalized.Error is not null ||
                normalized.Title != title || normalized.Content != content) throw Invalid();
            item = new(id, Number(value, "itemRevision", 1, int.MaxValue), title, content);
        }
        var actions = Rows(root, "allowedActions", 3).Select(v => v.GetString()).ToArray();
        var expected = item is null ? new[] { "publish" } : new[] { "publish", "edit", "withdraw" };
        if (!actions.SequenceEqual(expected)) throw Invalid();
        current(); deadline.Token.ThrowIfCancellationRequested();
        return new(accountScope, sourceRef, scopeKey, binding, policy, timeline, item,
            item is null ? null : Guid.NewGuid().ToString("N"), _targetClock.GetUtcNow().AddMinutes(5));
    }

    private static void RequireOfficialAnnouncementObject(JsonElement value, params string[] keys)
    {
        if (value.ValueKind != JsonValueKind.Object ||
            !value.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal)
                .SequenceEqual(keys.Order(StringComparer.Ordinal))) throw Invalid();
    }
    private static bool OfficialAnnouncementSource(string value) => Regex.IsMatch(value, "^officialFleet:[1-9][0-9]{0,18}$") &&
        long.TryParse(value[14..], System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var id) && id > 0;
    private static long OfficialAnnouncementRevision(JsonElement root, string key)
    {
        var value = root.GetProperty(key);
        return value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var number) && number >= 0 ? number : throw Invalid();
    }
    private void DisposeOfficialAnnouncementEditors()
    {
        Interlocked.Increment(ref _officialAnnouncementEditorEpoch);
        _officialAnnouncementEdits.Clear();
    }
}
