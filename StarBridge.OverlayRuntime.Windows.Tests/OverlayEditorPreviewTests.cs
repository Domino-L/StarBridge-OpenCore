using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.Desktop.Tests;

/// <summary>
/// What the visor would show, for the client's layout editor to draw its own simplified panels with (11-12 user: "编辑里还是
/// 要用模拟面板，只不过信息都一致"): samples flagged when there are no sources, sample names that are plainly samples ("示例数据
/// 就写全用示例名字/模拟名字"), the events box filled with the most events at once, each event with its kind's colour, the
/// decoration colour following the palette, and nothing drawn (text only).
/// </summary>
internal static class OverlayEditorPreviewTests
{
    internal static async Task Run()
    {
        using var runtime = new NativeInformationOverlayRuntime();
        IInformationOverlayEditorPreviewRuntime preview = runtime;
        InformationOverlayRuntimeWorkspace Workspace(int events, string language = "zh", OverlayVisualTheme theme = OverlayVisualTheme.Default,
            bool barrage = false) => new(1,
            InformationOverlayDefaults.DefaultSettings with
            {
                Skin = OverlaySkin.Visor, RequestedSkin = OverlaySkin.Visor, EnableStartupTransition = false,
                AutoFocusGameWindowOnOpen = false, AutoOpenOverlayOnGameStart = false, AutoOpenOverlayOnGameForeground = false,
                ShowEventNotifications = true, ShowMembers = true, ShowChat = true, Theme = theme, AutoThemeByShip = false,
                EventNotificationMaxVisibleCount = events,
                ChatDisplayMode = barrage ? OverlayChatDisplayMode.FullScreenBarrage : OverlayChatDisplayMode.MessageList,
            }, InformationOverlayDefaults.CreateLayout("preset1"), "Alt+O", false, GameLogSessionSnapshot.Empty, language);

        foreach (var events in new[] { 1, 3, 5 })
        {
            var content = await preview.ReadEditorContentAsync(Workspace(events));
            Check(content.Sample && content.Members.Rows.Count > 0, $"no sources: sample members, flagged ({events})", content.Members.Rows.Count);
            Check(content.Members.Rows.All(r => r.Name.StartsWith("示例队员 ", StringComparison.Ordinal)),
                "sample members are plainly samples", string.Join(",", content.Members.Rows.Select(r => r.Name)));
            Check(content.Events.Sample && content.Events.Rows.Count == events,
                $"{events} events: no live events, samples fill the box (it holds the most at once)", content.Events.Rows.Count);
            Check(content.Chat.Sample && content.Chat.Rows.Count > 0 && content.Chat.Rows.All(c => c.Who.StartsWith("示例队员 ", StringComparison.Ordinal)),
                "no chat: sample chat with sample names", string.Join(",", content.Chat.Rows.Select(c => c.Who)));
        }
        var five = await preview.ReadEditorContentAsync(Workspace(5));
        var tones = five.Events.Rows.Select(e => e.Tone).ToArray();
        Check(tones.Contains(nameof(OverlayVisorEventTone.Place)) && tones.Contains(nameof(OverlayVisorEventTone.Ship)) &&
              tones.Contains(nameof(OverlayVisorEventTone.Server)) && tones.Contains(nameof(OverlayVisorEventTone.SameServer)),
            "sample events carry their kind's colour", string.Join(",", tones));
        Check(five.Events.Rows.All(e => !e.Detail.Contains("Vega", StringComparison.Ordinal) && !e.Detail.Contains("Aster", StringComparison.Ordinal)),
            "sample events name sample members only", string.Join(" | ", five.Events.Rows.Select(e => e.Detail)));
        Check(five.Events.Title == "事件" && five.Chat.Title.Length > 0, "the block titles", new { events = five.Events.Title, chat = five.Chat.Title });

        // the decoration follows the palette (11-12: colour changes the background, never the status colours)
        var plain = await preview.ReadEditorContentAsync(Workspace(3));
        var drake = await preview.ReadEditorContentAsync(Workspace(3, theme: OverlayVisualTheme.Drake));
        Check(plain.Decoration.Length == 7 && plain.Decoration[0] == '#' && plain.Decoration != drake.Decoration,
            "the decoration colour follows the palette", new { plain = plain.Decoration, drake = drake.Decoration });

        // Traditional and English samples
        var tw = await preview.ReadEditorContentAsync(Workspace(3, "zh-TW"));
        var en = await preview.ReadEditorContentAsync(Workspace(3, "en"));
        Check(tw.Members.Rows.All(r => r.Name.StartsWith("範例隊員 ", StringComparison.Ordinal)) &&
              en.Members.Rows.All(r => r.Name.StartsWith("Sample member ", StringComparison.Ordinal)),
            "sample names in the editor's language", new { tw = tw.Members.Rows[0].Name, en = en.Members.Rows[0].Name });

        // the payload the bridge sends: text only, small
        var bytes = System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(five);
        Check(bytes.Length < 16 * 1024, "the reply is text only and small", bytes.Length);
    }

    private static void Check(bool value, string message, object? evidence = null)
    {
        if (!value) throw new InvalidOperationException($"{message} {evidence}");
        Console.WriteLine($"PASS editor preview: {message}");
    }
}
