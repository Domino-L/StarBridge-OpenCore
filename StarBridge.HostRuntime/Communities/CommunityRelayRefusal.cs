using System.Net;
using System.Text.Json;

namespace StarBridge.HostRuntime.Communities;

/// <summary>
/// Two relay refusals of community writes that the client explains instead of reporting an
/// uncertain or misleading outcome: 428 (the SCM account has not verified its game identity)
/// and a 409 whose body names <c>IDENTITY_AMBIGUOUS</c> (a name in the organization maps to
/// several accounts). Only the code is read; the relay's message text is not forwarded.
/// Any other 409 keeps the caller's existing meaning, and so does a body that cannot be
/// read within its own short timeout: the status already arrived, so the caller's own
/// mapping still applies. A cancellation by the caller (user cancel, app exit) is not a
/// timeout and keeps propagating.
/// </summary>
internal static class CommunityRelayRefusal
{
    internal const string IdentityRequired = "identityRequired";
    internal const string IdentityAmbiguous = "identityAmbiguous";
    private const int BodyLimit = 4096;
    private static readonly TimeSpan BodyTimeout = TimeSpan.FromSeconds(5);

    /// <param name="callerToken">The caller's own cancellation, not a deadline derived from it.</param>
    internal static async Task<string?> ReasonAsync(HttpResponseMessage response, CancellationToken callerToken,
        TimeSpan? bodyTimeout = null)
    {
        if (response.StatusCode == HttpStatusCode.PreconditionRequired) return IdentityRequired;
        if (response.StatusCode != HttpStatusCode.Conflict) return null;
        if (response.Content.Headers.ContentLength is > BodyLimit) return null;
        byte[] body;
        using var reading = CancellationTokenSource.CreateLinkedTokenSource(callerToken);
        reading.CancelAfter(bodyTimeout ?? BodyTimeout);
        var token = reading.Token;
        try
        {
            await using var stream = await response.Content.ReadAsStreamAsync(token);
            using var buffer = new MemoryStream();
            var chunk = new byte[1024];
            int count;
            // Never ask for more than one byte past the limit, so at most BodyLimit + 1
            // bytes are read even without a Content-Length.
            while ((count = await stream.ReadAsync(
                chunk.AsMemory(0, (int)Math.Min(chunk.Length, BodyLimit + 1 - buffer.Length)), token)) > 0)
            {
                buffer.Write(chunk, 0, count);
                if (buffer.Length > BodyLimit) return null;
            }
            body = buffer.ToArray();
        }
        catch (Exception error) when (error is IOException or HttpRequestException ||
            error is OperationCanceledException && !callerToken.IsCancellationRequested)
        {
            return null;
        }
        try
        {
            using var document = JsonDocument.Parse(body);
            var root = document.RootElement;
            return root.ValueKind == JsonValueKind.Object &&
                root.TryGetProperty("code", out var code) &&
                code.ValueKind == JsonValueKind.String &&
                code.ValueEquals("IDENTITY_AMBIGUOUS")
                ? IdentityAmbiguous
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
