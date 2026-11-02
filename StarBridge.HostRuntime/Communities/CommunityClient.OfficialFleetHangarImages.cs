using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.Core.ShipMedia;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Hangar;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private const string OfficialImageHeader = "X-StarBridge-Official-Fleet-Hangar-Version";
    private sealed record OfficialHangarImageFeatures(bool Read, bool Upload, bool Report, bool Reduce);
    private sealed record OfficialHangarImageOperation(bool ClearOnly, Func<CancellationToken, Task<string>>? ReadOwner,
        Func<long, string, string?>? ReadImage);

    // Typed native lane, shared with the existing Save core. The public Bridge
    // still refuses includeImages until all three actual image names exist.
    internal Task<object> ReadOfficialHangarImageDraftAsync(string bearer, JsonElement body, string scope, Action current,
        Func<LocalHangarSnapshot> local, CancellationToken token) =>
        ReadOfficialHangarSharingAsync(bearer, body, scope, current, local, token, negotiateImages: true);

    internal Task<CommunityCommand> SaveOfficialHangarImageDraftAsync(string bearer, JsonElement body, string scope, Action current,
        Func<LocalHangarSnapshot> local, Func<CancellationToken, Task<string>> owner, Func<long, string, string?> readImage, CancellationToken token) =>
        SaveOfficialHangarSharingCore(bearer, body, scope, current, local, token, new(false, owner, readImage));

    internal Task<CommunityCommand> ClearOfficialHangarImagesAsync(string bearer, JsonElement body, string scope, Action current,
        CancellationToken token) => SaveOfficialHangarSharingCore(bearer, body, scope, current,
            () => throw new InvalidOperationException("Image withdrawal must not read local inventory."), token, new(true, null, null));

    private static OfficialHangarImageFeatures ReadOfficialImageFeatures(JsonElement root)
    {
        var features = root.GetProperty("imageFeatures");
        if (features.ValueKind != JsonValueKind.Object || !features.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal).SequenceEqual(
            new[] { "protocolVersion", "read", "upload", "report", "reduce" }.Order(StringComparer.Ordinal))) throw Invalid();
        if (Number(features, "protocolVersion", 1, 1) != 1) throw Invalid();
        return new(features.GetProperty("read").GetBoolean(), features.GetProperty("upload").GetBoolean(),
            features.GetProperty("report").GetBoolean(), features.GetProperty("reduce").GetBoolean());
    }

    private static string[] ReadOfficialImageConsent(JsonElement root)
    {
        var consent = root.GetProperty("imageConsent");
        var count = Number(consent, "count", 0, 10000);
        var refs = Rows(consent, "grantRefs", 10000).Select(row => row.GetString() ?? "").ToArray();
        if (refs.Length != count || refs.Any(value => !Regex.IsMatch(value, "^[a-f0-9]{64}$")) ||
            refs.Distinct(StringComparer.Ordinal).Count() != refs.Length) throw Invalid();
        return refs.Order(StringComparer.Ordinal).ToArray();
    }

    private async Task<OfficialHangarImageReceipt> UploadOfficialImage(string bearer, OfficialHangarEdit edit,
        ShipMediaUploadRequestContract image, Action current, Action sent, CancellationToken token)
    {
        current(); token.ThrowIfCancellationRequested();
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, OfficialHangarPath + "/images"))
        { Content = JsonContent.Create(new { schemaVersion = 1, target = edit.Target, version = edit.Version, image }) };
        request.Headers.Authorization = new("Bearer", bearer); request.Headers.Add(OfficialImageHeader, "2");
        sent();
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        if (response.StatusCode != HttpStatusCode.OK) throw new AccountBridgeHostException("hangar.image_outcome_unknown");
        var root = await ReadOfficialHangarJson(response, token, 32 * 1024);
        current(); token.ThrowIfCancellationRequested();
        if (Number(root, "schemaVersion", 1, 1) != 1 || ParseOfficialHangarTarget(root.GetProperty("target")) != edit.Target ||
            Text(root, "status", 32) is not ("uploaded" or "unchanged")) throw Invalid();
        var receipt = root.GetProperty("receipt");
        var media = receipt.GetProperty("media").Deserialize<ShipMediaSummaryContract>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
        return new(media!, Text(receipt, "contentHash", 64), Text(receipt, "imageVersion", 64));
    }

    private async Task<CommunityCommand> PublishOfficialImages(string bearer, OfficialHangarEdit edit, string strategy,
        string[] selected, CommunityPublishedShip[] inventory, OfficialHangarImageGrant[] images, string owner,
        Action current, Action sent, CancellationToken token)
    {
        current(); token.ThrowIfCancellationRequested();
        using var request = new HttpRequestMessage(HttpMethod.Put, new Uri(_origin, OfficialHangarPath + "/publish"))
        {
            Content = JsonContent.Create(new
            {
                schemaVersion = 2,
                target = edit.Target,
                version = edit.Version,
                strategy,
                instanceRefs = selected,
                ships = inventory,
                imageGrants = images
            })
        };
        request.Headers.Authorization = new("Bearer", bearer); request.Headers.Add(OfficialImageHeader, "2");
        sent();
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        current(); token.ThrowIfCancellationRequested();
        if (response.StatusCode != HttpStatusCode.OK) return OfficialImageFailure(response.StatusCode);
        var root = await ReadOfficialHangarJson(response, token);
        current(); token.ThrowIfCancellationRequested();
        var sharing = root.GetProperty("sharing");
        var expected = images.Select(image => OfficialImageGrantRef(owner, edit.Target, image)).Order(StringComparer.Ordinal).ToArray();
        var acknowledged = Number(root, "schemaVersion", 2, 2) == 2 && Text(root, "status", 32) == "accepted" &&
            ParseOfficialHangarTarget(root.GetProperty("target")) == edit.Target && Text(sharing, "state", 32) == "available" &&
            Text(sharing, "strategy", 32) == strategy && OfficialHangarRef(Text(root, "intentRevision", 32)) && Text(root, "intentRevision", 32) != edit.Revision &&
            Regex.IsMatch(Text(sharing, "version", 64), "^[a-f0-9]{64}$") && Text(sharing, "version", 64) != edit.Version &&
            Rows(sharing, "instanceRefs", 10000).Select(row => row.GetString()).Order(StringComparer.Ordinal).SequenceEqual(selected) &&
            ReadOfficialImageConsent(root).SequenceEqual(expected, StringComparer.Ordinal);
        return acknowledged ? new("accepted") : new("unknown", "outcomeUnknown");
    }

    private async Task<CommunityCommand> ClearOfficialImages(string bearer, string reference, OfficialHangarEdit edit,
        Action current, Action sent, CancellationToken token)
    {
        if (edit.Images?.Reduce != true || edit.Revision is null) return new("rejected", "upgradeRequired");
        current(); token.ThrowIfCancellationRequested();
        if (!_officialHangarEdits.TryRemove(reference, out _)) return new("rejected", "refreshRequired");
        using var request = new HttpRequestMessage(HttpMethod.Put, new Uri(_origin, OfficialHangarPath + "/reduce"))
        {
            Content = JsonContent.Create(new
            {
                schemaVersion = 2,
                target = edit.Target,
                expectedRevision = edit.Revision,
                kind = "images",
                retainImageGrantRefs = Array.Empty<string>()
            })
        };
        request.Headers.Authorization = new("Bearer", bearer); request.Headers.Add(OfficialImageHeader, "2");
        sent();
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        current(); token.ThrowIfCancellationRequested();
        if (response.StatusCode != HttpStatusCode.OK) return OfficialImageFailure(response.StatusCode);
        var root = await ReadOfficialHangarJson(response, token); var intent = root.GetProperty("intent");
        current(); token.ThrowIfCancellationRequested();
        var revision = Text(intent, "revision", 32); var status = Text(root, "status", 32);
        return Number(root, "schemaVersion", 2, 2) == 2 && ParseOfficialHangarTarget(intent.GetProperty("target")) == edit.Target &&
            Text(intent, "strategy", 32) == edit.Strategy && OfficialHangarRef(revision) &&
            (status == "unchanged" && revision == edit.Revision || status == "accepted" && revision != edit.Revision) &&
            Number(intent, "imageCount", 0, 0) == 0 && ReadOfficialImageConsent(root).Length == 0 ? new("accepted") : new("unknown", "outcomeUnknown");
    }

    private static CommunityCommand OfficialImageFailure(HttpStatusCode status) => status switch
    {
        HttpStatusCode.Conflict => new("rejected", "refreshRequired"),
        HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
        HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
        HttpStatusCode.BadRequest or HttpStatusCode.RequestEntityTooLarge => new("rejected", "invalidDraft"),
        HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed => new("rejected", "upgradeRequired"),
        _ => new("unknown", "outcomeUnknown")
    };

    private static string OfficialImageGrantRef(string owner, OfficialHangarTarget target, OfficialHangarImageGrant image) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(string.Join('\n',
            "StarBridge.OfficialFleet.ShipImage.Grant.v1", owner, target.AuthorityNamespace, target.OrganizationId.ToString(CultureInfo.InvariantCulture),
            target.Sid, target.MembershipEpoch, image.InstanceRef, image.ImageVersion)))).ToLowerInvariant();
}
