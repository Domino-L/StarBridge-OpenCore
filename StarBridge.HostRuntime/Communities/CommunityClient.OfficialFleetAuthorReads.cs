using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal Action<Privacy.OfficialChatAuthorReadDiagnostic>? ChatAuthorDiagnostic { get; set; }
    private async Task<OfficialAuthorRead> ReadOfficialChatAuthors(string bearer, Target target, JsonElement body, string scope, long after, long before, CancellationToken token, int limit = 50, bool preview = false, bool allowChatAuthorsFallback = false, bool renewal = false)
    {
        using var diagnostic = new Privacy.OfficialChatAuthorReadObservation(preview ? "preview" : renewal ? "renewal" : "page", ChatAuthorDiagnostic);
        try
        {
            var requested = body.GetProperty("observeMessageRefs").EnumerateArray().Select(row => row.GetString()!).ToArray();
            var known = new List<(string Reference, ChatTarget Address)>(); var refresh = false;
            foreach (var reference in requested)
            {
                if (!_chatTargets.TryGetValue(reference, out var address)) { refresh = true; continue; }
                if (address.Code != target.Code || address.Scope != scope || !address.OfficialFleet) throw Invalid();
                known.Add((reference, address)); // Read-only address; never an authorization or direct identity query.
            }
            var source = "officialFleet:" + target.Code["OFFICIALFLEET:".Length..];
            diagnostic.Requested(known.Select(row => row.Address.SenderId).Where(OfficialBid).Distinct(StringComparer.Ordinal).Count());
            var command = new
            {
                schemaVersion = 2, sourceRef = source, fleetCode = target.Code,
                mode = "page", after, before, limit,
                observedMessages = known.Select(row => new { messageId = row.Address.MessageId, sequence = row.Address.Sequence }).ToArray()
            };
            var route = preview ? "/api/official-fleets/chat/messages/read-preview" : "/api/official-fleets/chat/messages/read";
            var root = await OfficialAuthorJson(bearer, route, command, 960 * 1024, token, allowChatAuthorsFallback, diagnostic);
            diagnostic.Raw(root);
            if (root.ValueKind != JsonValueKind.Object || Number(root, "schemaVersion", 2, 2) != 2 || Text(root, "sourceRef", 64) != source) throw Invalid();
            var page = root.GetProperty("page");
            var expected = Rows(page, "messages", 50).Select(row => Text(row, "senderAccountId", 512)).Where(OfficialBid).ToHashSet(StringComparer.Ordinal);
            var observed = known.Select(row => new OfficialObservedChat(row.Reference, row.Address, false)).ToArray();
            var hintValid = TryAuthorRefresh(root, out var upstreamRefresh); refresh |= upstreamRefresh;
            bool valid = hintValid && AuthorKeys(root, ["schemaVersion", "sourceRef", "page", "observedMessages", "identities", "authorRefreshRequired"]);
            try
            {
                var rows = Rows(root, "observedMessages", 50); if (rows.Length != known.Count) throw Invalid();
                for (int i = 0; i < rows.Length; i++)
                {
                    var row = rows[i]; var address = known[i].Address; var state = Text(row, "recordState", 16);
                    if (Text(row, "messageId", 128) != address.MessageId || ChatSequence(row, "sequence", true) != address.Sequence) throw Invalid();
                    if (state == "found")
                    {
                        if (!AuthorKeys(row, ["messageId", "sequence", "recordState", "senderAccountId"]) || Text(row, "senderAccountId", 512) != address.SenderId) throw Invalid();
                        observed[i] = observed[i] with { Found = true }; if (OfficialBid(address.SenderId)) expected.Add(address.SenderId);
                    }
                    else if (state != "notRetained" || !AuthorKeys(row, ["messageId", "sequence", "recordState"])) throw Invalid();
                }
            }
            catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or AccountBridgeHostException) { valid = false; refresh = true; }
            diagnostic.Requested(expected.Count);
            if (!valid) diagnostic.ParseFailed();
            var identities = valid ? AuthorIdentities(root, expected, diagnostic: diagnostic, preserveLapsedVisible: !preview) : new Dictionary<string, OfficialAuthorObservation>();
            if (!valid) { refresh = true; observed = observed.Select(row => row with { Found = false }).ToArray(); }
            return new(page, identities, observed, refresh);
        }
        catch (Exception error) { diagnostic.Fail(error, error is OfficialChatAuthorsDisabledException); throw; }
    }
    private void TrimOfficialChatAddresses(Target target, string scope, HashSet<string> pending)
    {
        var added = pending.Count(reference => !_chatTargets.ContainsKey(reference));
        var existing = _chatTargets.Where(pair => pair.Value.OfficialFleet && pair.Value.Code == target.Code && pair.Value.Scope == scope).ToArray();
        foreach (var old in existing.Where(pair => !pending.Contains(pair.Key)).OrderBy(pair => pair.Value.Sequence)
            .Take(Math.Max(0, existing.Length + added - 500))) _chatTargets.TryRemove(old.Key, out _);
        // Only official read addresses may be evicted here. Ordinary community action references keep their owner rules.
        foreach (var old in _chatTargets.Where(pair => pair.Value.OfficialFleet && !pending.Contains(pair.Key)).OrderBy(pair => pair.Value.Expires)
            .Take(Math.Max(0, _chatTargets.Count + added - 2000)).ToArray()) _chatTargets.TryRemove(old.Key, out _);
    }
    private sealed class OfficialChatAuthorsDisabledException : Exception { }
    private static async Task<bool> ChatAuthorsDisabled(HttpResponseMessage response, CancellationToken token)
    {
        const int maximum = 4096;
        if (response.Content.Headers.ContentLength > maximum) return false;
        using var stream = await response.Content.ReadAsStreamAsync(token);
        using var output = new MemoryStream(); var buffer = new byte[maximum + 1]; int count;
        while ((count = await stream.ReadAsync(buffer, token)) > 0)
        {
            if (output.Length + count > maximum) return false;
            output.Write(buffer, 0, count);
        }
        try
        {
            using var document = JsonDocument.Parse(output.ToArray()); var root = document.RootElement;
            return root.ValueKind == JsonValueKind.Object && root.EnumerateObject().Count(p => p.Name == "reason") == 1 &&
                root.TryGetProperty("reason", out var reason) && reason.ValueKind == JsonValueKind.String && reason.GetString() == "chatAuthorsDisabled";
        }
        catch (JsonException) { return false; }
    }
    private async Task<JsonElement> OfficialAuthorJson(string bearer, string path, object body, int maximum, CancellationToken token, bool allowChatAuthorsFallback = false,
        Privacy.OfficialChatAuthorReadObservation? chatDiagnostic = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, path)) { Content = JsonContent.Create(body) };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        try
        {
            Privacy.OfficialAnnouncementReadObservation.Sending();
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            Privacy.OfficialAnnouncementReadObservation.Response(response.StatusCode);
            chatDiagnostic?.Response(response.StatusCode);
            if (response.StatusCode == HttpStatusCode.Unauthorized) throw new AccountBridgeHostException("communities.identityUnavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden) throw new AccountBridgeHostException("communities.notAllowed");
            if (response.StatusCode == HttpStatusCode.Conflict) throw new AccountBridgeHostException("communities.announcementsChanged");
            if (response.StatusCode == HttpStatusCode.NotFound) throw new AccountBridgeHostException("communities.refreshRequired");
            if (allowChatAuthorsFallback && response.StatusCode == HttpStatusCode.ServiceUnavailable && await ChatAuthorsDisabled(response, token))
                throw new OfficialChatAuthorsDisabledException();
            if (!response.IsSuccessStatusCode) throw new AccountBridgeHostException("communities.unavailable", true, response.StatusCode);
            using var stream = await response.Content.ReadAsStreamAsync(token); using var output = new MemoryStream(); var buffer = new byte[8192]; int count;
            while ((count = await stream.ReadAsync(buffer, token)) > 0) { if (output.Length + count > maximum) throw Invalid(); output.Write(buffer, 0, count); }
            using var document = JsonDocument.Parse(output.ToArray()); return document.RootElement.Clone();
        }
        catch (HttpRequestException error) { throw new AccountBridgeHostException("communities.unavailable", true, error.StatusCode); }
        catch (IOException) { throw new AccountBridgeHostException("communities.unavailable", true); }
    }
}
