using Vortice.Direct2D1;
using WpfRect = System.Windows.Rect;

namespace StarBridge.Desktop;

/// <summary>
/// The organization overview drawn from facts, in tiers that follow the module's
/// height: small shows the whole organization and the viewer's own shard in one
/// line; larger sizes separate the organization from the viewer and add shard
/// bars, how everyone is online, and where people are.
/// </summary>
internal sealed partial class OverlayCompositionHudWindow
{
    private const float OverviewTitleTier = 80;
    private const float OverviewSelfTier = 105;
    private const float OverviewBarsTier = 170;
    private const float OverviewDetailTier = 260;

    private static readonly HudColor OverviewAppOnlineColor = FromBrush(StatusPalette.InfoBrush, HudColor.FromRgb(82, 183, 245));
    private static readonly HudColor OverviewAwayColor = FromBrush(StatusPalette.WarningBrush, HudColor.FromRgb(217, 164, 65));
    // Lighter than the disabled grey: the dot alone carries the status and must stay visible.
    private static readonly HudColor OverviewOfflineColor = HudColor.FromRgb(133, 145, 158);

    // The same four colours in every appearance; some skins theme Palette.Online away from green.
    private static HudColor PresenceDotColor(StarBridge.Core.Presence.PlayerPresenceKind presence) => presence switch
    {
        StarBridge.Core.Presence.PlayerPresenceKind.InGame => MemberRelevantColor,
        StarBridge.Core.Presence.PlayerPresenceKind.AppOnline => OverviewAppOnlineColor,
        StarBridge.Core.Presence.PlayerPresenceKind.Away => OverviewAwayColor,
        _ => OverviewOfflineColor
    };

    private static bool OverviewShowsTitle(OverlayCompositionFrameState state) =>
        state.OverviewFacts is null || state.SquadsRect.Height >= OverviewTitleTier;

    /// <summary>Returns the bottom of the drawn content so skins can place their trim under it.</summary>
    private float DrawOverviewFacts(ID2D1RenderTarget target, OverlayCompositionFrameState state, OverlayOverviewFacts facts,
        WpfRect rect, float left, float top, float rowY, float contentWidth, double textOpacity)
    {
        var zh = _language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var height = (float)rect.Height;
        var column = contentWidth / 3;
        var hair = state.Palette.Title;
        var own = facts.OwnShard;
        var facts3 = new (string Label, string Value, HudColor Color)[]
        {
            (zh ? "在线" : "Online", facts.Online.ToString(), state.Palette.Text),
            (zh ? "游戏中" : "In game", facts.InGame.ToString(), state.Palette.Online),
            own is not null
                ? (own.Label, own.Count.ToString(), state.Palette.Title)
                : (OverlayOverviewProjection.ShardLabel(zh), "—", state.Palette.Muted)
        };
        if (height >= OverviewTitleTier)
        {
            DrawText(target, zh ? $"共 {facts.Total} 人" : $"{facts.Total} members", _mutedRightFormat,
                left, top + 3, contentWidth - 8, 18, state.Palette.Muted, textOpacity);
        }
        var selfLine = facts.OwnPlace is null && own is null
            ? facts.ViewerInGame ? zh ? "位置未知" : "Location unknown" : zh ? "未进入游戏" : "Not in game"
            : string.Join(" · ", new[] { facts.OwnPlace, own?.Label }.Where(part => !string.IsNullOrWhiteSpace(part)));
        void You(float at)
        {
            DrawText(target, zh ? "你在" : "You", _mutedFormat, left, at + 1, 30, 18, state.Palette.Muted, textOpacity);
            DrawText(target, selfLine, _textFormat, left + 30, at, contentWidth - 30, 18, state.Palette.Title, textOpacity);
        }

        if (height < OverviewBarsTier)
        {
            var lineY = height < OverviewTitleTier ? (float)rect.Y + height / 2 - 9 : rowY;
            for (var i = 0; i < facts3.Length; i++)
            {
                var x = left + column * i;
                var used = Math.Min(column - 20, MeasureTextWidth(facts3[i].Label, _mutedFormat));
                DrawText(target, facts3[i].Label, _mutedFormat, x, lineY + 1, used + 2, 18, state.Palette.Muted, textOpacity);
                DrawText(target, facts3[i].Value, _overviewValueFormat, x + used + 5, lineY, column - used - 5, 18, facts3[i].Color, textOpacity);
            }
            if (height < OverviewSelfTier) return lineY + 18;
            DrawLine(target, left, rowY + 26, left + contentWidth, rowY + 26, hair, textOpacity * 0.25, 1);
            You(rowY + 33);
            var others = facts.Shards.Where(shard => !shard.IsOwn).ToArray();
            if (others.Length > 0 && rowY + 73 <= rect.Bottom - 6)
            {
                DrawText(target, OverlayOverviewProjection.OtherShardsLabel(zh), _mutedFormat, left, rowY + 55, 56, 18, state.Palette.Muted, textOpacity);
                DrawText(target, string.Join("   ", others.Select(shard => shard.Label + " " + shard.Count)), _mutedFormat,
                    left + 56, rowY + 55, contentWidth - 56, 18, state.Palette.Text, textOpacity * 0.9);
                return rowY + 73;
            }
            return rowY + 51;
        }

        for (var i = 0; i < facts3.Length; i++)
        {
            DrawText(target, facts3[i].Value, _overviewNumberFormat, left + column * i, rowY - 4, column, 28, facts3[i].Color, textOpacity);
            DrawText(target, facts3[i].Label, _mutedFormat, left + column * i, rowY + 24, column, 15, state.Palette.Muted, textOpacity);
        }
        var line = rowY + 46;
        DrawLine(target, left, line - 3, left + contentWidth, line - 3, hair, textOpacity * 0.25, 1);
        line += 3;
        var most = Math.Max(1, facts.Shards.Count == 0 ? 1 : facts.Shards.Max(shard => shard.Count));
        string? lastRegion = null;
        var barRows = Math.Max(0, (int)((rect.Bottom - 40 - line) / 20));
        var shown = facts.Shards.Take(height >= OverviewDetailTier ? Math.Min(6, barRows) : Math.Min(3, barRows)).Select(shard =>
        {
            var split = shard.Label.IndexOf(" #", StringComparison.Ordinal);
            return (Shard: shard, Region: split > 0 ? shard.Label[..split] : shard.Label, Tail: split > 0 ? shard.Label[(split + 1)..] : "");
        }).ToArray();
        var regionWidth = shown.Length == 0 ? 0 : Math.Min(contentWidth * 0.3f, shown.Max(row => MeasureTextWidth(row.Region, _mutedFormat)) + 6);
        var tailWidth = shown.Length == 0 ? 0 : Math.Min(contentWidth * 0.3f, shown.Max(row => MeasureTextWidth(row.Tail, _mutedFormat)) + 8);
        var barLeft = regionWidth + tailWidth;
        foreach (var (shard, region, tail) in shown)
        {
            if (region != lastRegion)
                DrawText(target, region, _mutedFormat, left, line, regionWidth, 18, state.Palette.Muted, textOpacity);
            lastRegion = region;
            DrawText(target, tail, _mutedFormat, left + regionWidth, line, tailWidth, 18, shard.IsOwn ? state.Palette.Title : state.Palette.Muted, textOpacity);
            FillRect(target, left + barLeft, line + 6, Math.Max(2, (contentWidth - barLeft - 34) * shard.Count / most), 6,
                shard.IsOwn ? state.Palette.Title : state.Palette.Muted, textOpacity * 0.7);
            DrawText(target, shard.Count.ToString(), _mutedRightFormat, left, line, contentWidth - 4, 18, state.Palette.Text, textOpacity);
            line += 20;
        }
        if (facts.Shards.Count == 0)
        {
            DrawText(target, facts.InGame == 0 ? zh ? "无人在游戏中" : "No one is in game" : zh ? "暂无服务器信息" : "No server data",
                _mutedFormat, left, line, contentWidth, 18, state.Palette.Muted, textOpacity);
            line += 20;
        }
        line += 4;
        DrawLine(target, left, line - 2, left + contentWidth, line - 2, hair, textOpacity * 0.25, 1);
        line += 5;
        You(line);
        line += 24;
        if (height < OverviewDetailTier || line + 24 > rect.Bottom - 8) return line;
        DrawLine(target, left, line - 2, left + contentWidth, line - 2, hair, textOpacity * 0.25, 1);
        line += 5;
        var statusX = left;
        foreach (var (label, count, color) in new[]
        {
            (zh ? "未进游戏" : "App online", facts.AppOnline, OverviewAppOnlineColor),
            (zh ? "暂离" : "Away", facts.Away, OverviewAwayColor),
            (zh ? "离线" : "Offline", facts.Offline, OverviewOfflineColor)
        })
        {
            target.FillEllipse(new Ellipse(new System.Numerics.Vector2(statusX + 4, line + 9), 3.5f, 3.5f), GetBrush(target, color, textOpacity));
            DrawText(target, label + " " + count, _mutedFormat, statusX + 11, line, column - 11, 18, state.Palette.Text, textOpacity * 0.9);
            statusX += column;
        }
        line += 24;
        foreach (var place in facts.Places)
        {
            if (line + 18 > rect.Bottom - 10) break;
            DrawText(target, place.Name, _mutedFormat, left, line, contentWidth - 30, 18,
                place.IsOwn ? state.Palette.Title : state.Palette.Text, textOpacity * 0.9);
            DrawText(target, place.Count.ToString(), _mutedRightFormat, left, line, contentWidth - 4, 18, state.Palette.Text, textOpacity);
            line += 18;
        }
        return line;
    }
}
