using System.Text.Json;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

public sealed class NotificationPolicyBridgeDispatcher(NotificationSettingsBridgeDispatcher settings,
    IBridgeRequestDispatcher account, Func<(BridgeAccountContext? Context, long Generation)> owner) : IBridgeRequestDispatcher
{
    public static IReadOnlyList<string> Capabilities { get; } = ["notificationPolicies.read", "notificationPolicies.save"];
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
            var save = request.Name.EndsWith("save", StringComparison.Ordinal);
            var body = request.Payload;
            LocalPrivacyStore.RejectDuplicates(body);
            string[] fields = save ? ["schemaVersion", "expectedRevision", "operationId", "rules"] : ["schemaVersion"];
            if (body.GetRawText().Length > 32768 || body.GetProperty("schemaVersion").GetInt32() != 1 ||
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
            var sources = targets.Communities.Select(row => new {
                sourceRef = NotificationPolicyStore.Organization(row.Code, row.JoinedAt), kind = "community",
                displayName = row.Name, logoImageData = row.LogoImageData
            }).ToArray();
            if (sources.Select(row => row.sourceRef).Distinct().Count() != sources.Length) return Error("sources_unavailable");
            var valid = sources.Select(row => row.sourceRef).Concat(["room", "friends", "directMessages"]).ToHashSet(StringComparer.Ordinal);
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
                snapshot = settings.SavePolicies(context.Context, expected, operation, rules, Current);
            }
            if (!Current()) return Error("account_changed");
            string Mode(string source) => snapshot.For(source) switch {
                NotificationSourceMode.Normal => "normal", NotificationSourceMode.ImportantOnly => "importantOnly", _ => "doNotDisturb"
            };
            return new(BridgeEnvelope.Response(request, new {
                schemaVersion = 1, revision = snapshot.Revision, operationId = snapshot.OperationId,
                sources = sources.Select(row => new { row.sourceRef, row.kind, row.displayName, row.logoImageData, mode = Mode(row.sourceRef) }),
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
    private sealed record BridgeTargets(
        [property: System.Text.Json.Serialization.JsonRequired] int SchemaVersion,
        string? PrimaryFleetCode,
        [property: System.Text.Json.Serialization.JsonRequired] CommunitySharingTarget[] Communities);
}
