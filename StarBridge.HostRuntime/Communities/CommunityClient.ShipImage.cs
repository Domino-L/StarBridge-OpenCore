using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal Task<object> ReadShipImageAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token) => GuardWorkspace(async () =>
    {
        current(); token.ThrowIfCancellationRequested();
        Validate(body, "targetRef", "shipRef", "offset", "version");
        var reference = Text(body, "targetRef", 32);
        var target = Resolve(reference, scope);
        var shipRef = Text(body, "shipRef", 32);
        var offset = Number(body, "offset", 0, 2 * 1024 * 1024 - 1);
        var version = Optional(body, "version", 64);
        if (offset % (192 * 1024) != 0 || offset > 0 && version is null || version is not null && !ShipHash(version)) throw Invalid();
        if (!_shipTargets.TryGetValue(shipRef, out var ship) || ship.Scope != scope || ship.Code != target.Code ||
            ship.Expires <= DateTimeOffset.UtcNow) throw new AccountBridgeHostException("communities.refreshRequired");
        var root = await WorkspaceJson(bearer, $"/api/fleets/ships/image?code={Uri.EscapeDataString(target.Code)}&shipId={ship.Id}&offset={offset}"
            + (version is null ? "" : "&version=" + version), token, 280 * 1024);
        current(); token.ThrowIfCancellationRequested();
        if (Resolve(reference, scope).Code != target.Code || !_shipTargets.TryGetValue(shipRef, out var stillCurrent) ||
            stillCurrent.Id != ship.Id || stillCurrent.Code != ship.Code || stillCurrent.Scope != scope ||
            stillCurrent.Expires <= DateTimeOffset.UtcNow) throw new AccountBridgeHostException("communities.refreshRequired");
        ShipObject(root);
        var actualVersion = Text(root, "version", 64);
        var contentHash = Text(root, "contentHash", 64);
        var mime = Text(root, "mimeType", 32);
        var total = Number(root, "totalBytes", 1, 2 * 1024 * 1024);
        var data = Text(root, "data", 256 * 1024);
        var count = Convert.FromBase64String(data).Length;
        int? next = root.GetProperty("next").ValueKind == JsonValueKind.Null ? null : Number(root, "next", 1, total);
        if (Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "code", 256) != target.Code ||
            Text(root, "shipId", 64) != ship.Id || !ShipHash(actualVersion) || !ShipHash(contentHash) ||
            version is not null && version != actualVersion || mime is not ("image/png" or "image/jpeg") ||
            Number(root, "offset", 0, total) != offset || offset >= total ||
            count != Math.Min(192 * 1024, total - offset) || next != (offset + count < total ? offset + count : null)) throw Invalid();
        var cropFocusX = ShipCrop(root, "cropFocusX", 0, 1);
        var cropFocusY = ShipCrop(root, "cropFocusY", 0, 1);
        var cropZoom = ShipCrop(root, "cropZoom", 1, 3);
        RenewTarget(reference, target, token);
        return new { schemaVersion = 1, targetRef = reference, shipRef, version = actualVersion, contentHash,
            mimeType = mime, totalBytes = total, offset, next, data, cropFocusX, cropFocusY, cropZoom };
    });
}
