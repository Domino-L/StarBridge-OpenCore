using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
using StarBridge.Core.Hangar;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

/// <summary>Verified reader and confirmed local inventory. No upload or credential operations.</summary>
public sealed class HangarReaderDispatcher(
    Func<HangarAccountIdentity?> currentIdentity, LocalHangarStore? store = null) : IDisposable
{
    private readonly object _sync = new();
    private HangarAccountIdentity? _owner;
    private HangarIdentityGuard? _guard;
    private HangarScanSession? _scan;
    private string? _operation;
    private ulong _document;
    private string? _source;
    private string? _stopped;
    private string? _verifiedScan;
    private int _observations;
    private DateTimeOffset _candidateExpires;

    public BridgeDispatchBatch Dispatch(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        lock (_sync)
        {
            try
            {
                BridgeEnvelopeValidator.ValidateWireShape(request);
                BridgeEnvelopeValidator.RequireCurrentVersion(request);
                var account = currentIdentity();
                if (request.MessageType != BridgeMessageTypes.Request || account is null ||
                    request.AccountContext != account.Account || request.SessionGeneration != account.Generation)
                { Stop("accountChanged"); return Error(request, "hangar.account_changed"); }
                var body = request.Payload;
                if (body.GetRawText().Length > 600 * 1024 || body.GetProperty("schemaVersion").GetInt32() != 1)
                    return Error(request, "hangar.invalid_observation");
                if (request.Name == "hangarReader.inventory")
                {
                    if (store is null) return Error(request, BridgeErrorCodes.CapabilityUnavailable);
                    var saved = store.Read(account.Account);
                    if (body.TryGetProperty("revision", out var expected) && expected.GetInt64() != saved.Revision)
                        return Error(request, "hangar.revision_conflict");
                    if (currentIdentity() != account) return Error(request, "hangar.account_changed");
                    var offset = body.TryGetProperty("offset", out var start) ? start.GetInt32() : 0;
                    var former = body.TryGetProperty("former", out var history) && history.GetBoolean();
                    if (offset < 0 || offset > (former ? saved.FormerShips?.Count ?? 0 : saved.Ships.Count))
                        return Error(request, "hangar.invalid_observation");
                    return InventoryView(request, saved, offset, former);
                }
                if (request.Name == "hangarReader.browserProfile")
                {
                    // Stable across restores, isolated by environment/issuer/subject. No PII in folder names.
                    var scope = JsonSerializer.Serialize(new[] { "rsi-reader-profile-v1", account.Account.Environment,
                        account.Account.Authority, account.Account.Subject });
                    var profileKey = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(scope)));
                    return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, profileKey }), []);
                }
                if (request.Name == "hangarReader.begin")
                {
                    Stop("cancelled");
                    if (!RsiHangarIdentityPolicy.Evaluate(account.Identity, [account.Identity.CanonicalHandle]).CanContinue)
                        return Error(request, "hangar.identity_unavailable");
                    _owner = account;
                    _guard = new(account, currentIdentity);
                    _scan = new();
                    _operation = Guid.NewGuid().ToString("N");
                    _document = 0; _source = null; _stopped = null; _observations = 0; _verifiedScan = null;
                    _candidateExpires = DateTimeOffset.UtcNow.AddMinutes(20);
                    return View(request, "ready");
                }
                if (_scan is null || body.GetProperty("operationId").GetString() != _operation)
                    return Error(request, "hangar.operation_expired");
                if (account != _owner)
                { Stop("accountChanged"); return View(request, "accountChanged"); }
                if (request.Name == "hangarReader.cancel")
                { Stop("cancelled"); return View(request, "cancelled"); }
                if (request.Name == "hangarReader.save")
                {
                    if (store is null) return Error(request, BridgeErrorCodes.CapabilityUnavailable);
                    if (!CanSave()) return Error(request, "hangar.operation_expired");
                    // Only the frozen Host result is saved. Client-supplied ships/owners are rejected.
                    var fields = body.EnumerateObject().Select(p => p.Name).ToArray();
                    if (fields.Distinct().Count() != fields.Length ||
                        fields.Any(f => f is not ("schemaVersion" or "operationId" or "expectedRevision" or "confirmEmpty")))
                        return Error(request, "hangar.invalid_observation");
                    var snapshot = _scan.Snapshot;
                    var saved = store.Save(account.Account, body.GetProperty("expectedRevision").GetInt64(),
                        _operation!, snapshot.Ships, snapshot.State == HangarScanState.NeedsReview,
                        body.TryGetProperty("confirmEmpty", out var clear) && clear.GetBoolean(),
                        () => !cancellationToken.IsCancellationRequested && currentIdentity() == account && CanSave());
                    if (currentIdentity() != account) return Error(request, "hangar.account_changed");
                    return InventoryView(request, saved, 0);
                }
                if (request.Name is not ("hangarReader.verify" or "hangarReader.observe")) return Error(request, BridgeErrorCodes.CapabilityUnavailable);
                if (_stopped is not null) return View(request, _stopped);
                if (_scan.Snapshot.State is not (HangarScanState.Collecting or HangarScanState.VerifyingFirstPage))
                    return View(request, Phase());
                if (++_observations > HangarScanSession.MaximumCaptures)
                { Stop("failed"); return View(request, "failed"); }
                var source = body.GetProperty("source").GetString();
                var navigation = body.GetProperty("documentGeneration").GetUInt64();
                var scanId = body.GetProperty("scanId").GetString();
                if (!body.GetProperty("locked").GetBoolean() || scanId is null || !Guid.TryParseExact(scanId, "N", out _))
                { Stop("pageChanged"); return View(request, "pageChanged"); }
                if (navigation == 0 || navigation < _document || !Uri.TryCreate(source, UriKind.Absolute, out var uri) ||
                    !RsiHangarNavigationPolicy.TryGetPage(uri, out var pageNumber))
                { Stop("pageChanged"); return View(request, "pageChanged"); }
                var observation = body.GetProperty("observation");
                if (request.Name == "hangarReader.verify")
                {
                    if (_verifiedScan is not null) { Stop("pageChanged"); return View(request, "pageChanged"); }
                    _guard!.NavigationStarted(navigation);
                    _guard.NavigationCompleted(navigation, uri, true);
                    var identity = observation.GetProperty("identity");
                    var check = _guard.Assess(navigation, uri, identity.GetRawText());
                    if (!check.CanContinue)
                    {
                        var phase = check.State switch {
                            HangarIdentityGuardState.IdentityRejected => check.Identity?.State switch {
                                RsiHangarIdentityState.ReaderIdentityUnavailable => "awaitingIdentity",
                                RsiHangarIdentityState.ReaderIdentityAmbiguous => "identityAmbiguous",
                                RsiHangarIdentityState.Mismatch => "identityMismatch",
                                RsiHangarIdentityState.ApplicationIdentityUnavailable => "identityUnavailable",
                                _ => "identityReadFailed"
                            },
                            HangarIdentityGuardState.DocumentUnavailable => "pageChanged",
                            HangarIdentityGuardState.AccountChanged => "accountChanged",
                            _ => "identityReadFailed"
                        };
                        Stop(phase); return View(request, phase);
                    }
                    // One identity observation for this locked native scan only. No reusable write permission.
                    _verifiedScan = scanId; _document = navigation; _source = source;
                    return View(request, "reading");
                }
                if (_verifiedScan is null) { Stop("identityReadFailed"); return View(request, "identityReadFailed"); }
                if (_verifiedScan != scanId || observation.TryGetProperty("identity", out _) || pageNumber != _scan.Snapshot.ExpectedPage)
                { Stop("pageChanged"); return View(request, "pageChanged"); }
                if (navigation > _document)
                {
                    _document = navigation; _source = source;
                }
                if (source != _source) { Stop("pageChanged"); return View(request, "pageChanged"); }
                var page = observation.GetProperty("page");
                if (page.GetProperty("schemaVersion").GetInt32() != 1 || page.GetProperty("documentUrl").GetString() != source)
                { Stop("pageChanged"); return View(request, "pageChanged"); }
                var status = page.GetProperty("status").GetString();
                if (status == "unconfirmedEmpty") return View(request, "emptyUnconfirmed");
                if (status != "ready")
                { Stop(status == "filtered" ? "filtered" : "unsupported"); return View(request, _stopped!); }
                var parsed = page.Deserialize<HangarPageObservation>(new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                if (parsed is null || parsed.Page != pageNumber)
                { Stop("pageChanged"); return View(request, "pageChanged"); }
                _scan.Observe((ulong)_observations, parsed);
                return View(request, Phase());
            }
            catch (LocalHangarStoreException error) { return Error(request, error.Code); }
            catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or
                FormatException or OverflowException or BridgeProtocolException)
            { Stop("failed"); return Error(request, "hangar.invalid_observation"); }
        }
    }

    private string Phase() => _scan!.Snapshot.State switch {
        HangarScanState.Complete => "complete", HangarScanState.NeedsReview => "needsReview",
        HangarScanState.VerifyingFirstPage => "verifying", HangarScanState.Collecting => "reading",
        HangarScanState.Cancelled => "cancelled", HangarScanState.TimedOut => "timedOut", _ => "failed"
    };
    private bool CanSave() => store is not null && _stopped is null && _verifiedScan is not null &&
        DateTimeOffset.UtcNow < _candidateExpires &&
        _scan?.Snapshot is { } snapshot &&
        (snapshot.State == HangarScanState.Complete ||
         snapshot.State == HangarScanState.NeedsReview && snapshot.Ships.Count > 0);

    private static BridgeDispatchBatch InventoryView(BridgeEnvelope request, LocalHangarSnapshot snapshot, int offset, bool former = false)
    {
        var ships = former ? snapshot.FormerShips ?? [] : snapshot.Ships;
        return new(BridgeEnvelope.Response(request, new {
            schemaVersion = 1, revision = snapshot.Revision, savedAt = snapshot.SavedAt,
            operationId = snapshot.OperationId, partial = snapshot.Partial, total = ships.Count,
            former, formerTotal = snapshot.FormerShips?.Count ?? 0,
            nextOffset = offset + 200 < ships.Count ? (int?)(offset + 200) : null,
            ships = ships.Skip(offset).Take(200).Select(HangarShipNames.PresentSaved).ToArray()
        }), []);
    }
    private BridgeDispatchBatch View(BridgeEnvelope request, string phase)
    {
        var snapshot = _scan!.Snapshot;
        if (snapshot.State == HangarScanState.TimedOut) phase = "timedOut";
        return new(BridgeEnvelope.Response(request, new {
            schemaVersion = 1, operationId = _operation, phase,
            handle = _owner is null ? null : RsiHangarIdentityPolicy.DisplayHandle(_owner.Identity),
            expectedPage = snapshot.ExpectedPage, totalPages = snapshot.TotalPages, pagesRead = snapshot.Pages.Count,
            shipCount = snapshot.Ships.Count, unclassifiedCount = snapshot.UnclassifiedCount,
            // Bounded, display-only preview. Internal pledge keys do not leave the Host.
            ships = phase is "reading" or "verifying" or "complete" or "needsReview"
                ? snapshot.Ships.Take(200).Select((s, i) => HangarShipNames.Present(s.Title, s.Liner, i)).ToArray() : [],
            canSave = CanSave()
        }), []);
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Hangar reading is unavailable.")), []);
    private void Stop(string reason) { _stopped = reason; _verifiedScan = null; _guard?.Cancel(); _scan?.Cancel(); }
    public void Dispose() { lock (_sync) { Stop("cancelled"); _scan = null; _owner = null; } }
}
