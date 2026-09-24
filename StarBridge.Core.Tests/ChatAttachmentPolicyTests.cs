using System.Text.Json;
using StarBridge.Core.Chat;

namespace StarBridge.Core.Tests;

internal static class ChatAttachmentPolicyTests
{
    internal static void RunAll()
    {
        foreach (var field in new[] { "version", "name", "settings", "layout" })
        foreach (object? invalid in new object?[] { null, new { nested = true }, new[] { "value" }, false })
        {
            var package = new Dictionary<string, object?>
            { ["version"] = 1, ["name"] = "预设", ["settings"] = "settings", ["layout"] = "layout" };
            package[field] = invalid;
            if (ChatAttachmentPolicy.TryNormalize(new("overlay_preset", "预设", "说明", JsonSerializer.Serialize(package)), out _, out _))
                throw new Exception("Malformed preset field was accepted: " + field);
        }
        var valid = JsonSerializer.Serialize(new { Version = 1, Name = "预设", Settings = "settings", Layout = "layout" });
        if (!ChatAttachmentPolicy.TryNormalize(new("overlay_preset", "预设", "说明", valid), out _, out _))
            throw new Exception("WPF PascalCase package rejected.");
    }
}
