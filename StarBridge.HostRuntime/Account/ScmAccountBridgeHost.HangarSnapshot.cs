using System.Text.Json;
using StarBridge.Core.Hangar;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    internal BridgeAccountContext? LegacyHangarMigrationContext =>
        _disposed || _session is not null || _reauthorizationRequired || _credentialTemporarilyUnavailable || _legacyRestoreUnavailable
            ? null : LegacyContext;
    public async Task<object> ReadMigrationHangarAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        var names = new HashSet<string>(StringComparer.Ordinal);
        if (payload.ValueKind != JsonValueKind.Object) throw new AccountBridgeHostException("hangar.invalid_request");
        foreach (var property in payload.EnumerateObject())
            if (!names.Add(property.Name) || property.Name is not ("schemaVersion" or "offset" or "snapshotSha256"))
                throw new AccountBridgeHostException("hangar.invalid_request");
        if (!payload.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1)
            throw new AccountBridgeHostException("hangar.invalid_request");
        var offset = 0;
        if (payload.TryGetProperty("offset", out var offsetValue) && (offsetValue.ValueKind != JsonValueKind.Number || !offsetValue.TryGetInt32(out offset)))
            throw new AccountBridgeHostException("hangar.invalid_request");
        if (offset < 0 || offset > 10000) throw new AccountBridgeHostException("hangar.invalid_request");
        var expected = payload.TryGetProperty("snapshotSha256", out var hash) && hash.ValueKind == JsonValueKind.String ? hash.GetString() : null;
        if (names.Contains("snapshotSha256") && (expected is not { Length: 64 } || !expected.All(Uri.IsHexDigit)))
            throw new AccountBridgeHostException("hangar.invalid_request");
        if (offset > 0 && expected is null) throw new AccountBridgeHostException("hangar.invalid_request");
        var read = await ReadMigrationHangarSourceAsync(context, token);
        if (expected is not null && expected != read.SnapshotSha256)
            throw new AccountBridgeHostException("hangar.migration_snapshot_changed", retryable: true);
        if (offset > read.Source.Ships.Count) throw new AccountBridgeHostException("hangar.invalid_request");
        var rows = read.Source.Ships.Skip(offset).Take(100).ToArray();
        var response = new { schemaVersion = 1, state = read.State, localCoverage = "unknown", snapshotSha256 = read.SnapshotSha256,
            total = read.Source.Ships.Count, offset, nextOffset = offset + rows.Length < read.Source.Ships.Count ? (int?)(offset + rows.Length) : null, ships = rows };
        if (JsonSerializer.SerializeToUtf8Bytes(response).Length > BridgeProtocol.MaximumFrameBytes / 2)
            throw new AccountBridgeHostException("hangar.migration_snapshot_too_large");
        return response;
    }

    internal async Task<Hangar.ServerHangarMigrationRead> ReadMigrationHangarSourceAsync(BridgeAccountContext context, CancellationToken token)
    {
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var session = RequireRelaySession(context);
        // This is an explicit old-account migration source, never a Java/SCM fallback.
        if (session.Legacy is null || _legacyPasswordLogin is null)
            throw new AccountBridgeHostException("hangar.migration_source_unavailable");
        var result = await SendRelayRequestAsync(session, (active, ct) => _legacyPasswordLogin.ReadHangarSnapshotAsync(
            active.Legacy!, new MigrationOwner(context.Environment, context.Authority, context.Subject), ct), token);
        token.ThrowIfCancellationRequested();
        if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
        RequireSameRelaySession(session, RequireRelaySession(context));
        return result.Result;
    }
}
