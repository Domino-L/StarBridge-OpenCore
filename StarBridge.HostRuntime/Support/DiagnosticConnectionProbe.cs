using System.Net.Http;
using System.Text.Json;

namespace StarBridge.HostRuntime.Support;

internal static class DiagnosticConnectionProbe
{
    internal static async Task<ApplicationSupportCheck> CheckAsync(Uri origin, CancellationToken cancellationToken,
        HttpMessageHandler? transport = null)
    {
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            deadline.CancelAfter(TimeSpan.FromSeconds(6));
            cancellationToken = deadline.Token;
            using var handler = transport ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false };
            using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(6) };
            using var response = await client.GetAsync(new Uri(origin.AbsoluteUri.TrimEnd('/') + "/health"),
                HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            if (!response.IsSuccessStatusCode) return new(ApplicationSupportStates.ActionRequired, "connectionFailed");
            await response.Content.LoadIntoBufferAsync(4096).WaitAsync(cancellationToken);
            string? status = null;
            try
            {
                using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
                if (payload.RootElement.TryGetProperty("status", out var item) && item.ValueKind == JsonValueKind.String)
                    status = item.GetString()?.ToLowerInvariant();
            }
            catch (JsonException) { /* WPF also accepts legacy successful health responses. */ }
            var healthy = status is not ("unhealthy" or "degraded");
            return new(healthy ? ApplicationSupportStates.Healthy : ApplicationSupportStates.ActionRequired,
                healthy ? "connectionHealthy" : "connectionFailed");
        }
        catch { return new(ApplicationSupportStates.Unavailable, "connectionUnavailable"); }
    }
}
