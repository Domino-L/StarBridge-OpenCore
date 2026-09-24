using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // A refreshed target must not replay a leave whose reply was lost. Keep the
    // uncertainty until an authoritative read confirms the old membership gone.
    private readonly ConcurrentDictionary<string, byte> _wpfS2UncertainLeaves = new();

    // ExecuteAsync already holds the common write gate. This branch only sends
    // WPF's ordinary exit payload, with neither successor nor disband consent.
    private async Task<CommunityCommand> LeaveWpfS2Async(string bearer, Target target, Action current, CancellationToken token)
    {
        var key = target.Scope + "\0" + target.Code.ToUpperInvariant();
        var sent = false;
        try
        {
            var fleet = (await WpfS2Membership(bearer, token)).SingleOrDefault(row =>
                Text(row, "code", 256).Equals(target.Code, StringComparison.OrdinalIgnoreCase));
            current(); token.ThrowIfCancellationRequested();
            if (fleet.ValueKind == JsonValueKind.Undefined)
            {
                _wpfS2UncertainLeaves.TryRemove(key, out _);
                InvalidateWpfS2Organization(target);
                return new("accepted"); // Already absent: no POST, no unrelated membership touched.
            }
            if (_wpfS2UncertainLeaves.ContainsKey(key)) return new("unknown", "outcomeUnknown");
            var ownership = await ReadWpfS2Ownership(bearer, fleet, target.WpfS2ViewerId!, token);
            if (!WpfS2CanLeave(fleet, target.WpfS2ViewerId!, ownership)) return new("rejected", "refreshRequired");
            current(); token.ThrowIfCancellationRequested();
            if (_wpfS2UncertainLeaves.Count >= 256) return new("rejected", "refreshRequired");
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/fleets/leave"))
                { Content = JsonContent.Create(new { FleetCode = target.Code }) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            _wpfS2UncertainLeaves[key] = 0;
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            current();
            if (!response.IsSuccessStatusCode)
            {
                if (response.StatusCode is HttpStatusCode.BadRequest or HttpStatusCode.Forbidden or HttpStatusCode.Unauthorized or HttpStatusCode.NotFound)
                {
                    _wpfS2UncertainLeaves.TryRemove(key, out _);
                    return new("rejected", "refreshRequired");
                }
                return new("unknown", "outcomeUnknown");
            }
            // Old Relay returns a whole snapshot. Do not export it or treat a
            // 200 alone as success; the authenticated membership is authoritative.
            var remaining = await WpfS2Membership(bearer, token);
            current(); token.ThrowIfCancellationRequested();
            if (remaining.Any(row => Text(row, "code", 256).Equals(target.Code, StringComparison.OrdinalIgnoreCase)))
                return new("unknown", "outcomeUnknown");
            _wpfS2UncertainLeaves.TryRemove(key, out _);
            return new("accepted");
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or
            AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException or
            JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { return new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired"); }
        finally { if (sent) InvalidateWpfS2Organization(target); }
    }

    private void InvalidateWpfS2Organization(Target target)
    {
        foreach (var pair in _targets.Where(x => x.Value.Scope == target.Scope &&
                     x.Value.Code.Equals(target.Code, StringComparison.OrdinalIgnoreCase)).ToArray())
            _targets.TryRemove(pair.Key, out _);
        foreach (var pair in _memberTargets.Where(x => x.Value.Scope == target.Scope &&
                     x.Value.Code.Equals(target.Code, StringComparison.OrdinalIgnoreCase)).ToArray())
            _memberTargets.TryRemove(pair.Key, out _);
        foreach (var pair in _shipTargets.Where(x => x.Value.Scope == target.Scope &&
                     x.Value.Code.Equals(target.Code, StringComparison.OrdinalIgnoreCase)).ToArray())
            _shipTargets.TryRemove(pair.Key, out _);
        foreach (var pair in _chatTargets.Where(x => x.Value.Scope == target.Scope &&
                     x.Value.Code.Equals(target.Code, StringComparison.OrdinalIgnoreCase)).ToArray())
            _chatTargets.TryRemove(pair.Key, out _);
        foreach (var pair in _announcementTargets.Where(x => x.Value.Scope == target.Scope &&
                     x.Value.Code.Equals(target.Code, StringComparison.OrdinalIgnoreCase)).ToArray())
            _announcementTargets.TryRemove(pair.Key, out _);
    }
}
