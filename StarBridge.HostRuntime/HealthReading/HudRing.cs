namespace StarBridge.HostRuntime.HealthReading;

// 量圆环亮弧（移植自 scripts/hud_health_v5.py）
internal static class HudRing
{
    static readonly double[] Sin = Enumerable.Range(0, 360).Select(a => Math.Sin(a * Math.PI / 180)).ToArray();
    static readonly double[] Cos = Enumerable.Range(0, 360).Select(a => Math.Cos(a * Math.PI / 180)).ToArray();

    static float VAt(HudPanelFrame f, int x, int y)
    {
        if (x < 0 || y < 0 || x >= HudPanelFrame.W || y >= HudPanelFrame.H) return 0;
        int i = (y * HudPanelFrame.W + x) * 3;
        return HudImageOps.V(f.Bgr[i], f.Bgr[i + 1], f.Bgr[i + 2]);
    }

    static float VBilinear(HudPanelFrame f, double x, double y)
    {
        int x0 = (int)Math.Floor(x), y0 = (int)Math.Floor(y);
        double ax = x - x0, ay = y - y0;
        return (float)((1 - ay) * ((1 - ax) * VAt(f, x0, y0) + ax * VAt(f, x0 + 1, y0)) + ay * ((1 - ax) * VAt(f, x0, y0 + 1) + ax * VAt(f, x0 + 1, y0 + 1)));
    }

    static (int h, int s) HSNearest(HudPanelFrame f, double x, double y)
    {
        int xi = (int)Math.Round(x), yi = (int)Math.Round(y);
        if (xi < 0 || yi < 0 || xi >= HudPanelFrame.W || yi >= HudPanelFrame.H) return (0, 0);
        int i = (yi * HudPanelFrame.W + xi) * 3;
        return HudImageOps.HS(f.Bgr[i], f.Bgr[i + 1], f.Bgr[i + 2]);
    }

    // 返回亮弧角度（0..360），或 -1 表示"看不到环的起点"（被挡或误匹配）
    public static int ArcDegrees(HudPanelFrame f, double cx, double cy, double r)
    {
        var prof = new float[360]; var hue = new int[360]; var sat = new int[360];
        var bgmax = new float[360];
        for (double dr = -3; dr <= 3; dr += 1)
        {
            double rr = r + dr;
            for (int a = 0; a < 360; a++)
            {
                double x = cx - rr * Sin[a], y = cy - rr * Cos[a];
                float v = VBilinear(f, x, y);
                if (v > prof[a]) { prof[a] = v; var hs = HSNearest(f, x, y); hue[a] = hs.h; sat[a] = hs.s; }
            }
        }
        foreach (double rr in new[] { r + 8, r - 9 })
            for (int a = 0; a < 360; a++)
                bgmax[a] = Math.Max(bgmax[a], VBilinear(f, cx - rr * Sin[a], cy - rr * Cos[a]));
        var lit = new bool[360];
        for (int a = 0; a < 360; a++) lit[a] = prof[a] > 120 && prof[a] > bgmax[a] + 35;
        // 末端橙色短刻度不算血条
        int i0 = 0;
        while (i0 < 360)
        {
            bool Orange(int k) => lit[k] && sat[k] > 30 && (hue[k] < 36 || hue[k] > 160);
            if (Orange(i0))
            {
                int b = i0; while (b < 360 && Orange(b)) b++;
                if (b - i0 <= 20) for (int k = i0; k < b; k++) lit[k] = false;
                i0 = b;
            }
            else i0++;
        }
        int head = 0, tail = 0;
        for (int a = 0; a < 30; a++) if (lit[a]) head++;
        for (int a = 330; a < 360; a++) if (lit[a]) tail++;
        if (head < 8 && tail < 8) return -1;
        // 最长暗弧（首尾相接）的起点 = 血量弧终点
        int bestLen = 0, bestStart = 0, run = 0, start = 0;
        for (int i = 0; i < 720; i++)
        {
            if (!lit[i % 360])
            {
                if (run == 0) start = i;
                run++;
                if (run > bestLen && run <= 360) { bestLen = run; bestStart = start; }
            }
            else run = 0;
        }
        if (bestLen < 8) return 360;
        return bestStart % 360;
    }
}
