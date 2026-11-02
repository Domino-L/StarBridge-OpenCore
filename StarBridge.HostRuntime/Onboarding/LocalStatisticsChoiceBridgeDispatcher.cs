using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Onboarding;

// Borrow the unique sampler's statistics owner. This does not grant whole
// onboarding readiness, account consent, history import, sharing or publication.
public sealed class LocalStatisticsChoiceBridgeDispatcher : IBridgeRequestDispatcher
{
    public const string Capability = "onboarding.localStatistics.v1";
    public const string ReadRequest = "onboarding.localStatistics.read";
    public const string ConfirmRequest = "onboarding.localStatistics.confirm";
    // One explicit, one-time history import for the same confirmed local profile.
    public const string HistoryCapability = "onboarding.localStatistics.history.v1";
    public const string HistoryReadRequest = "onboarding.localStatistics.historyRead";
    public const string HistoryScanStartRequest = "onboarding.localStatistics.historyScanStart";
    public const string HistoryScanReadRequest = "onboarding.localStatistics.historyScanRead";
    public const string HistoryScanCancelRequest = "onboarding.localStatistics.historyScanCancel";
    public const string HistoryConfirmRequest = "onboarding.localStatistics.historyConfirm";
    // Explicit, confirmed reset of the same local profile's time (WPF parity).
    public const string ResetCapability = "onboarding.localStatistics.reset.v1";
    public const string ResetPreviewRequest = "onboarding.localStatistics.resetPreview";
    public const string ResetConfirmRequest = "onboarding.localStatistics.resetConfirm";
    // Read-only "is recognition working" check: the confirmed local slot's current
    // observation. Never starts listening, probes again, saves or confirms anything.
    public const string RecognitionCapability = "onboarding.recognition.v1";
    public const string RecognitionReadRequest = "onboarding.recognition.read";
    public static bool Handles(string name) => name is ReadRequest or ConfirmRequest or HistoryReadRequest or
        HistoryScanStartRequest or HistoryScanReadRequest or HistoryScanCancelRequest or HistoryConfirmRequest or
        ResetPreviewRequest or ResetConfirmRequest or RecognitionReadRequest;
    private readonly Func<LocalGameplayTimeRuntime?> _runtime;
    private readonly Func<long> _generation;
    private readonly InstalledSetupStatisticsChoice? _installed;
    private volatile bool _disposed;
    internal LocalStatisticsChoiceBridgeDispatcher(LocalGameplayTimeRuntime runtime, Func<long> generation)
        : this(() => runtime, generation) { }
    // The root owns replacement and must drain the old owner before installing
    // another. Composite keeps this bridge, not the retired statistics instance.
    internal LocalStatisticsChoiceBridgeDispatcher(Func<LocalGameplayTimeRuntime?> runtime, Func<long> generation,
        InstalledSetupStatisticsChoice? installed = null)
    { _runtime = runtime; _generation = generation; _installed = installed; }
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        BridgeDispatchBatch result;
        try
        {
            token.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var runtime = _runtime();
            var installed = _installed?.Active == true;
            bool Current() => !_disposed && request.SessionGeneration == _generation() &&
                installed == (_installed?.Active == true) &&
                (installed || runtime is not null && ReferenceEquals(runtime, _runtime()));
            if (!Current()) return ValueTask.FromResult(Error(request, "firstUse.context_changed"));
            var confirm = request.Name == ConfirmRequest;
            if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
                !Handles(request.Name) || request.Payload.ValueKind != JsonValueKind.Object)
                return ValueTask.FromResult(Error(request, "firstUse.invalid_request"));
            if (request.Name is ResetPreviewRequest or ResetConfirmRequest)
                return ValueTask.FromResult(DispatchReset(request, runtime, installed, Current, token));
            if (request.Name == RecognitionReadRequest)
                return ValueTask.FromResult(DispatchRecognition(request, runtime, installed, Current, token));
            if (request.Name is not (ReadRequest or ConfirmRequest))
                return ValueTask.FromResult(DispatchHistory(request, runtime, installed, Current, token));
            var fields = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
            string[] expected = confirm ? ["schemaVersion", "choiceKey", "allowed"] : ["schemaVersion"];
            if (fields.Length != expected.Length || fields.Distinct(StringComparer.Ordinal).Count() != fields.Length ||
                fields.Except(expected, StringComparer.Ordinal).Any() ||
                !request.Payload.GetProperty("schemaVersion").TryGetInt32(out var schema) || schema != 1 ||
                confirm && (request.Payload.GetProperty("choiceKey").ValueKind != JsonValueKind.String ||
                    request.Payload.GetProperty("allowed").ValueKind is not (JsonValueKind.True or JsonValueKind.False)))
                return ValueTask.FromResult(Error(request, "firstUse.invalid_request"));
            var value = installed
                ? confirm ? _installed!.Confirm(request.Payload.GetProperty("choiceKey").GetString()!, request.Payload.GetProperty("allowed").GetBoolean(), Current, token)
                    : _installed!.Read(Current, token)
                : confirm ? runtime!.ConfirmConsent(request.Payload.GetProperty("choiceKey").GetString()!,
                    request.Payload.GetProperty("allowed").GetBoolean(), Current, token) : runtime!.ReadConsent(Current, token);
            token.ThrowIfCancellationRequested();
            result = Current() ? new(BridgeEnvelope.Response(request, new { schemaVersion = 1, state = value.State,
                choiceKey = value.ChoiceKey, consent = value.Consent, savedSeconds = value.SavedSeconds, recording = value.Recording },
                preserveRequestAccountContext: false), []) : Error(request, "firstUse.context_changed");
        }
        catch (LocalFirstUseException error) { result = Error(request, error.Code); }
        catch (OperationCanceledException) { result = new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or ArgumentException or KeyNotFoundException)
        { result = Error(request, "firstUse.invalid_request"); }
        catch { result = Error(request, "firstUse.statistics_read_failed"); }
        return ValueTask.FromResult(result);
    }
    private static BridgeDispatchBatch DispatchHistory(BridgeEnvelope request, LocalGameplayTimeRuntime? runtime, bool installed,
        Func<bool> current, CancellationToken token)
    {
        var argument = request.Name switch {
            HistoryScanReadRequest or HistoryScanCancelRequest => "scanId",
            HistoryConfirmRequest => "previewId",
            _ => null
        };
        var fields = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
        string[] expected = argument is null ? ["schemaVersion"] : ["schemaVersion", argument];
        if (fields.Length != expected.Length || fields.Distinct(StringComparer.Ordinal).Count() != fields.Length ||
            fields.Except(expected, StringComparer.Ordinal).Any() ||
            !request.Payload.GetProperty("schemaVersion").TryGetInt32(out var schema) || schema != 1 ||
            argument is not null && request.Payload.GetProperty(argument).ValueKind != JsonValueKind.String)
            return Error(request, "firstUse.invalid_request");
        var value = argument is null ? null : request.Payload.GetProperty(argument).GetString()!;
        // The online account owns its own statistics and import after installation.
        var result = installed || runtime is null ? new LocalHistoryImport("inactive") : request.Name switch {
            HistoryReadRequest => runtime.ReadHistory(current, token),
            HistoryScanStartRequest => runtime.StartHistoryScan(current, token),
            HistoryScanReadRequest => runtime.ReadHistoryScan(value!, false, current, token),
            HistoryScanCancelRequest => runtime.ReadHistoryScan(value!, true, current, token),
            _ => runtime.ConfirmHistory(value!, current, token)
        };
        token.ThrowIfCancellationRequested();
        if (!current()) return Error(request, "firstUse.context_changed");
        return new(BridgeEnvelope.Response(request, new {
            schemaVersion = 1, state = result.State, scanId = result.ScanId, phase = result.Phase,
            processedFiles = result.ProcessedFiles, totalFiles = result.TotalFiles, readBytes = result.ReadBytes,
            totalBytes = result.TotalBytes, previewId = result.PreviewId, seconds = result.Seconds,
            sessions = result.Sessions, incompleteSessions = result.IncompleteSessions, skippedFiles = result.SkippedFiles,
            importedSeconds = result.ImportedSeconds, importedAt = result.ImportedAt
        }, preserveRequestAccountContext: false), []);
    }
    private static BridgeDispatchBatch DispatchReset(BridgeEnvelope request, LocalGameplayTimeRuntime? runtime, bool installed,
        Func<bool> current, CancellationToken token)
    {
        var confirm = request.Name == ResetConfirmRequest;
        var fields = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
        string[] expected = confirm ? ["schemaVersion", "resetId"] : ["schemaVersion"];
        if (fields.Length != expected.Length || fields.Distinct(StringComparer.Ordinal).Count() != fields.Length ||
            fields.Except(expected, StringComparer.Ordinal).Any() ||
            !request.Payload.GetProperty("schemaVersion").TryGetInt32(out var schema) || schema != 1 ||
            confirm && request.Payload.GetProperty("resetId").ValueKind != JsonValueKind.String)
            return Error(request, "firstUse.invalid_request");
        var result = installed || runtime is null ? new LocalResetView("inactive") : confirm
            ? runtime.ConfirmReset(request.Payload.GetProperty("resetId").GetString()!, current, token)
            : runtime.PreviewReset(current, token);
        token.ThrowIfCancellationRequested();
        if (!current()) return Error(request, "firstUse.context_changed");
        return new(BridgeEnvelope.Response(request, new {
            schemaVersion = 1, state = result.State, resetId = result.ResetId,
            seconds = result.Seconds, historicalSeconds = result.HistoricalSeconds
        }, preserveRequestAccountContext: false), []);
    }
    private static BridgeDispatchBatch DispatchRecognition(BridgeEnvelope request, LocalGameplayTimeRuntime? runtime,
        bool installed, Func<bool> current, CancellationToken token)
    {
        var fields = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
        if (fields.Length != 1 || fields[0] != "schemaVersion" ||
            !request.Payload.GetProperty("schemaVersion").TryGetInt32(out var schema) || schema != 1)
            return Error(request, "firstUse.invalid_request");
        // An installed online account owns recognition; this local check is then inactive.
        var view = installed || runtime is null ? new LocalGameLogView("inactive") : runtime.Recognition;
        var ready = view.State == "ready";
        var session = ready ? view.LocalSession : Presence.GameLogSessionSnapshot.Empty;
        token.ThrowIfCancellationRequested();
        if (!current()) return Error(request, "firstUse.context_changed");
        // Raw paths, shards, process and player IDs never leave the Host.
        return new(BridgeEnvelope.Response(request, new {
            schemaVersion = 1, state = view.State, version = view.Version,
            handle = ready ? view.Handle : null, observedAt = ready ? view.ObservedAt : null,
            server = new { state = session.Server.State, region = session.Server.Region },
            location = new { state = session.Location.State, englishName = session.Location.EnglishName,
                zhHans = session.Location.ChineseName },
            ship = new { state = session.Ship.State, key = session.Ship.Key, englishName = session.Ship.EnglishName,
                zhHans = session.Ship.ChineseName, zhHant = session.Ship.TraditionalChineseName }
        }, preserveRequestAccountContext: false), []);
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Local recording choice could not be confirmed.", true)), []);
    // The account lifecycle owns retirement. Disposing this borrowed bridge only
    // seals its own observations, never installs or stops a second sampler.
    public void Dispose() => _disposed = true;
}
