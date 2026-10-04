namespace StarBridge.HostRuntime.Settings;

using StarBridge.NativeBridge;
using System.Diagnostics;
using System.Text.Json;

// No caller-supplied paths, owners, screenshot bytes or file operations. Folder
// selection is reused from the Host's existing Windows picker. Capture/encoding
// and image export remain owned by the Runner's local image tools.
public sealed class MenuScreenshotDirectoryBridgeDispatcher : IBridgeRequestDispatcher
{
    public static IReadOnlyList<string> Capabilities { get; } =
        ["menuScreenshotDirectory.read", "menuScreenshotDirectory.choose",
         "menuScreenshotDirectory.reset", "menuScreenshotDirectory.open",
         "menuScreenshotDirectory.chooseDraft", "menuScreenshotDirectory.commitDraft"];
    private readonly MenuScreenshotDirectoryStore _store;
    private readonly Func<long> _generation;
    private readonly Func<CancellationToken, Task<string?>> _choose;
    private readonly Func<string> _default;
    private readonly Action<string, Func<bool>> _open;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private volatile bool _disposed;
    private sealed record Selection(string Path, long Revision, long Generation);
    private readonly Dictionary<string, Selection> _selections = new(StringComparer.Ordinal);

    public MenuScreenshotDirectoryBridgeDispatcher(string root, Func<long> generation,
        Func<CancellationToken, Task<string?>> choose)
        : this(root, generation, choose, () => DefaultDirectory(root), OpenDirectory) { }

    internal MenuScreenshotDirectoryBridgeDispatcher(string root, Func<long> generation,
        Func<CancellationToken, Task<string?>> choose, Func<string> defaultDirectory,
        Action<string, Func<bool>> open)
    { _store = new(root); _generation = generation; _choose = choose; _default = defaultDirectory; _open = open; }

    private static string DefaultDirectory(string root)
    {
        var pictures = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
        return string.IsNullOrWhiteSpace(pictures) ? Path.Combine(Path.GetFullPath(root), "Screenshots")
            : Path.Combine(pictures, "StarBridge", "Screenshots");
    }

    private static void OpenDirectory(string directory, Func<bool> current)
    {
        if (!current()) throw new OperationCanceledException();
        Directory.CreateDirectory(directory); // Explicit "Open directory" only; reads never create it.
        if (!current()) throw new OperationCanceledException();
        Process.Start(new ProcessStartInfo { FileName = directory, UseShellExecute = true });
    }

    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        bool entered = false;
        try
        {
            await _gate.WaitAsync(cancellationToken); entered = true;
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var generation = _generation();
            foreach (var key in _selections.Where(item => item.Value.Generation != generation).Select(item => item.Key).ToArray())
                _selections.Remove(key);
            bool Current() => !_disposed && !cancellationToken.IsCancellationRequested && _generation() == generation;
            if (_disposed || request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
                request.SessionGeneration != generation) throw new BridgeProtocolException(
                    BridgeErrorCodes.StaleGeneration, "Screenshot settings session changed");
            if (!Capabilities.Contains(request.Name)) throw new ArgumentException("Unsupported screenshot directory request");
            bool read = request.Name == "menuScreenshotDirectory.read";
            Validate(request.Payload, read ? ["schemaVersion"] : request.Name == "menuScreenshotDirectory.commitDraft"
                ? ["schemaVersion", "expectedRevision", "token"] : ["schemaVersion", "expectedRevision"]);
            var value = _store.Read();
            bool cancelled = false, opened = false;
            if (!read)
            {
                var raw = request.Payload.GetProperty("expectedRevision");
                if (raw.ValueKind != JsonValueKind.Number || !raw.TryGetInt64(out var revision) || revision < 0 || revision == long.MaxValue)
                    throw new ArgumentException("Invalid screenshot directory revision");
                if (value.Revision != revision) throw new ApplicationPreferencesException(
                    "menuScreenshotDirectory.revision_conflict", "Screenshot directory changed", true);
                if (!Current()) throw new OperationCanceledException();
                if (request.Name == "menuScreenshotDirectory.chooseDraft")
                {
                    var selected = await _choose(cancellationToken);
                    if (!Current()) throw new OperationCanceledException();
                    if (selected != null && !MenuScreenshotDirectoryStore.ValidDirectory(selected)) throw new ArgumentException("Invalid selection");
                    string? token = null;
                    if (selected != null)
                    {
                        // Bounded ephemeral native-only choices, never persisted or supplied as paths by the renderer.
                        if (_selections.Count >= 16) _selections.Remove(_selections.Keys.First());
                        token = Guid.NewGuid().ToString("N");
                        _selections[token] = new(selected, revision, generation);
                    }
                    var draft = JsonSerializer.SerializeToElement(new { schemaVersion = 1, revision,
                        directory = selected ?? Resolve(value), token, cancelled = selected is null });
                    return new(BridgeEnvelope.Response(request, draft, preserveRequestAccountContext: false), []);
                }
                else if (request.Name == "menuScreenshotDirectory.commitDraft")
                {
                    var rawToken = request.Payload.GetProperty("token");
                    var token = rawToken.ValueKind == JsonValueKind.String ? rawToken.GetString() : null;
                    if (token is null || token.Length != 32 || !token.All(Uri.IsHexDigit)) throw new ArgumentException("Invalid selection token");
                    if (!_selections.TryGetValue(token, out var selection) || selection.Generation != generation || selection.Revision != revision)
                        throw new ApplicationPreferencesException("menuScreenshotDirectory.selection_unavailable", "Choose the directory again");
                    value = _store.Save(revision, selection.Path, Current);
                    _selections.Remove(token);
                }
                else if (request.Name == "menuScreenshotDirectory.choose")
                {
                    var selected = await _choose(cancellationToken);
                    if (!Current()) throw new OperationCanceledException();
                    if (selected is null) { cancelled = true; value = _store.Read(); }
                    else value = _store.Save(revision, selected, Current);
                }
                else if (request.Name == "menuScreenshotDirectory.reset")
                { Resolve(new()); value = _store.Save(revision, null, Current); }
                else
                {
                    _open(Resolve(value), Current);
                    opened = true;
                }
            }
            if (!Current()) throw new OperationCanceledException();
            var payload = JsonSerializer.SerializeToElement(new { schemaVersion = 1, revision = value.Revision,
                directory = Resolve(value), isDefault = value.Directory is null, cancelled, opened });
            return new(BridgeEnvelope.Response(request, payload, preserveRequestAccountContext: false), []);
        }
        catch (ApplicationPreferencesException error) { return Error(request, error.Code, error.Retryable); }
        catch (BridgeProtocolException error) { return Error(request, error.Code); }
        catch (ArgumentException) { return Error(request, "menuScreenshotDirectory.invalid_value"); }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (OperationCanceledException) { return Error(request, BridgeErrorCodes.StaleGeneration); }
        catch (Exception) { return Error(request, "menuScreenshotDirectory.unavailable", true); }
        finally { if (entered) _gate.Release(); }
    }

    private string Resolve(MenuScreenshotDirectoryStore.Snapshot value)
    {
        var path = value.Directory ?? _default();
        if (!MenuScreenshotDirectoryStore.ValidDirectory(path)) throw new InvalidDataException();
        return path;
    }
    private static void Validate(JsonElement payload, string[] keys)
    {
        if (payload.ValueKind != JsonValueKind.Object) throw new ArgumentException("Invalid screenshot directory payload");
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var field in payload.EnumerateObject())
            if (!keys.Contains(field.Name) || !seen.Add(field.Name)) throw new ArgumentException("Invalid screenshot directory payload");
        if (seen.Count != keys.Length || payload.GetProperty("schemaVersion").ValueKind != JsonValueKind.Number ||
            !payload.GetProperty("schemaVersion").TryGetInt32(out var version) || version != 1)
            throw new ArgumentException("Invalid screenshot directory payload");
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code, bool retryable = false) =>
        new(BridgeEnvelope.ErrorResponse(request, new BridgeError(code, "Screenshot directory operation failed", retryable)), []);
    public void Dispose() { _disposed = true; }
}
