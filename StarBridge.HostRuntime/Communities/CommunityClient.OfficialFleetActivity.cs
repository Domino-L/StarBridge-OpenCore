using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal sealed class OfficialActivityWaitSession
    {
        internal int Seconds = 25;
    }
    private readonly OfficialActivityWaitSession _defaultOfficialWaitSession = new();
    // 25s wait + two authority observations (up to 10s each) + transport margin.
    internal static readonly TimeSpan OfficialActivityWaitDeadline = TimeSpan.FromSeconds(50);
    internal static (string Source, string Instance, long Version) ParseOfficialActivity(JsonElement payload)
    {
        try {
            var fields = payload.EnumerateObject().Select(field => field.Name).ToArray();
            var source = payload.GetProperty("sourceRef").GetString();
            var instance = payload.GetProperty("instance").GetString();
            var version = payload.GetProperty("version").GetInt64();
            if (payload.GetRawText().Length > 512 || fields.Length != 4 || fields.Distinct().Count() != 4 ||
                fields.Except(new[] { "schemaVersion", "sourceRef", "instance", "version" }).Any() ||
                payload.GetProperty("schemaVersion").GetInt32() != 1 || version < -1 ||
                source is null || !Regex.IsMatch(source, "^officialFleet:[1-9][0-9]{0,18}$") ||
                instance is null || !(instance == "" || Guid.TryParseExact(instance, "N", out _))) throw Invalid();
            return (source, instance, version);
        } catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException) { throw Invalid(); }
    }

    internal async Task<object> WaitOfficialActivityAsync(string bearer, JsonElement payload, Action current, CancellationToken token,
        OfficialActivityWaitSession? session = null, TimeSpan? deadline = null)
    {
        var (source, instance, version) = ParseOfficialActivity(payload);
        current();
        session ??= _defaultOfficialWaitSession;
        // One limit for the whole wait: a late 400 must not restart the clock past the client's own.
        var limit = deadline ?? OfficialActivityWaitDeadline;
        var elapsed = System.Diagnostics.Stopwatch.StartNew();
        async Task<JsonElement> Read(int seconds)
        {
            var left = limit - elapsed.Elapsed;
            if (left <= TimeSpan.Zero) throw new AccountBridgeHostException("communities.unavailable", true);
            return await Realtime.ActivityWaitRead.JsonAsync(_officialActivityHttp, _origin, bearer,
            "/api/official-fleets/activity?sourceRef=" + Uri.EscapeDataString(source) +
            "&instance=" + Uri.EscapeDataString(instance) + "&after=" + version + "&waitSeconds=" + seconds,
            status => status switch {
                HttpStatusCode.Unauthorized => new("communities.identityUnavailable"),
                HttpStatusCode.Forbidden => new("communities.notAllowed"),
                HttpStatusCode.BadRequest when seconds == 25 => new("communities.waitDurationRejected"),
                _ => new("communities.unavailable", true) }, Invalid, token, left);
        }
        JsonElement json;
        var seconds = Volatile.Read(ref session.Seconds);
        try { json = await Read(seconds); }
        catch (AccountBridgeHostException error) when (seconds == 25 && error.Code == "communities.waitDurationRejected")
        {
            current(); token.ThrowIfCancellationRequested();
            Interlocked.Exchange(ref session.Seconds, 8);
            json = await Read(8);
        }
        current(); token.ThrowIfCancellationRequested();
        try {
            var fields = json.EnumerateObject().Select(field => field.Name).ToArray();
            var next = json.GetProperty("instanceId").GetString();
            var nextVersion = json.GetProperty("version").GetInt64();
            if (fields.Length != 4 || fields.Distinct().Count() != 4 ||
                fields.Except(new[] { "sourceRef", "instanceId", "version", "serverTime" }).Any() ||
                json.GetProperty("sourceRef").GetString() != source || !Guid.TryParseExact(next, "N", out _) ||
                nextVersion < 0 || next == instance && nextVersion < version ||
                !DateTimeOffset.TryParse(json.GetProperty("serverTime").GetString(), out _)) throw Invalid();
            return new { schemaVersion = 1, sourceRef = source, instance = next, version = nextVersion, chatEvents = true };
        } catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException) { throw Invalid(); }
    }
}
