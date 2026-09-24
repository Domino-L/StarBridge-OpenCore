using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // Explicit S2 adapter: no probing a newer route and no fallback after a failed write.
    // These references never contain a password, bearer, or an account ID visible to Flutter.
    private sealed record WpfGovernanceEdit(string Kind, string Scope, string TargetRef, Target Target,
        string? MemberRef, string? MemberId, string Version, DateTimeOffset Expires);
    private sealed record WpfGovernanceResult(string Status, string? Error = null, long? ProfileRevision = null)
    { public int SchemaVersion => 1; }
    private sealed record WpfGovernanceAttempt(string Hash, WpfGovernanceResult Result);
    private readonly object _wpfGovernanceGate = new();
    private readonly Dictionary<string, WpfGovernanceEdit> _wpfGovernanceEdits = new();
    private readonly Dictionary<string, WpfGovernanceAttempt> _wpfGovernanceAttempts = new();
    private readonly HashSet<string> _wpfGovernanceUncertain = new();
    private readonly HashSet<string> _wpfGovernanceConsumed = new();
    private long _wpfGovernanceEpoch;

    internal void InvalidateWpfS2Governance()
    {
        lock (_wpfGovernanceGate) { _wpfGovernanceEpoch++; _wpfGovernanceEdits.Clear(); _wpfGovernanceConsumed.Clear(); }
    }

    private async Task<JsonElement> WpfGovernanceFleet(string bearer, Target target, Action current, CancellationToken token)
    {
        if (string.IsNullOrEmpty(target.WpfS2ViewerId) || target.WpfS2Directory) throw Invalid();
        current();
        var rows = await WpfS2Membership(bearer, token);
        current();
        var fleet = rows.SingleOrDefault(row => Text(row, "code", 256).Equals(target.Code, StringComparison.OrdinalIgnoreCase));
        if (fleet.ValueKind == JsonValueKind.Undefined) throw new AccountBridgeHostException("communities.notAllowed");
        return fleet;
    }

    private static string WpfGovernanceVersion(JsonElement fleet) => WpfHash(new
    {
        code = Text(fleet, "code", 256), name = Text(fleet, "name", 512),
        owner = Optional(fleet, "ownerAccount", 512), commander = Optional(fleet, "commander", 1024),
        revision = WpfS2ProfileRevision(fleet), roles = WpfS2OptionalRows(fleet, "roleGroups", 512),
        permissions = WpfS2OptionalRows(fleet, "memberPermissions", 10000),
        // Online presence changes must not invalidate an otherwise unchanged confirmation.
        members = Rows(fleet, "members", 10000).Select(row => new
        {
            id = WpfS2MemberId(row), gameName = WpfText(row, "gameName", 512),
            callsign = WpfText(row, "callsign", 512), roleTitle = WpfText(row, "roleTitle", 512),
            joinedAt = WpfTimestamp(row, "joinedAt")
        }).OrderBy(row => row.id, StringComparer.OrdinalIgnoreCase)
    });

    private static string WpfHash(object value) => Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(value)));

    private static JsonElement WpfGovernanceMember(JsonElement fleet, string id)
    {
        var matches = Rows(fleet, "members", 10000).Where(row =>
            string.Equals(WpfS2MemberId(row), id, StringComparison.OrdinalIgnoreCase)).ToArray();
        if (matches.Length != 1) throw new AccountBridgeHostException("communities.refreshRequired");
        var member = matches[0];
        var name = WpfText(member, "gameName", 512);
        // Legacy writes resolve aliases. Reject ambiguous/anonymous names, even if the UI ref is unique.
        if (string.IsNullOrWhiteSpace(name) || Rows(fleet, "members", 10000).Count(row =>
            WpfText(row, "gameName", 512).Equals(name, StringComparison.OrdinalIgnoreCase) ||
            WpfText(row, "callsign", 512).Equals(name, StringComparison.OrdinalIgnoreCase)) != 1)
            throw new AccountBridgeHostException("communities.refreshRequired");
        return member;
    }

    private static JsonElement WpfMemberPermission(JsonElement fleet, JsonElement member)
    {
        var id = Optional(member, "accountId", 512);
        var name = WpfText(member, "gameName", 512);
        var matches = WpfS2OptionalRows(fleet, "memberPermissions", 10000).Where(row =>
            !string.IsNullOrEmpty(id) && string.Equals(Optional(row, "accountId", 512), id, StringComparison.OrdinalIgnoreCase) ||
            !string.IsNullOrEmpty(name) && WpfText(row, "gameName", 512).Equals(name, StringComparison.OrdinalIgnoreCase)).ToArray();
        if (matches.Length > 1) throw Invalid();
        return matches.SingleOrDefault();
    }

    private static bool WpfFlag(JsonElement row, string key) => row.ValueKind == JsonValueKind.Object &&
        row.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.True;

    private static bool WpfMemberIsOwner(JsonElement fleet, JsonElement member)
    {
        var id = Optional(member, "accountId", 512);
        var owner = Optional(fleet, "ownerAccount", 512);
        var permission = WpfMemberPermission(fleet, member);
        var role = permission.ValueKind == JsonValueKind.Object ? Optional(permission, "roleGroupKey", 128) : null;
        var gameName = WpfText(member, "gameName", 512);
        var commander = WpfText(fleet, "commander", 1024);
        return !string.IsNullOrEmpty(id) && string.Equals(id, owner, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(role, "fleet_commander", StringComparison.OrdinalIgnoreCase) ||
            gameName.Length > 0 && (commander.Equals(gameName, StringComparison.OrdinalIgnoreCase) ||
                commander.EndsWith("(" + gameName + ")", StringComparison.OrdinalIgnoreCase));
    }

    private async Task<bool> WpfMemberActionAllowed(string bearer, JsonElement fleet, JsonElement member,
        Target target, string kind, WpfS2Ownership ownership, CancellationToken token)
    {
        if (WpfMemberIsOwner(fleet, member)) return false;
        var id = Optional(member, "accountId", 512);
        if (!string.IsNullOrEmpty(id) && id.Equals(target.WpfS2ViewerId, StringComparison.OrdinalIgnoreCase)) return false;
        // Old snapshots can omit AccountId. Only the authenticated session can identify oneself.
        var session = await WorkspaceJson(bearer, "/api/auth/session", token, 2 * 1024 * 1024);
        if (!Text(session, "accountId", 512).Equals(target.WpfS2ViewerId, StringComparison.OrdinalIgnoreCase)) throw Invalid();
        var name = WpfText(member, "gameName", 512);
        if (new[] { "gameName", "userName", "callsign" }.Any(key =>
            string.Equals(Optional(session, key, 512), name, StringComparison.OrdinalIgnoreCase))) return false;
        if (ownership == WpfS2Ownership.Unknown) return false;
        if (ownership == WpfS2Ownership.Self) return true;
        return kind == "remove" && WpfS2HasPermissionId(fleet, target.WpfS2ViewerId!, "members.remove", ownership) &&
            !WpfFlag(WpfMemberPermission(fleet, member), "permissionEnabled");
    }

    internal Task<object> ReadWpfS2GovernanceAsync(string bearer, JsonElement body, string scope, string kind,
        Action current, CancellationToken token) => GuardWorkspace(async () =>
    {
        if (kind is not ("roles" or "role" or "remove" or "transfer" or "exit" or "disband")) throw Invalid();
        Validate(body, kind == "disband" ? ["targetRef"] : kind == "roles" ? ["targetRef", "editRef"] : ["targetRef", "memberRef", "editRef"]);
        var epoch = Interlocked.Read(ref _wpfGovernanceEpoch);
        var oldRef = Optional(body, "editRef", 32);
        WpfGovernanceEdit? previous = null;
        if (oldRef is not null)
        {
            if (body.TryGetProperty("targetRef", out _) || body.TryGetProperty("memberRef", out _)) throw Invalid();
            lock (_wpfGovernanceGate) previous = ResolveWpfGovernance(oldRef, scope, kind);
        }
        var targetRef = previous?.TargetRef ?? Text(body, "targetRef", 32);
        var target = previous?.Target ?? ResolveForRead(targetRef, scope, allowWpfS2: true);
        var memberRef = previous?.MemberRef ?? Optional(body, "memberRef", 32);
        var memberId = previous?.MemberId;
        if (kind is "role" or "remove" or "transfer" or "exit" && previous is null)
        {
            if (memberRef is null || !_memberTargets.TryGetValue(memberRef, out var entry) || entry.Scope != scope ||
                entry.Code != target.Code || entry.Expires <= _targetClock.GetUtcNow())
                throw new AccountBridgeHostException("communities.refreshRequired");
            memberId = entry.MemberId;
        }
        var fleet = await WpfGovernanceFleet(bearer, target, current, token);
        var ownership = await ReadWpfS2Ownership(bearer, fleet, target.WpfS2ViewerId!, token);
        var fields = new Dictionary<string, object?> { ["schemaVersion"] = 1, ["targetRef"] = targetRef };
        if (kind == "roles")
        {
            if (ownership != WpfS2Ownership.Self && !WpfS2HasPermission(fleet, target.WpfS2ViewerId!, "canManageFleetInfo"))
                throw new AccountBridgeHostException("communities.notAllowed");
            fields["roles"] = ParseRoleRows(fleet, "roleGroups", false);
            fields["code"] = target.Code;
            fields["name"] = Text(fleet, "name", 512);
            fields["profileRevision"] = WpfS2ProfileRevision(fleet);
            fields["access"] = new { canEditRoles = true, canAssignMembers = ownership == WpfS2Ownership.Self };
        }
        else if (kind == "disband")
        {
            fields["name"] = Text(fleet, "name", 512);
            fields["memberCount"] = Rows(fleet, "members", 10000).Length;
            fields["canDisband"] = ownership == WpfS2Ownership.Self;
            fields["credentialMode"] = "legacyPassword";
        }
        else
        {
            var member = WpfGovernanceMember(fleet, memberId!);
            var allowed = await WpfMemberActionAllowed(bearer, fleet, member, target, kind, ownership, token);
            foreach (var key in new[] { "gameName", "callsign", "roleTitle" }) fields[key] = WpfText(member, key, 512);
            fields["memberRef"] = memberRef;
            fields[kind == "role" ? "canAssign" : kind == "remove" ? "canRemove" : "canTransfer"] = allowed;
            if (kind == "role")
            {
                var permission = WpfMemberPermission(fleet, member);
                fields["roleKey"] = permission.ValueKind == JsonValueKind.Undefined ? "" : WpfText(permission, "roleGroupKey", 128);
                fields["roles"] = ParseRoleRows(fleet, "roleGroups", false)
                    .Where(row => WpfFlag(row, "isEnabled") && !Text(row, "key", 128).Equals("fleet_commander", StringComparison.OrdinalIgnoreCase))
                    .Select(row => new { key = Text(row, "key", 128), displayName = Text(row, "displayName", 512), color = Text(row, "color", 7) }).ToArray();
            }
            if (kind is "transfer" or "exit")
            {
                fields["leaveAfterTransfer"] = kind == "exit";
                var deputy = WpfS2OptionalRows(fleet, "roleGroups", 512).SingleOrDefault(row =>
                    WpfText(row, "key", 128) == "fleet_deputy_commander" && WpfFlag(row, "isEnabled"));
                fields["formerOwnerRoleTitle"] = deputy.ValueKind == JsonValueKind.Undefined ? "成员" : Text(deputy, "displayName", 512);
            }
        }
        current();
        token.ThrowIfCancellationRequested();
        lock (_wpfGovernanceGate)
        {
            if (epoch != _wpfGovernanceEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
            foreach (var old in _wpfGovernanceEdits.Where(row => row.Value.Expires <= _targetClock.GetUtcNow()).ToArray())
                _wpfGovernanceEdits.Remove(old.Key);
            if (_wpfGovernanceEdits.Count >= 256) throw new AccountBridgeHostException("communities.refreshRequired");
            var reference = Guid.NewGuid().ToString("N");
            _wpfGovernanceEdits[reference] = new(kind, scope, targetRef, target, memberRef, memberId,
                WpfGovernanceVersion(fleet), _targetClock.GetUtcNow().AddMinutes(kind == "disband" ? 5 : 15));
            fields[kind == "disband" ? "confirmationRef" : "editRef"] = reference;
            _targets[targetRef] = target with { Expires = _targetClock.GetUtcNow().AddMinutes(5) };
        }
        return fields;
    });

    private WpfGovernanceEdit ResolveWpfGovernance(string reference, string scope, string kind) =>
        _wpfGovernanceEdits.TryGetValue(reference, out var edit) && edit.Scope == scope && edit.Kind == kind &&
        edit.Expires > _targetClock.GetUtcNow() ? edit : throw new AccountBridgeHostException("communities.refreshRequired");

    internal async Task<object> WriteWpfS2GovernanceAsync(string bearer, JsonElement body, string scope, string kind,
        Action current, CancellationToken token)
    {
        switch (kind)
        {
            case "roles": ValidateRolesSave(body); break;
            case "role": ValidateMemberRoleSave(body); break;
            case "remove": ValidateMemberRemoval(body); break;
            case "transfer": case "exit": ValidateOwnershipTransfer(body); break;
            case "disband": ValidateDisband(body); break;
            case "log": Validate(body, "targetRef", "logRef"); break;
            default: throw Invalid();
        }
        var reference = Text(body, kind == "disband" ? "confirmationRef" : kind == "log" ? "logRef" : "editRef", 32);
        var requestKey = scope + "\0" + kind + "\0" + (kind is "disband" or "log" ? reference : Text(body, "requestId", 32));
        // Never hash/cache passwords. Disband consumes its confirmation once, including wrong-password replies.
        var hash = kind == "disband" ? reference : WpfHash(body);
        if (!await _write.WaitAsync(0, token)) return new WpfGovernanceResult("rejected", "busy");
        var sent = false;
        string? operation = null;
        var epoch = Interlocked.Read(ref _wpfGovernanceEpoch);
        try
        {
            current();
            WpfGovernanceEdit edit;
            lock (_wpfGovernanceGate)
            {
                if (_wpfGovernanceAttempts.TryGetValue(requestKey, out var prior))
                    return prior.Hash == hash ? prior.Result : new WpfGovernanceResult("rejected", "requestChanged");
                if (_wpfGovernanceAttempts.Count >= 512) return new WpfGovernanceResult("rejected", "refreshRequired");
                edit = ResolveWpfGovernance(reference, scope, kind);
                operation = scope + "\0" + kind + "\0" + edit.Target.Code + "\0" + edit.MemberId + "\0" + edit.Version;
                if (_wpfGovernanceUncertain.Contains(operation)) return new WpfGovernanceResult("unknown", "outcomeUnknown");
                if (_wpfGovernanceConsumed.Contains(reference)) return new WpfGovernanceResult("rejected", "refreshRequired");
            }
            if (kind is "disband" or "log" && Text(body, "targetRef", 32) != edit.TargetRef) throw Invalid();
            var fleet = await WpfGovernanceFleet(bearer, edit.Target, current, token);
            var ownership = await ReadWpfS2Ownership(bearer, fleet, edit.Target.WpfS2ViewerId!, token);
            current();
            var version = WpfGovernanceVersion(fleet);
            if (kind == "log")
            {
                var log = WpfS2OptionalRows(fleet, "eventLog", 100000).SingleOrDefault(row => Text(row, "id", 512) == edit.MemberId);
                if (log.ValueKind == JsonValueKind.Undefined) return new WpfGovernanceResult("rejected", "refreshRequired");
                version += "\0" + WpfHash(log);
            }
            if (version != edit.Version) return new WpfGovernanceResult("rejected", "conflict");
            object outgoing;
            string path;
            JsonElement member = default;
            if (kind == "roles")
            {
                if (ownership != WpfS2Ownership.Self && !WpfS2HasPermission(fleet, edit.Target.WpfS2ViewerId!, "canManageFleetInfo"))
                    return new WpfGovernanceResult("rejected", "notAllowed");
                outgoing = WpfRolesUpdate(fleet, body, edit.Target.Code);
                path = "/api/fleets/info";
            }
            else if (kind == "log")
            {
                if (!WpfS2HasPermissionId(fleet, edit.Target.WpfS2ViewerId!, "audit.delete", ownership))
                    return new WpfGovernanceResult("rejected", "notAllowed");
                outgoing = new { fleetCode = edit.Target.Code, logId = edit.MemberId };
                path = "/api/fleets/logs/delete";
            }
            else if (kind == "disband")
            {
                if (ownership != WpfS2Ownership.Self) return new WpfGovernanceResult("rejected", "notAllowed");
                outgoing = new { fleetCode = edit.Target.Code, password = body.GetProperty("password").GetString() };
                path = "/api/fleets/disband";
            }
            else
            {
                member = WpfGovernanceMember(fleet, edit.MemberId!);
                if (!await WpfMemberActionAllowed(bearer, fleet, member, edit.Target, kind, ownership, token))
                    return new WpfGovernanceResult("rejected", "notAllowed");
                var name = Text(member, "gameName", 512);
                path = kind switch { "role" => "/api/fleets/permissions", "remove" => "/api/fleets/members/remove",
                    "exit" => "/api/fleets/leave", _ => "/api/fleets/transfer-commander" };
                outgoing = kind == "role" ? WpfRoleAssignment(fleet, member, body, edit.Target.Code) : kind == "exit"
                    ? new { fleetCode = edit.Target.Code, transferCommanderTo = name }
                    : new { fleetCode = edit.Target.Code, targetGameName = name };
            }
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, path))
                { Content = JsonContent.Create(outgoing, outgoing.GetType()) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            current();
            deadline.Token.ThrowIfCancellationRequested();
            lock (_wpfGovernanceGate)
            {
                if (epoch != _wpfGovernanceEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
                ResolveWpfGovernance(reference, scope, kind);
                // Keep a read-only handle so the existing editor can reread after saving.
                // The handle can no longer authorize another mutation.
                if (!_wpfGovernanceConsumed.Add(reference)) return new WpfGovernanceResult("rejected", "refreshRequired");
                _wpfGovernanceUncertain.Add(operation);
                _wpfGovernanceAttempts[requestKey] = new(hash, new("unknown", "outcomeUnknown"));
                sent = true;
            }
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            WpfGovernanceResult result;
            if (!response.IsSuccessStatusCode)
                result = response.StatusCode switch
                {
                    HttpStatusCode.BadRequest => new("rejected", kind == "disband" ? "passwordInvalid" : "invalidDraft"),
                    HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                    HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                    HttpStatusCode.NotFound => new("rejected", "refreshRequired"),
                    HttpStatusCode.Conflict => new("rejected", "conflict"),
                    _ => new("unknown", "outcomeUnknown")
                };
            else
            {
                using var document = await ReadBoundedJsonAsync(response, 8 * 1024 * 1024, deadline.Token);
                var receipt = document.RootElement;
                if (kind == "disband")
                {
                    if (!WpfFlag(receipt, "disbanded") || !Text(receipt, "fleet", 256).Equals(edit.Target.Code, StringComparison.OrdinalIgnoreCase)) throw Invalid();
                }
                else
                {
                    if (!Text(receipt, "code", 256).Equals(edit.Target.Code, StringComparison.OrdinalIgnoreCase)) throw Invalid();
                    if (kind == "log")
                    {
                        if (WpfS2OptionalRows(receipt, "eventLog", 100000).Any(row => Text(row, "id", 512) == edit.MemberId)) throw Invalid();
                    }
                    else WpfVerifyGovernanceReceipt(kind, fleet, receipt, member, body);
                }
                result = new("accepted", ProfileRevision: kind == "roles" ? WpfS2ProfileRevision(receipt) : null);
            }
            current();
            deadline.Token.ThrowIfCancellationRequested();
            lock (_wpfGovernanceGate)
            {
                if (epoch != _wpfGovernanceEpoch) return new WpfGovernanceResult("unknown", "outcomeUnknown");
                _wpfGovernanceAttempts[requestKey] = new(hash, result);
                if (result.Status != "unknown") _wpfGovernanceUncertain.Remove(operation);
            }
            return result;
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or
            AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { return new WpfGovernanceResult(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired"); }
        finally { _write.Release(); }
    }

    private static object WpfRolesUpdate(JsonElement fleet, JsonElement body, string code)
    {
        var baseline = ParseRoleRows(fleet, "roleGroups", false);
        var drafts = ParseRoleRows(body, "roles", true);
        foreach (var original in baseline.Where(row => WpfFlag(row, "isSystem")))
            if (!drafts.Any(row => Text(row, "key", 128) == Text(original, "key", 128))) throw Invalid();
        var roles = drafts.Select(row =>
        {
            var original = baseline.SingleOrDefault(value => Text(value, "key", 128).Equals(Text(row, "key", 128), StringComparison.OrdinalIgnoreCase));
            var fields = row.EnumerateObject().ToDictionary(p => p.Name, p => (object?)p.Value.Clone());
            fields["isSystem"] = WpfFlag(original, "isSystem");
            fields["createdAt"] = original.ValueKind == JsonValueKind.Undefined ? DateTimeOffset.UtcNow.ToString("O") : Timestamp(original, "createdAt");
            fields["updatedAt"] = DateTimeOffset.UtcNow;
            if (Text(row, "key", 128).Equals("fleet_commander", StringComparison.OrdinalIgnoreCase))
            {
                if (original.ValueKind == JsonValueKind.Undefined) throw Invalid();
                fields["permissions"] = original.GetProperty("permissions").Clone();
                fields["isEnabled"] = original.GetProperty("isEnabled").Clone();
            }
            return fields;
        }).ToArray();
        var update = BuildWpfS2ProfileUpdate(fleet, code, WpfS2ProfileRevision(fleet), JsonSerializer.SerializeToElement(new { }));
        update["roleGroups"] = roles;
        update["updatedSections"] = new[] { "role-groups" };
        return update;
    }

    private static object WpfRoleAssignment(JsonElement fleet, JsonElement member, JsonElement body, string code)
    {
        var key = Text(body, "roleKey", 128);
        var role = ParseRoleRows(fleet, "roleGroups", false).SingleOrDefault(row => Text(row, "key", 128) == key);
        if (key.Length > 0 && (role.ValueKind == JsonValueKind.Undefined || !WpfFlag(role, "isEnabled") ||
            key.Equals("fleet_commander", StringComparison.OrdinalIgnoreCase))) throw Invalid();
        var permissions = key.Length == 0 ? [] : Rows(role, "permissions", 256).Select(row => row.GetString()!).ToArray();
        return new { fleetCode = code, permission = new
        {
            gameName = Text(member, "gameName", 512), callsign = WpfText(member, "callsign", 512),
            roleTitle = key.Length == 0 ? "成员" : Text(role, "displayName", 512), permissionEnabled = key.Length > 0,
            canRemoveMembers = permissions.Contains("members.remove", StringComparer.OrdinalIgnoreCase),
            canPublishTasks = false, canPublishPlans = false,
            canManageFleetInfo = permissions.Any(id => id.StartsWith("fleet.", StringComparison.OrdinalIgnoreCase) ||
                new[] { "members.review", "audit.view", "audit.delete" }.Contains(id, StringComparer.OrdinalIgnoreCase)),
            updatedAt = DateTimeOffset.UtcNow, roleGroupKey = key.Length == 0 ? null : key,
            extraAllowedPermissions = (string[]?)null, extraDeniedPermissions = (string[]?)null
        }, removeGameName = (string?)null };
    }

    private static void WpfVerifyGovernanceReceipt(string kind, JsonElement before, JsonElement after, JsonElement member, JsonElement body)
    {
        if (kind == "roles")
        {
            if (WpfS2ProfileRevision(after) <= WpfS2ProfileRevision(before)) throw Invalid();
            var wanted = (Dictionary<string, object?>)WpfRolesUpdate(before, body, Text(before, "code", 256));
            var expected = JsonSerializer.SerializeToElement(new { roles = wanted["roleGroups"] });
            // Compare only editable fields; the service owns timestamps and assigned-member counts.
            var actual = ParseRoleRows(after, "roleGroups", false);
            if (actual.Length != Rows(expected, "roles", 512).Length) throw Invalid();
            foreach (var role in Rows(expected, "roles", 512))
            {
                var saved = actual.SingleOrDefault(row => Text(row, "key", 128) == Text(role, "key", 128));
                if (saved.ValueKind == JsonValueKind.Undefined) throw Invalid();
                foreach (var key in new[] { "displayName", "description", "color" })
                    if (saved.GetProperty(key).GetString() != role.GetProperty(key).GetString()) throw Invalid();
                if (saved.GetProperty("sortOrder").GetInt32() != role.GetProperty("sortOrder").GetInt32() ||
                    saved.GetProperty("isEnabled").GetBoolean() != role.GetProperty("isEnabled").GetBoolean() ||
                    !Rows(saved, "permissions", 256).Select(row => row.GetString()).ToHashSet(StringComparer.OrdinalIgnoreCase)
                        .SetEquals(Rows(role, "permissions", 256).Select(row => row.GetString()))) throw Invalid();
            }
            return;
        }
        var id = WpfS2MemberId(member);
        if (kind == "remove")
        {
            if (Rows(after, "members", 10000).Any(row => string.Equals(WpfS2MemberId(row), id, StringComparison.OrdinalIgnoreCase) ||
                WpfText(row, "gameName", 512).Equals(Text(member, "gameName", 512), StringComparison.OrdinalIgnoreCase))) throw Invalid();
        }
        else if (kind == "role")
        {
            var saved = WpfGovernanceMember(after, id!);
            var permission = WpfMemberPermission(after, saved);
            if (permission.ValueKind == JsonValueKind.Undefined || WpfText(permission, "roleGroupKey", 128) != Text(body, "roleKey", 128)) throw Invalid();
        }
        else
        {
            if (string.IsNullOrEmpty(Optional(after, "ownerAccount", 512)) ||
                Optional(after, "ownerAccount", 512) == Optional(before, "ownerAccount", 512) ||
                !WpfMemberIsOwner(after, WpfGovernanceMember(after, id!))) throw Invalid();
            if (kind == "exit")
            {
                var former = Rows(before, "members", 10000).Where(row => WpfMemberIsOwner(before, row)).ToArray();
                if (former.Length != 1 || Rows(after, "members", 10000).Any(row =>
                    string.Equals(WpfS2MemberId(row), WpfS2MemberId(former[0]), StringComparison.OrdinalIgnoreCase))) throw Invalid();
            }
        }
    }
}
