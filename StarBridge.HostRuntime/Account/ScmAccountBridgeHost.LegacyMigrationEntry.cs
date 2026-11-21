using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

/// <summary>What Flutter learns about the migration: states and counts, never an account ID.</summary>
internal sealed record LegacyMigrationView(
    bool Available, string State, int Friends, int Communities, int Merged,
    bool RecoveryRequired, string LocalData, bool ResultPending)
{
    public int SchemaVersion => 1;
    internal static LegacyMigrationView Unavailable { get; } = new(false, "none", 0, 0, 0, false, "pending", false);
}

/// <summary>
/// Old-account migration entry (account plan item 9, migration-entry-073/PLAN.md).
/// The relay migrates a linked person on the first relay session read of a 0.7.3+
/// client; reading the status never starts it. So a refresh first runs the existing
/// compatibility read (which also writes the local owner alias once the relay reports
/// "migrated", plan item 8), then reads the status for the result page.
/// </summary>
internal sealed partial class ScmAccountBridgeHost
{
    internal LegacyMigrationClient? LegacyMigration { get; init; }
    internal LegacyMigrationResultMarks? MigrationResultMarks { get; init; }

    // The old account of the last status read, kept in the Host only, so that the
    // acknowledgement never needs Flutter to carry an account ID.
    private (BridgeAccountContext Scm, string LegacyAccountId)? _lastMigrated;

    public async Task<object> ReadLegacyMigrationAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        var refresh = MigrationRequest(payload);
        if (refresh) await GetCompatibilityStateAsync(context, token).ConfigureAwait(false);
        return await MigrationAsync(context, (client, bearer, ct) => client.ReadAsync(bearer, ct), token).ConfigureAwait(false);
    }

    public async Task<object> RetryLegacyMigrationAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        MigrationRequest(payload);
        return await MigrationAsync(context, (client, bearer, ct) => client.RetryAsync(bearer, ct), token).ConfigureAwait(false);
    }

    public Task<object> AcknowledgeLegacyMigrationAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        MigrationRequest(payload);
        RequireRelaySession(context);
        if (_lastMigrated is { } last && last.Scm == context)
            MigrationResultMarks?.MarkShown(context, last.LegacyAccountId);
        return Task.FromResult<object>(new { schemaVersion = 1, acknowledged = true });
    }

    private async Task<object> MigrationAsync(BridgeAccountContext context,
        Func<LegacyMigrationClient, string, CancellationToken, Task<LegacyMigrationStatus?>> send, CancellationToken token)
    {
        var client = LegacyMigration;
        if (client is null) return LegacyMigrationView.Unavailable;
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_credentialTemporarilyUnavailable && !_reauthorizationRequired)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CredentialTemporarilyUnavailable, retryable: true);
        if (_reauthorizationRequired)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        LegacyMigrationStatus? status;
        try
        {
            var result = await SendRelayRequestAsync(session,
                (active, ct) => send(client, active.AccessToken, ct), token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
            _session = result.ActiveSession.Scm;
            status = result.Result;
        }
        catch (ScmApiAuthenticationException)
        { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
        if (status is null) return LegacyMigrationView.Unavailable;
        switch (status.State)
        {
            case "none":
                _lastMigrated = null;
                MigrationResultMarks?.Forget(context);
                break;
            case "failed":
                Support.IdentityGateJournal.Event("migration", "code=failed reason=" + SafeReason(status.Reason));
                break;
            case "completed":
                _lastMigrated = (context, status.LegacyAccountId!);
                // The alias is written by the compatibility read's own two-source check;
                // ask once if it has not happened yet (never write it from here).
                if (LocalDataOwnerAliasState(context) == "none")
                    await GetCompatibilityStateAsync(context, token).ConfigureAwait(false);
                break;
        }
        var alias = status.State == "completed" ? LocalDataOwnerAliasState(context) : "none";
        return new LegacyMigrationView(
            true, status.State, status.Friends, status.Communities, status.Merged,
            status.State == "failed" && status.Reason == "migration_recovery_required",
            alias switch { "written" => "linked", "conflict" => "conflict", _ => "pending" },
            status.State == "completed" &&
                !(MigrationResultMarks?.Shown(context, status.LegacyAccountId!) ?? false));
    }

    private static bool MigrationRequest(JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty("schemaVersion", out var version) ||
            version.ValueKind != JsonValueKind.Number || version.GetInt32() != 1)
            throw new AccountBridgeHostException("account.migration_request_invalid");
        foreach (var property in payload.EnumerateObject())
            if (property.Name is not ("schemaVersion" or "refresh"))
                throw new AccountBridgeHostException("account.migration_request_invalid");
        return payload.TryGetProperty("refresh", out var refresh) &&
            (refresh.ValueKind is JsonValueKind.True ||
             (refresh.ValueKind is JsonValueKind.False ? false : throw new AccountBridgeHostException("account.migration_request_invalid")));
    }

    // Reason codes go to the diagnostics log only; anything unexpected is not copied.
    private static string SafeReason(string? reason) =>
        reason is { Length: > 0 and <= 64 } && reason.All(c => c is (>= 'a' and <= 'z') or (>= '0' and <= '9') or '_')
            ? reason : "other";
}
