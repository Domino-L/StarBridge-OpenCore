using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace StarBridge.HostRuntime.Account;

internal sealed record DailySupportGrant(string Entitlement, DateTimeOffset ExpiresAt);
internal sealed record DailySupportReceipt(string Id, string LocalDay, string? Entitlement, DateTimeOffset? ExpiresAt);
internal sealed record DailySupportView(int SchemaVersion, string Outcome, DailySupportReceipt? Receipt,
    DailySupportGrant[] TemporaryEntitlements);

internal sealed class DailySupportClient : IDisposable
{
    private readonly HttpClient http;
    private readonly Uri endpoint;
    internal DailySupportClient(Uri origin, HttpMessageHandler? handler = null)
    {
        if (!origin.IsAbsoluteUri || origin.UserInfo.Length != 0 || origin.Query.Length != 0 || origin.Fragment.Length != 0 ||
            (origin.Scheme != "https" && !(origin.Scheme == "http" && origin.IsLoopback)))
            throw new ArgumentException("Trusted Relay origin required.");
        endpoint = new Uri(origin, "/api/support/daily");
        http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false })
            { Timeout = TimeSpan.FromSeconds(15) };
    }
    internal async Task<DailySupportView> SendAsync(string bearer, int? offsetMinutes, CancellationToken token)
    {
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
        budget.CancelAfter(TimeSpan.FromSeconds(15));
        token = budget.Token;
        using var request = new HttpRequestMessage(offsetMinutes.HasValue ? HttpMethod.Post : HttpMethod.Get, endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        if (offsetMinutes.HasValue) request.Content = JsonContent.Create(new { utcOffsetMinutes = offsetMinutes.Value });
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        if (!response.IsSuccessStatusCode) throw new AccountBridgeHostException("support.unavailable");
        using var stream = await response.Content.ReadAsStreamAsync(token);
        using var buffer = new MemoryStream();
        var chunk = new byte[4096];
        int read;
        while ((read = await stream.ReadAsync(chunk, token)) > 0)
        {
            if (buffer.Length + read > 65536) throw new AccountBridgeHostException("support.invalid_response");
            buffer.Write(chunk, 0, read);
        }
        return Parse(buffer.ToArray());
    }
    internal static DailySupportView Parse(byte[] bytes)
    {
        var view = JsonSerializer.Deserialize<DailySupportView>(bytes, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        if (view is null || view.SchemaVersion != 1 ||
            view.Outcome is not ("ready" or "granted" or "thanked" or "alreadyClaimed") ||
            view.TemporaryEntitlements is null || view.TemporaryEntitlements.Length > 128 ||
            view.TemporaryEntitlements.Any(g => g is null || !ValidEntitlement(g.Entitlement) || g.ExpiresAt == default) ||
            view.Receipt is { } r && (string.IsNullOrEmpty(r.Id) || r.Id.Length > 64 ||
                !DateOnly.TryParseExact(r.LocalDay, "yyyy-MM-dd", out _) ||
                (r.Entitlement is null) != (r.ExpiresAt is null) || r.Entitlement is not null && !ValidEntitlement(r.Entitlement)) ||
            view.Outcome != "ready" && view.Receipt is null ||
            view.Outcome == "granted" && view.Receipt?.Entitlement is null ||
            view.Outcome == "thanked" && view.Receipt?.Entitlement is not null)
            throw new AccountBridgeHostException("support.invalid_response");
        return view;
    }
    private static bool ValidEntitlement(string? value) => value is { Length: > 13 and <= 128 } &&
        value.StartsWith("overlay.skin.", StringComparison.Ordinal) && !value.Any(c => char.IsWhiteSpace(c) || char.IsControl(c));
    public void Dispose() => http.Dispose();
}
