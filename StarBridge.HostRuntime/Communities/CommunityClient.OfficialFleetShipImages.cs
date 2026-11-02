using System.Text.Json;
using StarBridge.HostRuntime.Account;
namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal OfficialShipImageReference LookupOfficialShipImage(JsonElement body, string accountScope, TimeProvider clock, bool report = false)
    {
        var targetRef = Text(body, "targetRef", 32); var shipRef = Text(body, "shipRef", 32);
        if (!LowerHex(targetRef, 32) || !LowerHex(shipRef, 32)) throw Invalid();
        var matches = _officialShipDisplayReferences.Values.Where(row => row.Reference == shipRef && row.Expires > clock.GetUtcNow() &&
            row.Image is { } image && image.AccountScope == accountScope + "|" + image.SourceRef && image.TargetRef == targetRef).Take(2).ToArray();
        if (matches.Length != 1 || matches[0].Image is not { } bound) throw new AccountBridgeHostException("communities.refreshRequired");
        return ResolveOfficialShipImage(body, bound.SourceRef, bound.AccountScope, clock, report);
    }
    internal OfficialShipImageReference ResolveOfficialShipImage(JsonElement body, string source, string scope, TimeProvider clock, bool report = false)
    {
        var targetRef = Text(body, "targetRef", 32); var shipRef = Text(body, "shipRef", 32);
        RequireOfficialFleetTarget(body, source, scope);
        var matches = _officialShipDisplayReferences.Values.Where(row => row.Reference == shipRef && row.Expires > clock.GetUtcNow() &&
            row.Image is { } image && image.AccountScope == scope && image.SourceRef == source && image.TargetRef == targetRef).Take(2).ToArray();
        if (matches.Length != 1 || matches[0].Image is not { } bound || bound.MemberId <= 0 || bound.Version is null ||
            !bound.Read || report && !bound.Report) throw new AccountBridgeHostException("communities.refreshRequired");
        return bound;
    }
    internal Task<object> ReadOfficialShipImageAsync(string bearer, JsonElement body, string source, string scope,
        Action current, TimeProvider clock, CancellationToken token) => GuardWorkspace(async () =>
    {
        Validate(body, "targetRef", "shipRef", "offset", "version");
        var bound = ResolveOfficialShipImage(body, source, scope, clock);
        var reference = Text(body, "targetRef", 32); var shipRef = Text(body, "shipRef", 32);
        var offset = Number(body, "offset", 0, 2 * 1024 * 1024 - 1); var version = Optional(body, "version", 64);
        if (offset % (192 * 1024) != 0 || offset > 0 && version is null || version is not null && version != bound.Version) throw Invalid();
        current(); token.ThrowIfCancellationRequested();
        var raw = await WorkspaceJson(bearer, "/api/official-fleets/ship-images?sourceRef=" + Uri.EscapeDataString(source) + "&shipId=" + bound.ShipId +
            "&offset=" + offset + "&version=" + bound.Version, token, 280 * 1024);
        current(); token.ThrowIfCancellationRequested();
        if (ResolveOfficialShipImage(body, source, scope, clock) != bound) throw new AccountBridgeHostException("communities.refreshRequired");
        string[] keys = ["schemaVersion",
            "sourceRef",
            "shipId",
            "version",
            "contentHash",
            "mimeType",
            "totalBytes",
            "offset",
            "next",
            "data",
            "cropFocusX",
            "cropFocusY",
            "cropZoom",
            "identityObservedAtUtc",
            "identityValidUntilUtc"];
        if (raw.ValueKind != JsonValueKind.Object || !raw.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal).SequenceEqual(keys.Order(StringComparer.Ordinal)) ||
            Text(raw, "sourceRef", 64) != source || Text(raw, "shipId", 64) != bound.ShipId ||
            !raw.GetProperty("identityObservedAtUtc").TryGetDateTimeOffset(out var observed) ||
            !raw.GetProperty("identityValidUntilUtc").TryGetDateTimeOffset(out var expires) || observed.Offset != TimeSpan.Zero || expires.Offset != TimeSpan.Zero ||
            observed > clock.GetUtcNow().AddSeconds(1) || expires <= observed || expires > observed.AddSeconds(5) || clock.GetUtcNow() >= expires)
            throw new AccountBridgeHostException("communities.identityUnavailable");
        var result = ProjectImageChunk(raw, reference, shipRef, offset, bound.Version);
        current(); token.ThrowIfCancellationRequested();
        if (clock.GetUtcNow() >= expires) throw new AccountBridgeHostException("communities.identityUnavailable");
        return result;
    });
}
