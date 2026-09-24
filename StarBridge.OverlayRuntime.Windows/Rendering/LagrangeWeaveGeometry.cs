using System.Numerics;

namespace StarBridge.Desktop;

[Flags]
internal enum LagrangePanelJoin
{
    None = 0,
    Top = 1,
    Bottom = 2
}

internal readonly record struct LagrangeCubicCurve(
    Vector2 Start,
    Vector2 Control1,
    Vector2 Control2,
    Vector2 End);

internal sealed record LagrangePanelChromePlan(
    IReadOnlyList<Vector2> FillOutline,
    IReadOnlyList<LagrangeCubicCurve> ShellCurves,
    IReadOnlyList<LagrangeCubicCurve> FieldCurves,
    Vector2 Anchor,
    Vector2 TitleTickStart,
    Vector2 TitleTickEnd,
    LagrangePanelJoin Join);

internal static class LagrangeWeaveGeometry
{
    public const float ChromeBand = 16;

    public static LagrangePanelChromePlan BuildPanel(
        string moduleKey,
        float width,
        float height,
        LagrangePanelJoin join)
    {
        width = Math.Max(4, width);
        height = Math.Max(4, height);
        var left = 1.5f;
        var top = 1.5f;
        var right = width - 1.5f;
        var bottom = height - 1.5f;
        var corner = Math.Clamp(Math.Min(width, height) * 0.18f, 16, 34);
        var anchorY = ResolveAnchorY(moduleKey, height);
        var anchor = new Vector2(right - 8, anchorY);
        var shell = new List<LagrangeCubicCurve>(6);

        if (!join.HasFlag(LagrangePanelJoin.Top))
        {
            shell.Add(new LagrangeCubicCurve(
                new Vector2(left + corner, top),
                new Vector2(left + width * 0.24f, top - 0.4f),
                new Vector2(right - corner * 1.8f, top + 0.4f),
                new Vector2(right - corner, top + 2)));
            shell.Add(new LagrangeCubicCurve(
                new Vector2(right - corner, top + 2),
                new Vector2(right - 8, top + 5),
                new Vector2(right - 2, top + corner * 0.55f),
                new Vector2(right - 2, top + corner)));
        }

        shell.Add(new LagrangeCubicCurve(
            new Vector2(right - 2, top + corner),
            new Vector2(right - 1, anchorY - corner * 0.65f),
            new Vector2(anchor.X + 2, anchorY - 7),
            anchor));
        shell.Add(new LagrangeCubicCurve(
            anchor,
            new Vector2(anchor.X + 1, anchorY + 8),
            new Vector2(right - 3, bottom - corner * 0.85f),
            new Vector2(right - corner * 0.72f, bottom - 2)));

        if (!join.HasFlag(LagrangePanelJoin.Bottom))
        {
            shell.Add(new LagrangeCubicCurve(
                new Vector2(right - corner * 0.72f, bottom - 2),
                new Vector2(right - width * 0.25f, bottom + 0.2f),
                new Vector2(left + corner * 1.55f, bottom - 0.2f),
                new Vector2(left + corner, bottom - 1)));
            shell.Add(new LagrangeCubicCurve(
                new Vector2(left + corner, bottom - 1),
                new Vector2(left + 5, bottom - 3),
                new Vector2(left + 1, bottom - corner * 0.55f),
                new Vector2(left + 1, bottom - corner)));
        }

        shell.Add(new LagrangeCubicCurve(
            new Vector2(left + 1, bottom - corner),
            new Vector2(left, height * 0.72f),
            new Vector2(left, height * 0.30f),
            new Vector2(left + 2, top + corner)));
        shell.Add(new LagrangeCubicCurve(
            new Vector2(left + 2, top + corner),
            new Vector2(left + 3, top + 8),
            new Vector2(left + 10, top + 3),
            new Vector2(left + corner, top)));

        var fieldStartX = Math.Max(left + width * 0.53f, right - Math.Clamp(width * 0.34f, 62, 148));
        var field = new List<LagrangeCubicCurve>(7);
        for (var index = -3; index <= 3; index++)
        {
            var spread = index * Math.Clamp(height * 0.048f, 4.5f, 10);
            var startY = Math.Clamp(anchorY + spread * 1.35f, top + 10, bottom - 10);
            field.Add(new LagrangeCubicCurve(
                new Vector2(fieldStartX + Math.Abs(index) * 3, startY),
                new Vector2(right - 42, startY + spread * 0.16f),
                new Vector2(anchor.X - 19, anchorY + spread * 0.28f),
                anchor));
        }

        var titleTickY = top + 10;
        return new LagrangePanelChromePlan(
            BuildFillOutline(width, height, corner, anchor, join),
            shell,
            field,
            anchor,
            new Vector2(left + corner + 8, titleTickY),
            new Vector2(Math.Min(right - 78, left + corner + 54), titleTickY),
            join);
    }

    public static Vector2 Evaluate(LagrangeCubicCurve curve, float progress)
    {
        var t = Math.Clamp(progress, 0, 1);
        var inverse = 1 - t;
        return inverse * inverse * inverse * curve.Start +
               3 * inverse * inverse * t * curve.Control1 +
               3 * inverse * t * t * curve.Control2 +
               t * t * t * curve.End;
    }

    private static IReadOnlyList<Vector2> BuildFillOutline(
        float width,
        float height,
        float corner,
        Vector2 anchor,
        LagrangePanelJoin join)
    {
        var left = 1.5f;
        var top = 1.5f;
        var right = width - 1.5f;
        var bottom = height - 1.5f;
        var points = new List<Vector2>(72);

        if (join.HasFlag(LagrangePanelJoin.Top))
        {
            points.Add(new Vector2(left + 1, top));
            points.Add(new Vector2(right - 2, top));
            points.Add(new Vector2(right - 2, top + corner));
        }
        else
        {
            AppendCurve(
                points,
                new LagrangeCubicCurve(
                    new Vector2(left + corner, top),
                    new Vector2(left + width * 0.24f, top - 0.4f),
                    new Vector2(right - corner * 1.8f, top + 0.4f),
                    new Vector2(right - corner, top + 2)));
            AppendCurve(
                points,
                new LagrangeCubicCurve(
                    new Vector2(right - corner, top + 2),
                    new Vector2(right - 8, top + 5),
                    new Vector2(right - 2, top + corner * 0.55f),
                    new Vector2(right - 2, top + corner)),
                includeStart: false);
        }

        AppendCurve(
            points,
            new LagrangeCubicCurve(
                new Vector2(right - 2, top + corner),
                new Vector2(right - 1, anchor.Y - corner * 0.65f),
                new Vector2(anchor.X + 2, anchor.Y - 7),
                anchor),
            includeStart: false);
        AppendCurve(
            points,
            new LagrangeCubicCurve(
                anchor,
                new Vector2(anchor.X + 1, anchor.Y + 8),
                new Vector2(right - 3, bottom - corner * 0.85f),
                new Vector2(right - corner * 0.72f, bottom - 2)),
            includeStart: false);

        if (join.HasFlag(LagrangePanelJoin.Bottom))
        {
            points.Add(new Vector2(right - 2, bottom));
            points.Add(new Vector2(left + 1, bottom));
            points.Add(new Vector2(left + 1, bottom - corner));
        }
        else
        {
            AppendCurve(
                points,
                new LagrangeCubicCurve(
                    new Vector2(right - corner * 0.72f, bottom - 2),
                    new Vector2(right - width * 0.25f, bottom + 0.2f),
                    new Vector2(left + corner * 1.55f, bottom - 0.2f),
                    new Vector2(left + corner, bottom - 1)),
                includeStart: false);
            AppendCurve(
                points,
                new LagrangeCubicCurve(
                    new Vector2(left + corner, bottom - 1),
                    new Vector2(left + 5, bottom - 3),
                    new Vector2(left + 1, bottom - corner * 0.55f),
                    new Vector2(left + 1, bottom - corner)),
                includeStart: false);
        }

        AppendCurve(
            points,
            new LagrangeCubicCurve(
                new Vector2(left + 1, bottom - corner),
                new Vector2(left, height * 0.72f),
                new Vector2(left, height * 0.30f),
                new Vector2(left + 2, top + corner)),
            includeStart: false);

        if (join.HasFlag(LagrangePanelJoin.Top))
        {
            points.Add(new Vector2(left + 1, top));
        }
        else
        {
            AppendCurve(
                points,
                new LagrangeCubicCurve(
                    new Vector2(left + 2, top + corner),
                    new Vector2(left + 3, top + 8),
                    new Vector2(left + 10, top + 3),
                    new Vector2(left + corner, top)),
                includeStart: false);
        }

        return points;
    }

    private static void AppendCurve(
        List<Vector2> points,
        LagrangeCubicCurve curve,
        bool includeStart = true)
    {
        const int segments = 7;
        if (includeStart)
        {
            points.Add(curve.Start);
        }

        for (var index = 1; index <= segments; index++)
        {
            points.Add(Evaluate(curve, index / (float)segments));
        }
    }

    private static float ResolveAnchorY(string moduleKey, float height)
    {
        if (moduleKey.Equals("Notice", StringComparison.OrdinalIgnoreCase))
        {
            return height * 0.50f;
        }

        if (moduleKey.Equals("Squads", StringComparison.OrdinalIgnoreCase))
        {
            return Math.Clamp(height * 0.32f, 24, height - 18);
        }

        if (moduleKey.Equals("Chat", StringComparison.OrdinalIgnoreCase))
        {
            return Math.Clamp(height * 0.70f, 20, height - 18);
        }

        return height * 0.52f;
    }
}
