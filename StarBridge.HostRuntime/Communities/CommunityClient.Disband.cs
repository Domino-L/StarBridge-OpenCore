using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record DisbandConfirmation(string Code, string TargetRef, string Scope, string Version, DateTimeOffset Expires);
    private readonly ConcurrentDictionary<string, DisbandConfirmation> _disbandConfirmations = new();

    internal Task<object> ReadDisbandAsync(string bearer, JsonElement body, string scope, Action current, CancellationToken token) =>
        GuardWorkspace(async () =>
        {
            Validate(body, "targetRef");
            current();
            var targetRef = Text(body, "targetRef", 32);
            var target = Resolve(targetRef, scope);
            var root = await WorkspaceJson(bearer, "/api/fleets/disband-preview?code=" + Uri.EscapeDataString(target.Code), token);
            if (Encoding.UTF8.GetByteCount(root.GetRawText()) > 16 * 1024 || Number(root, "schemaVersion", 1, 1) != 1 ||
                Text(root, "code", 256) != target.Code || Text(root, "credentialMode", 32) != "legacyPassword" ||
                root.EnumerateObject().Select(p => p.Name).Distinct().Count() != root.EnumerateObject().Count()) throw Invalid();
            var name = Text(root, "name", 512);
            var version = Text(root, "version", 64);
            if (string.IsNullOrWhiteSpace(name) || !LowerHex(version, 64)) throw Invalid();
            var memberCount = Number(root, "memberCount", 0, 100000);
            var canDisband = root.GetProperty("canDisband").GetBoolean();
            token.ThrowIfCancellationRequested();
            current();
            foreach (var old in _disbandConfirmations.Where(p => p.Value.Expires <= DateTimeOffset.UtcNow ||
                         p.Value.Code == target.Code && p.Value.Scope == scope).ToArray())
                _disbandConfirmations.TryRemove(old.Key, out _);
            if (_disbandConfirmations.Count >= 128) throw new AccountBridgeHostException("communities.refreshRequired");
            var confirmationRef = Guid.NewGuid().ToString("N");
            if (canDisband) _disbandConfirmations[confirmationRef] = new(target.Code, targetRef, scope, version, DateTimeOffset.UtcNow.AddMinutes(5));
            return new { schemaVersion = 1, targetRef, confirmationRef, name, memberCount, canDisband, credentialMode = "legacyPassword" };
        });

    private static bool LowerHex(string value, int length) => value.Length == length && value.All(c => c is >= 'a' and <= 'f' or >= '0' and <= '9');

    internal static void ValidateDisband(JsonElement body)
    {
        Validate(body, "targetRef", "confirmationRef", "password");
        try
        {
            if (!LowerHex(Text(body, "targetRef", 32), 32) || !LowerHex(Text(body, "confirmationRef", 32), 32)) throw Invalid();
            var password = body.GetProperty("password").GetString();
            // Preserve the credential exactly. Never trim, cache or include it in an idempotency key.
            if (string.IsNullOrWhiteSpace(password) || password.Length > 4096) throw Invalid();
        }
        catch (Exception e) when (e is InvalidOperationException or KeyNotFoundException or JsonException) { throw Invalid(); }
    }

    internal async Task<object> DisbandAsync(string bearer, JsonElement body, string scope, Action current, CancellationToken token)
    {
        ValidateDisband(body);
        var targetRef = Text(body, "targetRef", 32);
        var confirmationRef = Text(body, "confirmationRef", 32);
        var target = Resolve(targetRef, scope);
        if (!_disbandConfirmations.TryGetValue(confirmationRef, out var entry) || entry.Scope != scope ||
            entry.TargetRef != targetRef || entry.Code != target.Code || entry.Expires <= DateTimeOffset.UtcNow)
            return new CommunityCommand("rejected", "refreshRequired");
        if (!await _write.WaitAsync(0, token)) return new CommunityCommand("rejected", "busy");
        var sent = false;
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            current();
            token.ThrowIfCancellationRequested();
            if (!_disbandConfirmations.TryRemove(confirmationRef, out _)) return new CommunityCommand("rejected", "refreshRequired");
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin,
                "/api/fleets/disband?projection=disband&version=" + entry.Version))
            { Content = JsonContent.Create(new { fleetCode = entry.Code, password = body.GetProperty("password").GetString() }) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            if (response.StatusCode != HttpStatusCode.OK)
                return new CommunityCommand(response.StatusCode is HttpStatusCode.BadRequest or HttpStatusCode.Unauthorized or
                    HttpStatusCode.Forbidden or HttpStatusCode.NotFound or HttpStatusCode.Conflict ? "rejected" : "unknown",
                    response.StatusCode switch
                    {
                        HttpStatusCode.BadRequest => "passwordInvalid",
                        HttpStatusCode.Unauthorized => "identityUnavailable",
                        HttpStatusCode.Forbidden => "notAllowed",
                        HttpStatusCode.NotFound or HttpStatusCode.Conflict => "refreshRequired",
                        _ => "outcomeUnknown"
                    });
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            var buffer = new byte[1025];
            var length = 0;
            int count;
            while (length < buffer.Length && (count = await stream.ReadAsync(buffer.AsMemory(length), deadline.Token)) > 0) length += count;
            if (length > 1024) return new CommunityCommand("unknown", "outcomeUnknown");
            using var receipt = JsonDocument.Parse(buffer.AsMemory(0, length));
            var root = receipt.RootElement;
            if (root.EnumerateObject().Count() != 2 || Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "status", 16) != "accepted")
                return new CommunityCommand("unknown", "outcomeUnknown");
            current();
            return new CommunityCommand("accepted");
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or AccountBridgeHostException or
            StarBridge.NativeBridge.BridgeStaleGenerationException)
        { return new CommunityCommand(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired"); }
        finally { _write.Release(); }
    }
}
