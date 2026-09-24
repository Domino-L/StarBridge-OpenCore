namespace StarBridge.HostRuntime.Overlay;

using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.Core.Overlay;

internal static class OverlayWorkspaceWireProjection
{
    private static readonly JsonSerializerOptions InputOptions = CreateInputOptions();
    private static readonly IReadOnlySet<string> SettingFields = new HashSet<string>(
        ProjectConstructorState(OverlayDisplaySettings.Default).Keys,
        StringComparer.Ordinal);
    private static readonly IReadOnlySet<string> LayoutFields = new HashSet<string>(
        ["key", "x", "y", "width", "height", "horizontalAnchor", "verticalAnchor", "isLocked", "textOpacity", "backgroundOpacity", "decorationOpacity"],
        StringComparer.Ordinal);

    internal static IReadOnlyDictionary<string, object?> Settings(OverlayDisplaySettings settings) =>
        ProjectConstructorState(settings);

    internal static IReadOnlyDictionary<string, object?> Layout(InformationOverlayLayoutItem item) =>
        new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["key"] = item.Key,
            ["x"] = item.X,
            ["y"] = item.Y,
            ["width"] = item.Width,
            ["height"] = item.Height,
            ["horizontalAnchor"] = item.HorizontalAnchor.ToString(),
            ["verticalAnchor"] = item.VerticalAnchor.ToString(),
            ["isLocked"] = item.IsLocked,
            ["textOpacity"] = item.TextOpacity,
            ["backgroundOpacity"] = item.BackgroundOpacity,
            ["decorationOpacity"] = item.DecorationOpacity
        };

    internal static OverlayDisplaySettings ParseSettings(JsonElement value)
    {
        RequireExactFields(value, SettingFields);
        try
        {
            var parsed = value.Deserialize<OverlayDisplaySettings>(InputOptions) ??
                         throw new JsonException();
            return OverlayDisplaySettings.Parse(parsed.Serialize());
        }
        catch (Exception exception) when (exception is JsonException or InvalidOperationException or ArgumentException)
        {
            throw new OverlaySettingsException("overlay.workspace_invalid_value", false, exception);
        }
    }

    internal static IReadOnlyList<InformationOverlayLayoutItem> ParseLayout(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Array)
        {
            throw new OverlaySettingsException("overlay.workspace_invalid_layout");
        }

        var result = new List<InformationOverlayLayoutItem>();
        foreach (var item in value.EnumerateArray())
        {
            RequireExactFields(item, LayoutFields);
            try
            {
                var horizontal = Enum.Parse<OverlayHorizontalAnchor>(
                    item.GetProperty("horizontalAnchor").GetString() ?? string.Empty,
                    ignoreCase: false);
                var vertical = Enum.Parse<OverlayVerticalAnchor>(
                    item.GetProperty("verticalAnchor").GetString() ?? string.Empty,
                    ignoreCase: false);
                result.Add(new InformationOverlayLayoutItem(
                    item.GetProperty("key").GetString() ?? string.Empty,
                    ReadFiniteDouble(item, "x"),
                    ReadFiniteDouble(item, "y"),
                    ReadFiniteDouble(item, "width"),
                    ReadFiniteDouble(item, "height"),
                    horizontal,
                    vertical,
                    item.GetProperty("isLocked").GetBoolean(),
                    ReadFiniteDouble(item, "textOpacity"),
                    ReadFiniteDouble(item, "backgroundOpacity"),
                    ReadFiniteDouble(item, "decorationOpacity")));
            }
            catch (Exception exception) when (exception is InvalidOperationException or ArgumentException or FormatException)
            {
                throw new OverlaySettingsException("overlay.workspace_invalid_layout", false, exception);
            }
        }

        return result;
    }

    private static IReadOnlyDictionary<string, object?> ProjectConstructorState(object value)
    {
        var type = value.GetType();
        var constructor = type.GetConstructors(BindingFlags.Instance | BindingFlags.Public)
            .OrderByDescending(candidate => candidate.GetParameters().Length)
            .FirstOrDefault() ?? throw new InvalidOperationException(
                $"{type.Name} has no public state constructor.");
        var result = new Dictionary<string, object?>(StringComparer.Ordinal);
        foreach (var parameter in constructor.GetParameters())
        {
            var parameterName = parameter.Name ?? throw new InvalidOperationException(
                $"{type.Name} contains an unnamed state field.");
            var property = type.GetProperty(
                parameterName,
                BindingFlags.Instance | BindingFlags.Public | BindingFlags.IgnoreCase) ??
                throw new InvalidOperationException(
                    $"{type.Name}.{parameterName} has no public state property.");
            result[ToCamelCase(parameterName)] = ProjectValue(property.GetValue(value));
        }

        return result;
    }

    private static object? ProjectValue(object? value)
    {
        if (value is null)
        {
            return null;
        }

        var type = value.GetType();
        if (value is OverlayEventNotificationTypes eventTypes)
        {
            return (int)eventTypes;
        }
        if (type.IsEnum)
        {
            return value.ToString();
        }

        if (value is string or bool or byte or sbyte or short or ushort or int or uint or long or ulong or
            float or double or decimal)
        {
            return value;
        }

        return ProjectConstructorState(value);
    }

    private static string ToCamelCase(string value) =>
        value.Length == 0 ? value : char.ToLowerInvariant(value[0]) + value[1..];

    private static void RequireExactFields(JsonElement value, IReadOnlySet<string> expected)
    {
        if (value.ValueKind != JsonValueKind.Object)
        {
            throw new OverlaySettingsException("overlay.workspace_invalid_value");
        }

        var actual = value.EnumerateObject().Select(property => property.Name).ToHashSet(StringComparer.Ordinal);
        if (!actual.SetEquals(expected))
        {
            throw new OverlaySettingsException("overlay.workspace_invalid_value");
        }
    }

    private static double ReadFiniteDouble(JsonElement value, string propertyName)
    {
        var number = value.GetProperty(propertyName).GetDouble();
        if (!double.IsFinite(number))
        {
            throw new FormatException();
        }
        return number;
    }

    private static JsonSerializerOptions CreateInputOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = false,
            UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
        };
        options.Converters.Add(new JsonStringEnumConverter());
        return options;
    }
}
