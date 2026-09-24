namespace StarBridge.HostRuntime.Account;

using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using StarBridge.Core.TrustSafety;

internal sealed record AccountSafetySanction(string SanctionId, string Type, string Summary,
    DateTimeOffset IssuedAt, DateTimeOffset? ExpiresAt, DateTimeOffset? RevokedAt);
internal sealed record AccountSafetyView(AccountSafetySanction[] Sanctions,
    SanctionAppealRecordContract[] Appeals, string[] Restrictions, DateTimeOffset UpdatedAt)
{
    public int SchemaVersion => 1;
}

// Existing S2 endpoints and contracts; authentication remains owned by ScmAccountBridgeHost.
internal sealed partial class AccountSafetyClient : IDisposable
{
    internal const int MaximumBytes = 2 * 1024 * 1024;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private readonly Uri _origin;
    private readonly HttpClient _http;

    internal AccountSafetyClient(Uri origin, HttpMessageHandler? handler = null)
    {
        if (!origin.IsAbsoluteUri || origin.UserInfo.Length != 0 || origin.Query.Length != 0 ||
            origin.Fragment.Length != 0 || (origin.Scheme != "https" && !(origin.Scheme == "http" && origin.IsLoopback)))
            throw new ArgumentException("A trusted Relay origin is required.", nameof(origin));
        _origin = origin;
        _http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(12) };
    }

    internal async Task<AccountSafetyView> ReadAsync(string bearer, CancellationToken token)
    {
        var status = GetAsync("/api/trust-safety/status", bearer, token);
        var appeals = GetAsync("/api/appeals/mine", bearer, token);
        await Task.WhenAll(status, appeals);
        token.ThrowIfCancellationRequested();
        return Parse(await status, await appeals);
    }

    private async Task<byte[]> GetAsync(string path, string bearer, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_origin, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        try
        {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode == HttpStatusCode.Unauthorized) throw new AccountBridgeHostException("accountSafety.identity_unavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden) throw new AccountBridgeHostException("accountSafety.forbidden");
            if (!response.IsSuccessStatusCode) throw new AccountBridgeHostException("accountSafety.read_unavailable", true);
            if (response.Content.Headers.ContentLength > MaximumBytes) throw Invalid();
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var buffer = new MemoryStream();
            var chunk = new byte[8192];
            int count;
            while ((count = await stream.ReadAsync(chunk, deadline.Token)) != 0)
            {
                if (buffer.Length + count > MaximumBytes) throw Invalid();
                buffer.Write(chunk, 0, count);
            }
            return buffer.ToArray();
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        { throw new AccountBridgeHostException("accountSafety.read_unavailable", true); }
        catch (Exception error) when (error is HttpRequestException or IOException)
        { throw new AccountBridgeHostException("accountSafety.read_unavailable", true); }
    }

    internal static AccountSafetyView Parse(byte[] statusBytes, byte[] appealBytes)
    {
        try
        {
            using var statusDoc = Document(statusBytes);
            using var appealDoc = Document(appealBytes);
            var root = statusDoc.RootElement;
            // Required S2 booleans must not default a malformed response to a healthy account.
            foreach (var name in new[] { "chatRestricted", "socialRestricted", "accountRestricted" })
                _ = root.GetProperty(name).GetBoolean();
            _ = root.GetProperty("updatedAt").GetDateTimeOffset();
            _ = appealDoc.RootElement.GetProperty("updatedAt").GetDateTimeOffset();
            var status = root.Deserialize<TrustSafetyAccountStatusContract>(Json) ?? throw Invalid();
            var appeals = appealDoc.RootElement.Deserialize<MySanctionAppealsContract>(Json) ?? throw Invalid();
            if (status.ActiveSanctions is null || appeals.Appeals is null ||
                status.ActiveSanctions.Length > 2000 || appeals.Appeals.Length > 2000) throw Invalid();
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (var item in status.ActiveSanctions)
            {
                if (item is null || !ValidText(item.SanctionId, 256) || !ids.Add(item.SanctionId) ||
                    !ValidText(item.Type, 128) || !ValidText(item.Summary, 4000, true) || item.IssuedAt == default) throw Invalid();
            }
            ids.Clear();
            foreach (var item in appeals.Appeals)
            {
                if (item is null || !ValidText(item.AppealId, 256) || !ids.Add(item.AppealId) ||
                    !ValidText(item.SanctionId, 256) || !ValidText(item.SanctionType, 128) ||
                    !ValidText(item.Details, SanctionAppealValidation.MaximumDetailsLength, true) ||
                    !ValidText(item.Status, 128) || item.CreatedAt == default || item.UpdatedAt == default ||
                    (item.OutcomeSummary is not null && !ValidText(item.OutcomeSummary, 4000, true))) throw Invalid();
            }
            var restrictions = new List<string>();
            if (status.ChatRestricted) restrictions.Add(AccountSanctionTypes.ChatMute);
            if (status.SocialRestricted) restrictions.Add(AccountSanctionTypes.SocialRestriction);
            if (status.AccountRestricted) restrictions.Add(AccountSanctionTypes.AccountRestriction);
            if (status.ProfileRestricted) restrictions.Add(AccountSanctionTypes.ProfileRestriction);
            if (status.RoomCreationRestricted) restrictions.Add(AccountSanctionTypes.RoomCreationRestriction);
            if (status.RoomParticipationRestricted) restrictions.Add(AccountSanctionTypes.RoomParticipationRestriction);
            if (status.FleetParticipationRestricted) restrictions.Add(AccountSanctionTypes.FleetParticipationRestriction);
            if (status.ShipMediaUploadRestricted) restrictions.Add(AccountSanctionTypes.ShipMediaUploadRestriction);
            return new(status.ActiveSanctions.Select(item => new AccountSafetySanction(item.SanctionId,
                item.Type, item.Summary, item.IssuedAt, item.ExpiresAt, item.RevokedAt)).ToArray(),
                appeals.Appeals, restrictions.ToArray(), status.UpdatedAt < appeals.UpdatedAt ? status.UpdatedAt : appeals.UpdatedAt);
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
        { throw Invalid(); }
    }

    private static bool ValidText(string? value, int max, bool multiline = false) => value is not null &&
        value.Length <= max && (multiline || value.Length > 0) &&
        !value.Any(c => char.IsControl(c) && !(multiline && c is '\r' or '\n' or '\t'));

    private static JsonDocument Document(byte[] bytes)
    {
        if (bytes.Length > MaximumBytes) throw Invalid();
        var document = JsonDocument.Parse(bytes);
        try { RejectDuplicates(document.RootElement); return document; }
        catch { document.Dispose(); throw; }
    }

    private static void RejectDuplicates(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var property in value.EnumerateObject())
            {
                if (!names.Add(property.Name)) throw Invalid();
                RejectDuplicates(property.Value);
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (var item in value.EnumerateArray()) RejectDuplicates(item);
    }

    private static AccountBridgeHostException Invalid() => new("accountSafety.data_invalid");
    public void Dispose() => _http.Dispose();
}
