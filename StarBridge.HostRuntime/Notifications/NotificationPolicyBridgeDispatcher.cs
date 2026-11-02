using System.Text.Json;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

public sealed class NotificationPolicyBridgeDispatcher(NotificationSettingsBridgeDispatcher settings,
    IBridgeRequestDispatcher account, Func<(BridgeAccountContext? Context, long Generation)> owner) : IBridgeRequestDispatcher
{
    public static IReadOnlyList<string> Capabilities { get; } = ["notificationPolicies.read", "notificationPolicies.save",
        "notificationPolicies.readV2", "notificationPolicies.saveV2"];
    private sealed record Source(string SourceRef, string Kind, string DisplayName, string? LogoImageData,
        string? OrganizationCode = null);
    private bool _disposed;
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public void Dispose() => _disposed = true;
    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        try {
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var context = owner();
            bool Current() => !_disposed && !cancellationToken.IsCancellationRequested && owner() == context;
            if (!Current() || context.Context is null || request.AccountContext != context.Context || request.SessionGeneration != context.Generation ||
                request.MessageType != BridgeMessageTypes.Request || !Capabilities.Contains(request.Name)) return Error("account_changed");
            var v2 = request.Name.EndsWith("V2", StringComparison.Ordinal);
            var save = request.Name is "notificationPolicies.save" or "notificationPolicies.saveV2";
            var body = request.Payload;
            LocalPrivacyStore.RejectDuplicates(body);
            string[] fields = save ? ["schemaVersion", "expectedRevision", "operationId", "rules"] : ["schemaVersion"];
            if (body.GetRawText().Length > 32768 || body.GetProperty("schemaVersion").GetInt32() != (v2 ? 2 : 1) ||
                body.EnumerateObject().Count() != fields.Length || body.EnumerateObject().Any(p => !fields.Contains(p.Name))) return Error("invalid_request");
            // Reuse the established authenticated membership/logo reader, not a
            // second directory or a client-supplied organization identity.
            var read = BridgeEnvelope.Request("privacy.communityTargets", Guid.NewGuid().ToString("N"), context.Generation,
                new { schemaVersion = 1 }, context.Context);
            var directory = (await account.DispatchAsync(read, cancellationToken)).Response;
            if (!Current()) return Error("account_changed");
            if (directory.Status != "ok" || directory.AccountContext != context.Context || directory.SessionGeneration != context.Generation)
                return Error("sources_unavailable");
            // Bridge responses omit null properties. Keep the HTTP DTO strict,
            // but accept an omitted primary fleet in this internal projection.
            var targets = directory.Payload.Deserialize<BridgeTargets>(LocalPrivacyStore.Json);
            if (targets is null || targets.SchemaVersion != 2 || targets.Communities is null || targets.Communities.Length > 64) return Error("sources_unavailable");
            var sources = targets.Communities.Select(row => new Source(
                NotificationPolicyStore.Organization(row.Code, row.JoinedAt), "community", row.Name, row.LogoImageData, row.Code)).ToList();
            var official = v2 ? await ReadOfficialSource(context.Context, context.Generation, Current, cancellationToken) : null;
            if (official != null) sources.Add(official);
            if (!Current()) return Error("account_changed");
            if (sources.Select(row => row.SourceRef).Distinct().Count() != sources.Count) return Error("sources_unavailable");
            var valid = sources.Select(row => row.SourceRef).Concat(["room", "friends", "directMessages"]).ToHashSet(StringComparer.Ordinal);
            var snapshot = settings.ReadPolicies(context.Context);
            if (save) {
                var input = body.GetProperty("rules");
                if (input.ValueKind != JsonValueKind.Array || input.GetArrayLength() > 128) return Error("invalid_request");
                var rules = input.EnumerateArray().Select(row => {
                    if (row.EnumerateObject().Count() != 2 || row.EnumerateObject().Any(p => p.Name is not ("sourceRef" or "mode"))) throw new JsonException();
                    var key = row.GetProperty("sourceRef").GetString() ?? throw new JsonException();
                    if (!valid.Contains(key)) throw new JsonException();
                    return new NotificationPolicyRule(key, row.GetProperty("mode").GetString() switch {
                        "normal" => NotificationSourceMode.Normal,
                        "importantOnly" => NotificationSourceMode.ImportantOnly,
                        "doNotDisturb" => NotificationSourceMode.DoNotDisturb,
                        _ => throw new JsonException()
                    });
                }).ToArray();
                var expected = body.GetProperty("expectedRevision").GetInt64();
                var operation = body.GetProperty("operationId").GetString() ?? "";
                if (expected < 0 || expected == long.MaxValue || !Guid.TryParseExact(operation, "N", out _) ||
                    rules.Select(rule => rule.Source).Distinct().Count() != rules.Length) return Error("invalid_request");
                if (v2) {
                    var fresh = await ReadOfficialSource(context.Context, context.Generation, Current, cancellationToken);
                    if (fresh?.SourceRef != official?.SourceRef) return Error("sources_unavailable");
                }
                // V1 cannot represent official rules. Saving an older editor
                // must not silently reset an official source to normal. Keep
                // inactive official preferences as well; these grant no access.
                rules = [.. rules, .. snapshot.Rules.Where(rule => NotificationPolicyStore.IsOfficialFleetKey(rule.Source) &&
                    (!v2 || !valid.Contains(rule.Source)))];
                snapshot = settings.SavePolicies(context.Context, expected, operation, rules, Current);
            }
            if (!Current()) return Error("account_changed");
            string Mode(string source) => snapshot.For(source) switch {
                NotificationSourceMode.Normal => "normal", NotificationSourceMode.ImportantOnly => "importantOnly", _ => "doNotDisturb"
            };
            return new(BridgeEnvelope.Response(request, new {
                schemaVersion = v2 ? 2 : 1, revision = snapshot.Revision, operationId = snapshot.OperationId,
                sources = sources.Select(row => new { sourceRef = row.SourceRef, kind = row.Kind, displayName = row.DisplayName,
                    organizationCode = v2 && !save ? row.OrganizationCode : null,
                    logoImageData = row.LogoImageData, mode = Mode(row.SourceRef) }),
                roomMode = Mode("room"), friendMode = Mode("friends"), directMessageMode = Mode("directMessages")
            }), []);
        } catch (NotificationSettingsConflictException) { return Error("write_conflict"); }
        catch (Account.AccountBridgeHostException) { return Error("sources_unavailable"); }
        catch (HttpRequestException) { return Error("sources_unavailable"); }
        catch (OperationCanceledException) { return Error("account_changed"); }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or ArgumentException or
            FormatException or OverflowException or BridgeProtocolException) { return Error("invalid_request"); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return Error("storage_unavailable"); }
        BridgeDispatchBatch Error(string code) => new(BridgeEnvelope.ErrorResponse(request,
            new("notificationPolicies." + code, "Notification source rules are unavailable.")), []);
    }
    private async Task<Source?> ReadOfficialSource(BridgeAccountContext context, long generation, Func<bool> current, CancellationToken token)
    {
        async Task<BridgeEnvelope> Read(string command, bool authenticated) {
            var request = BridgeEnvelope.Request(command, Guid.NewGuid().ToString("N"), generation,
                new { schemaVersion = 1 }, authenticated ? context : null);
            var response = (await account.DispatchAsync(request, token)).Response;
            if (!current()) throw new OperationCanceledException();
            if (response.Status != "ok" || response.AccountContext != context || response.SessionGeneration != generation ||
                response.Payload.GetProperty("schemaVersion").GetInt32() != 1)
                throw new Account.AccountBridgeHostException("communities.identityUnavailable");
            return response;
        }
        var identity = await Read("account.getCurrent", false);
        var state = identity.Payload.GetProperty("state").GetString();
        if (state == "legacySignedIn") return null; // Explicit owner selection, never an SCM failure fallback.
        if (state != "signedIn") throw new Account.AccountBridgeHostException("communities.identityUnavailable");
        var official = (await Read("officialFleet.getIdentity", true)).Payload;
        if (!official.TryGetProperty("freshness", out var freshness) || freshness.GetString() != "live")
            throw new Account.AccountBridgeHostException("communities.identityUnavailable");
        if (official.GetProperty("state").GetString() == "notMember" &&
            (!official.TryGetProperty("fleet", out var absent) || absent.ValueKind == JsonValueKind.Null)) return null;
        if (official.GetProperty("state").GetString() != "member") throw new JsonException();
        var fleet = official.GetProperty("fleet");
        var name = fleet.GetProperty("name").GetString();
        if (name is null || string.IsNullOrWhiteSpace(name) || name.Length > 256 || name.Any(char.IsControl)) throw new JsonException();
        var source = fleet.GetProperty("sourceRef").GetString() ?? throw new JsonException();
        return new(NotificationPolicyStore.OfficialFleet(source), "officialFleet", name, null);
    }
    private sealed record BridgeTargets(
        [property: System.Text.Json.Serialization.JsonRequired] int SchemaVersion,
        string? PrimaryFleetCode,
        [property: System.Text.Json.Serialization.JsonRequired] CommunitySharingTarget[] Communities);
}
