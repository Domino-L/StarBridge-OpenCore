using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Lifecycle;

namespace StarBridge.HostRuntime.Onboarding;

public interface IFirstUseLogPicker
{
    Task<string?> PickAsync(string locale, CancellationToken token);
}

// Coordinates the existing Native owners; no renderer identity, file path,
// consent boolean or installation claim is accepted by this protocol.
public sealed partial class FirstUseBridgeDispatcher : IBridgeRequestDispatcher
{
    public const string Capability = "onboarding.firstUse.v1";
    public static bool Handles(string name) => name is "onboarding.read" or "onboarding.execute" or "onboarding.saveProgress" or "onboarding.finish";
    private readonly AccountBridgeRuntime _root;
    private readonly NativeAccountRuntimeBinding _native;
    private readonly FirstUseModeRuntime _mode;
    private readonly FirstUseCompletionRuntime _completion;
    private readonly FirstUseStartupReader _startup;
    private readonly LocalFirstUseStore _local;
    private readonly FirstUseCompletionStore _completed;
    private readonly LocalLogEvidenceOwner _evidence;
    private readonly IFirstUseLogPicker _picker;
    private readonly Action<AccountBridgeRuntime> _configure;
    private readonly Func<string> _locale;
    private readonly AsyncWorkRetirement _work = new();
    private readonly SemaphoreSlim _gate = new(1, 1);
    private volatile bool _closed;
    private Issued? _issued;
    private sealed record Issued(string Key, string Fingerprint, long Generation);
    private sealed record View(Dictionary<string, object?> Facts, LocalFirstUseSnapshot Local,
        FirstUseCompletionObservation Completion, Dictionary<string, object?>? Completed, long Generation)
    {
        internal string Fingerprint => Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new { Facts, Local, Completed, Generation })));
    }

    internal FirstUseBridgeDispatcher(string root, AccountBridgeRuntime account, NativeAccountRuntimeBinding native,
        FirstUseStartupReader startup, IFirstUseLogPicker picker, Action<AccountBridgeRuntime> configure,
        Func<string> locale)
    {
        _root = account; _native = native; _startup = startup; _picker = picker; _configure = configure; _locale = locale;
        _mode = account.FirstUseMode ?? throw new InvalidOperationException("First-use mode owner missing.");
        _completion = account.FirstUseCompletion ?? throw new InvalidOperationException("First-use completion owner missing.");
        _local = new(root); _completed = new(root);
        _evidence = new(_local, current: () => !_closed && _mode.AllowsLocalIdentitySetup);
    }
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        using var work = _work.Enter(token);
        if (work is null) return Error(request, "firstUse.context_changed");
        var cancel = request.Name == "onboarding.execute" && request.Payload.ValueKind == JsonValueKind.Object &&
            request.Payload.TryGetProperty("action", out var action) && action.ValueKind == JsonValueKind.String && action.GetString() == "cancelLogin";
        var entered = false;
        try
        {
            work.Token.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_closed || request.SessionGeneration < 0 || request.SessionGeneration != _mode.ControlGeneration)
                return Error(request, "firstUse.context_changed");
            if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null || !Handles(request.Name))
                return Error(request, "firstUse.invalid_request");
            ValidateBody(request);
            if (!cancel)
            {
                entered = await _gate.WaitAsync(0, work.Token).ConfigureAwait(false);
                if (!entered) return Error(request, "firstUse.operation_in_progress");
            }
            var view = await Capture(work.Token).ConfigureAwait(false);
            Dictionary<string, object?>? saved = null;
            if (request.Name != "onboarding.read")
            {
                var issued = _issued;
                if (issued is null || request.Payload.GetProperty("expectedStateKey").GetString() != issued.Key ||
                    issued.Generation != request.SessionGeneration || !cancel && view.Fingerprint != issued.Fingerprint)
                    return Error(request, "firstUse.context_changed");
                var checkpoint = ReadCheckpoint(request.Payload.GetProperty("checkpoint"), view);
                if (request.Name == "onboarding.execute")
                    await Execute(request.Payload.GetProperty("action").GetString()!, checkpoint, view, work.Token).ConfigureAwait(false);
                else if (request.Name == "onboarding.saveProgress")
                {
                    SaveProgress(checkpoint, view, work.Token);
                    saved = checkpoint;
                }
                else
                {
                    if (checkpoint["step"] as string != "summary" || checkpoint["mode"] as string != view.Completion.Mode ||
                        checkpoint["mode"] as string != view.Local.Progress?.Mode ||
                        _mode.Current.State is not ("local" or "offline" or "online") ||
                        view.Completion.State is not ("ready" or "completed"))
                        return Error(request, "firstUse.completion_required");
                    // Explicit finish revalidates current game evidence rather
                    // than trusting the persisted association or a stale page.
                    var source = view.Local.SelectedSourceKey ?? throw new LocalFirstUseException("firstUse.evidence_required");
                    var current = _evidence.Refresh(source, work.Token);
                    if (!current.IdentityConfirmed || current.RequiresFreshEvidence)
                        return Error(request, "firstUse.evidence_required");
                    var readiness = await _completion.ReadAsync(work.Token).ConfigureAwait(false);
                    if (readiness.State == "ready") await _completion.FinishAsync(readiness.CompletionKey!, work.Token).ConfigureAwait(false);
                    else if (readiness.State != "completed") return Error(request, "firstUse.completion_required");
                }
                view = await Capture(work.Token).ConfigureAwait(false);
            }
            work.Token.ThrowIfCancellationRequested();
            if (_closed) return Error(request, "firstUse.context_changed");
            _issued = new(Guid.NewGuid().ToString("N"), view.Fingerprint, view.Generation);
            return new(BridgeEnvelope.Response(request, new Dictionary<string, object?> {
                ["schemaVersion"] = 1, ["stateKey"] = _issued.Key, ["facts"] = view.Facts,
                ["restored"] = ProgressWire(view.Local.Progress, view), ["saved"] = saved, ["completed"] = view.Completed,
                // The reply stays on its original correlation. This next-generation
                // fact is only transport freshness; no account context is issued.
                ["controlGeneration"] = view.Generation
            }, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request with { AccountContext = null }), []); }
        catch (LocalFirstUseException error) { return Error(request, error.Code); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or ArgumentException or KeyNotFoundException)
        { return Error(request, "firstUse.invalid_request"); }
        catch { return Error(request, "firstUse.unavailable"); }
        finally { if (entered) _gate.Release(); }
    }

    private static void ValidateBody(BridgeEnvelope request)
    {
        var body = request.Payload;
        string[] expected = request.Name == "onboarding.read" ? ["schemaVersion"] : request.Name == "onboarding.execute"
            ? ["schemaVersion", "expectedStateKey", "checkpoint", "action"] : ["schemaVersion", "expectedStateKey", "checkpoint"];
        if (body.ValueKind != JsonValueKind.Object || body.GetRawText().Length > 4096) throw new LocalFirstUseException("firstUse.invalid_request");
        var fields = body.EnumerateObject().Select(p => p.Name).ToArray();
        if (fields.Length != expected.Length || fields.Distinct().Count() != fields.Length || fields.Except(expected).Any() ||
            !body.GetProperty("schemaVersion").TryGetInt32(out var schema) || schema != 1 ||
            request.Name != "onboarding.read" && body.GetProperty("expectedStateKey").ValueKind != JsonValueKind.String ||
            request.Name == "onboarding.execute" && body.GetProperty("action").ValueKind != JsonValueKind.String)
            throw new LocalFirstUseException("firstUse.invalid_request");
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request with { AccountContext = null }, new(code, "Setup could not be confirmed.", true)), []);
    internal Task RetireAsync() { _closed = true; _issued = null; return _work.Close(); }
    public void Dispose() => _ = RetireAsync();
}
