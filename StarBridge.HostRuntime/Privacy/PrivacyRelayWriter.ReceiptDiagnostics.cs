using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Privacy;

internal sealed partial class PrivacyRelayWriter
{
    internal Action<string, string, int, string, long?, string?>? ReceiptDiagnostic { get; set; }

    private async Task ObservePublicationReceiptAsync(HttpResponseMessage response, Func<Task> validate,
        string stage = "publication-receipt")
    {
        try { await validate(); }
        catch (Exception error) when (error is JsonException or AccountBridgeHostException { Code: "privacy_publication.response_invalid" })
        {
            RecordPublicationReceipt(response, stage, "privacy_publication.response_invalid", error);
            throw;
        }
    }

    private async Task<T> ObservePublicationReceiptAsync<T>(HttpResponseMessage response, Func<Task<T>> validate, string stage)
    {
        T result = default!;
        await ObservePublicationReceiptAsync(response, async () => { result = await validate(); }, stage);
        return result;
    }

    private void RecordPublicationReceipt(HttpResponseMessage response, string stage, string code, Exception error)
    {
        try
        {
            // Preflight GETs use ResponseHeadersRead; only writes are buffered.
            // Inspect existing metadata only; never read or log body contents.
            var mediaType = response.Content.Headers.ContentType?.MediaType;
            var category = mediaType?.ToLowerInvariant() switch
            {
                null => "none",
                "application/json" or "text/json" => "json",
                "text/html" or "application/xhtml+xml" => "html",
                var value when value.EndsWith("+json", StringComparison.Ordinal) => "json",
                var value when value.StartsWith("text/", StringComparison.Ordinal) => "text",
                _ => "other"
            };
            var field = error.Data[ReceiptMismatchKey] as string;
            ReceiptDiagnostic?.Invoke(stage, code, (int)response.StatusCode, category, response.Content.Headers.ContentLength,
                IsReceiptField(field) ? field : null);
        }
        catch { /* Metadata and journal failures cannot affect publication. */ }
    }
}
