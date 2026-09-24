using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Events;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Privacy;

internal sealed record EventFeedReceipt(string SessionId, long Sequence);

internal sealed partial class PrivacyRelayWriter
{
    internal async Task<SharedActivityRead> ReadEventFeedAsync(string bearer, string scope, string id, CancellationToken token)
    {
        if (scope is not ("organization" or "room") || string.IsNullOrWhiteSpace(id) || id.Length > 256)
            throw new AccountBridgeHostException("events.invalid_request");
        using var request = Request(HttpMethod.Get, new Uri(_eventSettings.AbsoluteUri + "/feed?" + scope + "=" + Uri.EscapeDataString(id)), bearer);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        RequireEventSuccess(response);
        using var document = await ReadAsync(response, token);
        try
        {
            var result = document.RootElement.Deserialize<SharedActivityRead>(LocalPrivacyStore.Json);
            if (result is null || result.SchemaVersion != 1 || result.Publishers is null || result.Publishers.Length > 64 ||
                (DateTimeOffset.UtcNow - result.ObservedAt).Duration() > TimeSpan.FromSeconds(30) ||
                result.Publishers.Any(p => p is null || string.IsNullOrWhiteSpace(p.AccountId) || p.AccountId.Length > 256 ||
                    p.Callsign is null || p.Callsign.Length > 180 || p.Events is null || p.Events.Length > 128 ||
                    p.Events.Any(e => e is null || !Guid.TryParseExact(e.Id, "N", out _) ||
                        SharedActivityEvent.Category(e.Type) == 0 || !e.IsFresh(result.ObservedAt)) ||
                    p.Events.Select(e => e.Id).Distinct(StringComparer.OrdinalIgnoreCase).Count() != p.Events.Length) ||
                result.Publishers.Sum(p => p.Events.Length) > 64 ||
                result.Publishers.Select(p => p.AccountId).Distinct(StringComparer.OrdinalIgnoreCase).Count() != result.Publishers.Length)
                throw new JsonException();
            return result;
        }
        catch (Exception e) when (e is JsonException or ArgumentException)
        { throw new AccountBridgeHostException("events.response_invalid"); }
    }
    internal async Task<EventFeedReceipt> WriteEventFeedAsync(string bearer, string action, long revision,
        string? sessionId, long sequence, SharedActivityEvent[] events, Action current, CancellationToken token)
    {
        current();
        using var request = Request(HttpMethod.Post, new Uri(_eventSettings.AbsoluteUri + "/feed"), bearer);
        request.Content = JsonContent.Create(new { schemaVersion = 1, action, revision, sessionId, sequence, events });
        // No retry/readback of a data batch. Uncertain transmission abandons the
        // lease and starts a fresh baseline, never replaying its pending events.
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        current();
        RequireEventSuccess(response);
        using var document = await ReadAsync(response, token);
        var root = document.RootElement;
        try
        {
            var id = root.GetProperty("sessionId").GetString();
            if (root.GetProperty("schemaVersion").GetInt32() != 1 || !Guid.TryParseExact(id, "N", out _) ||
                root.GetProperty("sequence").GetInt64() != sequence || action != "start" && id != sessionId ||
                root.EnumerateObject().Count() != 4 ||
                (action == "stop" ? !root.GetProperty("stopped").GetBoolean() :
                    root.GetProperty("expiresAt").GetDateTimeOffset() <= DateTimeOffset.UtcNow))
                throw new JsonException();
            current();
            return new(id!, sequence);
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
        { throw new AccountBridgeHostException("events.response_invalid"); }
    }
}
