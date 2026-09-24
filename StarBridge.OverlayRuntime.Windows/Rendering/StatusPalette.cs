using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Windows;
using StarBridge.Core.Presence;
using MediaBrush = System.Windows.Media.Brush;
using MediaColor = System.Windows.Media.Color;
using MediaSolidBrush = System.Windows.Media.SolidColorBrush;

namespace StarBridge.Desktop;


internal static class StatusPalette
{
    public static MediaBrush InfoBrush { get; } = Brush(0x52, 0xB7, 0xF5);
    public static MediaBrush SuccessBrush { get; } = Brush(0x43, 0xD8, 0x7A);
    public static MediaBrush WarningBrush { get; } = Brush(0xD9, 0xA4, 0x41);
    public static MediaBrush DangerBrush { get; } = Brush(0xD2, 0x68, 0x5E);
    public static MediaBrush DisabledBrush { get; } = Brush(0x46, 0x54, 0x5D);

    public static MediaBrush ForOnlineState(string? status)
    {
        return PlayerPresencePresentation.Brush(PlayerPresencePresentation.ResolveShared(status, status));
    }

    public static MediaBrush ForTaskStatus(string? status)
    {
        var value = status ?? "";
        if (value.Contains("删除", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("取消", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("失败", StringComparison.OrdinalIgnoreCase))
        {
            return DangerBrush;
        }

        if (value.Contains("完成", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("成功", StringComparison.OrdinalIgnoreCase))
        {
            return SuccessBrush;
        }

        if (value.Contains("进行", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("待", StringComparison.OrdinalIgnoreCase))
        {
            return WarningBrush;
        }

        return InfoBrush;
    }

    public static MediaBrush ForEvent(string? type, string? title)
    {
        var text = $"{type} {title}";
        if (text.Contains("删除", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("取消", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("关闭", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("移除", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("解散", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("失败", StringComparison.OrdinalIgnoreCase))
        {
            return DangerBrush;
        }

        if (text.Contains("完成", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("加入", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("创建", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("启用", StringComparison.OrdinalIgnoreCase))
        {
            return SuccessBrush;
        }

        if (text.Contains("任务", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("计划", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("待", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("再次通知", StringComparison.OrdinalIgnoreCase))
        {
            return WarningBrush;
        }

        return InfoBrush;
    }

    public static MediaBrush? TryBrushFromHex(string? hex)
    {
        if (string.IsNullOrWhiteSpace(hex))
        {
            return null;
        }

        try
        {
            var color = (MediaColor)System.Windows.Media.ColorConverter.ConvertFromString(hex.Trim());
            var brush = new MediaSolidBrush(color);
            brush.Freeze();
            return brush;
        }
        catch
        {
            return null;
        }
    }

    public static MediaBrush BrushFromHex(string? hex, MediaBrush fallback) =>
        TryBrushFromHex(hex) ?? fallback;

    private static MediaBrush Brush(byte red, byte green, byte blue)
    {
        var brush = new MediaSolidBrush(MediaColor.FromRgb(red, green, blue));
        brush.Freeze();
        return brush;
    }

}

