using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> OfficialFleetGovernanceManagementAsync(BridgeAccountContext context, JsonElement body, string action, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token); deadline.CancelAfter(TimeSpan.FromSeconds(12));
        _ = RequireSession(context);
        var generation = Generation;
        string? targetRef = null;
        if (action is "readMemberRoles" or "assignRole" && body.TryGetProperty("targetRef", out var reference))
        {
            if (reference.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(reference.GetString()) ||
                reference.GetString()!.Length > 256 || body.TryGetProperty("targetSubject", out _))
                throw new AccountBridgeHostException("communities.dataInvalid");
            targetRef = reference.GetString()!;
            var source = body.GetProperty("sourceRef").GetString()!;
            var normalized = JsonNode.Parse(body.GetRawText())!.AsObject();
            normalized.Remove("targetRef"); normalized["targetSubject"] = "scm-v1:" + new string('0', 64);
            var placeholder = JsonSerializer.SerializeToElement(normalized);
            if (action == "assignRole") _ = CommunityClient.ValidateGovernanceWrite(placeholder, action);
            else
            {
                var keys = body.EnumerateObject().Select(p => p.Name).ToArray();
                if (keys.Length != 3 || keys.Distinct(StringComparer.Ordinal).Count() != 3 ||
                    !body.GetProperty("schemaVersion").TryGetInt32(out var schema) || schema != 1 ||
                    !keys.OrderBy(k => k, StringComparer.Ordinal).SequenceEqual(new[] { "schemaVersion", "sourceRef", "targetRef" }))
                    throw new AccountBridgeHostException("communities.dataInvalid");
            }
            var subject = await ResolveOfficialFleetProfileTargetAsync(new("officialFleet", targetRef, source, ""), context, generation, deadline.Token);
            normalized["targetSubject"] = subject;
            body = JsonSerializer.SerializeToElement(normalized);
        }
        var session = RequireRelaySession(context);
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            deadline.Token.ThrowIfCancellationRequested();
            if (_disposed || Generation != generation) throw new BridgeStaleGenerationException(generation, Generation);
            _ = RequireSession(context); RequireSameRelaySession(RequireRelaySession(context), session);
        }
        Current();
        var result = await SendRelayRequestAsync<object>(session, (active, cancel) =>
            client.OfficialGovernanceManagementAsync(active.AccessToken, body, action, Current, cancel), deadline.Token);
        Current(); CommitSharingSession(session, result.ActiveSession); Current();
        if (action == "readMemberRoles" && targetRef is not null && result.Result is JsonElement page)
        {
            var projection = JsonNode.Parse(page.GetRawText())!.AsObject();
            projection.Remove("targetSubject"); projection["targetRef"] = targetRef;
            return JsonSerializer.SerializeToElement(projection);
        }
        return result.Result;
    }
}
