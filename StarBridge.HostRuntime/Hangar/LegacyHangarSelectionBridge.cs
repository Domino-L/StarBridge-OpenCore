using System.Text.Json;
using StarBridge.Core.Hangar;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

internal sealed class LegacyHangarSelectionBridge : IDisposable
{
    internal static readonly string[] Requests = ["hangar.migrationSelectLocal", "hangar.migrationConfirmLocal", "hangar.migrationReadLocal", "hangar.migrationClearLocal", "hangar.migrationCompare"];
    private readonly Func<(BridgeAccountContext? Context, long Generation)> _owner;
    private readonly LegacyHangarSelection _selection;
    private readonly Func<BridgeAccountContext, CancellationToken, Task<ServerHangarMigrationRead>>? _readServer;
    internal LegacyHangarSelectionBridge(ILegacyHangarFilePicker picker,
        Func<(BridgeAccountContext? Context, long Generation)> owner, Func<bool> hasStorageLease,
        Func<BridgeAccountContext, CancellationToken, Task<ServerHangarMigrationRead>>? readServer = null)
    {
        _owner = owner;
        _readServer = readServer;
        _selection = new(picker, () => {
            var value = owner();
            return (value.Context is { } c ? new MigrationOwner(c.Environment, c.Authority, c.Subject) : null, value.Generation);
        }, hasStorageLease);
    }
    internal void Invalidate() => _selection.Invalidate();
    internal async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token)
    {
        try
        {
            token.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = _owner();
            if (request.MessageType != BridgeMessageTypes.Request || owner.Context is null ||
                request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation)
                return Error(request, "hangar.account_changed");
            var body = request.Payload;
            string[] allowed = request.Name switch {
                "hangar.migrationSelectLocal" => ["schemaVersion", "locale"],
                "hangar.migrationConfirmLocal" => ["schemaVersion", "selectionRef", "belongsToCurrentAccount"],
                "hangar.migrationReadLocal" => ["schemaVersion", "selectionRef", "offset"],
                "hangar.migrationClearLocal" => ["schemaVersion", "selectionRef"],
                "hangar.migrationCompare" => ["schemaVersion", "selectionRef", "localSha256", "serverSha256", "offset"],
                _ => throw new InvalidDataException()
            };
            var names = body.EnumerateObject().Select(p => p.Name).ToArray();
            if (names.Length != allowed.Length || names.Distinct().Count() != names.Length ||
                names.Except(allowed).Any() || body.GetProperty("schemaVersion").GetInt32() != 1)
                return Error(request, "hangar.invalid_request");
            object result;
            if (request.Name == "hangar.migrationSelectLocal")
            {
                var locale = body.GetProperty("locale").GetString();
                if (locale is not ("zh-CN" or "zh-TW" or "en")) return Error(request, "hangar.invalid_request");
                var selected = await _selection.SelectAsync(locale, token);
                result = new { schemaVersion = 1, state = selected.State, selected.SelectionRef, selected.FileName };
            }
            else if (request.Name == "hangar.migrationClearLocal")
            {
                _selection.Clear(body.GetProperty("selectionRef").GetString() ?? "");
                result = new { schemaVersion = 1, state = "cleared" };
            }
            else if (request.Name == "hangar.migrationCompare")
            {
                var reference = body.GetProperty("selectionRef").GetString() ?? "";
                var local = _selection.Read(reference);
                var localHash = body.GetProperty("localSha256").GetString();
                var serverHash = body.GetProperty("serverSha256").GetString();
                var offset = body.GetProperty("offset").GetInt32();
                if (localHash is not { Length: 64 } || !localHash.All(Uri.IsHexDigit) ||
                    serverHash is not { Length: 64 } || !serverHash.All(Uri.IsHexDigit) || offset < 0 || offset > 20000)
                    return Error(request, "hangar.invalid_request");
                // Malformed local rows may hide duplicate identifiers: never silently omit them from matching.
                if (local.State != "read" || local.Snapshot is null || _readServer is null)
                    return Error(request, "hangar.migration_source_unavailable");
                if (localHash != local.Snapshot.Sha256) return Error(request, "hangar.migration_snapshot_changed");
                var server = await _readServer(owner.Context, token);
                token.ThrowIfCancellationRequested();
                // Recheck selection lifetime, lease and account after network I/O.
                if (_selection.Read(reference) != local || _owner() != owner)
                    return Error(request, "hangar.account_changed");
                if (server.State != "available") return Error(request, "hangar.migration_source_unavailable");
                if (server.SnapshotSha256 != serverHash) return Error(request, "hangar.migration_snapshot_changed");
                var compared = HangarMigrationPreview.CompareObserved(local.Snapshot.Source, server.Source);
                if (offset > compared.Rows.Count) return Error(request, "hangar.invalid_request");
                var rows = compared.Rows.Skip(offset).Take(100).Select(r => new {
                    r.LocalIndex, r.ServerIndex, state = r.State.ToString(),
                    differentFields = r.State == ObservedMigrationRowState.Different
                        ? HangarMigrationPreview.DifferentFields(local.Snapshot.Source.Ships[r.LocalIndex!.Value].Fields,
                            server.Source.Ships[r.ServerIndex!.Value].Fields) : Array.Empty<string>() }).ToArray();
                result = new { schemaVersion = 1, selectionRef = reference, localSha256 = localHash,
                    serverSha256 = serverHash, compared.CanCompareObservedRecords, compared.BothSourcesComplete,
                    total = compared.Rows.Count, offset,
                    nextOffset = offset + rows.Length < compared.Rows.Count ? (int?)(offset + rows.Length) : null, rows };
            }
            else
            {
                var reference = body.GetProperty("selectionRef").GetString() ?? "";
                var confirm = request.Name == "hangar.migrationConfirmLocal";
                var snapshot = confirm
                    ? _selection.Confirm(reference, body.GetProperty("belongsToCurrentAccount").GetBoolean())
                    : _selection.Read(reference);
                var offset = confirm ? 0 : body.GetProperty("offset").GetInt32();
                var rows = snapshot.Snapshot?.Rows ?? [];
                if (offset < 0 || offset > rows.Count) return Error(request, "hangar.invalid_request");
                var page = rows.Skip(offset).Take(100).Select(r => new { r.Line, r.Ship, r.Issue }).ToArray();
                result = new { schemaVersion = 1, state = snapshot.State, selectionRef = reference,
                    snapshotSha256 = snapshot.Snapshot?.Sha256, ownership = "user-confirmed", total = rows.Count, offset,
                    nextOffset = offset + page.Length < rows.Count ? (int?)(offset + page.Length) : null, rows = page };
                if (JsonSerializer.SerializeToUtf8Bytes(result).Length > BridgeProtocol.MaximumFrameBytes / 2)
                    return Error(request, "hangar.migration_snapshot_too_large");
            }
            token.ThrowIfCancellationRequested();
            if (_owner() != owner) { Invalidate(); return Error(request, "hangar.account_changed"); }
            return new(BridgeEnvelope.Response(request, result), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (Account.AccountBridgeHostException) { return Error(request, "hangar.migration_source_unavailable"); }
        catch (BridgeProtocolException) { return Error(request, "hangar.invalid_request"); }
        catch (Exception error) when (error is InvalidDataException or IOException or InvalidOperationException or
            ArgumentException or UnauthorizedAccessException or JsonException or KeyNotFoundException or FormatException)
        { return Error(request, "hangar.migration_local_unavailable"); }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Local hangar preview is unavailable.")), []);
    public void Dispose() => _selection.Dispose();
}
