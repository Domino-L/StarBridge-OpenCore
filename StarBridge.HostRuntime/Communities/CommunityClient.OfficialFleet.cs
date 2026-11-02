using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private static string CommunicationPath(Target target, string suffix) =>
        (target.OfficialFleet ? "/api/official-fleets" : "/api/fleets") + suffix;

    internal async Task<object> OpenOfficialFleetAsync(string bearer, string sourceRef, string scope,
        Action current, CancellationToken token)
    {
        current();
        var root = await WorkspaceJson(bearer, "/api/official-fleets/context", token);
        current(); token.ThrowIfCancellationRequested();
        if (Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "sourceRef", 64) != sourceRef ||
            !Text(root, "fleetCode", 64).Equals(sourceRef, StringComparison.OrdinalIgnoreCase) ||
            root.GetProperty("canManageAnnouncements").GetBoolean()) throw Invalid();
        var code = sourceRef.ToUpperInvariant();
        if (root.TryGetProperty("activityAvailable", out var activity) && activity.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            throw Invalid();
        var authorSchema = root.TryGetProperty("authorIdentitySchemaVersion", out var authorValue) ? authorValue.GetInt32() : 0;
        if (authorSchema is < 0 or > 1) throw Invalid();
        var previewAuthorsAvailable = root.TryGetProperty("previewAuthorsAvailable", out var preview) && preview.ValueKind == JsonValueKind.True;
        var name = Text(root, "name", 256);
        var prior = _targets.FirstOrDefault(pair => pair.Value.Scope == scope && pair.Value.Code == code && pair.Value.OfficialFleet);
        var reference = prior.Key ?? Guid.NewGuid().ToString("N");
        _targets[reference] = new(code, scope, _targetClock.GetUtcNow().AddMinutes(5), name, OfficialFleet: true,
            AuthorIdentitySchemaVersion: authorSchema, PreviewAuthorsAvailable: previewAuthorsAvailable);
        TrimTargets();
        return new
        {
            schemaVersion = 1,
            sourceRef,
            targetRef = reference,
            name,
            announcementsAvailable = root.GetProperty("announcementsAvailable").GetBoolean(),
            chatAvailable = root.GetProperty("chatAvailable").GetBoolean(),
            chatSendAvailable = root.GetProperty("canSend").GetBoolean(),
            readReceiptsAvailable = root.GetProperty("readReceiptsAvailable").GetBoolean(),
            activityAvailable = activity.ValueKind == JsonValueKind.True,
            authorIdentitySchemaVersion = authorSchema,
            previewAuthorsAvailable
        };
    }

    internal void RequireOfficialFleetTarget(JsonElement payload, string sourceRef, string scope)
    {
        var target = ResolveForRead(Text(payload, "targetRef", 32), scope);
        if (!target.OfficialFleet || !target.Code.Equals(sourceRef, StringComparison.OrdinalIgnoreCase)) throw Invalid();
    }
}
