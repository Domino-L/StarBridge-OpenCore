namespace StarBridge.Core.Overlay;

using System.Text.Json;

public sealed record OverlaySourceExport(OverlayPresetSources Sources, bool RemovedOrganizationBindings);

/// <summary>Versioned source policy only; legacy WPF settings and account choices are not rewritten here.</summary>
public static class OverlayPresetSourcesCodec
{
    public const int Version = 2;
    public const int MaximumPayloadLength = 16384;

    public static OverlayPresetSources FromLegacy(OverlayScenePreference preference) => new(
        preference switch
        {
            OverlayScenePreference.Auto or OverlayScenePreference.Fleet => OverlaySourceBinding.Follow,
            OverlayScenePreference.PartyRoom => new(OverlaySourceMode.Room),
            _ => throw new ArgumentException("Unknown legacy overlay source.")
        });

    public static string Serialize(OverlayPresetSources sources)
    {
        ArgumentNullException.ThrowIfNull(sources);
        var wire = new Dictionary<string, object?>
        {
            ["schemaVersion"] = sources.ChatSources.Count > 0 ? 3 : Version,
            ["sourceBinding"] = BindingWire(sources.Binding),
            ["autoSwitch"] = sources.AutoSwitch,
            ["moduleSources"] = Enum.GetValues<OverlaySourceModule>().ToDictionary(
                ModuleName, module => BindingWire(sources.Modules.GetValueOrDefault(module, OverlaySourceBinding.Follow)))
        };
        if (sources.ChatSources.Count > 0) wire["chatSources"] = sources.ChatSources.Select(BindingWire).ToArray();
        return JsonSerializer.Serialize(wire);
    }

    public static OverlayPresetSources Parse(string payload)
    {
        if (string.IsNullOrWhiteSpace(payload) || payload.Length > MaximumPayloadLength)
            throw new FormatException("Invalid source policy size.");
        try
        {
            using var document = JsonDocument.Parse(payload, new JsonDocumentOptions { MaxDepth = 8 });
            var root = document.RootElement;
            var version = root.GetProperty("schemaVersion").GetInt32();
            Exact(root, version == 3 ? ["schemaVersion", "sourceBinding", "autoSwitch", "moduleSources", "chatSources"] :
                ["schemaVersion", "sourceBinding", "autoSwitch", "moduleSources"]);
            if (version is not (Version or 3))
                throw new FormatException("Unsupported source policy version.");
            var modulesNode = root.GetProperty("moduleSources");
            Exact(modulesNode, Enum.GetValues<OverlaySourceModule>().Select(ModuleName).ToArray());
            var modules = Enum.GetValues<OverlaySourceModule>().ToDictionary(
                module => module, module => ParseBinding(modulesNode.GetProperty(ModuleName(module))));
            var chat = version == 3 ? root.GetProperty("chatSources").EnumerateArray().Select(ParseBinding).ToArray() : [];
            if (version == 3 && chat.Length == 0) throw new FormatException("Empty multi-source chat policy.");
            return new(ParseBinding(root.GetProperty("sourceBinding")), root.GetProperty("autoSwitch").GetBoolean(), modules, chat);
        }
        catch (Exception exception) when (exception is JsonException or InvalidOperationException or ArgumentException or OverflowException or KeyNotFoundException)
        {
            throw new FormatException("Invalid overlay source policy.", exception);
        }
    }

    /// <summary>Apply on both export/share and import. Removed identities never survive in the result.</summary>
    public static OverlaySourceExport ForTransfer(OverlayPresetSources sources)
    {
        ArgumentNullException.ThrowIfNull(sources);
        var removed = sources.Binding.Mode == OverlaySourceMode.Community ||
            sources.Modules.Values.Concat(sources.ChatSources).Any(binding => binding.Mode == OverlaySourceMode.Community);
        static OverlaySourceBinding Clean(OverlaySourceBinding binding) =>
            binding.Mode == OverlaySourceMode.Community ? OverlaySourceBinding.Automatic : binding;
        // After stripping account-bound organizations only the room can remain.
        // Encode that exact intent as v2's explicit chat override so existing
        // share recipients/servers need no upgrade; never drop a surviving source.
        var modules = sources.Modules.ToDictionary(pair => pair.Key, pair => Clean(pair.Value));
        if (sources.ChatSources.Count > 0)
            modules[OverlaySourceModule.Chat] = sources.ChatSources.Any(binding => binding.Mode == OverlaySourceMode.Room)
                ? new(OverlaySourceMode.Room) : OverlaySourceBinding.Follow;
        // Import/share never installs automatic behavior on the recipient's device.
        return new(new(Clean(sources.Binding),
            false,
            modules), removed);
    }

    private static object BindingWire(OverlaySourceBinding binding) => new
    {
        mode = ModeName(binding.Mode), communityCode = binding.CommunityCode, ownerKey = binding.OwnerKey
    };

    private static OverlaySourceBinding ParseBinding(JsonElement node)
    {
        Exact(node, "mode", "communityCode", "ownerKey");
        var mode = node.GetProperty("mode").GetString() switch
        {
            "none" => OverlaySourceMode.None,
            "auto" => OverlaySourceMode.Auto,
            "room" => OverlaySourceMode.Room,
            "community" => OverlaySourceMode.Community,
            _ => throw new FormatException("Unsupported source binding.")
        };
        return new(mode, node.GetProperty("communityCode").GetString(), node.GetProperty("ownerKey").GetString());
    }

    private static string ModeName(OverlaySourceMode mode) => mode switch
    {
        OverlaySourceMode.None => "none", OverlaySourceMode.Auto => "auto", OverlaySourceMode.Room => "room",
        OverlaySourceMode.Community => "community", _ => throw new ArgumentException("Unsupported source binding.")
    };
    private static string ModuleName(OverlaySourceModule module) => module switch
    {
        OverlaySourceModule.Notice => "notice", OverlaySourceModule.Overview => "overview",
        OverlaySourceModule.Members => "members", OverlaySourceModule.Chat => "chat",
        OverlaySourceModule.Events => "events", _ => throw new ArgumentException("Unsupported overlay module.")
    };

    private static void Exact(JsonElement node, params string[] fields)
    {
        if (node.ValueKind != JsonValueKind.Object) throw new FormatException("Expected source policy object.");
        var actual = new HashSet<string>(StringComparer.Ordinal);
        foreach (var property in node.EnumerateObject())
            if (!actual.Add(property.Name)) throw new FormatException("Duplicate source policy field.");
        if (!actual.SetEquals(fields)) throw new FormatException("Unexpected source policy fields.");
    }
}
