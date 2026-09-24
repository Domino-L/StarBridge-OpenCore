using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Profiles;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class LegacyPasswordLoginClient
{
    internal async Task<GameplayTimeResetState> ReadGameplayResetAsync(string accessToken, CancellationToken token)
    {
        using var request = GameplayResetRequest(accessToken, HttpMethod.Get);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        response.EnsureSuccessStatusCode();
        using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 8192);
        ValidateResetJson(json.RootElement);
        var state = json.RootElement.Deserialize<GameplayTimeResetState>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
        ValidateResetState(state);
        token.ThrowIfCancellationRequested();
        return state!;
    }

    internal async Task<GameplayTimeResetResult> ResetGameplayTimeAsync(string accessToken,
        GameplayTimeResetRequest reset, CancellationToken token)
    {
        if (reset.SchemaVersion != 1 || reset.ExpectedRevision < 0 || !Guid.TryParseExact(reset.OperationId, "N", out _))
            throw new ArgumentException("Invalid reset request.");
        using var request = GameplayResetRequest(accessToken, HttpMethod.Post);
        request.Content = JsonContent.Create(reset);
        // Reuse the no-redirect S2 client. Deliberately no retry or authentication replay for POST.
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        if (response.StatusCode is not (HttpStatusCode.OK or HttpStatusCode.Conflict)) response.EnsureSuccessStatusCode();
        using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 8192);
        Profiles.LocalPersonalProfileStore.RejectDuplicates(json.RootElement);
        if (!json.RootElement.TryGetProperty("state", out var stateJson)) throw new JsonException();
        ValidateResetJson(stateJson);
        var result = json.RootElement.Deserialize<GameplayTimeResetResult>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
        ValidateResetState(result?.State);
        var expected = response.StatusCode == HttpStatusCode.Conflict ? "conflict" : "completed";
        if (result!.Outcome != expected || expected == "completed" &&
            (result.State.LastOperationId != reset.OperationId || result.State.LastExpectedRevision != reset.ExpectedRevision ||
             result.State.Revision <= reset.ExpectedRevision)) throw new JsonException("Invalid reset receipt.");
        token.ThrowIfCancellationRequested();
        return result;
    }

    private HttpRequestMessage GameplayResetRequest(string accessToken, HttpMethod method)
    {
        var request = new HttpRequestMessage(method, new Uri(_baseUri, "api/profile/me/gameplay-time-reset"));
        request.Headers.Authorization = new("Bearer", accessToken);
        request.Headers.CacheControl = new() { NoCache = true, NoStore = true };
        return request;
    }

    private static void ValidateResetState(GameplayTimeResetState? state)
    {
        if (state is null || state.SchemaVersion != 1 || state.Revision < 0 || state.PlayTimeSeconds < 0 ||
            state.HistoricalSessionCount < 0 || state.HistoricalIncompleteSessionCount < 0 ||
            state.HistoricalIncompleteSessionCount > state.HistoricalSessionCount ||
            state.HistoricalPlayTimeSeconds < 0 || state.HistoricalPlayTimeSeconds > state.PlayTimeSeconds ||
            state.HistoryImportOperationId is { } historyOperation &&
                (!Guid.TryParseExact(historyOperation, "N", out _) || state.HistoryImportedAt is null) ||
            (state.LastOperationId is null) != (state.LastExpectedRevision is null) ||
            state.LastOperationId is not null && (!Guid.TryParseExact(state.LastOperationId, "N", out _) ||
                state.LastExpectedRevision < 0 || state.LastExpectedRevision >= state.Revision))
            throw new JsonException("Invalid reset state.");
    }

    private static void ValidateResetJson(JsonElement value)
    {
        Profiles.LocalPersonalProfileStore.RejectDuplicates(value);
        if (value.ValueKind != JsonValueKind.Object) throw new JsonException();
        // Required even when null: an older server cannot provide import recovery
        // evidence, so it must not authorize a new versioned history upload.
        if (!value.TryGetProperty("historyImportOperationId", out _) ||
            !value.TryGetProperty("observedAt", out var observed) || !observed.TryGetDateTimeOffset(out _) ||
            !value.TryGetProperty("historicalSessionCount", out var sessions) || !sessions.TryGetInt32(out _) ||
            !value.TryGetProperty("historicalIncompleteSessionCount", out var incomplete) || !incomplete.TryGetInt32(out _) ||
            !value.TryGetProperty("isPublic", out var visibility) || visibility.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            throw new JsonException();
        foreach (var field in new[] { "schemaVersion", "revision", "playTimeSeconds", "historicalPlayTimeSeconds" })
            if (!value.TryGetProperty(field, out var number) || !number.TryGetInt64(out _)) throw new JsonException();
    }
}
