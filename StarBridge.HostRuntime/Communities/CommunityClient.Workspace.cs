using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record MemberTarget(string MemberId, string Code, string Scope, DateTimeOffset Expires);
    private readonly ConcurrentDictionary<string, MemberTarget> _memberTargets = new();
    private readonly object _workspaceMemberGate = new();

    internal Task<object> ReadWorkspaceAsync(string bearer, JsonElement body, string scope, CancellationToken token,
        Action<Notifications.PlayerActivitySourceSnapshot>? observed = null) =>
        GuardWorkspace(() => ReadWorkspaceCore(bearer, body, scope, token, observed));
    internal Task<object> ReadMediaAsync(string bearer, JsonElement body, string scope, CancellationToken token) =>
        GuardWorkspace(() => ReadMediaCore(bearer, body, scope, token));
    private static async Task<object> GuardWorkspace(Func<Task<object>> read)
    {
        try { return await read(); }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { throw Invalid(); }
    }

    private async Task<object> ReadWorkspaceCore(string bearer, JsonElement body, string scope, CancellationToken token,
        Action<Notifications.PlayerActivitySourceSnapshot>? observed)
    {
        Validate(body, "targetRef", "query", "offset");
        var reference = Text(body, "targetRef", 32);
        var target = ResolveForRead(reference, scope, allowWpfS2: true);
        var query = Text(body, "query", 128).Trim();
        var offset = Number(body, "offset", 0, 1000000);
        var root = target.WpfS2ViewerId is not null
            ? await WpfS2Workspace(bearer, target, query, offset, token, observed)
            : await WorkspaceJson(bearer, $"/api/fleets/workspace?code={Uri.EscapeDataString(target.Code)}&q={Uri.EscapeDataString(query)}&offset={offset}", token);
        var membershipVersion = target.WpfS2ViewerId is null ? 2 : 1;
        if (Number(root, "schemaVersion", 1, 1) != 1 || Number(root, "membershipModelVersion", membershipVersion, membershipVersion) != membershipVersion ||
            Text(root, "code", 256) != target.Code || Text(root, "query", 128) != query || Number(root, "offset", 0, 1000000) != offset) throw Invalid();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var memberIds = new List<string>();
        var members = Rows(root, "members", 20).Select(member =>
        {
            var id = Text(member, "memberId", 512);
            if (id.Length == 0 || !seen.Add(id)) throw Invalid();
            memberIds.Add(id);
            var fields = Strings(member, ("gameName", 512), ("callsign", 512), ("roleTitle", 128), ("roleColor", 7),
                ("liveStatus", 64));
            var avatarVersion = Optional(member, "avatarVersion", 64);
            if (avatarVersion is not null && !LowerHex(avatarVersion, 64)) throw Invalid();
            fields["avatarVersion"] = avatarVersion;
            var color = (string)fields["roleColor"]!;
            if (color.Length != 7 || color[0] != '#' || color.Skip(1).Any(c => !Uri.IsHexDigit(c))) throw Invalid();
            foreach (var key in new[] { "isSelf", "isOwner", "online", "hasAvatar", "arrivalPendingConfirmation" }) fields[key] = member.GetProperty(key).GetBoolean();
            foreach (var key in new[] { "ship", "location", "locationConfidence", "serverRegion", "serverShard", "arrivalTargetCode" }) fields[key] = Optional(member, key, 512);
            fields["hasServerSession"] = OptionalServerSession(member);
            foreach (var key in new[] { "lastUpdated", "joinedAt" }) fields[key] = Timestamp(member, key);
            return fields;
        }).ToArray();
        var response = Strings(root, ("code", 256), ("name", 512), ("tags", 2048), ("language", 512), ("activeTime", 1024));
        response["description"] = Text(root, "description", 8192, true);
        response["schemaVersion"] = 1;
        response["targetRef"] = reference;
        response["query"] = query;
        response["offset"] = offset;
        var matched = Number(root, "matchedCount", 0, 1000000);
        var total = Number(root, "totalCount", 0, 1000000);
        int? next = root.GetProperty("next").ValueKind == JsonValueKind.Null ? null : Number(root, "next", 0, 1000000);
        if (matched > total || offset > matched || members.Length != Math.Min(20, matched - offset) ||
            next != (offset + members.Length < matched ? offset + members.Length : null)) throw Invalid();
        response["next"] = next;
        response["totalCount"] = total;
        response["matchedCount"] = matched;
        response["members"] = members;
        response["timeZoneId"] = Optional(root, "timeZoneId", 128);
        var zoneId = response["timeZoneId"] as string;
        if (!string.IsNullOrWhiteSpace(zoneId))
        {
            try
            {
                var zone = TimeZoneInfo.FindSystemTimeZoneById(zoneId);
                response["timeZoneStandardOffsetMinutes"] = (int)zone.BaseUtcOffset.TotalMinutes;
                response["timeZoneUsesDaylightSaving"] = zone.SupportsDaylightSavingTime;
            }
            catch (Exception e) when (e is TimeZoneNotFoundException or InvalidTimeZoneException)
            {
                // An unknown display zone must not make the organization unreadable.
            }
        }
        response["websiteUrl"] = Optional(root, "websiteUrl", 2048);
        response["fetchedAt"] = Timestamp(root, "fetchedAt") ?? throw Invalid();
        response["hasLogo"] = root.GetProperty("hasLogo").GetBoolean();
        response["hasBanner"] = root.GetProperty("hasBanner").GetBoolean();
        response["activeSystemIds"] = ParseSystems(root.GetProperty("activeSystemIds"));
        response["externalContacts"] = Rows(root, "externalContacts", 100).Select(row => Strings(row, ("platform", 128), ("value", 2048))).ToArray();
        response["activityWindows"] = Rows(root, "activityWindows", 3).Select(row => new
        {
            days = ParseSystems(row.GetProperty("days")), startTime = Text(row, "startTime", 5),
            endTime = Text(row, "endTime", 5), endsNextDay = row.GetProperty("endsNextDay").GetBoolean()
        }).ToArray();
        var access = root.GetProperty("access");
        var accessFlags = new[] { "isOwner", "canEditProfile", "canReviewApplications", "canRemoveMembers", "canCreateInvite", "canManageAnnouncements" }
            .ToDictionary(key => key, key => access.GetProperty(key).GetBoolean());
        foreach (var key in new[] { "canEditLogo", "canEditBanner", "canViewLogs" })
            accessFlags[key] = access.TryGetProperty(key, out var value) && value.GetBoolean();
        response["access"] = accessFlags;
        token.ThrowIfCancellationRequested();
        RenewTarget(reference, target, token);
        // Only a fully validated, authorized read may renew opaque identities.
        // Reuse is bounded by organization, account generation (scope) and lease;
        // never match by display names or expose the underlying account ID.
        lock (_workspaceMemberGate)
        {
            var now = DateTimeOffset.UtcNow;
            foreach (var old in _memberTargets.Where(p => p.Value.Expires <= now).ToArray())
                _memberTargets.TryRemove(old.Key, out _);
            if (_memberTargets.Count > 10000) _memberTargets.Clear();
            for (var i = 0; i < members.Length; i++)
            {
                var id = memberIds[i];
                var existing = _memberTargets.FirstOrDefault(p => p.Value.MemberId == id &&
                    p.Value.Code == target.Code && p.Value.Scope == scope && p.Value.Expires > now);
                var memberRef = existing.Key ?? Guid.NewGuid().ToString("N");
                _memberTargets[memberRef] = new(id, target.Code, scope, now.AddMinutes(5));
                members[i]["memberRef"] = memberRef;
            }
        }
        return response;
    }

    private static bool? OptionalServerSession(JsonElement member) =>
        !member.TryGetProperty("hasServerSession", out var session) || session.ValueKind == JsonValueKind.Null
            ? null : session.GetBoolean();

    private async Task<object> ReadMediaCore(string bearer, JsonElement body, string scope, CancellationToken token)
    {
        Validate(body, "targetRef", "kind", "memberRef", "offset", "version");
        var reference = Text(body, "targetRef", 32);
        var target = Resolve(reference, scope, allowWpfS2: true);
        var kind = Text(body, "kind", 16);
        var memberRef = Optional(body, "memberRef", 32);
        var version = Optional(body, "version", 64);
        var offset = Number(body, "offset", 0, 2 * 1024 * 1024);
        if (kind is not ("logo" or "banner" or "avatar" or "applicant") || (kind is "avatar" or "applicant") != !string.IsNullOrEmpty(memberRef) ||
            offset % (192 * 1024) != 0 || offset > 0 && version is null || version is not null &&
            (version.Length != 64 || version.Any(c => !Uri.IsHexDigit(c)))) throw Invalid();
        string? memberId = null;
        if (memberRef is not null && kind == "applicant")
        {
            if (!_admissionTargets.TryGetValue(memberRef, out var application) || application.Kind != "applications" ||
                application.Code != target.Code || application.Scope != scope || application.Expires <= DateTimeOffset.UtcNow)
                throw new AccountBridgeHostException("communities.refreshRequired");
            memberId = application.Id;
        }
        else if (memberRef is not null)
        {
            if (!_memberTargets.TryGetValue(memberRef, out var member) || member.Code != target.Code || member.Scope != scope ||
                member.Expires <= DateTimeOffset.UtcNow) throw new AccountBridgeHostException("communities.refreshRequired");
            memberId = member.MemberId;
        }
        var path = $"/api/fleets/media?code={Uri.EscapeDataString(target.Code)}&kind={kind}&offset={offset}";
        if (memberId is not null) path += "&memberId=" + Uri.EscapeDataString(memberId);
        if (version is not null) path += "&version=" + Uri.EscapeDataString(version);
        var root = target.WpfS2Directory && kind == "logo"
            ? ReadDirectoryLogo(reference, offset, version, token)
            : target.WpfS2ViewerId is not null
            ? await WpfS2Media(bearer, target, kind, memberId, offset, version, token)
            : await WorkspaceJson(bearer, path, token);
        var hash = Text(root, "version", 64);
        var mime = Text(root, "mimeType", 32);
        if (Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "kind", 16) != kind || Optional(root, "memberId", 512) != memberId ||
            hash.Length != 64 || hash.Any(c => !Uri.IsHexDigit(c)) || version is not null && hash != version ||
            Number(root, "offset", 0, 2 * 1024 * 1024) != offset || mime is not ("image/png" or "image/jpeg" or "image/bmp" or "image/gif" or "image/webp")) throw Invalid();
        var total = Number(root, "totalBytes", 1, kind == "banner" ? 2 * 1024 * 1024 : 512 * 1024);
        var data = Text(root, "data", 256 * 1024);
        var count = Convert.FromBase64String(data).Length;
        int? next = root.GetProperty("next").ValueKind == JsonValueKind.Null ? null : Number(root, "next", 0, total);
        if (offset >= total || count != Math.Min(192 * 1024, total - offset) || next != (offset + count < total ? offset + count : null)) throw Invalid();
        return new { schemaVersion = 1, kind, memberRef, version = hash, mimeType = mime, totalBytes = total, offset, next, data };
    }

    private async Task<JsonElement> WorkspaceJson(string bearer, string path, CancellationToken token, int maximumBytes = 960 * 1024)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_origin, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        try
        {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode == HttpStatusCode.Unauthorized) throw new AccountBridgeHostException("communities.identityUnavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden) throw new AccountBridgeHostException("communities.notAllowed");
            if (response.StatusCode == HttpStatusCode.Conflict) throw new AccountBridgeHostException("communities.mediaChanged");
            if (response.StatusCode == HttpStatusCode.NotFound) throw new AccountBridgeHostException("communities.notFound");
            if (!response.IsSuccessStatusCode) throw new AccountBridgeHostException("communities.unavailable", true);
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var buffer = new MemoryStream();
            var chunk = new byte[8192];
            int count;
            while ((count = await stream.ReadAsync(chunk, deadline.Token)) > 0)
            {
                if (buffer.Length + count > maximumBytes) throw Invalid();
                buffer.Write(chunk, 0, count);
            }
            using var document = JsonDocument.Parse(buffer.ToArray());
            return document.RootElement.Clone();
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested) { throw new AccountBridgeHostException("communities.unavailable", true); }
        catch (Exception e) when (e is HttpRequestException or IOException) { throw new AccountBridgeHostException("communities.unavailable", true); }
        catch (JsonException) { throw Invalid(); }
    }

    private static int Number(JsonElement value, string key, int min, int max)
    {
        var number = value.GetProperty(key).GetInt32();
        return number >= min && number <= max ? number : throw Invalid();
    }
    private static JsonElement[] Rows(JsonElement value, string key, int max)
    {
        var rows = value.GetProperty(key);
        if (rows.GetArrayLength() > max) throw Invalid();
        return rows.EnumerateArray().ToArray();
    }
    private static Dictionary<string, object?> Strings(JsonElement value, params (string Key, int Max)[] fields) =>
        fields.ToDictionary(field => field.Key, field => (object?)Text(value, field.Key, field.Max));
    private static string? Timestamp(JsonElement value, string key)
    {
        var text = Optional(value, key, 64);
        if (text is not null && !DateTimeOffset.TryParse(text, out _)) throw Invalid();
        return text;
    }
}
