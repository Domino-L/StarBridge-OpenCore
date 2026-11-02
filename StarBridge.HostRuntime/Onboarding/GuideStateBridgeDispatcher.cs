using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Onboarding;

public sealed class GuideStateBridgeDispatcher : IBridgeRequestDispatcher
{
    public const string Capability = "guide.state.v1";
    public const string ReadRequest = "guide.state.read";
    public const string UpdateRequest = "guide.state.update";
    public static bool Handles(string name) => name is ReadRequest or UpdateRequest;
    private readonly GuideStateStore _store;
    private readonly Func<FirstUseModeRuntime.GuideScope?> _scope;
    private readonly Func<long> _generation;
    private readonly object _gate = new();
    private volatile bool _disposed;
    internal GuideStateBridgeDispatcher(string root, Func<FirstUseModeRuntime.GuideScope?> scope, Func<long> generation)
    { _store = new(root); _scope = scope; _generation = generation; }
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        lock (_gate)
        {
            try
            {
                token.ThrowIfCancellationRequested();
                BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
                if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null || !Handles(request.Name))
                    GuideStateStore.Invalid();
                var ops = Validate(request.Payload, request.Name == UpdateRequest);
                bool SessionCurrent() => !_disposed && request.SessionGeneration >= 0 && request.SessionGeneration == _generation() && !token.IsCancellationRequested;
                if (!SessionCurrent()) return ValueTask.FromResult(Error(request, "guide.context_changed"));
                var scope = _scope();
                if (scope is null) return ValueTask.FromResult(new BridgeDispatchBatch(
                    BridgeEnvelope.Response(request, new { schemaVersion = 1, state = "unavailable" }, preserveRequestAccountContext: false), []));
                bool Current() => SessionCurrent() && scope == _scope();
                var value = request.Name == ReadRequest ? _store.Read(scope.ProfileId) : _store.Update(scope.ProfileId, ops, Current);
                if (!Current()) return ValueTask.FromResult(Error(request, "guide.context_changed"));
                return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(request, new {
                    schemaVersion = 1, state = "ready", eligible = value.Eligible, seen = value.Seen,
                    checklist = new { collapsed = value.Checklist.Collapsed, dismissed = value.Checklist.Dismissed,
                        celebrated = value.Checklist.Celebrated, done = value.Checklist.Done }
                }, preserveRequestAccountContext: false), []));
            }
            catch (LocalFirstUseException e) { return ValueTask.FromResult(Error(request, e.Code)); }
            catch (OperationCanceledException) { return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.CancelledResponse(request with { AccountContext = null }), [])); }
            catch (Exception e) when (e is JsonException or InvalidOperationException or ArgumentException or KeyNotFoundException)
            { return ValueTask.FromResult(Error(request, "guide.invalid_request")); }
            catch { return ValueTask.FromResult(Error(request, "guide.storage_failed")); }
        }
    }

    private static JsonElement[] Validate(JsonElement payload, bool update)
    {
        Fields(payload, update ? ["ops"] : [], update ? 1 : 0);
        if (!update) return [];
        var list = payload.GetProperty("ops");
        if (list.ValueKind != JsonValueKind.Array || list.GetArrayLength() is < 1 or > 16) GuideStateStore.Invalid();
        var ops = list.EnumerateArray().ToArray();
        foreach (var op in ops)
        {
            if (op.ValueKind != JsonValueKind.Object || !op.TryGetProperty("op", out var kind) || kind.ValueKind != JsonValueKind.String)
                GuideStateStore.Invalid();
            var name = op.GetProperty("op").GetString();
            switch (name)
            {
                case "markSeen": case "markDone":
                    Fields(op, ["op", "id"], 2);
                    if (op.GetProperty("id").ValueKind != JsonValueKind.String || !GuideStateStore.ValidId(op.GetProperty("id").GetString())) GuideStateStore.Invalid();
                    break;
                case "markEligible": case "resetSeen": case "resetChecklist": Fields(op, ["op"], 1); break;
                case "setChecklist":
                    Fields(op, ["op", "collapsed", "dismissed", "celebrated"], 2, exact: false);
                    foreach (var p in op.EnumerateObject())
                        if (p.Name != "op" && p.Value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) GuideStateStore.Invalid();
                    break;
                default: GuideStateStore.Invalid(); break;
            }
        }
        return ops;
    }
    private static void Fields(JsonElement value, string[] allowed, int count, bool exact = true)
    {
        if (value.ValueKind != JsonValueKind.Object) GuideStateStore.Invalid();
        var names = value.EnumerateObject().Select(p => p.Name).ToArray();
        if ((exact ? names.Length != count : names.Length < count) || names.Except(allowed, StringComparer.Ordinal).Any() ||
            names.Distinct(StringComparer.Ordinal).Count() != names.Length) GuideStateStore.Invalid();
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request with { AccountContext = null }, new(code, "Guide state could not be saved or read.", true)), []);
    public void Dispose() => _disposed = true;
}
