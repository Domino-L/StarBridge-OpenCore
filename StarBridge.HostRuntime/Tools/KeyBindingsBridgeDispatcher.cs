namespace StarBridge.HostRuntime.Tools;

using System.Text.Json;
using StarBridge.NativeBridge;

public sealed class KeyBindingsBridgeDispatcher : IBridgeRequestDispatcher
{
    public const string RequestName = "keyBindings.read";
    // Room for the envelope: a frame over the Bridge limit would end the whole connection.
    private const int MaximumPayloadBytes = 900 * 1024;
    private const int MaximumCorrelationLength = 256;
    public const string SaveViewRequestName = "keyBindings.saveView";
    public static IReadOnlyList<string> Capabilities { get; } = [RequestName, SaveViewRequestName];
    private static readonly string[] Keyboards = ["full", "tkl", "p75", "p65", "p60"];
    private static readonly string[] Mice = ["standard", "many"];
    private readonly string? _viewPath;
    private readonly object _saveGate = new();
    private readonly KeyBindingsReader _reader;
    private readonly Func<long> _generation;
    private volatile bool _disposed;

    public KeyBindingsBridgeDispatcher(string dataRoot, Func<string?> selectedGameLog, Func<long> generation)
        : this(new KeyBindingsReader(selectedGameLog), generation, Path.Combine(dataRoot, "key-bindings-view.json"))
    {
    }

    internal KeyBindingsBridgeDispatcher(KeyBindingsReader reader, Func<long> generation, string? viewPath = null)
    {
        _reader = reader;
        _generation = generation;
        _viewPath = viewPath;
    }

    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || request.SessionGeneration != _generation()) return Unavailable(request);
            if (request.Name == SaveViewRequestName && request.MessageType == BridgeMessageTypes.Request)
                return SaveView(request);
            if (request.MessageType != BridgeMessageTypes.Request || request.Name != RequestName ||
                request.CorrelationId is not { Length: <= MaximumCorrelationLength } ||
                request.AccountContext is not null || request.Payload.ValueKind != JsonValueKind.Object ||
                request.Payload.EnumerateObject().Count() is not (3 or 4) ||
                !request.Payload.TryGetProperty("schemaVersion", out var schema) ||
                schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1 ||
                !request.Payload.TryGetProperty("channel", out var channel) ||
                channel.ValueKind != JsonValueKind.String || !KeyBindingsReader.ValidChannel(channel.GetString()) ||
                !request.Payload.TryGetProperty("language", out var language) ||
                language.ValueKind != JsonValueKind.String || !KeyBindingsReader.ValidLanguage(language.GetString()) ||
                // A fourth field can only be the names language.
                request.Payload.EnumerateObject().Count() == 4 && !request.Payload.TryGetProperty("localization", out _) ||
                !OptionalLocalization(request.Payload, out var localization))
                return new(BridgeEnvelope.ErrorResponse(request,
                    new BridgeError(BridgeErrorCodes.InvalidEnvelope, "Invalid key bindings request.")), []);
            var name = channel.GetString()!;
            var interfaceLanguage = language.GetString()!;
            // A slow disk must not hold a Bridge pipe worker.
            var snapshot = await Task.Run(() => _reader.Read(name, interfaceLanguage, localization), cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            if (_disposed || request.SessionGeneration != _generation()) return Unavailable(request);
            var wire = Wire(snapshot);
            wire["view"] = await Task.Run(ReadView, cancellationToken);
            if (JsonSerializer.SerializeToUtf8Bytes(wire).Length > MaximumPayloadBytes)
            {
                var view = wire["view"];
                wire = Wire(snapshot with { State = "format", Maps = [], NamesState = "unused", NamesPath = null,
                    Localizations = [], Localization = null, LocalizationFallback = false });
                wire["view"] = view;
            }
            return new(BridgeEnvelope.Response(request, wire, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (BridgeProtocolException error)
        {
            return new(BridgeEnvelope.ErrorResponse(request,
                new BridgeError(error.Code, "Invalid key bindings request.")), []);
        }
        catch { return Unavailable(request); }
    }

    // The chosen keyboard size and mouse style. A missing or odd file means no choice yet.
    private Dictionary<string, object?>? ReadView()
    {
        if (_viewPath is null) return null;
        try
        {
            var info = new FileInfo(_viewPath);
            if (!info.Exists || info.Length > 1024) return null;
            using var document = JsonDocument.Parse(File.ReadAllBytes(_viewPath));
            // No keyboard: none chosen, the page picks one by width.
            var keyboard = document.RootElement.TryGetProperty("keyboard", out var size) &&
                size.ValueKind != JsonValueKind.Null ? size.GetString() : null;
            var mouse = document.RootElement.GetProperty("mouse").GetString();
            var root = document.RootElement;
            var localization = root.TryGetProperty("localization", out var saved) &&
                saved.ValueKind == JsonValueKind.String ? saved.GetString() : null;
            // The page layout came later: anything odd in it is simply not remembered.
            return (keyboard is null || Keyboards.Contains(keyboard)) && Mice.Contains(mouse)
                ? new()
                {
                    ["keyboard"] = keyboard, ["mouse"] = mouse,
                    ["localization"] = KeyBindingsReader.ValidLocalization(localization) ? localization : null,
                    ["listHeight"] = ListHeight(root, out var height) ? height : null,
                    ["listOpen"] = Flag(root, "listOpen", out var listOpen) ? listOpen : null,
                    ["notesOpen"] = Flag(root, "notesOpen", out var notesOpen) ? notesOpen : null,
                }
                : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or KeyNotFoundException or InvalidOperationException)
        {
            return null;
        }
    }

    private BridgeDispatchBatch SaveView(BridgeEnvelope request)
    {
        if (request.AccountContext is not null || request.CorrelationId is not { Length: <= MaximumCorrelationLength } ||
            request.Payload.ValueKind != JsonValueKind.Object || !KnownViewFields(request.Payload) ||
            !request.Payload.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number ||
            !schema.TryGetInt32(out var version) || version != 1 ||
            request.Payload.TryGetProperty("keyboard", out var keyboard) &&
            (keyboard.ValueKind != JsonValueKind.String || !Keyboards.Contains(keyboard.GetString())) ||
            !request.Payload.TryGetProperty("mouse", out var mouse) || mouse.ValueKind != JsonValueKind.String ||
            !Mice.Contains(mouse.GetString()) || !OptionalLocalization(request.Payload, out var chosen) ||
            !Optional(request.Payload, "listHeight", ListHeight, out int? height) ||
            !Optional(request.Payload, "listOpen", (JsonElement e, out bool v) => Flag(e, "listOpen", out v), out bool? listOpen) ||
            !Optional(request.Payload, "notesOpen", (JsonElement e, out bool v) => Flag(e, "notesOpen", out v), out bool? notesOpen))
            return new(BridgeEnvelope.ErrorResponse(request,
                new BridgeError(BridgeErrorCodes.InvalidEnvelope, "Invalid key bindings request.")), []);
        if (_viewPath is null) return Unavailable(request);
        var view = new Dictionary<string, object?>
        {
            ["mouse"] = mouse.GetString(), ["localization"] = chosen,
            ["listHeight"] = height, ["listOpen"] = listOpen, ["notesOpen"] = notesOpen,
        };
        // No key at all when none was chosen: an earlier build reading the file keeps the rest.
        if (keyboard.ValueKind == JsonValueKind.String) view["keyboard"] = keyboard.GetString();
        var bytes = JsonSerializer.SerializeToUtf8Bytes(view);
        // One save at a time, through a fresh file of our own: never one left behind, which could be a link.
        lock (_saveGate)
        {
            var folder = Path.GetDirectoryName(_viewPath)!;
            if ((File.GetAttributes(folder) & FileAttributes.ReparsePoint) != 0 ||
                File.Exists(_viewPath) && (File.GetAttributes(_viewPath) & FileAttributes.ReparsePoint) != 0)
                return Unavailable(request);
            var temporary = Path.Combine(folder, $"key-bindings-view.{Guid.NewGuid():N}.tmp");
            try
            {
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    stream.Write(bytes);
                File.Move(temporary, _viewPath, overwrite: true);
            }
            finally
            {
                if (File.Exists(temporary)) File.Delete(temporary);
            }
        }
        return new(BridgeEnvelope.Response(request, new Dictionary<string, object?> { ["schemaVersion"] = 1, ["saved"] = true },
            preserveRequestAccountContext: false), []);
    }

    private static readonly HashSet<string> ViewFields =
        ["schemaVersion", "keyboard", "mouse", "localization", "listHeight", "listOpen", "notesOpen"];

    // Each field at most once and none unknown, so nothing extra is ever written to the file.
    private static bool KnownViewFields(JsonElement payload)
    {
        var names = payload.EnumerateObject().Select(property => property.Name).ToList();
        return names.Count is >= 2 and <= 7 && names.Distinct(StringComparer.Ordinal).Count() == names.Count &&
            names.All(ViewFields.Contains);
    }

    private delegate bool FieldReader<T>(JsonElement payload, out T value);

    // An absent field is fine; a present one must read.
    private static bool Optional<T>(JsonElement payload, string name, FieldReader<T> read, out T? value) where T : struct
    {
        value = null;
        if (!payload.TryGetProperty(name, out _)) return true;
        if (!read(payload, out var found)) return false;
        value = found;
        return true;
    }

    // The list's height in logical pixels, within what any window could give it.
    private static bool ListHeight(JsonElement payload, out int height)
    {
        height = 0;
        return payload.TryGetProperty("listHeight", out var value) && value.ValueKind == JsonValueKind.Number &&
            value.TryGetInt32(out height) && height is >= 120 and <= 4000;
    }

    private static bool Flag(JsonElement payload, string name, out bool flag)
    {
        flag = false;
        if (!payload.TryGetProperty(name, out var value) || value.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            return false;
        flag = value.GetBoolean();
        return true;
    }

    // A folder name, or null, under the "localization" key; absent means follow the interface.
    private static bool OptionalLocalization(JsonElement payload, out string? localization)
    {
        localization = null;
        if (!payload.TryGetProperty("localization", out var value)) return true;
        if (value.ValueKind == JsonValueKind.Null) return true;
        if (value.ValueKind != JsonValueKind.String || !KeyBindingsReader.ValidLocalization(value.GetString())) return false;
        localization = value.GetString();
        return true;
    }

    private static BridgeDispatchBatch Unavailable(BridgeEnvelope request) => new(BridgeEnvelope.ErrorResponse(request,
        new BridgeError("keyBindings.unavailable", "Key bindings are unavailable.", true)), []);

    // Dictionaries keep explicit nulls, which the Bridge would drop from anonymous objects.
    private static Dictionary<string, object?> Wire(KeyBindingsSnapshot snapshot) => new()
    {
        ["schemaVersion"] = 1,
        ["state"] = snapshot.State,
        ["channel"] = snapshot.Channel,
        ["path"] = snapshot.Path,
        ["modifiedAtUtc"] = snapshot.ModifiedAt,
        ["defaultsVersion"] = snapshot.DefaultsVersion,
        ["defaultsRelease"] = snapshot.DefaultsRelease,
        ["localizations"] = snapshot.Localizations ?? [],
        ["localization"] = snapshot.Localization,
        ["localizationFallback"] = snapshot.LocalizationFallback,
        ["namesState"] = snapshot.NamesState,
        ["namesPath"] = snapshot.NamesPath,
        ["maps"] = snapshot.Maps.Select(map => new Dictionary<string, object?>
        {
            ["name"] = map.Name,
            ["localizedName"] = map.LocalizedName,
            ["actions"] = map.Actions.Select(action => new Dictionary<string, object?>
            {
                ["name"] = action.Name,
                ["localizedName"] = action.LocalizedName,
                ["bindings"] = action.Bindings.Select(binding => new Dictionary<string, object?>
                {
                    ["device"] = binding.Device,
                    ["instance"] = binding.Instance,
                    ["input"] = binding.Input,
                    ["customized"] = binding.Customized,
                    ["multiTap"] = binding.MultiTap,
                    ["mode"] = binding.Mode,
                }).ToArray(),
            }).ToArray(),
        }).ToArray(),
    };

    public void Dispose() => _disposed = true;
}
