using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.OfficialFleet;

namespace StarBridge.HostRuntime.Account;

// Public metadata only. The caller must independently authorize affiliation visibility
// before exposing Image. FleetCode is the official affiliation's RSI SID.
internal sealed class PublicOrganizationLogoReader
{
    internal sealed record Logo(long Id, string Sid, string Image);
    private sealed record Entry(Task<Logo?> Pending, DateTimeOffset Expires);
    private static readonly SemaphoreSlim GlobalRequests = new(2, 2);
    // Bounded work (CX-M08): beyond these the logo is simply left out.
    internal const int MaxCachedOrganizations = 256, MaxPendingReads = 16;
    private int _pending;
    private readonly object _gate = new();
    private readonly Dictionary<string, Entry> _entries = new(StringComparer.OrdinalIgnoreCase);
    private readonly Func<string, CancellationToken, Task<JsonDocument>> _read;
    private readonly Func<DateTimeOffset> _now;

    internal PublicOrganizationLogoReader(OAuthPkceClient client)
        : this((sid, token) => client.ReadPublicOrganizationAsync(
            "get?sid=" + Uri.EscapeDataString(sid), token)) { }

    internal PublicOrganizationLogoReader(
        Func<string, CancellationToken, Task<JsonDocument>> read,
        Func<DateTimeOffset>? now = null)
    {
        _read = read;
        _now = now ?? (() => DateTimeOffset.UtcNow);
    }

    // No owner/session/token input. Shared reads have their own bounded lifetime.
    internal Task<Logo?> ReadAsync(string sid)
    {
        sid = sid?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(sid) || sid.Length > 128 || sid.Any(char.IsControl))
            return Task.FromResult<Logo?>(null);
        lock (_gate)
        {
            var now = _now();
            if (_entries.TryGetValue(sid, out var existing) && existing.Expires > now)
                return existing.Pending;
            foreach (var key in _entries.Where(row => row.Value.Expires <= now)
                .Select(row => row.Key).ToArray()) _entries.Remove(key);
            if (_pending >= MaxPendingReads || _entries.Count >= MaxCachedOrganizations)
                return Task.FromResult<Logo?>(null);
            _pending++;
            var completion = new TaskCompletionSource<Logo?>(TaskCreationOptions.RunContinuationsAsynchronously);
            _entries[sid] = new(completion.Task, DateTimeOffset.MaxValue);
            _ = ReadAndCacheAsync(sid, completion);
            return completion.Task;
        }
    }

    private async Task ReadAndCacheAsync(string sid, TaskCompletionSource<Logo?> completion)
    {
        Logo? logo = null;
        try
        {
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(12));
            await GlobalRequests.WaitAsync(deadline.Token).ConfigureAwait(false);
            try
            {
                using var document = await _read(sid, deadline.Token).ConfigureAwait(false);
                var root = document.RootElement;
                var id = OfficialFleetPublicId.Read(root.GetProperty("id"));
                var returnedSid = root.GetProperty("sid").GetString();
                var image = root.GetProperty("image").GetString();
                if (id > 0 && string.Equals(sid, returnedSid?.Trim(), StringComparison.OrdinalIgnoreCase) &&
                    image is { Length: > 0 and <= 2048 } &&
                    Uri.TryCreate(image, UriKind.Absolute, out var uri) &&
                    uri.Scheme == Uri.UriSchemeHttps && uri.UserInfo.Length == 0 && uri.Host.Length > 0)
                    logo = new(id, returnedSid!, image);
            }
            finally { GlobalRequests.Release(); }
        }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or
            InvalidOperationException or KeyNotFoundException or OperationCanceledException or TimeoutException or
            AccountBridgeHostException or ScmApiProtocolException)
        {
            // Optional decoration failure must not fail an authorized profile read.
        }
        finally
        {
            lock (_gate)
            {
                _pending--;
                _entries[sid] = new(completion.Task, _now().Add(logo is null
                    ? TimeSpan.FromMinutes(5) : TimeSpan.FromHours(24)));
            }
            completion.TrySetResult(logo);
        }
    }
}
