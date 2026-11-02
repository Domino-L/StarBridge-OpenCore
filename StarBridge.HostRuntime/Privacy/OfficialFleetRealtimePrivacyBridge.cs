using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

// An adapter to the existing signed local privacy store, not another settings owner.
internal sealed class OfficialFleetRealtimePrivacyBridge(LocalPrivacyStore store,
    Func<(BridgeAccountContext? Owner, long Generation)> current,
    Func<BridgeAccountContext,long,CancellationToken,Task<OfficialRealtimeContextWire>> readContext,
    Func<bool> enabled)
{
    private sealed record Context(BridgeAccountContext Owner, long Generation, OfficialFleetRealtimeTarget Target,
        string ExpectedServerRevision, bool Positive, bool AudienceSupported = false);
    private readonly Dictionary<string, Context> _contexts = new(StringComparer.Ordinal);
    private readonly object _gate = new();
    private Context? _currentScope;
    private string? _scopeRef;
    internal bool AudienceSupported {
        get { lock (_gate) return enabled() && _currentScope is { AudienceSupported: true } scope &&
            current() == (scope.Owner, scope.Generation); }
    }
    internal async Task<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token)
    {
        try {
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = current();
            bool Current() => !token.IsCancellationRequested && current() == owner;
            if (owner.Owner is null || request.AccountContext != owner.Owner || request.SessionGeneration != owner.Generation ||
                request.MessageType != BridgeMessageTypes.Request || !Current()) throw new LocalPrivacyException("privacy_local.account_changed");
            if (!enabled()) return Error(request, BridgeErrorCodes.CapabilityUnavailable);
            var body = request.Payload; LocalPrivacyStore.RejectDuplicates(body);
            if (body.GetRawText().Length > 4096 || body.GetProperty("schemaVersion").GetInt32() != 1) throw new LocalPrivacyException("privacy_local.invalid_request");
            if (request.Name == "privacy.officialFleetRead") {
                if (body.EnumerateObject().Any(p => p.Name != "schemaVersion")) throw new LocalPrivacyException("privacy_local.invalid_request");
                var saved = store.Read(owner.Owner); string? selected = null; string state = "unavailable"; string? source = null;
                OfficialFleetRealtimeTarget? currentTarget = null; bool canSave = false; string? scopeRef = null;
                try {
                    var remote = await readContext(owner.Owner, owner.Generation, token);
                    if (!Current()) throw new LocalPrivacyException("privacy_local.account_changed");
                    var fresh = new Context(owner.Owner, owner.Generation, remote.Target, remote.ExpectedRevision, remote.WritesAvailable, remote.AudienceRankSupported);
                    scopeRef = RememberScope(fresh); selected = Remember(fresh);
                    source = remote.SourceRef; state = "available"; currentTarget = remote.Target; canSave = remote.WritesAvailable;
                } catch (Account.AccountBridgeHostException) { if (!Current()) throw new LocalPrivacyException("privacy_local.account_changed"); }
                finally { if (currentTarget is null) RetirePositive(owner.Owner, owner.Generation); }
                var choice = saved.Settings?.OfficialFleet;
                var cancel = choice is null ? null : Remember(new(owner.Owner, owner.Generation, choice.Target, choice.ExpectedServerRevision, false));
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, state, sourceRef = source,
                    scopeRef, contextRef = selected, cancelContextRef = cancel, saved.Revision,
                    // A default editor suggestion is neither a saved target nor
                    // permission to publish. Never reinterpret an existing choice
                    // (including all-off or another membership epoch) as missing.
                    // store.Read above throws on invalid storage, before defaults.
                    fields = choice is not null && choice.Target == currentTarget ? choice.Fields :
                        choice is null && canSave ? CommunityRealtimeScope.SupportedFields : PlayerSharedStateFields.None,
                    savedFields = choice?.Fields ?? PlayerSharedStateFields.None, savedForCurrentSource = choice is not null && choice.Target == currentTarget,
                    maximumRankValue = JsonSerializer.SerializeToElement(choice?.MaximumRankValue), audienceRankSupported = AudienceSupported,
                    choiceRequired = choice is null && canSave,
                    canSave, canCancel = choice is not null && choice.Fields != PlayerSharedStateFields.None, publicationApplied = false }), []);
            }
            if (request.Name != "privacy.officialFleetSave" || body.EnumerateObject().Any(p => p.Name is not
                ("schemaVersion" or "contextRef" or "expectedRevision" or "operationId" or "fields" or "maximumRankValue")))
                throw new LocalPrivacyException("privacy_local.invalid_request");
            Context? context; lock (_gate) _contexts.TryGetValue(body.GetProperty("contextRef").GetString() ?? "", out context);
            var fields = (PlayerSharedStateFields)body.GetProperty("fields").GetInt32();
            var audienceSpecified = body.TryGetProperty("maximumRankValue", out var rank);
            var maximum = audienceSpecified && rank.ValueKind != JsonValueKind.Null ? rank.GetInt32() : (int?)null;
            if (maximum is not (null or >= 1 and <= 4)) throw new LocalPrivacyException("privacy_local.invalid_request");
            if (context is null || context.Owner != owner.Owner || context.Generation != owner.Generation ||
                !context.Positive && fields != 0 || (fields & ~CommunityRealtimeScope.SupportedFields) != 0)
                throw new LocalPrivacyException("privacy_local.account_changed");
            var requested = maximum;
            var operation = body.GetProperty("operationId").GetString()!;
            var expected = body.GetProperty("expectedRevision").GetInt64();
            (LocalPrivacySettings Settings, int? Maximum) Merge(LocalPrivacySnapshot saved)
            {
                var audience = requested;
                // A legacy Bridge editor cannot silently erase a newer restrictive
                // choice while changing its fields. Explicit null selects everyone;
                // a full withdrawal needs no retained audience restriction.
                if (!audienceSpecified && fields != 0 && saved.Settings?.OfficialFleet is { } retainedChoice && retainedChoice.Target == context.Target)
                    audience = retainedChoice.MaximumRankValue;
                if (fields == 0) audience = null;
                var merged = saved.Settings ?? new LocalPrivacySettings(true,
                    new(PlayerSharedStateFields.None, false, false, []), new(PlayerSharedStateFields.None, false), []);
                if (!context.Positive && merged.OfficialFleet?.Target != context.Target) throw new LocalPrivacyException("privacy_local.changed");
                return (merged with { OfficialFleet = new(context.Target, fields, context.ExpectedServerRevision, operation, audience) }, audience);
            }
            var previous = store.Read(owner.Owner);
            (var settings, maximum) = Merge(previous);
            // Acknowledging an exact durable operation performs no publication.
            // Reuse the store's comparison, then let SaveAsync recheck under its
            // admission/lock; new operations still need fresh remote evidence.
            var committed = LocalPrivacyStore.IsCommittedOperation(previous, expected, operation, settings);
            if (!committed && maximum is not null) {
                if (!context.AudienceSupported) return Error(request, "official_fleet.audience_unsupported");
                var remote = await readContext(owner.Owner, owner.Generation, token);
                if (!Current()) throw new LocalPrivacyException("privacy_local.account_changed");
                if (!remote.AudienceRankSupported) { RetirePositive(owner.Owner, owner.Generation); return Error(request, "official_fleet.audience_unsupported"); }
                if (!remote.WritesAvailable || remote.Target != context.Target || remote.ExpectedRevision != context.ExpectedServerRevision)
                    throw new LocalPrivacyException("privacy_local.changed");
            }
            var checkedMaximum = maximum;
            var next = await store.SaveMergedAsync(owner.Owner, expected, operation, saved =>
            {
                var locked = Merge(saved);
                // The remote check above covered this audience and no other.
                if (locked.Maximum != checkedMaximum) throw new LocalPrivacyException("privacy_local.changed");
                return locked.Settings;
            }, Current, token).ConfigureAwait(false);
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, next.Revision, next.OperationId,
                fields, maximumRankValue = JsonSerializer.SerializeToElement(maximum), state = "saved", publicationApplied = false }), []);
        }
        catch (LocalPrivacyException error) { return Error(request, error.Code); }
        catch (Account.AccountBridgeHostException error) { return Error(request, error.Code); }
        catch (TimeoutException) { return Error(request, "privacy_publication.timeout"); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or
            OverflowException or BridgeProtocolException or ArgumentException) { return Error(request, "privacy_local.invalid_request"); }
    }
    private void RetirePositive(BridgeAccountContext owner, long generation) {
        lock (_gate) {
            foreach (var key in _contexts.Where(p => p.Value.Positive && p.Value.Owner == owner && p.Value.Generation == generation).Select(p => p.Key).ToArray()) _contexts.Remove(key);
            if (_currentScope?.Owner == owner && _currentScope.Generation == generation) _currentScope = null;
        }
    }
    private string RememberScope(Context value) {
        lock (_gate) {
            if (_currentScope is null || _currentScope.Owner != value.Owner || _currentScope.Generation != value.Generation || _currentScope.Target != value.Target || _currentScope.AudienceSupported != value.AudienceSupported) {
                foreach (var key in _contexts.Where(p => p.Value.Positive).Select(p => p.Key).ToArray()) _contexts.Remove(key);
                _scopeRef = Guid.NewGuid().ToString("N");
            }
            _currentScope = value; return _scopeRef!;
        }
    }
    private string Remember(Context value) {
        lock (_gate) { while (_contexts.Count >= 64) _contexts.Remove(_contexts.Keys.First());
            var key = Guid.NewGuid().ToString("N"); _contexts.Add(key, value); return key; }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Official realtime choice unavailable.", true)), []);
}
