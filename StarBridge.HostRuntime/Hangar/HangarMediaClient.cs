using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.ShipMedia;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Hangar;

/// <summary>Host-only media transport. Callers supply authenticated ownership and
/// an explicit prepared image, never a path or bearer received from Flutter.</summary>
internal sealed class HangarMediaClient : IDisposable
{
    private readonly HttpClient _http;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    internal HangarMediaClient(Uri origin, HttpMessageHandler? handler = null)
    {
        if (!origin.IsAbsoluteUri || origin.UserInfo.Length != 0 || origin.Query.Length != 0 || origin.Fragment.Length != 0 ||
            origin.Scheme != "https" && !(origin.Scheme == "http" && origin.IsLoopback))
            throw new ArgumentException("Trusted origin required.");
        _http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false }) { BaseAddress = origin, Timeout = TimeSpan.FromSeconds(12) };
    }

    internal async Task<ShipMediaSummaryContract[]> ReadAsync(string bearer, string owner, Action current, CancellationToken token)
        => await Execute(false, current, token, async deadline => await ReadCoreAsync(bearer, owner, current, deadline));

    private async Task<ShipMediaSummaryContract[]> ReadCoreAsync(string bearer, string owner, Action current, CancellationToken token)
    {
        using var response = await Send(HttpMethod.Get, "/api/ship-media/mine", bearer, null, current, token);
        using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 4 * 1024 * 1024);
        var catalog = json.RootElement.Deserialize<ShipMediaCatalogContract>(Json);
        if (catalog?.Items is not { Length: <= 20000 } rows || rows.Any(row => !Valid(row, owner)) ||
            rows.Select(row => row.MediaId).Distinct(StringComparer.Ordinal).Count() != rows.Length)
            throw new AccountBridgeHostException("hangar.image_invalid_response");
        current(); token.ThrowIfCancellationRequested();
        return rows;
    }

    internal async Task<ShipMediaSummaryContract> UploadAsync(string bearer, string owner, ShipMediaUploadRequestContract image,
        Action current, CancellationToken token)
        => await Execute(true, current, token, async deadline => await UploadCoreAsync(bearer, owner, image, current, deadline));

    private async Task<ShipMediaSummaryContract> UploadCoreAsync(string bearer, string owner, ShipMediaUploadRequestContract image,
        Action current, CancellationToken token)
    {
        if (!Guid.TryParseExact(image.ClientRequestId, "N", out _) || string.IsNullOrWhiteSpace(image.ShipInstanceId) ||
            image.ShipInstanceId.Length > 128 || string.IsNullOrWhiteSpace(image.ShipCode) || image.ShipCode.Length > 160 ||
            image.ImageBase64.Length > ((ShipMediaPolicy.MaximumImageBytes + 2) / 3 * 4))
            throw new AccountBridgeHostException("hangar.invalid_request");
        using var response = await Send(HttpMethod.Post, "/api/ship-media", bearer, image, current, token);
        using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 32 * 1024);
        var result = json.RootElement.Deserialize<ShipMediaUploadResponseContract>(Json);
        if (result is null || result.Status is not ("uploaded" or "unchanged") || !Valid(result.Media, owner) ||
            result.Media.ShipInstanceId != image.ShipInstanceId || !string.Equals(result.Media.ShipCode, image.ShipCode, StringComparison.OrdinalIgnoreCase))
            throw new AccountBridgeHostException("hangar.image_outcome_unknown");
        current(); token.ThrowIfCancellationRequested();
        return result.Media;
    }

    internal async Task DeleteAsync(string bearer, string mediaId, Action current, CancellationToken token)
        => await Execute(true, current, token, async deadline => { await DeleteCoreAsync(bearer, mediaId, current, deadline); return true; });

    private async Task DeleteCoreAsync(string bearer, string mediaId, Action current, CancellationToken token)
    {
        if (!Guid.TryParseExact(mediaId, "N", out _)) throw new AccountBridgeHostException("hangar.invalid_request");
        using var response = await Send(HttpMethod.Delete, "/api/ship-media/" + mediaId, bearer, null, current, token);
        if (response.StatusCode != HttpStatusCode.NoContent) throw new AccountBridgeHostException("hangar.image_outcome_unknown");
        current(); token.ThrowIfCancellationRequested();
    }

    // The deadline includes response-body reads, which HttpClient's HeadersRead timeout does not.
    // A failed write may already have committed: never retry it automatically or report a definite failure.
    private static async Task<T> Execute<T>(bool write, Action current, CancellationToken token,
        Func<CancellationToken, Task<T>> operation)
    {
        current(); token.ThrowIfCancellationRequested();
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        try { return await operation(deadline.Token); }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or OperationCanceledException)
        {
            current(); token.ThrowIfCancellationRequested();
            throw new AccountBridgeHostException(write ? "hangar.image_outcome_unknown" :
                error is JsonException ? "hangar.image_invalid_response" : "hangar.image_unavailable");
        }
    }

    private async Task<HttpResponseMessage> Send(HttpMethod method, string path, string bearer, object? body, Action current, CancellationToken token)
    {
        current(); token.ThrowIfCancellationRequested();
        using var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        if (body is not null) request.Content = JsonContent.Create(body);
        var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        if (response.IsSuccessStatusCode) return response;
        var status = response.StatusCode;
        response.Dispose();
        throw new AccountBridgeHostException(status switch {
            HttpStatusCode.Unauthorized => "hangar.identity_unavailable", HttpStatusCode.Forbidden => "hangar.image_not_allowed",
            HttpStatusCode.BadRequest => "hangar.image_invalid", HttpStatusCode.TooManyRequests => "hangar.image_rate_limited",
            _ => method == HttpMethod.Get ? "hangar.image_unavailable" : "hangar.image_outcome_unknown" });
    }

    private static bool Valid(ShipMediaSummaryContract? row, string owner) => row is not null && row.OwnerAccountId == owner &&
        Guid.TryParseExact(row.MediaId, "N", out _) && row.ShipInstanceId is { Length: > 0 and <= 160 } &&
        row.ShipCode is { Length: > 0 and <= 160 } && row.SizeBytes is > 0 and <= ShipMediaPolicy.MaximumImageBytes &&
        row.Width is > 0 and <= ShipMediaPolicy.MaximumDimension && row.Height is > 0 and <= ShipMediaPolicy.MaximumDimension;
    public void Dispose() => _http.Dispose();
}
