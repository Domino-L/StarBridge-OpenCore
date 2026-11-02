using System.Collections.Concurrent;
using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private const string OfficialHangarPath = "/api/official-fleets/hangar-sharing";
    private const int OfficialHangarPageSize = 100, OfficialHangarMaximumSelected = 10000;
    private sealed record OfficialHangarTarget(string AuthorityNamespace, long OrganizationId, string Sid, string MembershipEpoch)
    { internal string SourceRef => "officialFleet:" + OrganizationId.ToString(CultureInfo.InvariantCulture); }
    private sealed record OfficialHangarIntent(OfficialHangarTarget Target, string Revision, string Strategy, int SelectedCount,
        OfficialHangarImageFeatures? Images = null, int? ImageCount = null);
    private sealed record OfficialHangarCurrent(string State, OfficialHangarTarget? Target, string? Version,
        string? Revision, string? Strategy, string[] Selected, OfficialHangarImageFeatures? Images = null, string[]? ImageGrantRefs = null);
    private sealed record OfficialHangarScope(string AccountScope, OfficialHangarTarget Target, DateTimeOffset Expires);
    private sealed record OfficialHangarOption(string Ref, string InstanceId, string? Name, bool InInventory);
    private sealed record OfficialHangarEdit(string AccountScope, string SourceRef, OfficialHangarTarget Target,
        string? Version, string? Revision, string? Strategy, string[] Selected, long? LocalRevision, bool CanGrant,
        OfficialHangarOption[] Options, DateTimeOffset Expires, OfficialHangarImageFeatures? Images = null, string[]? ImageGrantRefs = null);
    private readonly ConcurrentDictionary<string, OfficialHangarEdit> _officialHangarEdits = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, OfficialHangarScope> _officialHangarScopes = new(StringComparer.Ordinal);
    private readonly object _officialHangarGate = new();
    private long _officialHangarEpoch;

    private void InvalidateOfficialHangarEdits()
    {
        lock (_officialHangarGate) { _officialHangarEpoch++; _officialHangarEdits.Clear(); _officialHangarScopes.Clear(); }
    }

    internal Task<object> ReadOfficialHangarSharingAsync(string bearer, JsonElement body, string accountScope,
        Action current, Func<LocalHangarSnapshot> localSource, CancellationToken token, bool negotiateImages = false) => GuardWorkspace(async () =>
    {
        Validate(body, "sourceRef", "scopeRef");
        var requestedSource = Optional(body, "sourceRef", 64);
        var requestedScope = Optional(body, "scopeRef", 32);
        if (requestedSource is not null && !OfficialHangarSource(requestedSource) || requestedScope is not null && !OfficialHangarRef(requestedScope)) throw Invalid();
        var epoch = Interlocked.Read(ref _officialHangarEpoch);
        current();
        var actual = await ReadOfficialHangarCurrent(bearer, token, negotiateImages);
        current();
        var intents = await ReadOfficialHangarIntents(bearer, token, negotiateImages);
        return await ObserveOfficialHangarRead("official-hangar-project", () =>
        {
            current();
            OfficialHangarTarget? chosen = null;
            if (requestedScope is not null)
            {
                if (!_officialHangarScopes.TryGetValue(requestedScope, out var scope) || scope.AccountScope != accountScope || scope.Expires <= _targetClock.GetUtcNow())
                    throw new AccountBridgeHostException("communities.refreshRequired");
                chosen = scope.Target;
            }
            else if (actual.Target is not null && (requestedSource is null || actual.Target.SourceRef == requestedSource)) chosen = actual.Target;
            else chosen = intents.FirstOrDefault(intent => requestedSource is null || intent.Target.SourceRef == requestedSource)?.Target;
            var previous = intents.SingleOrDefault(intent => intent.Target == chosen);
            if (requestedScope is not null && previous is null && actual.Target != chosen) throw new AccountBridgeHostException("communities.refreshRequired");
            var isCurrent = chosen is not null && actual.Target == chosen && actual.Version is not null &&
                actual.State is "available" or "selectionRequired" or "unavailable";
            if (isCurrent && previous?.Revision != actual.Revision) throw new AccountBridgeHostException("communities.refreshRequired");

            LocalHangarSnapshot? local = null;
            var inventoryState = "unavailable";
            try
            {
                local = localSource();
                inventoryState = local.Revision < 1 || local.SavedAt is null ? "missing" : local.Partial ? "partial" : "complete";
                if (local.Ships.Count > 10000 || local.Ships.Any(ship => string.IsNullOrWhiteSpace(ship.Id) || ship.Id.Length > 128 ||
                        ship.Title.Length > 512 || ship.Title.Any(char.IsControl)) || local.Ships.Select(ship => ship.Id).Distinct(StringComparer.Ordinal).Count() != local.Ships.Count)
                    throw new LocalHangarStoreException("hangar.unavailable", "Invalid local inventory.");
            }
            catch (Exception failure) when (failure is LocalHangarStoreException or IOException or UnauthorizedAccessException)
            { local = null; inventoryState = "unavailable"; }
            current(); token.ThrowIfCancellationRequested();
            var selected = isCurrent ? actual.Selected : [];
            var names = local?.Ships.ToDictionary(ship => ship.Id, ship => ship.Title, StringComparer.Ordinal) ?? [];
            var options = (isCurrent ? names.Keys.Concat(selected) : []).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal)
                .Select(id => new OfficialHangarOption(Guid.NewGuid().ToString("N"), id, names.GetValueOrDefault(id), names.ContainsKey(id))).ToArray();
            if (options.Length > 20000) throw Invalid();
            var targets = intents.Select(intent => intent.Target).Concat(actual.Target is null ? [] : new[] { actual.Target }).Distinct().ToArray();
            var scopes = new List<object>();
            string? chosenRef = null;
            var editRef = Guid.NewGuid().ToString("N");
            var now = _targetClock.GetUtcNow();
            lock (_officialHangarGate)
            {
                if (epoch != _officialHangarEpoch) throw new AccountBridgeHostException("communities.refreshRequired");
                foreach (var old in _officialHangarEdits.Where(pair => pair.Value.AccountScope == accountScope || pair.Value.Expires <= now).ToArray())
                    _officialHangarEdits.TryRemove(old.Key, out _);
                foreach (var old in _officialHangarScopes.Where(pair => pair.Value.Expires <= now).ToArray()) _officialHangarScopes.TryRemove(old.Key, out _);
                if (_officialHangarEdits.Count >= 8 || _officialHangarScopes.Count + targets.Length > 1024) throw new AccountBridgeHostException("communities.refreshRequired");
                foreach (var target in targets)
                {
                    var reference = _officialHangarScopes.FirstOrDefault(pair => pair.Value.AccountScope == accountScope && pair.Value.Target == target).Key ?? Guid.NewGuid().ToString("N");
                    _officialHangarScopes[reference] = new(accountScope, target, now.AddMinutes(15));
                    if (target == chosen) chosenRef = reference;
                    scopes.Add(new { scopeRef = reference, name = target.Sid, isCurrent = target == actual.Target });
                }
                if (chosen is not null)
                    _officialHangarEdits[editRef] = new(accountScope, chosen.SourceRef, chosen, isCurrent ? actual.Version : null,
                        previous?.Revision, isCurrent ? actual.Strategy : previous?.Strategy, selected,
                        local?.Revision, isCurrent, options, now.AddMinutes(15), isCurrent ? actual.Images : previous?.Images, isCurrent ? actual.ImageGrantRefs : null);
            }
            var selectedIds = selected.ToHashSet(StringComparer.Ordinal);
            var selectedRefs = options.Where(option => selectedIds.Contains(option.InstanceId)).Select(option => option.Ref).ToArray();
            var response = new
            {
                schemaVersion = 1,
                editRef,
                sourceRef = chosen?.SourceRef,
                state = isCurrent ? actual.State : actual.State == "available" ? "forbidden" : actual.State,
                strategy = isCurrent ? actual.Strategy : previous?.Strategy,
                inventoryState,
                canGrant = isCurrent,
                canPublish = isCurrent && inventoryState == "complete",
                canReduce = previous is not null,
                selectionKnown = isCurrent,
                selectedCount = isCurrent ? selected.Length : previous?.SelectedCount ?? 0,
                maximumSelected = OfficialHangarMaximumSelected,
                selectedRefs,
                imageFeatures = negotiateImages ? OfficialImageFeatureView(isCurrent ? actual.Images : previous?.Images) : null,
                imageCount = isCurrent ? actual.ImageGrantRefs?.Length ?? 0 : previous?.ImageCount ?? 0,
                canClearImages = previous is not null && (isCurrent ? actual.Images : previous.Images)?.Reduce == true &&
                    (isCurrent ? actual.ImageGrantRefs?.Length ?? 0 : previous.ImageCount ?? 0) > 0,
                scopes,
                scopeRef = chosenRef,
                page = OfficialHangarPage(editRef, options, 0)
            };
            return Task.FromResult(ObserveOfficialHangarShape(BoundOfficialHangar(response)));
        });
    });

    private static object OfficialImageFeatureView(OfficialHangarImageFeatures? features)=>new {
        protocolVersion=1,read=features?.Read==true,upload=features?.Upload==true,report=features?.Report==true,reduce=features?.Reduce==true };
    internal bool OfficialImageGrantEditorSupported(JsonElement body,string scope)=>
        _officialHangarEdits.TryGetValue(Text(body,"editRef",32),out var edit) && edit.AccountScope==scope &&
        edit.SourceRef==Text(body,"sourceRef",64) && edit.Expires>_targetClock.GetUtcNow() &&
        edit.Images is {Read:true,Upload:true,Report:true,Reduce:true};

    internal object ReadOfficialHangarSharingPage(JsonElement body, string accountScope, Action current)
    {
        Validate(body, "sourceRef", "editRef", "offset"); current();
        var reference = Text(body, "editRef", 32); var source = Text(body, "sourceRef", 64);
        var offset = Number(body, "offset", 0, 20000);
        if (!OfficialHangarRef(reference) || offset % OfficialHangarPageSize != 0 ||
            !_officialHangarEdits.TryGetValue(reference, out var edit) || edit.AccountScope != accountScope || edit.SourceRef != source || edit.Expires <= _targetClock.GetUtcNow() ||
            offset > edit.Options.Length) throw new AccountBridgeHostException("communities.refreshRequired");
        return BoundOfficialHangar(OfficialHangarPage(reference, edit.Options, offset));
    }

    private static object OfficialHangarPage(string reference, OfficialHangarOption[] options, int offset) => new
    {
        schemaVersion = 1,
        editRef = reference,
        offset,
        totalOptions = options.Length,
        next = offset + OfficialHangarPageSize < options.Length ? (int?)(offset + OfficialHangarPageSize) : null,
        options = options.Skip(offset).Take(OfficialHangarPageSize).Select(option => new
        {
            shipRef = option.Ref,
            name = option.Name,
            missing = !option.InInventory,
            grantable = option.InInventory
        }).ToArray()
    };

    internal static void ValidateOfficialHangarSave(JsonElement body)
    {
        Validate(body, "sourceRef", "editRef", "strategy", "selectedRefs");
        if (!OfficialHangarRef(Text(body, "editRef", 32)) || !OfficialHangarSource(Text(body, "sourceRef", 64)) ||
            Text(body, "strategy", 32) is not ("notShared" or "organizationPool" or "operationOnly")) throw Invalid();
        var refs = Rows(body, "selectedRefs", OfficialHangarMaximumSelected).Select(row => row.GetString() ?? "").ToArray();
        if (refs.Any(value => !OfficialHangarRef(value)) || refs.Distinct(StringComparer.Ordinal).Count() != refs.Length ||
            Text(body, "strategy", 32) != "organizationPool" && refs.Length != 0) throw Invalid();
    }

    internal Task<CommunityCommand> SaveOfficialHangarSharingAsync(string bearer, JsonElement body, string accountScope,
        Action current, Func<LocalHangarSnapshot> localSource, CancellationToken token) =>
        SaveOfficialHangarSharingCore(bearer, body, accountScope, current, localSource, token, null);

    private async Task<CommunityCommand> SaveOfficialHangarSharingCore(string bearer, JsonElement body, string accountScope,
        Action current, Func<LocalHangarSnapshot> localSource, CancellationToken token, OfficialHangarImageOperation? images)
    {
        if (images?.ClearOnly == true) Validate(body, "sourceRef", "editRef"); else ValidateOfficialHangarSave(body);
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var sent = false;
        // Plain V1 keeps its existing caller-owned timeout. The image lane alone
        // owns one budget, created before local reads/identity IO, never per upload.
        try
        {
            using var imageBudget = images is null ? null : new CancellationTokenSource(TimeSpan.FromSeconds(12), _targetClock);
            using var linkedBudget = imageBudget is null ? null : CancellationTokenSource.CreateLinkedTokenSource(token, imageBudget.Token);
            if (linkedBudget is not null) token = linkedBudget.Token;
            current();
            var sourceEpoch = Interlocked.Read(ref _officialHangarEpoch);
            var reference = Text(body, "editRef", 32); var strategy = images?.ClearOnly == true ? "" : Text(body, "strategy", 32);
            var selectedRefs = images?.ClearOnly == true ? [] : Rows(body, "selectedRefs", OfficialHangarMaximumSelected).Select(row => row.GetString()!).ToArray();
            if (!_officialHangarEdits.TryGetValue(reference, out var edit) || edit.AccountScope != accountScope ||
                edit.SourceRef != Text(body, "sourceRef", 64) || edit.Expires <= _targetClock.GetUtcNow()) return new("rejected", "refreshRequired");
            void ScopeCurrent()
            {
                current();
                if (sourceEpoch != Interlocked.Read(ref _officialHangarEpoch)) throw new AccountBridgeHostException("communities.refreshRequired");
            }
            if (images?.ClearOnly == true)
                return await ClearOfficialImages(bearer, reference, edit, ScopeCurrent, () => sent = true, token);
            if (images is not null && (edit.Images?.Upload != true || strategy != "organizationPool")) return new("rejected", "upgradeRequired");
            var mapped = edit.Options.ToDictionary(option => option.Ref, option => option.InstanceId, StringComparer.Ordinal);
            if (selectedRefs.Any(value => !mapped.ContainsKey(value))) return new("rejected", "invalidDraft");
            var selected = selectedRefs.Select(value => mapped[value]).Order(StringComparer.Ordinal).ToArray();
            var reduction = images is null && edit.Revision is not null && (strategy == "notShared" || edit.Strategy == "organizationPool" && strategy == "organizationPool" &&
                selected.Length < edit.Selected.Length && !selected.Except(edit.Selected, StringComparer.Ordinal).Any());
            CommunityPublishedShip[]? inventory = null;
            LocalHangarSnapshot? snapshot = null;
            if (!reduction)
            {
                if (!edit.CanGrant || edit.Version is null) return new("rejected", "notAllowed");
                if (strategy == "organizationPool")
                {
                    snapshot = localSource();
                    if (snapshot.Revision != edit.LocalRevision) return new("rejected", "localInventoryChanged");
                    inventory = CommunityHangarPublication.Build(snapshot);
                    if (selected.Except(inventory.Select(ship => ship.Id), StringComparer.Ordinal).Any()) return new("rejected", "localInventoryChanged");
                }
            }
            current(); token.ThrowIfCancellationRequested();
            // Consumption precedes send; post-send errors are values, never an
            // exception that can make an OAuth retry replay an uncertain write.
            OfficialHangarImageGrant[]? imageGrants = null;
            if (images is not null)
            {
                var owner = await images.ReadOwner!(token);
                if (!Regex.IsMatch(owner, "^scm-v1:[a-f0-9]{64}$")) throw Invalid();
                void ImageCurrent()
                {
                    ScopeCurrent();
                    if (localSource().Revision != snapshot!.Revision) throw new LocalHangarStoreException("hangar.revision_conflict", "Local inventory changed.");
                }
                imageGrants = await HangarImagePublication.PrepareSelectedAsync(snapshot!, selected, owner,
                    id => images.ReadImage!(snapshot!.Revision, id),
                    (image, ct) => UploadOfficialImage(bearer, edit, image, ImageCurrent, () => sent = true, ct),
                    () => { if (!_officialHangarEdits.TryRemove(reference, out _)) throw Invalid(); }, ImageCurrent, token);
                current(); token.ThrowIfCancellationRequested();
                return await PublishOfficialImages(bearer, edit, strategy, selected, inventory!, imageGrants, owner, ImageCurrent, () => sent = true, token);
            }
            if (!_officialHangarEdits.TryRemove(reference, out _)) return new("rejected", "refreshRequired");
            using var request = new HttpRequestMessage(HttpMethod.Put, new Uri(_origin, OfficialHangarPath + (reduction ? "/reduce" : inventory is not null ? "/publish" : "")));
            request.Content = reduction
                ? JsonContent.Create(new { schemaVersion = 1, target = edit.Target, expectedRevision = edit.Revision, strategy, instanceRefs = selected })
                : inventory is not null
                ? JsonContent.Create(new { schemaVersion = 1, target = edit.Target, version = edit.Version, strategy, instanceRefs = selected, ships = inventory })
                : JsonContent.Create(new { schemaVersion = 1, target = edit.Target, version = edit.Version, strategy, instanceRefs = selected });
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            if (response.StatusCode != HttpStatusCode.OK) return response.StatusCode switch
            {
                HttpStatusCode.Conflict => new("rejected", "refreshRequired"),
                HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                HttpStatusCode.PreconditionRequired => new("rejected", "localHangarRequired"),
                HttpStatusCode.BadRequest or HttpStatusCode.RequestEntityTooLarge => new("rejected", "invalidDraft"),
                HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed => new("rejected", "upgradeRequired"),
                _ => new("unknown", "outcomeUnknown")
            };
            var root = await ReadOfficialHangarJson(response, token);
            current(); token.ThrowIfCancellationRequested();
            if (Number(root, "schemaVersion", 1, 1) != 1) throw Invalid();
            var saved = root.GetProperty(reduction ? "intent" : "sharing");
            var acknowledged = Text(saved, "strategy", 32) == strategy &&
                Rows(saved, "instanceRefs", OfficialHangarMaximumSelected).Select(row => row.GetString()).Order(StringComparer.Ordinal).SequenceEqual(selected);
            if (reduction) acknowledged &= ParseOfficialHangarTarget(saved.GetProperty("target")) == edit.Target && OfficialHangarRef(Text(saved, "revision", 32)) && Text(saved, "revision", 32) != edit.Revision;
            else acknowledged &= Text(saved, "state", 32) == "available" && Regex.IsMatch(Text(saved, "version", 64), "^[a-f0-9]{64}$") &&
                Text(saved, "version", 64) != edit.Version && OfficialHangarRef(Text(root, "intentRevision", 32)) && Text(root, "intentRevision", 32) != edit.Revision;
            return acknowledged ? new("accepted") : new("unknown", "outcomeUnknown");
        }
        catch (LocalHangarStoreException) { return new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "localHangarRequired"); }
        catch (Exception failure) when (failure is HttpRequestException or IOException or OperationCanceledException or AccountBridgeHostException or
            BridgeStaleGenerationException or JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
        { return new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired"); }
        finally { _write.Release(); }
    }

    private async Task<OfficialHangarCurrent> ReadOfficialHangarCurrent(string bearer, CancellationToken token, bool negotiateImages = false)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_origin, OfficialHangarPath));
        request.Headers.Authorization = new("Bearer", bearer);
        if (negotiateImages) request.Headers.Add(OfficialImageHeader, "2");
        using var response = await ObserveOfficialHangarRead("official-hangar-current-http",
            () => _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token));
        if (response.StatusCode == HttpStatusCode.Unauthorized)
            return await ObserveOfficialHangarRead<OfficialHangarCurrent>("official-hangar-current-parse",
                () => throw new AccountBridgeHostException("communities.identityUnavailable"), (int)response.StatusCode);
        if (response.StatusCode != HttpStatusCode.OK)
        {
            var state = response.StatusCode == HttpStatusCode.Forbidden ? "forbidden" : "unavailable";
            try
            {
                state = await ObserveOfficialHangarRead("official-hangar-current-parse", async () =>
                {
                    var failure = await ReadOfficialHangarJson(response, token);
                    return Optional(failure, "error", 64) == "stale" ? "stale" : state;
                }, (int)response.StatusCode);
            }
            catch (Exception failure) when (failure is JsonException or AccountBridgeHostException or InvalidOperationException or KeyNotFoundException) { }
            return new(state, null, null, null, null, []);
        }
        return await ObserveOfficialHangarRead<OfficialHangarCurrent>("official-hangar-current-parse", async () =>
        {
            var root = await ReadOfficialHangarJson(response, token);
            var protocol = Number(root, "schemaVersion", 1, negotiateImages ? 2 : 1);
            var target = ParseOfficialHangarTarget(root.GetProperty("target"));
            var sharing = root.GetProperty("sharing");
            var stateText = Text(sharing, "state", 32); var strategy = Optional(sharing, "strategy", 32);
            var version = Optional(sharing, "version", 64); var revision = Optional(root, "intentRevision", 32);
            var selected = Rows(sharing, "instanceRefs", OfficialHangarMaximumSelected).Select(row => row.GetString() ?? "").ToArray();
            if (stateText is not ("available" or "selectionRequired" or "unavailable" or "stale" or "forbidden") ||
                strategy is not (null or "notShared" or "organizationPool" or "operationOnly") ||
                version is not null && !Regex.IsMatch(version, "^[a-f0-9]{64}$") || revision is not null && !OfficialHangarRef(revision) ||
                selected.Any(value => value.Length is < 1 or > 128 || value != value.Trim() || value.Any(char.IsControl)) ||
                selected.Distinct(StringComparer.Ordinal).Count() != selected.Length || strategy != "organizationPool" && selected.Length != 0) throw Invalid();
            var features = protocol == 2 ? ReadOfficialImageFeatures(root) : null;
            var grants = protocol == 2 ? ReadOfficialImageConsent(root) : null;
            if (grants?.Length > selected.Length) throw Invalid();
            return new(stateText, target, version, revision, strategy, selected, features, grants);
        }, (int)response.StatusCode);
    }

    private async Task<OfficialHangarIntent[]> ReadOfficialHangarIntents(string bearer, CancellationToken token, bool negotiateImages = false)
    {
        var items = new List<OfficialHangarIntent>(); int offset = 0; int? total = null;
        do
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_origin, OfficialHangarPath + "/intents?offset=" + offset + "&limit=20"));
            request.Headers.Authorization = new("Bearer", bearer);
            if (negotiateImages) request.Headers.Add(OfficialImageHeader, "2");
            using var response = await ObserveOfficialHangarRead("official-hangar-intents-http",
                () => _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token));
            await ObserveOfficialHangarRead("official-hangar-intents-parse", async () =>
            {
                if (response.StatusCode != HttpStatusCode.OK) throw new AccountBridgeHostException(response.StatusCode == HttpStatusCode.Unauthorized ? "communities.identityUnavailable" : "communities.unavailable", true);
                var root = await ReadOfficialHangarJson(response, token); var page = root.GetProperty("intents");
                var count = Number(page, "totalCount", 0, 100);
                var protocol = Number(root, "schemaVersion", 1, negotiateImages ? 2 : 1);
                var features = protocol == 2 ? ReadOfficialImageFeatures(root) : null;
                if (Text(page, "state", 32) != "available" || Number(page, "offset", 0, 100) != offset ||
                    Number(page, "limit", 20, 20) != 20 || total is not null && total != count) throw Invalid();
                total = count;
                var rows = Rows(page, "items", 20);
                if (rows.Length != Math.Min(20, count - offset) || page.GetProperty("hasMore").GetBoolean() != (offset + rows.Length < count)) throw Invalid();
                foreach (var row in rows)
                {
                    var target = ParseOfficialHangarTarget(row.GetProperty("target")); var revision = Text(row, "revision", 32); var strategy = Text(row, "strategy", 32);
                    var selected = Number(row, "selectedCount", 0, OfficialHangarMaximumSelected);
                    if (!OfficialHangarRef(revision) || strategy is not ("notShared" or "organizationPool" or "operationOnly") ||
                        strategy != "organizationPool" && selected != 0 || Rows(row, "instanceRefs", 0).Length != 0 || items.Any(item => item.Target == target)) throw Invalid();
                    var imageCount = protocol == 2 ? Number(row, "imageCount", 0, selected) : (int?)null;
                    items.Add(new(target, revision, strategy, selected, features, imageCount));
                }
                offset += rows.Length;
                return true;
            }, (int)response.StatusCode);
        } while (offset < total);
        return items.ToArray();
    }

    private static bool OfficialHangarRef(string value) => Regex.IsMatch(value, "^[a-f0-9]{32}$");
    private static bool OfficialHangarSource(string value) => Regex.IsMatch(value, "^officialFleet:[1-9][0-9]{0,18}$") &&
        long.TryParse(value.AsSpan("officialFleet:".Length), NumberStyles.None, CultureInfo.InvariantCulture, out _);
    private static OfficialHangarTarget ParseOfficialHangarTarget(JsonElement raw)
    {
        var names = new[] { "authorityNamespace", "organizationId", "sid", "membershipEpoch" };
        if (raw.ValueKind != JsonValueKind.Object || raw.EnumerateObject().Count() != names.Length || names.Any(name => !raw.TryGetProperty(name, out _))) throw Invalid();
        var ns = Text(raw, "authorityNamespace", 256); var sid = Text(raw, "sid", 10); var epoch = Text(raw, "membershipEpoch", 64);
        if (string.IsNullOrWhiteSpace(ns) || ns != ns.Trim() || ns.Any(char.IsControl) || !raw.GetProperty("organizationId").TryGetInt64(out var id) || id <= 0 ||
            !Regex.IsMatch(sid, "^[A-Z0-9]{1,10}$") || !Regex.IsMatch(epoch, "^scm-observed-membership-row-v1:[1-9][0-9]{0,18}$") ||
            !long.TryParse(epoch.AsSpan("scm-observed-membership-row-v1:".Length), NumberStyles.None, CultureInfo.InvariantCulture, out _)) throw Invalid();
        return new(ns, id, sid, epoch);
    }
    private static object BoundOfficialHangar(object value)
    {
        if (JsonSerializer.SerializeToUtf8Bytes(value).Length > 768 * 1024) throw Invalid();
        return value;
    }
    private static async Task<JsonElement> ReadOfficialHangarJson(HttpResponseMessage response, CancellationToken token, int maximum = 2 * 1024 * 1024)
    {
        if (response.Content.Headers.ContentLength > maximum) throw Invalid();
        await using var stream = await response.Content.ReadAsStreamAsync(token);
        var bytes = new byte[maximum + 1]; int count = 0;
        while (count < bytes.Length) { int read = await stream.ReadAsync(bytes.AsMemory(count), token); if (read == 0) break; count += read; }
        if (count > maximum) throw Invalid();
        using var document = JsonDocument.Parse(bytes.AsMemory(0, count)); return document.RootElement.Clone();
    }
}
