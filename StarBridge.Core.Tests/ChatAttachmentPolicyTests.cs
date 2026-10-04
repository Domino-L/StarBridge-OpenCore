using System.Text.Json;
using StarBridge.Core.Chat;
using StarBridge.Core.Overlay;

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
        var privateSources = new OverlayPresetSources(new(OverlaySourceMode.Community, "private-org", "private-owner"), true,
            new Dictionary<OverlaySourceModule, OverlaySourceBinding> { [OverlaySourceModule.Chat] = new(OverlaySourceMode.Community, "private-module", "private-owner") });
        var v2 = JsonSerializer.Serialize(new { Version = 2, Name = "预设", Settings = "settings", Layout = "layout",
            Sources = JsonSerializer.Deserialize<JsonElement>(OverlayPresetSourcesCodec.Serialize(privateSources)), RemovedOrganizationBindings = false });
        if (!ChatAttachmentPolicy.TryNormalize(new("overlay_preset", "预设", "说明", v2), out var normalized, out _) ||
            normalized!.OverlayPresetPackage!.Contains("private-")) throw new Exception("Chat transfer leaked organization identities.");
        using var document = JsonDocument.Parse(normalized.OverlayPresetPackage!);
        var safe = OverlayPresetSourcesCodec.Parse(document.RootElement.GetProperty("Sources").GetRawText());
        if (safe.AutoSwitch || safe.Binding.Mode != OverlaySourceMode.Auto ||
            safe.Modules[OverlaySourceModule.Chat].Mode != OverlaySourceMode.Auto ||
            !document.RootElement.GetProperty("RemovedOrganizationBindings").GetBoolean()) throw new Exception("Chat transfer sanitization mismatch.");
        foreach (var invalid in new[] { v2.Replace("\"Version\":2", "\"Version\":3"),
            v2.TrimEnd('}') + ",\"extra\":true}", v2.Replace("\"RemovedOrganizationBindings\":false", "\"RemovedOrganizationBindings\":null") })
            if (ChatAttachmentPolicy.TryNormalize(new("overlay_preset", "预设", "说明", invalid), out _, out _))
                throw new Exception("Invalid v2 package accepted.");
        var roomSources = new OverlayPresetSources(new(OverlaySourceMode.Room), true,
            new Dictionary<OverlaySourceModule, OverlaySourceBinding> { [OverlaySourceModule.Events] = OverlaySourceBinding.Automatic });
        var roomPackage = JsonSerializer.Serialize(new { Version = 2, Name = "预设", Settings = "settings", Layout = "layout",
            Sources = JsonSerializer.Deserialize<JsonElement>(OverlayPresetSourcesCodec.Serialize(roomSources)), RemovedOrganizationBindings = false });
        if (!ChatAttachmentPolicy.TryNormalize(new("overlay_preset", "预设", "说明", roomPackage), out var roomResult, out _))
            throw new Exception("Room source package rejected.");
        using var roomDocument = JsonDocument.Parse(roomResult!.OverlayPresetPackage!);
        var roomSafe = OverlayPresetSourcesCodec.Parse(roomDocument.RootElement.GetProperty("Sources").GetRawText());
        if (roomSafe.AutoSwitch || roomSafe.Binding.Mode != OverlaySourceMode.Room ||
            roomSafe.Modules[OverlaySourceModule.Events].Mode != OverlaySourceMode.Auto ||
            roomDocument.RootElement.GetProperty("RemovedOrganizationBindings").GetBoolean())
            throw new Exception("Transfer lost safe per-module choices or enabled auto-switch.");
        if (!ChatAttachmentPolicy.TryNormalize(roomResult, out var again, out _) || again != roomResult)
            throw new Exception("Preset normalization must be idempotent.");
        foreach (var invalid in new[] { roomPackage.Replace("\"Version\":2", "\"Version\":2,\"version\":2"),
            roomPackage.Replace("\"schemaVersion\":2", "\"schemaVersion\":2,\"schemaVersion\":2"),
            roomPackage.Replace("\"mode\":\"room\"", "\"mode\":\"local\""),
            roomPackage.Replace("\"ownerKey\":null", "\"ownerKey\":\"unexpected-owner\""),
            roomPackage.Replace("\"Settings\":\"settings\"", "\"Settings\":\"" + new string('x', ChatAttachmentPolicy.MaximumPresetPackageLength) + "\"") })
            if (ChatAttachmentPolicy.TryNormalize(new("overlay_preset", "预设", "说明", invalid), out _, out _))
                throw new Exception("Malformed, identity-bearing, or oversized v2 package accepted.");
    }
}
