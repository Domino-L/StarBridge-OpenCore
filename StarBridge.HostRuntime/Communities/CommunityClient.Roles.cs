using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed record CommunityRolesSaveResult(string Status, string? Error = null, long? ProfileRevision = null)
{
    public int SchemaVersion => 1;
}

internal sealed partial class CommunityClient
{
    private sealed record RolesEdit(string Code, string Scope, string TargetRef, long Revision,
        JsonElement[] Roles, DateTimeOffset Expires);
    private sealed record RolesAttempt(string Hash, CommunityRolesSaveResult Result);
    private readonly object _rolesGate = new();
    private readonly Dictionary<string, RolesEdit> _rolesEdits = new();
    private readonly Dictionary<string, RolesAttempt> _rolesAttempts = new();
    private readonly HashSet<string> _rolesUncertain = new();
    private long _rolesEpoch;

    internal void InvalidateRolesEdits()
    {
        lock (_rolesGate) { _rolesEpoch++; _rolesEdits.Clear(); }
        InvalidateWpfS2Governance();
    }

    internal Task<object> ReadRolesAsync(string bearer, JsonElement body, string scope, Action current,
        CancellationToken token) => GuardWorkspace(async () =>
    {
        Validate(body, "targetRef", "editRef");
        var reference = Optional(body, "targetRef", 32);
        var editReference = Optional(body, "editRef", 32);
        if ((reference is null) == (editReference is null)) throw Invalid();
        current();
        long epoch;
        RolesEdit? edit;
        lock (_rolesGate)
        {
            epoch = _rolesEpoch;
            edit = editReference is null ? null : ResolveRolesEdit(editReference, scope);
        }
        var code = edit?.Code ?? ResolveForRead(reference!, scope).Code;
        var root = await WorkspaceJson(bearer, "/api/fleets/roles?code=" + Uri.EscapeDataString(code), token);
        if (Encoding.UTF8.GetByteCount(root.GetRawText()) > 256 * 1024 ||
            Number(root, "schemaVersion", 1, 1) != 1 || Number(root, "membershipModelVersion", 2, 2) != 2 ||
            Text(root, "code", 256) != code) throw Invalid();
        var revision = RolesRevision(root);
        var name = Text(root, "name", 512);
        var access = root.GetProperty("access");
        if (!access.GetProperty("canEditRoles").GetBoolean()) throw new AccountBridgeHostException("communities.notAllowed");
        var canAssignMembers = access.GetProperty("canAssignMembers").GetBoolean();
        var roles = ParseRoleRows(root, "roles", draft: false);
        current();
        token.ThrowIfCancellationRequested();
        lock (_rolesGate)
        {
            if (epoch != _rolesEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
            foreach (var old in _rolesEdits.Where(row => row.Value.Expires <= DateTimeOffset.UtcNow).ToArray())
                _rolesEdits.Remove(old.Key);
            if (_rolesEdits.Count >= 128) throw new AccountBridgeHostException("communities.refreshRequired");
            var targetRef = reference ?? edit!.TargetRef;
            _targets[targetRef] = new(code, scope, DateTimeOffset.UtcNow.AddMinutes(5));
            var editRef = Guid.NewGuid().ToString("N");
            _rolesEdits[editRef] = new(code, scope, targetRef, revision, roles, DateTimeOffset.UtcNow.AddMinutes(30));
            return new { schemaVersion = 1, targetRef, editRef, code, name, profileRevision = revision,
                access = new { canEditRoles = true, canAssignMembers }, roles };
        }
    });

    private RolesEdit ResolveRolesEdit(string reference, string scope) =>
        _rolesEdits.TryGetValue(reference, out var edit) && edit.Scope == scope && edit.Expires > DateTimeOffset.UtcNow
            ? edit : throw new AccountBridgeHostException("communities.refreshRequired");

    private static long RolesRevision(JsonElement root)
    {
        var revision = root.GetProperty("profileRevision").GetInt64();
        return revision is >= 0 and <= 9007199254740991 ? revision : throw Invalid();
    }

    // Reconstruct the allowlisted projection; unknown server fields never cross the Bridge.
    private static JsonElement[] ParseRoleRows(JsonElement root, string field, bool draft)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        return Rows(root, field, 512).Select(row =>
        {
            if (row.ValueKind != JsonValueKind.Object) throw Invalid();
            var names = row.EnumerateObject().Select(p => p.Name).ToArray();
            if (names.Distinct().Count() != names.Length) throw Invalid();
            string[] editable = ["key", "displayName", "description", "color", "sortOrder", "isEnabled", "permissions"];
            if (draft && names.Any(key => !editable.Contains(key))) throw Invalid();
            foreach (var textField in new[] { "key", "displayName", "description", "color" })
                if (row.GetProperty(textField).ValueKind != JsonValueKind.String) throw Invalid();
            var key = Text(row, "key", 128);
            var name = Text(row, "displayName", 512);
            if (string.IsNullOrWhiteSpace(key) || key.Trim() != key || string.IsNullOrWhiteSpace(name) || !seen.Add(key)) throw Invalid();
            var permissions = Rows(row, "permissions", 256).Select(value =>
            {
                if (value.ValueKind != JsonValueKind.String) throw Invalid();
                var id = value.GetString()!;
                if (string.IsNullOrWhiteSpace(id) || id.Length > 128 || id.Any(char.IsControl)) throw Invalid();
                return id;
            }).ToArray();
            var data = new Dictionary<string, object?>
            {
                ["key"] = key, ["displayName"] = name, ["description"] = Text(row, "description", 4096, true),
                ["color"] = Text(row, "color", 64), ["sortOrder"] = row.GetProperty("sortOrder").GetInt32(),
                ["isEnabled"] = row.GetProperty("isEnabled").GetBoolean(), ["permissions"] = permissions
            };
            if (!draft)
            {
                data["isSystem"] = row.GetProperty("isSystem").GetBoolean();
                data["memberCount"] = Number(row, "memberCount", 0, int.MaxValue);
                data["createdAt"] = Timestamp(row, "createdAt") ?? throw Invalid();
                data["updatedAt"] = Timestamp(row, "updatedAt") ?? throw Invalid();
            }
            return JsonSerializer.SerializeToElement(data);
        }).ToArray();
    }

    internal static void ValidateRolesSave(JsonElement body)
    {
        try
        {
            Validate(body, "requestId", "editRef", "roles", "confirmUncertainRetry");
            if (Encoding.UTF8.GetByteCount(body.GetRawText()) > 256 * 1024) throw Invalid();
            foreach (var key in new[] { "requestId", "editRef" })
            {
                var reference = Text(body, key, 32);
                if (reference.Length != 32 || reference.Any(c => c is not (>= 'a' and <= 'f' or >= '0' and <= '9'))) throw Invalid();
            }
            if (body.TryGetProperty("confirmUncertainRetry", out var confirm)) confirm.GetBoolean();
            ParseRoleRows(body, "roles", draft: true);
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { throw Invalid(); }
    }

    internal async Task<CommunityRolesSaveResult> SaveRolesAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token)
    {
        ValidateRolesSave(body);
        var key = scope + "\0" + Text(body, "requestId", 32);
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(body.GetRawText())));
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var sent = false;
        var wasUncertain = false;
        string? operation = null;
        long epoch = 0;
        try
        {
            current();
            RolesEdit edit;
            lock (_rolesGate)
            {
                epoch = _rolesEpoch;
                if (_rolesAttempts.TryGetValue(key, out var previous))
                    return previous.Hash == hash ? previous.Result : new("rejected", "requestChanged");
                if (_rolesAttempts.Count >= 256) return new("rejected", "refreshRequired");
                edit = ResolveRolesEdit(Text(body, "editRef", 32), scope);
                operation = scope + "\0" + edit.Code + "\0" + edit.Revision;
                wasUncertain = _rolesUncertain.Contains(operation);
                if (wasUncertain &&
                    !(body.TryGetProperty("confirmUncertainRetry", out var confirm) && confirm.GetBoolean()))
                    return new("unknown", "outcomeUnknown");
            }
            var baseline = edit.Roles.ToDictionary(row => Text(row, "key", 128), StringComparer.OrdinalIgnoreCase);
            var drafts = ParseRoleRows(body, "roles", draft: true);
            if (edit.Roles.Any(row => row.GetProperty("isSystem").GetBoolean() &&
                !drafts.Any(draft => Text(draft, "key", 128) == Text(row, "key", 128)))) return new("rejected", "invalidDraft");
            var outgoing = drafts.Select(row =>
            {
                baseline.TryGetValue(Text(row, "key", 128), out var original);
                var exists = original.ValueKind == JsonValueKind.Object;
                var result = row.EnumerateObject().ToDictionary(p => p.Name, p => (object?)p.Value.Clone());
                result["isSystem"] = exists && original.GetProperty("isSystem").GetBoolean();
                result["createdAt"] = exists ? Timestamp(original, "createdAt") : DateTimeOffset.UtcNow.ToString("O");
                result["updatedAt"] = DateTimeOffset.UtcNow.ToString("O");
                // The owner seat's permissions are not an editable grant, even for its owner.
                if (Text(row, "key", 128) == "fleet_commander" && exists)
                {
                    result["permissions"] = original.GetProperty("permissions").Clone();
                    result["isEnabled"] = original.GetProperty("isEnabled").GetBoolean();
                }
                return result;
            }).ToArray();
            if (JsonSerializer.SerializeToUtf8Bytes(outgoing).Length > 256 * 1024) return new("rejected", "invalidDraft");
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/fleets/info?projection=roles"))
            { Content = JsonContent.Create(new { fleetCode = edit.Code, expectedProfileRevision = edit.Revision,
                updatedSections = new[] { "role-groups" }, roleGroups = outgoing }) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            current();
            token.ThrowIfCancellationRequested();
            lock (_rolesGate)
            {
                if (epoch != _rolesEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
                _rolesAttempts[key] = new(hash, new("unknown", "outcomeUnknown"));
                _rolesUncertain.Add(operation);
            }
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            CommunityRolesSaveResult receipt;
            if (response.StatusCode != HttpStatusCode.OK)
                receipt = response.StatusCode switch
                {
                    HttpStatusCode.Conflict => new("rejected", "conflict"),
                    HttpStatusCode.BadRequest => new("rejected", "invalidDraft"),
                    HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                    HttpStatusCode.NotFound => new("rejected", "refreshRequired"),
                    HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                    _ => new("unknown", "outcomeUnknown")
                };
            else
            {
                using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
                using var buffer = new MemoryStream();
                var chunk = new byte[4096]; int count;
                while ((count = await stream.ReadAsync(chunk, deadline.Token)) > 0)
                {
                    if (buffer.Length + count > 4096) throw Invalid();
                    buffer.Write(chunk, 0, count);
                }
                using var json = JsonDocument.Parse(buffer.ToArray());
                var root = json.RootElement;
                var revision = RolesRevision(root);
                if (Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "status", 16) != "accepted" || revision <= edit.Revision) throw Invalid();
                receipt = new("accepted", ProfileRevision: revision);
            }
            current();
            lock (_rolesGate)
            {
                if (epoch != _rolesEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
                _rolesAttempts[key] = new(hash, receipt);
                if (receipt.Status == "accepted") _rolesUncertain.Remove(operation);
                // A rejection of a retry cannot prove that the earlier unknown request did not commit.
                else if (receipt.Status == "rejected" && !wasUncertain)
                    _rolesUncertain.Remove(operation);
            }
            return receipt;
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or
            AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { return new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired"); }
        finally { _write.Release(); }
    }
}
