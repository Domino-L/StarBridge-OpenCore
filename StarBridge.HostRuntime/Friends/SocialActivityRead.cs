namespace StarBridge.HostRuntime.Friends;

using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

internal sealed partial class FriendsReader
{
    internal static (string Instance, long Version) ParseActivity(JsonElement payload)
    {
        try {
            var fields = payload.EnumerateObject().Select(p => p.Name).ToArray();
            var instance = payload.GetProperty("instance").GetString();
            var version = payload.GetProperty("version").GetInt64();
            if (fields.Length != 3 || fields.Distinct().Count() != 3 ||
                fields.Except(new[] { "schemaVersion", "instance", "version" }).Any() ||
                payload.GetProperty("schemaVersion").GetInt32() != 1 || version < -1 ||
                instance is null || !(instance == "" || Guid.TryParseExact(instance, "N", out _))) throw InvalidRequest();
            return (instance, version);
        } catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException) {
            throw InvalidRequest();
        }
    }

    internal async Task<object> WaitActivityAsync(string bearer, JsonElement payload, CancellationToken token,
        bool community = false)
    {
        var (instance, version) = ParseActivity(payload);
        // Eight-second heartbeat fits the existing 12s HTTP / 15s bridge limits.
        // The server returns immediately on change, not at the heartbeat deadline.
        var resource = community ? "fleets" : "social";
        var path = $"/api/{resource}/activity?instance={Uri.EscapeDataString(instance)}&after={version}&waitSeconds=8";
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_origin, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
        if (response.StatusCode == HttpStatusCode.Unauthorized) throw new AccountBridgeHostException("friends.identity_unavailable");
        if (!response.IsSuccessStatusCode) throw new AccountBridgeHostException("friends.read_unavailable", true);
        if (response.Content.Headers.ContentLength > 4096) throw Invalid();
        using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
        using var buffer = new MemoryStream();
        var bytes = new byte[1024];
        int count;
        while ((count = await stream.ReadAsync(bytes, deadline.Token)) > 0) {
            if (buffer.Length + count > 4096) throw Invalid();
            buffer.Write(bytes, 0, count);
        }
        using var json = JsonDocument.Parse(buffer.ToArray());
        RejectDuplicates(json.RootElement);
        var nextInstance = json.RootElement.GetProperty("instanceId").GetString();
        var nextVersion = json.RootElement.GetProperty("version").GetInt64();
        if (!Guid.TryParseExact(nextInstance, "N", out _) || nextVersion < 0) throw Invalid();
        return community
            ? (object)new { schemaVersion = 1, instance = nextInstance, version = nextVersion,
                presenceEvents = json.RootElement.TryGetProperty("presenceEvents", out var supports) && supports.ValueKind == JsonValueKind.True }
            : new { schemaVersion = 1, instance = nextInstance, version = nextVersion };
    }
}
