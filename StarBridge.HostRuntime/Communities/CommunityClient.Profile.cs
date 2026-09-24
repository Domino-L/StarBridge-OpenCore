using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Fleets;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed record CommunityProfileSaveResult(string Status, string? Error = null, long? ProfileRevision = null)
{
    public int SchemaVersion => 1;
    internal string? OrganizationCode { get; init; }
    internal string? OrganizationName { get; init; }
}

internal sealed partial class CommunityClient
{
    private sealed record ProfileEdit(string Code, string Scope, string TargetRef, long Revision,
        JsonElement Profile, bool CanEditProfile, bool CanEditLogo, bool CanEditBanner, DateTimeOffset Expires);
    private sealed record ProfileAttempt(string Hash, CommunityProfileSaveResult Result);
    private readonly ConcurrentDictionary<string, ProfileEdit> _profileEdits = new();
    private readonly ConcurrentDictionary<string, ProfileAttempt> _profileAttempts = new();
    private readonly object _profileCacheGate = new();
    private long _profileEpoch;
    internal void InvalidateProfileEdits()
    {
        lock (_profileCacheGate) { _profileEpoch++; _profileEdits.Clear(); _wpfS2ProfileEdits.Clear(); }
    }
    private static readonly Dictionary<string, int> ProfileTexts = new()
    {
        ["name"] = 512,
        ["description"] = 8192, ["type"] = 2048, ["activeTime"] = 1024, ["joinPolicy"] = 32,
        ["logoText"] = 128, ["activeDaysDescription"] = 1024, ["activityCadence"] = 128,
        ["timeZoneId"] = 128, ["recruitingTarget"] = 512, ["recruitingNote"] = 2048,
        ["inviteCodeCreationPolicy"] = 32, ["fleetInvitationCardPolicy"] = 32,
        ["publicMemberScaleMode"] = 32, ["publicShipScaleMode"] = 32, ["language"] = 512, ["websiteUrl"] = 2048
    };
    private static readonly string[] ProfileFlags = ["emailNotificationsEnabled", "recruitingEnabled", "publicListingEnabled",
        "publicShowDescription", "publicShowTags", "publicShowActiveSystems", "publicShowActivityTime", "publicShowExternalContacts"];

    internal Task<object> ReadProfileAsync(string bearer, JsonElement body, string scope, CancellationToken token) =>
        GuardWorkspace(async () =>
        {
            var epoch = Interlocked.Read(ref _profileEpoch);
            Validate(body, "targetRef", "editRef");
            var reference = Optional(body, "targetRef", 32);
            var editReference = Optional(body, "editRef", 32);
            if ((reference is null) == (editReference is null)) throw Invalid();
            var edit = editReference is null ? null : ResolveProfileEdit(editReference, scope);
            var code = edit?.Code ?? ResolveForRead(reference!, scope).Code;
            var root = await WorkspaceJson(bearer, "/api/fleets/profile?code=" + Uri.EscapeDataString(code), token);
            return CaptureProfile(root, code, scope, reference ?? edit!.TargetRef, epoch);
        });

    private object CaptureProfile(JsonElement root, string code, string scope, string targetRef, long epoch)
    {
        var (revision, profile, access) = ParseProfile(root, code);
        var name = Text(root, "name", 512);
        var hasLogo = root.GetProperty("hasLogo").GetBoolean();
        var hasBanner = root.GetProperty("hasBanner").GetBoolean();
        lock (_profileCacheGate)
        {
            if (epoch != _profileEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
            foreach (var old in _profileEdits.Where(row => row.Value.Expires <= DateTimeOffset.UtcNow).ToArray())
                _profileEdits.TryRemove(old.Key, out _);
            if (_profileEdits.Count >= 128) throw new AccountBridgeHostException("communities.refreshRequired");
            // A fresh authorized editor read also refreshes the existing target
            // used for media and workspace reload after a long editing session.
            _targets[targetRef] = new(code, scope, DateTimeOffset.UtcNow.AddMinutes(5));
            var editRef = Guid.NewGuid().ToString("N");
            _profileEdits[editRef] = new(code, scope, targetRef, revision, profile, access["canEditProfile"],
                access["canEditLogo"], access["canEditBanner"], DateTimeOffset.UtcNow.AddMinutes(30));
            return new
            {
                schemaVersion = 1, targetRef, editRef, code, name, profileRevision = revision, hasLogo, hasBanner,
                access, profile
            };
        }
    }

    private static (long Revision, JsonElement Profile, Dictionary<string, bool> Access) ParseProfile(JsonElement root, string code)
    {
        if (Number(root, "schemaVersion", 1, 1) != 1 || Number(root, "membershipModelVersion", 2, 2) != 2 || Text(root, "code", 256) != code) throw Invalid();
        var revision = root.GetProperty("profileRevision").GetInt64();
        if (revision is < 0 or > 9007199254740991) throw Invalid();
        var source = root.GetProperty("profile");
        var fields = new Dictionary<string, object?>();
        foreach (var (key, max) in ProfileTexts)
        {
            if (key == "name") { fields[key] = Text(root, "name", max); continue; }
            var value = source.GetProperty(key);
            fields[key] = value.ValueKind == JsonValueKind.Null ? null : Text(source, key, max, key == "description");
        }
        foreach (var key in ProfileFlags) fields[key] = source.GetProperty(key).GetBoolean();
        fields["activityWindows"] = ReadProfileWindows(source);
        fields["activeSystemIds"] = ParseSystems(source.GetProperty("activeSystemIds"));
        fields["externalContacts"] = ReadProfileContacts(source);
        var access = new[] { "canEditProfile", "canEditLogo", "canEditBanner" }
            .ToDictionary(key => key, key => root.GetProperty("access").GetProperty(key).GetBoolean());
        if (!access.Values.Any(value => value)) throw Invalid();
        return (revision, JsonSerializer.SerializeToElement(fields), access);
    }

    private static object[] ReadProfileWindows(JsonElement source) => Rows(source, "activityWindows", 3).Select(row => (object)new
    {
        days = ParseSystems(row.GetProperty("days")), startTime = Text(row, "startTime", 5),
        endTime = Text(row, "endTime", 5), endsNextDay = row.GetProperty("endsNextDay").GetBoolean()
    }).ToArray();
    private static object[] ReadProfileContacts(JsonElement source) => Rows(source, "externalContacts", 5)
        .Select(row => (object)Strings(row, ("platform", 128), ("value", 2048))).ToArray();
    private ProfileEdit ResolveProfileEdit(string reference, string scope) =>
        _profileEdits.TryGetValue(reference, out var edit) && edit.Scope == scope && edit.Expires > DateTimeOffset.UtcNow
            ? edit : throw new AccountBridgeHostException("communities.refreshRequired");

    internal static void ValidateProfileSave(JsonElement body)
    {
        try
        {
            Validate(body, "requestId", "editRef", "changes");
            foreach (var key in new[] { "requestId", "editRef" })
            {
                var value = Text(body, key, 32);
                if (value.Length != 32 || value.Any(c => c is not (>= 'a' and <= 'f' or >= '0' and <= '9'))) throw Invalid();
            }
            var changes = body.GetProperty("changes");
            if (changes.ValueKind != JsonValueKind.Object || !changes.EnumerateObject().Any()) throw Invalid();
            var seen = new HashSet<string>();
            foreach (var entry in changes.EnumerateObject())
            {
                if (!seen.Add(entry.Name)) throw Invalid();
                if (ProfileTexts.TryGetValue(entry.Name, out var max))
                {
                    if (entry.Value.ValueKind != JsonValueKind.String) throw Invalid();
                    Text(changes, entry.Name, max, entry.Name == "description");
                    if (!CommunityProfileEditingRules.TextFits(entry.Name, entry.Value.GetString()!) ||
                        (entry.Name == "type" && !CommunityProfileEditingRules.TagsFit(entry.Value.GetString()!))) throw Invalid();
                }
                else if (ProfileFlags.Contains(entry.Name) || entry.Name is "clearLogoImage" or "clearBannerImage")
                    entry.Value.GetBoolean();
                else if (entry.Name == "logoImageData")
                {
                    var data = Text(changes, entry.Name, 700000);
                    var comma = data.IndexOf(',');
                    if (comma < 0 || data[..comma] is not ("data:image/png;base64" or "data:image/jpeg;base64" or "data:image/bmp;base64") ||
                        Convert.FromBase64String(data[(comma + 1)..]).Length is 0 or > 512 * 1024) throw Invalid();
                }
                else if (entry.Name == "activityWindows")
                {
                    ReadProfileWindows(changes);
                    foreach (var window in entry.Value.EnumerateArray())
                    {
                        var days = CreationArray(window, "days", 7);
                        if (days.Length == 0 || days.Any(day => day is not ("mon" or "tue" or "wed" or "thu" or "fri" or "sat" or "sun")) ||
                            !LegacyFleetCreationRules.IsTime24(Text(window, "startTime", 5)) ||
                            !LegacyFleetCreationRules.IsTime24(Text(window, "endTime", 5)) ||
                            !CommunityProfileEditingRules.ActivityWindowFits(Text(window, "startTime", 5), Text(window, "endTime", 5), window.GetProperty("endsNextDay").GetBoolean())) throw Invalid();
                    }
                }
                else if (entry.Name == "activeSystemIds")
                {
                    var systems = CreationArray(changes, entry.Name, 3);
                    if (systems.Length == 0 || systems.Any(id => id is not ("stanton" or "pyro" or "nyx"))) throw Invalid();
                }
                else if (entry.Name == "externalContacts") ReadProfileContacts(changes);
                else throw Invalid(); // In particular, no roles, identity, revision, URL or arbitrary banner upload.
            }
            if (changes.TryGetProperty("joinPolicy", out var policy) && policy.GetString() is not ("Open" or "Approval" or "Invite")) throw Invalid();
            if (changes.TryGetProperty("publicMemberScaleMode", out var memberScale) && memberScale.GetString() is not ("Exact" or "Approx" or "Hidden")) throw Invalid();
            if (changes.TryGetProperty("publicShipScaleMode", out var shipScale) && shipScale.GetString() is not ("TypeSummary" or "TotalOnly" or "Hidden")) throw Invalid();
            if (changes.TryGetProperty("timeZoneId", out var zone) && zone.GetString() != "UTC" &&
                !TimeZoneInfo.GetSystemTimeZones().Any(value => value.Id == zone.GetString())) throw Invalid();
            foreach (var key in new[] { "inviteCodeCreationPolicy", "fleetInvitationCardPolicy" })
                if (changes.TryGetProperty(key, out var value) && value.GetString() is not ("all_members" or "management" or "commander")) throw Invalid();
            if (changes.TryGetProperty("logoImageData", out _) && changes.TryGetProperty("clearLogoImage", out var clear) && clear.GetBoolean()) throw Invalid();
        }
        catch (Exception e) when (e is InvalidOperationException or KeyNotFoundException or FormatException or JsonException)
        { throw Invalid(); }
    }

    internal async Task<CommunityProfileSaveResult> SaveProfileAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token)
    {
        ValidateProfileSave(body);
        var editRef = Text(body, "editRef", 32);
        var key = scope + "\0" + Text(body, "requestId", 32);
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(body.GetRawText())));
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var sent = false;
        try
        {
            current();
            if (_profileAttempts.TryGetValue(key, out var previous))
                return previous.Hash == hash ? previous.Result : new("rejected", "requestChanged");
            if (_profileAttempts.Count >= 256) return new("rejected", "refreshRequired");
            var edit = ResolveProfileEdit(editRef, scope);
            var changes = body.GetProperty("changes");
            var sections = new HashSet<string>();
            var outgoing = edit.Profile.EnumerateObject().Where(row => row.Name != "name").ToDictionary(row => row.Name, row => (object?)row.Value.Clone());
            foreach (var entry in changes.EnumerateObject())
            {
                var section = entry.Name switch { "name" => "name", "logoText" or "logoImageData" or "clearLogoImage" => "logo", "clearBannerImage" => "banner",
                    "description" => "description", "emailNotificationsEnabled" => "email-notifications", _ => "profile" };
                if (!(section switch { "logo" => edit.CanEditLogo, "banner" => edit.CanEditBanner, _ => edit.CanEditProfile }))
                    return new("rejected", "notAllowed");
                sections.Add(section);
                outgoing[entry.Name] = entry.Value.Clone();
            }
            outgoing["fleetCode"] = edit.Code;
            ValidateRecruitmentChange(changes, outgoing);
            outgoing["expectedProfileRevision"] = edit.Revision;
            outgoing["updatedSections"] = sections.Order().ToArray();
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/fleets/info?projection=profile"))
                { Content = JsonContent.Create(outgoing) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            current();
            token.ThrowIfCancellationRequested();
            _profileAttempts[key] = new(hash, new("unknown", "outcomeUnknown"));
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            CommunityProfileSaveResult result;
            if (!response.IsSuccessStatusCode)
                result = response.StatusCode switch
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
                var chunk = new byte[8192]; int count;
                while ((count = await stream.ReadAsync(chunk, deadline.Token)) > 0)
                {
                    if (buffer.Length + count > 96 * 1024) throw Invalid();
                    buffer.Write(chunk, 0, count);
                }
                using var json = JsonDocument.Parse(buffer.ToArray());
                var (revision, _, _) = ParseProfile(json.RootElement, edit.Code);
                if (changes.TryGetProperty("name", out var renamed) && Text(json.RootElement, "name", 512) != renamed.GetString()!.Trim()) throw Invalid();
                if (revision <= edit.Revision) throw Invalid();
                current();
                // Receipt only. Even a repeated accepted request cannot resurrect cached
                // private profile data; the editor must perform an authorized fresh read.
                result = new("accepted", ProfileRevision: revision) {
                    OrganizationCode = changes.TryGetProperty("name", out _) ? edit.Code : null,
                    OrganizationName = changes.TryGetProperty("name", out _) ? Text(json.RootElement, "name", 512) : null
                };
            }
            _profileAttempts[key] = new(hash, result);
            return result;
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or
            AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException)
        {
            var result = new CommunityProfileSaveResult(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired");
            if (sent) _profileAttempts[key] = new(hash, result);
            return result;
        }
        finally { _write.Release(); }
    }

    private static void ValidateRecruitmentChange(JsonElement changes, Dictionary<string, object?> outgoing)
    {
        if (!new[] { "recruitingEnabled", "publicListingEnabled", "joinPolicy" }.Any(key => changes.TryGetProperty(key, out _))) return;
        var state = JsonSerializer.SerializeToElement(outgoing);
        if (!CommunityProfileEditingRules.RecruitmentFits(
            state.GetProperty("recruitingEnabled").GetBoolean(),
            state.GetProperty("publicListingEnabled").GetBoolean(),
            state.GetProperty("joinPolicy").GetString())) throw Invalid();
    }
}
