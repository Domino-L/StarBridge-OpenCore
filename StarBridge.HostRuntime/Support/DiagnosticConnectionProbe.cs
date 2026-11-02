using System.Net.Http;
using System.Text.Json;

namespace StarBridge.HostRuntime.Support;

internal static class DiagnosticConnectionProbe
{
    internal static async Task<ApplicationSupportCheck> CheckAsync(Uri origin, CancellationToken cancellationToken,
        HttpMessageHandler? transport = null, Lifecycle.DeviceNetworkAdmission? network = null)
    {
        using var work = network?.Enter(cancellationToken);
        if (network is not null && work is null) return new(ApplicationSupportStates.Unavailable, "connectionPaused");
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, work?.Token ?? CancellationToken.None);
            deadline.CancelAfter(TimeSpan.FromSeconds(6));
            cancellationToken = deadline.Token;
            using var handler = transport ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false };
            using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(6) };
            using var response = await client.GetAsync(new Uri(origin.AbsoluteUri.TrimEnd('/') + "/health"),
                HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            if (!response.IsSuccessStatusCode) return new(ApplicationSupportStates.ActionRequired, "connectionFailed");
            using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var bytes = new MemoryStream();
            var buffer = new byte[1024]; int read;
            while ((read = await content.ReadAsync(buffer, cancellationToken)) != 0)
            {
                if (bytes.Length + read > 4096) return new(ApplicationSupportStates.Unavailable, "connectionUnavailable");
                bytes.Write(buffer, 0, read);
            }
            work?.RequireCurrent();
            cancellationToken.ThrowIfCancellationRequested();
            string? status = null;
            try
            {
                using var payload = JsonDocument.Parse(bytes.ToArray());
                if (payload.RootElement.TryGetProperty("status", out var item) && item.ValueKind == JsonValueKind.String)
                    status = item.GetString()?.ToLowerInvariant();
            }
            catch (JsonException) { /* WPF also accepts legacy successful health responses. */ }
            var healthy = status is not ("unhealthy" or "degraded");
            work?.RequireCurrent();
            return new(healthy ? ApplicationSupportStates.Healthy : ApplicationSupportStates.ActionRequired,
                healthy ? "connectionHealthy" : "connectionFailed");
        }
        catch { return new(ApplicationSupportStates.Unavailable, work?.IsCurrent == false ? "connectionPaused" : "connectionUnavailable"); }
    }
}
