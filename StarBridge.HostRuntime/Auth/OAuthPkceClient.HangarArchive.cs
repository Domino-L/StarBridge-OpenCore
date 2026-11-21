using System.Net;
using System.Net.Http;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Auth;

/// <summary>Outcome of one account hangar copy request. Unsupported = the server switch is off (404).</summary>
public enum HangarArchiveOutcome { Ok, Conflict, Unsupported, RateLimited, Invalid }

public sealed record HangarArchiveReadResult(HangarArchiveOutcome Outcome, bool Exists, long Revision, JsonElement? Archive);

public sealed record HangarArchiveWriteResult(HangarArchiveOutcome Outcome, long Revision);

public sealed partial class OAuthPkceClient
{
    // The stored archive plus room for server re-serialization and the response wrapper.
    private const int HangarArchiveResponseBytes = 4 * 1024 * 1024;

    private Uri HangarArchiveEndpoint => new(options.ResourceServerBaseUri, "app-api/starbridge/v1/hangar-archive");

    internal Task<(HangarArchiveReadResult Result, ScmOAuthSession ActiveSession)> ReadHangarArchiveAsync(
        ScmOAuthSession session, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null) =>
        SendResourceRequestAsync(session, async (active, ct) => {
            if (!active.Capabilities.Contains("profile.read", StringComparer.Ordinal))
                throw new ScmApiForbiddenException("Hangar archive read requires profile.read.");
            using var request = new HttpRequestMessage(HttpMethod.Get, HangarArchiveEndpoint);
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct,
                completionOption: HttpCompletionOption.ResponseHeadersRead);
            if (Special(response.StatusCode) is { } special) return new HangarArchiveReadResult(special, false, 0, null);
            await ScmHttpClient.EnsureSuccessAsync(response, "Hangar archive read", ct);
            using var document = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, ct, HangarArchiveResponseBytes);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("exists", out var exists) ||
                exists.ValueKind is not (JsonValueKind.True or JsonValueKind.False) ||
                !root.TryGetProperty("revision", out var revision) || !revision.TryGetInt64(out var value) || value < 0)
                throw new ScmApiProtocolException("Hangar archive response is invalid.");
            if (!exists.GetBoolean()) return new HangarArchiveReadResult(HangarArchiveOutcome.Ok, false, value, null);
            if (value < 1 || !root.TryGetProperty("archive", out var archive) || archive.ValueKind != JsonValueKind.Object)
                throw new ScmApiProtocolException("Hangar archive response is invalid.");
            return new HangarArchiveReadResult(HangarArchiveOutcome.Ok, true, value, archive.Clone());
        }, token, sessionReady);

    internal Task<(HangarArchiveWriteResult Result, ScmOAuthSession ActiveSession)> WriteHangarArchiveAsync(
        ScmOAuthSession session, long expectedRevision, byte[] archiveJson, CancellationToken token,
        Action<ScmOAuthSession>? sessionReady = null)
    {
        if (expectedRevision < 0 || archiveJson is null || archiveJson.Length > StarBridge.HostRuntime.Hangar.HangarArchive.MaximumBytes)
            throw new ArgumentException("Invalid hangar archive write.");
        return SendResourceRequestAsync(session, async (active, ct) => {
            if (!active.Capabilities.Contains("profile.write", StringComparer.Ordinal))
                throw new ScmApiForbiddenException("Hangar archive write requires profile.write.");
            using var buffer = new MemoryStream();
            using (var writer = new Utf8JsonWriter(buffer))
            {
                writer.WriteStartObject();
                writer.WriteNumber("expectedRevision", expectedRevision);
                writer.WritePropertyName("archive");
                writer.WriteRawValue(archiveJson, skipInputValidation: false);
                writer.WriteEndObject();
            }
            using var request = new HttpRequestMessage(HttpMethod.Put, HangarArchiveEndpoint)
            { Content = new ByteArrayContent(buffer.ToArray()) };
            request.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct,
                requestTimeout: TimeSpan.FromSeconds(30), completionOption: HttpCompletionOption.ResponseHeadersRead);
            if (response.StatusCode == HttpStatusCode.Conflict)
            {
                using var conflict = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, ct, 4096);
                return conflict.RootElement.TryGetProperty("revision", out var current) && current.TryGetInt64(out var at) && at >= 0
                    ? new HangarArchiveWriteResult(HangarArchiveOutcome.Conflict, at)
                    : throw new ScmApiProtocolException("Hangar archive conflict response is invalid.");
            }
            if (Special(response.StatusCode) is { } special) return new HangarArchiveWriteResult(special, 0);
            await ScmHttpClient.EnsureSuccessAsync(response, "Hangar archive write", ct);
            using var document = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, ct, 4096);
            return document.RootElement.TryGetProperty("revision", out var revision) && revision.TryGetInt64(out var value) &&
                   value == expectedRevision + 1
                ? new HangarArchiveWriteResult(HangarArchiveOutcome.Ok, value)
                : throw new ScmApiProtocolException("Hangar archive write acknowledgement is invalid.");
        }, token, sessionReady);
    }

    internal Task<(HangarArchiveWriteResult Result, ScmOAuthSession ActiveSession)> DeleteHangarArchiveAsync(
        ScmOAuthSession session, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null) =>
        SendResourceRequestAsync(session, async (active, ct) => {
            if (!active.Capabilities.Contains("profile.write", StringComparer.Ordinal))
                throw new ScmApiForbiddenException("Hangar archive delete requires profile.write.");
            using var request = new HttpRequestMessage(HttpMethod.Delete, HangarArchiveEndpoint);
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct,
                completionOption: HttpCompletionOption.ResponseHeadersRead);
            if (Special(response.StatusCode) is { } special) return new HangarArchiveWriteResult(special, 0);
            await ScmHttpClient.EnsureSuccessAsync(response, "Hangar archive delete", ct);
            using var document = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, ct, 4096);
            return document.RootElement.TryGetProperty("deleted", out var deleted) &&
                   deleted.ValueKind is JsonValueKind.True or JsonValueKind.False
                ? new HangarArchiveWriteResult(HangarArchiveOutcome.Ok, 0)
                : throw new ScmApiProtocolException("Hangar archive delete acknowledgement is invalid.");
        }, token, sessionReady);

    private static HangarArchiveOutcome? Special(HttpStatusCode status) => status switch
    {
        HttpStatusCode.NotFound => HangarArchiveOutcome.Unsupported,
        HttpStatusCode.TooManyRequests => HangarArchiveOutcome.RateLimited,
        HttpStatusCode.BadRequest => HangarArchiveOutcome.Invalid,
        _ => null
    };
}
