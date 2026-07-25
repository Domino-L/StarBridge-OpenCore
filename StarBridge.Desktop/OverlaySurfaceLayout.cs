using System;
using System.Windows;

namespace StarBridge.Desktop;

internal static class OverlaySurfaceLayout
{
    public const double EventNotificationEdgeInset = 0;
    public const double EventNotificationVerticalInset = 0;

    public static Rect ResolveItemRect(OverlayLayoutItem item, double surfaceWidth, double surfaceHeight)
    {
        var surface = NormalizeSurface(surfaceWidth, surfaceHeight);
        var constraints = GetModuleConstraints(item.Key, surface.Width, surface.Height);
        var rawWidth = Math.Clamp(item.Width, 0.01, 1) * surface.Width;
        var rawHeight = Math.Clamp(item.Height, 0.01, 1) * surface.Height;
        var width = ClampDimension(rawWidth, constraints.MinWidth, constraints.MaxWidth, surface.Width);
        var height = ClampDimension(rawHeight, constraints.MinHeight, constraints.MaxHeight, surface.Height);
        var left = ResolveLeft(item, width, surface.Width);
        var top = ResolveTop(item, height, surface.Height);

        return new Rect(
            Math.Clamp(left, 0, Math.Max(0, surface.Width - width)),
            Math.Clamp(top, 0, Math.Max(0, surface.Height - height)),
            width,
            height);
    }

    /// <summary>
    /// Resolves a complete layout and removes only collisions introduced by
    /// per-module minimum sizes. Deliberate overlap in the saved normalized
    /// layout remains untouched, and the saved items are never mutated.
    /// </summary>
    public static IReadOnlyDictionary<string, Rect> ResolveItems(
        IEnumerable<OverlayLayoutItem> items,
        double surfaceWidth,
        double surfaceHeight)
    {
        var surface = NormalizeSurface(surfaceWidth, surfaceHeight);
        var materialized = items
            .Where(item => item is not null)
            .GroupBy(item => item.Key, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .ToArray();
        var intended = materialized.ToDictionary(
            item => item.Key,
            item => ResolveIntendedRect(item, surface.Width, surface.Height),
            StringComparer.OrdinalIgnoreCase);
        var effective = materialized.ToDictionary(
            item => item.Key,
            item => ResolveItemRect(item, surface.Width, surface.Height),
            StringComparer.OrdinalIgnoreCase);
        var verticalOrder = materialized
            .OrderBy(item => intended[item.Key].Top)
            .ThenBy(item => intended[item.Key].Left)
            .ToArray();

        for (var lowerIndex = 1; lowerIndex < verticalOrder.Length; lowerIndex++)
        {
            var lower = verticalOrder[lowerIndex];
            var lowerIntended = intended[lower.Key];
            var lowerEffective = effective[lower.Key];
            var requiredTop = lowerEffective.Top;

            for (var upperIndex = 0; upperIndex < lowerIndex; upperIndex++)
            {
                var upper = verticalOrder[upperIndex];
                var upperIntended = intended[upper.Key];
                if (upperIntended.Bottom > lowerIntended.Top + 0.01 ||
                    HorizontalOverlapRatio(upperIntended, lowerIntended) < 0.50)
                {
                    continue;
                }

                var upperEffective = effective[upper.Key];
                if (upperEffective.Bottom <= requiredTop + 0.01)
                {
                    continue;
                }

                var intendedGap = Math.Max(
                    0,
                    lowerIntended.Top - upperIntended.Bottom);
                requiredTop = Math.Max(
                    requiredTop,
                    upperEffective.Bottom + intendedGap);
            }

            if (requiredTop > lowerEffective.Top + 0.01)
            {
                effective[lower.Key] = new Rect(
                    lowerEffective.Left,
                    requiredTop,
                    lowerEffective.Width,
                    lowerEffective.Height);
            }
        }

        return effective;
    }

    public static void ApplyRectToItem(OverlayLayoutItem item, Rect rect, double surfaceWidth, double surfaceHeight)
    {
        var surface = NormalizeSurface(surfaceWidth, surfaceHeight);
        var constraints = GetModuleConstraints(item.Key, surface.Width, surface.Height);
        var width = ClampDimension(rect.Width, constraints.MinWidth, constraints.MaxWidth, surface.Width);
        var height = ClampDimension(rect.Height, constraints.MinHeight, constraints.MaxHeight, surface.Height);
        var left = Math.Clamp(rect.Left, 0, Math.Max(0, surface.Width - width));
        var top = Math.Clamp(rect.Top, 0, Math.Max(0, surface.Height - height));

        item.Width = Math.Clamp(width / surface.Width, 0.01, 1);
        item.Height = Math.Clamp(height / surface.Height, 0.01, 1);
        item.X = Math.Clamp(left / surface.Width, 0, Math.Max(0, 1 - item.Width));
        item.Y = Math.Clamp(top / surface.Height, 0, Math.Max(0, 1 - item.Height));
    }

    public static Rect ResolveEventNotificationRect(
        double surfaceWidth,
        double surfaceHeight,
        OverlayEventNotificationSide side,
        double normalizedY,
        double preferredHeight,
        double snapSize = 0)
    {
        var surface = NormalizeSurface(surfaceWidth, surfaceHeight);
        var width = ResolveEventNotificationWidth(surface.Width);
        var height = Math.Clamp(preferredHeight, 72, Math.Max(72, surface.Height));
        var minTop = EventNotificationVerticalInset;
        var maxTop = Math.Max(minTop, surface.Height - height - EventNotificationVerticalInset);
        var available = Math.Max(1, maxTop - minTop);
        var top = minTop + available * Math.Clamp(normalizedY, 0, 1);
        if (snapSize > 0)
        {
            top = Math.Round(top / snapSize, MidpointRounding.AwayFromZero) * snapSize;
        }

        top = Math.Clamp(top, minTop, maxTop);
        var left = side == OverlayEventNotificationSide.Left
            ? EventNotificationEdgeInset
            : Math.Max(EventNotificationEdgeInset, surface.Width - width - EventNotificationEdgeInset);
        return new Rect(left, top, width, height);
    }

    public static double ResolveEventNotificationWidth(double surfaceWidth)
    {
        return Math.Clamp(Math.Max(1, surfaceWidth) * 0.22, 320, 380);
    }

    public static OverlayHorizontalAnchor ResolveHorizontalAnchor(OverlayLayoutItem item)
    {
        return item.HorizontalAnchor;
    }

    public static OverlayVerticalAnchor ResolveVerticalAnchor(OverlayLayoutItem item)
    {
        return item.VerticalAnchor;
    }

    private static double ResolveLeft(OverlayLayoutItem item, double resolvedWidth, double surfaceWidth)
    {
        return ResolveHorizontalAnchor(item) switch
        {
            OverlayHorizontalAnchor.Left => item.X * surfaceWidth,
            OverlayHorizontalAnchor.Right => surfaceWidth - ((1 - item.X - item.Width) * surfaceWidth) - resolvedWidth,
            _ => ((item.X + item.Width / 2) * surfaceWidth) - resolvedWidth / 2
        };
    }

    private static double ResolveTop(OverlayLayoutItem item, double resolvedHeight, double surfaceHeight)
    {
        return ResolveVerticalAnchor(item) switch
        {
            OverlayVerticalAnchor.Top => item.Y * surfaceHeight,
            OverlayVerticalAnchor.Bottom => surfaceHeight - ((1 - item.Y - item.Height) * surfaceHeight) - resolvedHeight,
            _ => ((item.Y + item.Height / 2) * surfaceHeight) - resolvedHeight / 2
        };
    }

    private static OverlayModuleConstraints GetModuleConstraints(string key, double surfaceWidth, double surfaceHeight)
    {
        var aspect = surfaceWidth / Math.Max(1, surfaceHeight);
        var isWide = aspect >= 2.1;
        return key switch
        {
            "Notice" => new OverlayModuleConstraints(420, isWide ? 1040 : 1120, 52, 118),
            "Squads" => new OverlayModuleConstraints(240, isWide ? 460 : 540, 150, isWide ? 620 : 620),
            "Members" => new OverlayModuleConstraints(240, isWide ? 480 : 520, 140, 440),
            "Chat" => new OverlayModuleConstraints(240, isWide ? 760 : 680, 104, 440),
            _ => new OverlayModuleConstraints(80, surfaceWidth, 50, surfaceHeight)
        };
    }

    private static (double Width, double Height) NormalizeSurface(double width, double height)
    {
        return (Math.Max(1, width), Math.Max(1, height));
    }

    private static double ClampDimension(double value, double min, double max, double surfaceExtent)
    {
        var upper = Math.Clamp(max, 1, Math.Max(1, surfaceExtent));
        var lower = Math.Clamp(min, 1, upper);
        return Math.Clamp(value, lower, upper);
    }

    private static Rect ResolveIntendedRect(
        OverlayLayoutItem item,
        double surfaceWidth,
        double surfaceHeight)
    {
        var width = Math.Clamp(item.Width, 0.01, 1) * surfaceWidth;
        var height = Math.Clamp(item.Height, 0.01, 1) * surfaceHeight;
        return new Rect(
            ResolveLeft(item, width, surfaceWidth),
            ResolveTop(item, height, surfaceHeight),
            width,
            height);
    }

    private static double HorizontalOverlapRatio(Rect first, Rect second)
    {
        var overlap = Math.Max(
            0,
            Math.Min(first.Right, second.Right) -
            Math.Max(first.Left, second.Left));
        return overlap / Math.Max(1, Math.Min(first.Width, second.Width));
    }

    private readonly record struct OverlayModuleConstraints(
        double MinWidth,
        double MaxWidth,
        double MinHeight,
        double MaxHeight);
}
