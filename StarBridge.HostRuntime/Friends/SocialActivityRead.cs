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
        // Realtime v1: answer from the pushed stream when connected. The community
        // projection also needs the relay's presence capability, learned once from
        // an HTTP response, so the stream takes over only after that is known.
        if (RealtimeClient is { } realtime && (!community || _communityPresenceEvents is not null))
        {
            Dictionary<string, string[]> targets;
            var credentialOwner = Owner(bearer, "");
            lock (_targetGate) targets = _conversations.Where(p =>
                    p.Value.CredentialOwner == credentialOwner && p.Value.Expires >= DateTimeOffset.UtcNow)
                .GroupBy(p => p.Value.Id, StringComparer.Ordinal)
                .ToDictionary(g => g.Key, g => g.Select(p => p.Key).ToArray(), StringComparer.Ordinal);
            realtime.SetDirectMessageTargets(bearer, targets, token);
            var served = await realtime.TryWaitAsync(bearer, community, instance, version, TimeSpan.FromSeconds(8), token);
            token.ThrowIfCancellationRequested();
            if (served is { } cursor)
            {
                var hints = realtime.DirectMessageChanges(bearer, instance, version);
                return community
                    ? (object)new { schemaVersion = 1, instance = cursor.Instance, version = cursor.Version,
                        presenceEvents = _communityPresenceEvents == true }
                    : new { schemaVersion = 1, instance = cursor.Instance, version = cursor.Version,
                        directMessagesPushHealthy = realtime.DirectMessagesPushHealthy,
                        directMessagesOnly = hints.Only,
                        directMessageTargets = hints.Targets };
            }
        }
        // Eight-second heartbeat fits the existing 12s HTTP / 15s bridge limits.
        // The server returns immediately on change, not at the heartbeat deadline.
        var resource = community ? "fleets" : "social";
        var path = $"/api/{resource}/activity?instance={Uri.EscapeDataString(instance)}&after={version}&waitSeconds=8";
        var json = await Realtime.ActivityWaitRead.JsonAsync(_http, _origin, bearer, path,
            status => status == HttpStatusCode.Unauthorized
                ? new("friends.identity_unavailable") : new("friends.read_unavailable", true), Invalid, token);
        RejectDuplicates(json);
        var nextInstance = json.GetProperty("instanceId").GetString();
        var nextVersion = json.GetProperty("version").GetInt64();
        if (!Guid.TryParseExact(nextInstance, "N", out _) || nextVersion < 0) throw Invalid();
        var presence = json.TryGetProperty("presenceEvents", out var supports) && supports.ValueKind == JsonValueKind.True;
        if (community) _communityPresenceEvents = presence;
        return community
            ? (object)new { schemaVersion = 1, instance = nextInstance, version = nextVersion,
                presenceEvents = presence }
            : new { schemaVersion = 1, instance = nextInstance, version = nextVersion,
                directMessagesPushHealthy = false };
    }

    private bool? _communityPresenceEvents;
}
