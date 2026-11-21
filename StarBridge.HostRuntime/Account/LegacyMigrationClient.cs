using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;

namespace StarBridge.HostRuntime.Account;

/// <summary>What the relay says about this SCM user's old-account migration.</summary>
internal sealed record LegacyMigrationStatus(
    string State, string? LegacyAccountId, int Friends, int Communities, int Merged, string? Reason);

/// <summary>
/// The relay's migration status and retry (MIGRATION-INTERFACE-073 §2, account plan item 9).
/// Both answer 404 while the migration switch is off: that is "not offered", never an error.
/// Reading the status never starts a migration; the next relay session read does.
/// </summary>
internal sealed class LegacyMigrationClient : IDisposable
{
    private const int MaximumBytes = 16 * 1024;
    private readonly Uri _origin;
    private readonly HttpClient _http;

    internal LegacyMigrationClient(Uri origin, HttpMessageHandler? handler = null)
    {
        if (!origin.IsAbsoluteUri || origin.UserInfo.Length != 0 || origin.Query.Length != 0 ||
            origin.Fragment.Length != 0 || (origin.Scheme != "https" && !(origin.Scheme == "http" && origin.IsLoopback)))
            throw new ArgumentException("A trusted Relay origin is required.", nameof(origin));
        _origin = origin;
        _http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(12) };
        // Without the version header the relay treats this as an old client.
        Support.RelayClientVersion.Apply(_http);
    }

    /// <returns>Null when the relay does not offer migration (switch off).</returns>
    internal Task<LegacyMigrationStatus?> ReadAsync(string bearer, CancellationToken token) =>
        SendAsync(HttpMethod.Get, "/api/auth/legacy-migration/status", bearer, token);

    /// <returns>Null when the relay does not offer migration (switch off).</returns>
    internal Task<LegacyMigrationStatus?> RetryAsync(string bearer, CancellationToken token) =>
        SendAsync(HttpMethod.Post, "/api/auth/legacy-migration/retry", bearer, token);

    private async Task<LegacyMigrationStatus?> SendAsync(HttpMethod method, string path, string bearer, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var request = new HttpRequestMessage(method, new Uri(_origin, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
        if (response.StatusCode == HttpStatusCode.NotFound) return null;
        if (response.StatusCode == HttpStatusCode.Unauthorized)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var body = await ReadBodyAsync(response, deadline.Token);
        // Another request of this person is migrating right now (writes answer 409).
        if (response.StatusCode == HttpStatusCode.Conflict && Code(body) == "account_migrating")
            return new("migrating", null, 0, 0, 0, null);
        if (!response.IsSuccessStatusCode) throw new AccountBridgeHostException("account.migration_unavailable", true);
        return Parse(body);
    }

    private static async Task<byte[]> ReadBodyAsync(HttpResponseMessage response, CancellationToken token)
    {
        if (response.Content.Headers.ContentLength is > MaximumBytes) throw Invalid();
        await using var stream = await response.Content.ReadAsStreamAsync(token);
        using var buffer = new MemoryStream();
        var chunk = new byte[4096];
        int count;
        while ((count = await stream.ReadAsync(
            chunk.AsMemory(0, (int)Math.Min(chunk.Length, MaximumBytes + 1 - buffer.Length)), token)) > 0)
        {
            buffer.Write(chunk, 0, count);
            if (buffer.Length > MaximumBytes) throw Invalid();
        }
        return buffer.ToArray();
    }

    private static string? Code(byte[] body)
    {
        try
        {
            using var document = JsonDocument.Parse(body);
            return document.RootElement.ValueKind == JsonValueKind.Object &&
                document.RootElement.TryGetProperty("code", out var code) && code.ValueKind == JsonValueKind.String
                ? code.GetString() : null;
        }
        catch (JsonException) { return null; }
    }

    internal static LegacyMigrationStatus Parse(byte[] body)
    {
        try
        {
            using var document = JsonDocument.Parse(body);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty("schemaVersion", out var version) || version.ValueKind != JsonValueKind.Number ||
                version.GetInt32() != 1) throw Invalid();
            var state = Text(root, "state", 16);
            if (state is not ("none" or "migrating" or "completed" or "failed")) throw Invalid();
            var legacy = Optional(root, "legacyAccountId", 256);
            if ((state == "completed") != !string.IsNullOrWhiteSpace(legacy)) throw Invalid();
            int friends = 0, communities = 0, merged = 0;
            if (root.TryGetProperty("counts", out var counts) && counts.ValueKind != JsonValueKind.Null)
            {
                if (counts.ValueKind != JsonValueKind.Object) throw Invalid();
                friends = Count(counts, "friends");
                communities = Count(counts, "communities");
                merged = Count(counts, "merged");
            }
            var reason = state == "failed" ? Optional(root, "reason", 128) : null;
            return new(state, legacy, friends, communities, merged, reason);
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or FormatException)
        {
            throw Invalid();
        }
    }

    private static string Text(JsonElement root, string name, int limit) =>
        Optional(root, name, limit) ?? throw Invalid();

    private static string? Optional(JsonElement root, string name, int limit)
    {
        if (!root.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null) return null;
        if (value.ValueKind != JsonValueKind.String) throw Invalid();
        var text = value.GetString()!;
        return text.Length > limit ? throw Invalid() : text;
    }

    private static int Count(JsonElement counts, string name)
    {
        if (!counts.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null) return 0;
        if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var number) || number < 0 || number > 1_000_000)
            throw Invalid();
        return number;
    }

    private static AccountBridgeHostException Invalid() => new("account.migration_data_invalid");

    public void Dispose() => _http.Dispose();
}
