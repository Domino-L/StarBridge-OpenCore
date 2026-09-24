namespace StarBridge.HostRuntime.Friends;

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.HostRuntime.Account;

internal sealed record RecentlyPlayedPrivacyView(
    bool Enabled,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? EnabledAt,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? DisabledAt,
    long Revision)
{
    public int SchemaVersion => 1;
}

internal sealed record RecentlyPlayedPrivacyWrite(bool Enabled, long ExpectedRevision);

internal sealed partial class FriendsReader
{
    internal static void ParseRecentlyPlayedPrivacyRead(JsonElement payload)
    {
        try
        {
            var names = payload.EnumerateObject().Select(property => property.Name).ToArray();
            if (names.Length != 1 || names[0] != "schemaVersion" ||
                payload.GetProperty("schemaVersion").GetInt32() != 1)
                throw RecentlyPlayedPrivacyError("invalid_request");
        }
        catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException)
        {
            throw RecentlyPlayedPrivacyError("invalid_request");
        }
    }

    internal static RecentlyPlayedPrivacyWrite ParseRecentlyPlayedPrivacyWrite(JsonElement payload)
    {
        try
        {
            var names = payload.EnumerateObject().Select(property => property.Name).ToArray();
            if (names.Length != 3 || names.Distinct().Count() != names.Length ||
                names.Any(name => name is not ("schemaVersion" or "enabled" or "expectedRevision")) ||
                payload.GetProperty("schemaVersion").GetInt32() != 1)
                throw RecentlyPlayedPrivacyError("invalid_request");
            var revision = payload.GetProperty("expectedRevision").GetInt64();
            if (revision < 0) throw RecentlyPlayedPrivacyError("invalid_request");
            return new RecentlyPlayedPrivacyWrite(
                payload.GetProperty("enabled").GetBoolean(),
                revision);
        }
        catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or
                                      FormatException or OverflowException)
        {
            throw RecentlyPlayedPrivacyError("invalid_request");
        }
    }

    internal Task<RecentlyPlayedPrivacyView> ReadRecentlyPlayedPrivacyAsync(
        string bearer,
        CancellationToken token) =>
        SendRecentlyPlayedPrivacyAsync(bearer, write: null, token);

    internal Task<RecentlyPlayedPrivacyView> SaveRecentlyPlayedPrivacyAsync(
        string bearer,
        RecentlyPlayedPrivacyWrite write,
        CancellationToken token,
        Action ensureCurrent) =>
        SendRecentlyPlayedPrivacyAsync(bearer, write, token, ensureCurrent);

    private async Task<RecentlyPlayedPrivacyView> SendRecentlyPlayedPrivacyAsync(
        string bearer,
        RecentlyPlayedPrivacyWrite? write,
        CancellationToken token,
        Action? ensureCurrent = null)
    {
        var writing = write is not null;
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var request = new HttpRequestMessage(
            writing ? HttpMethod.Post : HttpMethod.Get,
            new Uri(_origin, "/api/friends/recently-played/privacy"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        if (write is not null)
        {
            ensureCurrent?.Invoke();
            request.Content = JsonContent.Create(new
            {
                write.Enabled,
                write.ExpectedRevision
            });
        }

        try
        {
            using var response = await _http.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                deadline.Token);
            if (response.StatusCode == HttpStatusCode.Unauthorized)
                throw RecentlyPlayedPrivacyError("identity_unavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden)
                throw RecentlyPlayedPrivacyError("forbidden");
            if (response.StatusCode == HttpStatusCode.Conflict)
                throw RecentlyPlayedPrivacyError("write_conflict");
            if (!response.IsSuccessStatusCode)
                throw RecentlyPlayedPrivacyError(writing ? "privacy_outcome_unknown" : "privacy_unavailable");

            using var document = JsonDocument.Parse(await CommandBody(response, deadline.Token));
            RejectDuplicates(document.RootElement);
            var result = ParseRecentlyPlayedPrivacyResponse(document.RootElement);
            if (write is not null &&
                (result.Enabled != write.Enabled || result.Revision < write.ExpectedRevision))
                throw RecentlyPlayedPrivacyError("privacy_outcome_unknown");
            return result;
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        {
            throw RecentlyPlayedPrivacyError(writing ? "privacy_outcome_unknown" : "privacy_unavailable");
        }
        catch (Exception error) when (error is HttpRequestException or IOException)
        {
            throw RecentlyPlayedPrivacyError(writing ? "privacy_outcome_unknown" : "privacy_unavailable");
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or
                                      FormatException or KeyNotFoundException or OverflowException)
        {
            throw RecentlyPlayedPrivacyError(writing ? "privacy_outcome_unknown" : "data_invalid");
        }
    }

    private static RecentlyPlayedPrivacyView ParseRecentlyPlayedPrivacyResponse(JsonElement root)
    {
        var names = root.EnumerateObject().Select(property => property.Name).ToArray();
        if (names.Length != 4 || names.Distinct().Count() != names.Length ||
            names.Any(name => name is not ("enabled" or "enabledAt" or "disabledAt" or "revision")))
            throw new FormatException();
        var revision = root.GetProperty("revision").GetInt64();
        if (revision < 0) throw new FormatException();
        return new RecentlyPlayedPrivacyView(
            root.GetProperty("enabled").GetBoolean(),
            OptionalDate(root.GetProperty("enabledAt")),
            OptionalDate(root.GetProperty("disabledAt")),
            revision);
    }

    private static DateTimeOffset? OptionalDate(JsonElement value) =>
        value.ValueKind == JsonValueKind.Null ? null : value.GetDateTimeOffset();

    private static AccountBridgeHostException RecentlyPlayedPrivacyError(string code) =>
        new("recentlyPlayed." + code);
}
