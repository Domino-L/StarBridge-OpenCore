using System.Text.Json;
using StarBridge.Core.Chat;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class OverlaySharedPresetTests
{
    internal static async Task Sharing()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-preset-sharing-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var runtime = new UntouchedRuntime();
            using var host = new OverlayBridgeDispatcher(root, () => 1, () => GameLogSessionSnapshot.Empty, runtime);
            async Task<BridgeEnvelope> Request(string name, object data) =>
                (await host.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 1, data))).Response;
            async Task<JsonElement> Read() => (await Request("overlay.getWorkspace", new { schemaVersion = 1 })).Payload;
            var before = await Read();
            var revision = before.GetProperty("revision").GetInt64();
            var active = before.GetProperty("activePresetId").GetString();
            var export = await Request("overlay.updateWorkspace", new { schemaVersion = 1, action = "exportSharedPreset", expectedRevision = revision, presetId = active });
            Check(export.Status == "ok", "Export succeeds.");
            Check(Directory.GetFiles(root).Length == 0, "Export is read-only.");
            var attachment = export.Payload.GetProperty("attachment").Deserialize<ChatAttachmentContract>(BridgeProtocol.JsonOptions)!;
            Check(ChatAttachmentPolicy.TryNormalize(attachment, out _, out _), "Existing WPF chat contract accepts export.");
            var package = OverlaySharedPreset.Parse(attachment.OverlayPresetPackage);
            Check(package.Version == 1 && package.Settings.Contains(','), "WPF v1 uses legacy CSV, not Flutter wire maps.");
            Check(!package.Serialize().Contains("hotkey", StringComparison.OrdinalIgnoreCase), "Device hotkey is not shared.");
            package = package with { Name = "受限外观", Settings = (OverlayDisplaySettings.Parse(package.Settings) with
                { Skin = OverlaySkin.NightShadow, RequestedSkin = OverlaySkin.NightShadow }).Serialize() };
            var imported = await Request("overlay.updateWorkspace", new { schemaVersion = 1, action = "importSharedPreset", expectedRevision = revision, package = package.Serialize() });
            Check(imported.Status == "ok", "Import creates a new preset.");
            var after = await Read();
            Check(after.GetProperty("presets").GetArrayLength() == before.GetProperty("presets").GetArrayLength() + 1, "Exactly one additive import.");
            Check(after.GetProperty("activePresetId").GetString() == active &&
                after.GetProperty("settings").GetRawText() == before.GetProperty("settings").GetRawText(), "Current overlay and settings are unchanged.");
            Check(after.GetProperty("hotkey").GetRawText() == before.GetProperty("hotkey").GetRawText() &&
                after.GetProperty("appearances").GetRawText() == before.GetProperty("appearances").GetRawText(), "Hotkey and eligibility catalog unchanged.");
            Check(runtime.Calls == 0, "Import/export never sync or open the live overlay.");
            var importedPreset = after.GetProperty("presets").EnumerateArray().Single(p => p.GetProperty("id").GetString() == imported.Payload.GetProperty("presetId").GetString());
            Check(importedPreset.GetProperty("settings").GetProperty("requestedSkin").GetString() == "NightShadow", "Keep requested appearance without granting it.");
            var files = Directory.GetFiles(root, "*", SearchOption.AllDirectories).ToDictionary(p => p, File.ReadAllBytes);
            var conflict = await Request("overlay.updateWorkspace", new { schemaVersion = 1, action = "importSharedPreset", expectedRevision = revision, package = package.Serialize() });
            Check(conflict.Status == "error", "Stale revision cannot import twice.");
            foreach (var invalid in new[] {
                "{}", new string('x', ChatAttachmentPolicy.MaximumPresetPackageLength + 1),
                package.Serialize().Replace("\"Version\":1", "\"Version\":2"),
                (package with { Settings = "nonsense" }).Serialize(),
                (package with { Layout = "Chat,NaN,0,1,1" }).Serialize(),
                (package with { Layout = "Chat,0,0,1,1;Chat,0,0,1,1" }).Serialize(),
                (package with { Layout = "secret,0,0,1,1" }).Serialize(),
                package.Serialize().TrimEnd('}') + ",\"entitlements\":[\"overlay.skin.night-shadow\"]}"
            }) {
                var failure = await Request("overlay.updateWorkspace", new { schemaVersion = 1, action = "importSharedPreset", expectedRevision = after.GetProperty("revision").GetInt64(), package = invalid });
                Check(failure.Status == "error" && failure.Error?.Code == "overlay.shared_preset_invalid", "Invalid package rejected before write.");
            }
            Check(Directory.GetFiles(root, "*", SearchOption.AllDirectories).Length == files.Count && files.All(p => File.ReadAllBytes(p.Key).SequenceEqual(p.Value)), "Failures do not mutate files.");
            var second = await Request("overlay.updateWorkspace", new { schemaVersion = 1, action = "importSharedPreset", expectedRevision = after.GetProperty("revision").GetInt64(), package = package.Serialize() });
            Check(second.Status == "ok" && second.Payload.GetProperty("name").GetString() != package.Name, "Name collisions create a distinct name.");
            var legacy = OverlaySharedPreset.Parse(new OverlaySharedPreset(1, "旧预设", "0,CallsignAndGameName,0,0,0", "Chat,0,0,0.2,0.2;Mission,0,0,1,1").Serialize());
            Check(InformationOverlayLayoutItem.ParseMany(legacy.Layout).Count() == 4 && !legacy.Layout.Contains("Mission"), "Legacy missing modules default; retired Mission removed.");
            Check(!ChatAttachmentPolicy.TryNormalize(new("overlay_preset", "title", "summary", "{\"version\":{},\"name\":7,\"settings\":[],\"layout\":false}"), out _, out _), "Malformed field kinds cannot throw from chat normalization.");
        }
        finally { Directory.Delete(root, true); }
    }
    private static void Check(bool value, string reason) { if (!value) throw new Exception(reason); }
    private sealed class UntouchedRuntime : IInformationOverlayRuntime
    {
        internal int Calls;
        public ValueTask<InformationOverlayRuntimeSnapshot> ExecuteAsync(InformationOverlayRuntimeCommand command, InformationOverlayRuntimeWorkspace workspace, CancellationToken cancellationToken = default)
        { Calls++; return ValueTask.FromResult(InformationOverlayRuntimeSnapshot.Unavailable); }
        public void Dispose() { }
    }
}
