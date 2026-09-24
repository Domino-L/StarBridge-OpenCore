using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Hangar;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private const string HangarSharingPath = "/api/fleets/hangar-sharing";
    private sealed record HangarConsent(string Version, bool Explicit, string[] Codes);
    private sealed record HangarEdit(string Scope, string Version, Dictionary<string, string> Codes, string[] SelectedCodes, DateTimeOffset Expires);
    private readonly ConcurrentDictionary<string, HangarEdit> _hangarEdits = new();
    private readonly object _hangarEditGate = new();
    private long _hangarEditEpoch;

    internal void InvalidateHangarEdits() { lock (_hangarEditGate) { _hangarEditEpoch++; _hangarEdits.Clear(); } }

    internal Task<object> ReadHangarSharingAsync(string bearer, JsonElement body, string scope, Action current,
        CancellationToken token, string? legacyViewerId = null) => GuardWorkspace(async () =>
    {
        Validate(body);
        var epoch = Interlocked.Read(ref _hangarEditEpoch);
        current();
        var consent = await ReadHangarConsent(bearer, token);
        var options = new List<object>();
        var codes = new Dictionary<string, string>(StringComparer.Ordinal);
        var distinctCodes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var cursors = new HashSet<string>(StringComparer.Ordinal);
        string? after = null;
        // Existing directory authority and pagination; never infer memberships from
        // a profile, the active organization or a cached sidebar selection.
        do
        {
            current();
            var query = new CommunityQuery("mine", "", after, null);
            var page = legacyViewerId is null
                ? await ReadAsync(bearer, query, scope, token)
                : await ReadWpfS2Async(bearer, query, scope, legacyViewerId, token);
            current();
            foreach (var item in page.Items)
            {
                if (item.Relationship is not ("owner" or "member")) continue;
                var code = Resolve(item.TargetRef, scope, allowWpfS2: legacyViewerId is not null).Code.ToUpperInvariant();
                if (!distinctCodes.Add(code)) throw Invalid();
                codes.Add(item.TargetRef, code);
                options.Add(new { targetRef = item.TargetRef, name = item.Name,
                    selected = consent.Codes.Contains(code, StringComparer.OrdinalIgnoreCase) });
            }
            after = page.Next;
            if (after is not null && (!cursors.Add(after) || cursors.Count >= 200)) throw Invalid();
        } while (after is not null);
        // Membership changes during paging invalidate the editor rather than losing
        // an undisplayed selection when the user saves the visible options.
        var confirmed = await ReadHangarConsent(bearer, token);
        if (confirmed.Version != consent.Version || confirmed.Explicit != consent.Explicit ||
            !confirmed.Codes.SequenceEqual(consent.Codes) || consent.Codes.Any(code => !distinctCodes.Contains(code)))
            throw new AccountBridgeHostException("communities.refreshRequired");
        current();
        token.ThrowIfCancellationRequested();
        var editRef = Guid.NewGuid().ToString("N");
        lock (_hangarEditGate)
        {
            if (epoch != _hangarEditEpoch) throw new AccountBridgeHostException("communities.refreshRequired");
            foreach (var old in _hangarEdits.Where(row => row.Value.Scope == scope || row.Value.Expires <= _targetClock.GetUtcNow()))
                _hangarEdits.TryRemove(old.Key, out _);
            if (_hangarEdits.Count >= 128) throw new AccountBridgeHostException("communities.refreshRequired");
            _hangarEdits[editRef] = new(scope, consent.Version, codes, consent.Codes, _targetClock.GetUtcNow().AddMinutes(15));
        }
        return new { schemaVersion = 1, editRef, usesExplicitTargets = consent.Explicit, maximumTargets = 64, options };
    });

    internal static (string Reference, string[] Selected) ParseHangarSharingSave(JsonElement body)
    {
        try
        {
            Validate(body, "editRef", "selectedRefs", "inventoryMode");
            if (body.TryGetProperty("inventoryMode", out var inventoryMode) &&
                inventoryMode.GetString() is not ("saved" or "local" or "auto")) throw Invalid();
            var reference = Text(body, "editRef", 32);
            var selected = Rows(body, "selectedRefs", 64).Select(row => row.GetString() ?? "").ToArray();
            bool Valid(string value) => value.Length == 32 && value.All(char.IsAsciiHexDigit);
            if (!Valid(reference) || selected.Any(value => !Valid(value)) || selected.Distinct().Count() != selected.Length) throw Invalid();
            return (reference, selected);
        }
        catch (Exception e) when (e is InvalidOperationException or KeyNotFoundException or FormatException) { throw Invalid(); }
    }

    internal async Task<CommunityCommand> SaveHangarSharingAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token, Func<CommunityPublishedShip[]>? inventorySource = null)
    {
        var (reference, selected) = ParseHangarSharingSave(body);
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var sent = false;
        try
        {
            current();
            if (!_hangarEdits.TryGetValue(reference, out var edit) || edit.Scope != scope ||
                edit.Expires <= _targetClock.GetUtcNow() || selected.Any(row => !edit.Codes.ContainsKey(row)))
                return new("rejected", "refreshRequired");
            var codes = selected.Select(row => edit.Codes[row]).Order(StringComparer.Ordinal).ToArray();
            // A pure narrowing must remain possible even if the local scan or game
            // binding is unavailable. Equal/new selections also refresh the inventory.
            var narrowing = codes.Length < edit.SelectedCodes.Length && !codes.Except(edit.SelectedCodes).Any();
            var useSavedInventory = body.TryGetProperty("inventoryMode", out var mode) && mode.GetString() == "saved";
            CommunityPublishedShip[]? inventory = null;
            if (!useSavedInventory && codes.Length > 0 && !narrowing && inventorySource is not null)
            {
                try { inventory = inventorySource(); }
                catch (LocalHangarStoreException) when (mode.ValueKind == JsonValueKind.String && mode.GetString() == "auto")
                { /* Missing/partial/unreadable local inventory is never an empty publication. */ }
            }
            // Version is captured by an authorized read, not accepted from Flutter.
            // A consumed editor cannot silently replay an uncertain write.
            current();
            token.ThrowIfCancellationRequested();
            if (!_hangarEdits.TryRemove(reference, out _)) return new("rejected", "refreshRequired");
            using var request = new HttpRequestMessage(HttpMethod.Put, new Uri(_origin, HangarSharingPath + (inventory is null ? "" : "/publish")))
            { Content = inventory is null ? JsonContent.Create(new { schemaVersion = 1, version = edit.Version, selectedCodes = codes }) :
                JsonContent.Create(new { schemaVersion = 1, version = edit.Version, selectedCodes = codes, ships = inventory }) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode != HttpStatusCode.OK)
                return response.StatusCode switch
                {
                    HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed or HttpStatusCode.Gone => new("rejected", "upgradeRequired"),
                    HttpStatusCode.Conflict => new("rejected", "refreshRequired"),
                    HttpStatusCode.BadRequest or HttpStatusCode.RequestEntityTooLarge => new("rejected", "invalidDraft"),
                    HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                    HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                    _ => new("unknown", "outcomeUnknown")
                };
            var saved = await ParseHangarResponse(response, deadline.Token, inventory?.Length);
            current();
            token.ThrowIfCancellationRequested();
            return saved.Explicit && saved.Version != edit.Version && saved.Codes.SequenceEqual(codes)
                ? new("accepted") : new("unknown", "outcomeUnknown");
        }
        catch (LocalHangarStoreException) { return new("rejected", "localHangarRequired"); }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or
            AccountBridgeHostException or BridgeStaleGenerationException or JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
        { return new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired"); }
        finally { _write.Release(); }
    }

    private async Task<HangarConsent> ReadHangarConsent(string bearer, CancellationToken token)
    {
        try { return await ReadHangarConsentCore(bearer, token); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        { throw new AccountBridgeHostException("communities.unavailable", true); }
        catch (Exception e) when (e is HttpRequestException or IOException)
        { throw new AccountBridgeHostException("communities.unavailable", true); }
    }

    private async Task<HangarConsent> ReadHangarConsentCore(string bearer, CancellationToken token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_origin, HangarSharingPath));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
        if (response.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed or HttpStatusCode.Gone)
            throw new AccountBridgeHostException("communities.upgradeRequired");
        if (response.StatusCode == HttpStatusCode.Unauthorized) throw new AccountBridgeHostException("communities.identityUnavailable");
        if (response.StatusCode == HttpStatusCode.Forbidden) throw new AccountBridgeHostException("communities.notAllowed");
        if (response.StatusCode != HttpStatusCode.OK) throw new AccountBridgeHostException("communities.unavailable", true);
        return await ParseHangarResponse(response, deadline.Token);
    }

    private static async Task<HangarConsent> ParseHangarResponse(HttpResponseMessage response, CancellationToken token, int? publishedCount = null)
    {
        using var stream = await response.Content.ReadAsStreamAsync(token);
        var buffer = new byte[16 * 1024 + 1];
        var length = 0;
        while (length < buffer.Length)
        {
            var read = await stream.ReadAsync(buffer.AsMemory(length), token);
            if (read == 0) break;
            length += read;
        }
        if (length == buffer.Length) throw Invalid();
        using var document = JsonDocument.Parse(buffer.AsMemory(0, length));
        var root = document.RootElement;
        if (publishedCount is not null)
        {
            Validate(root, "sharing", "publishedShips");
            if (root.GetProperty("publishedShips").GetInt32() != publishedCount) throw Invalid();
            root = root.GetProperty("sharing");
        }
        Validate(root, "version", "usesExplicitTargets", "selectedCodes");
        var version = Text(root, "version", 64);
        var explicitTargets = root.GetProperty("usesExplicitTargets").GetBoolean();
        var codes = Rows(root, "selectedCodes", 64).Select(value => value.GetString() ?? "").ToArray();
        if (version.Length != 64 || version.Any(c => !char.IsAsciiHexDigit(c)) ||
            codes.Any(code => code.Length is 0 or > 128 || code != code.Trim() || code.Any(char.IsControl)) ||
            codes.Distinct(StringComparer.OrdinalIgnoreCase).Count() != codes.Length || !explicitTargets && codes.Length > 0)
            throw Invalid();
        return new(version, explicitTargets, codes.Select(code => code.ToUpperInvariant()).Order(StringComparer.Ordinal).ToArray());
    }
}
