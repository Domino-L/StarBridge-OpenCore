using System.Text;
using System.Text.Json;

namespace StarBridge.Core.Overlay;

/// <summary>Bounded, immutable presentation options. Private appearances own their value schemas;
/// this envelope carries no entitlement, source authority, executable content or asset paths.</summary>
public sealed record OverlayAppearanceOptions
{
    public const int MaximumBytes = 16 * 1024;
    public static OverlayAppearanceOptions Empty { get; } = new("{\"schemaVersion\":1,\"profiles\":{}}");
    public string Json { get; }
    private OverlayAppearanceOptions(string json) => Json = json;
    public JsonElement ToElement() => JsonSerializer.Deserialize<JsonElement>(Json);
    public JsonElement? Profile(string id) => ToElement().GetProperty("profiles").TryGetProperty(id, out var profile)
        ? profile : null;

    public static OverlayAppearanceOptions Parse(string json)
    {
        if (string.IsNullOrWhiteSpace(json) || Encoding.UTF8.GetByteCount(json) > MaximumBytes)
            throw new FormatException("Invalid appearance options.");
        try
        {
            using var document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 8 });
            var root = document.RootElement;
            Exact(root, "schemaVersion", "profiles");
            if (!root.GetProperty("schemaVersion").TryGetInt32(out var schema) || schema != 1)
                throw new FormatException("Unsupported appearance options.");
            var profiles = root.GetProperty("profiles");
            if (profiles.ValueKind != JsonValueKind.Object || profiles.EnumerateObject().Count() > 8)
                throw new FormatException("Invalid appearance profiles.");
            var budget = 1024;
            Validate(root, ref budget);
            foreach (var profile in profiles.EnumerateObject())
            {
                Exact(profile.Value, "version", "values");
                if (!profile.Value.GetProperty("version").TryGetInt32(out var version) || version is < 1 or > 1000 ||
                    profile.Value.GetProperty("values").ValueKind != JsonValueKind.Object)
                    throw new FormatException("Invalid appearance profile.");
            }
            return new OverlayAppearanceOptions(JsonSerializer.Serialize(root));
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException)
        {
            throw new FormatException("Invalid appearance options.", error);
        }
    }

    private static void Exact(JsonElement value, params string[] expected)
    {
        if (value.ValueKind != JsonValueKind.Object || !value.EnumerateObject().Select(p => p.Name)
            .Order(StringComparer.Ordinal).SequenceEqual(expected.Order(StringComparer.Ordinal)))
            throw new FormatException("Invalid appearance fields.");
    }

    private static void Validate(JsonElement value, ref int budget)
    {
        if (--budget < 0) throw new FormatException("Too many appearance values.");
        switch (value.ValueKind)
        {
            case JsonValueKind.Object:
                var keys = new HashSet<string>(StringComparer.Ordinal);
                foreach (var property in value.EnumerateObject())
                {
                    if (property.Name.Length is < 1 or > 64 ||
                        property.Name.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not ('_' or '-')) ||
                        property.Name is "__proto__" or "prototype" or "constructor" || !keys.Add(property.Name))
                        throw new FormatException("Invalid appearance key.");
                    Validate(property.Value, ref budget);
                }
                break;
            case JsonValueKind.Array:
                foreach (var item in value.EnumerateArray()) Validate(item, ref budget);
                break;
            case JsonValueKind.String:
                if (value.GetString()!.Length > 256) throw new FormatException("Appearance value too long.");
                break;
            case JsonValueKind.Number:
                if (!value.TryGetDouble(out var number) || !double.IsFinite(number))
                    throw new FormatException("Invalid appearance number.");
                break;
            case JsonValueKind.True: case JsonValueKind.False: case JsonValueKind.Null: break;
            default: throw new FormatException("Invalid appearance value.");
        }
    }
}
