namespace StarBridge.HostRuntime.HealthReading;

// 按"蓝白色"找血量图标中间的加号（11-11 实测：亮地面、低血量时圆环几乎是空的，边缘法会被地面纹理淹没）。
// 颜色图：B-R（HUD 是蓝白色，地面、墙多是灰或黄）乘亮度。模板是程序画的十字（不用游戏画面）。
// 候选还要过"四角是空的"检查：真加号四个角是背景，药丸、带箭头的十字会把角填上。
internal sealed class HudColourPlus
{
    public static readonly double[] Scales = { 0.84, 0.92, 1.0, 1.08 };   // 1.0 = 实测 2560x1440 下臂长 23、臂宽 6
    readonly float[][] tpl = new float[Scales.Length][]; readonly int[] tw = new int[Scales.Length];
    readonly float[][] tplHalf = new float[Scales.Length][]; readonly int[] twHalf = new int[Scales.Length];
    public double MinScore = 0.45, MinCorner = 0.4, MinStd = 8;
    // 十字中心相对圆环中心的偏移（实测，按比例）
    const double OffX = 1.3, OffY = -2.3;

    public HudColourPlus()
    {
        for (int i = 0; i < Scales.Length; i++)
        {
            (tpl[i], tw[i]) = Cross(Scales[i]);
            (tplHalf[i], twHalf[i]) = Cross(Scales[i] / 2);
        }
    }

    static (float[] d, int n) Cross(double s)
    {
        int L = Math.Max(5, (int)Math.Round(23 * s)), W = Math.Max(2, (int)Math.Round(6 * s)), pad = Math.Max(2, (int)Math.Round(4 * s));
        int n = L + 2 * pad; var t = new float[n * n]; int c0 = pad + (L - W) / 2;
        for (int y = pad; y < pad + L; y++) for (int x = c0; x < c0 + W; x++) t[y * n + x] = 1;
        for (int y = c0; y < c0 + W; y++) for (int x = pad; x < pad + L; x++) t[y * n + x] = 1;
        return (Blur(t, n, n, Math.Max(0.5, s)), n);
    }

    static float[] Blur(float[] a, int w, int h, double sigma)
    {
        int r = (int)Math.Ceiling(sigma * 2.5); var k = new double[2 * r + 1]; double ks = 0;
        for (int i = -r; i <= r; i++) { k[i + r] = Math.Exp(-0.5 * i * i / (sigma * sigma)); ks += k[i + r]; }
        for (int i = 0; i < k.Length; i++) k[i] /= ks;
        var tmp = new float[a.Length]; var o = new float[a.Length];
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) { double s = 0; for (int i = -r; i <= r; i++) { int xx = Math.Clamp(x + i, 0, w - 1); s += k[i + r] * a[y * w + xx]; } tmp[y * w + x] = (float)s; }
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) { double s = 0; for (int i = -r; i <= r; i++) { int yy = Math.Clamp(y + i, 0, h - 1); s += k[i + r] * tmp[yy * w + x]; } o[y * w + x] = (float)s; }
        return o;
    }

    // Both return a reused buffer (11-13 performance check, see HudScratch): valid until the next call of the same kind.
    public static float[] Map(HudPanelFrame f) => Map(f, 0, 0, HudPanelFrame.W, HudPanelFrame.H, HudScratch.ColourFull);

    // 只算 (x0..x1, y0..y1) 这一块（跟踪时用，省时），其余为 0
    public static float[] Map(HudPanelFrame f, int x0, int y0, int x1, int y1) => Map(f, x0, y0, x1, y1, HudScratch.ColourLocal);

    static float[] Map(HudPanelFrame f, int x0, int y0, int x1, int y1, int slot)
    {
        var m = HudScratch.Get<float>(slot, HudPanelFrame.W * HudPanelFrame.H, clear: true);
        x0 = Math.Max(0, x0); y0 = Math.Max(0, y0); x1 = Math.Min(HudPanelFrame.W, x1); y1 = Math.Min(HudPanelFrame.H, y1);
        for (int y = y0; y < y1; y++)
            for (int x = x0; x < x1; x++)
            {
                int i = y * HudPanelFrame.W + x, j = i * 3;
                int b = f.Bgr[j], g = f.Bgr[j + 1], r = f.Bgr[j + 2];
                m[i] = Math.Max(0, b - r) * (Math.Max(b, g) / 255f);
            }
        return m;
    }

    static float[] Half(float[] m, int w, int h, out int hw, out int hh)
    {
        hw = w / 2; hh = h / 2; var o = HudScratch.Get<float>(HudScratch.ColourHalf, hw * hh, clear: false);
        for (int y = 0; y < hh; y++) for (int x = 0; x < hw; x++)
                o[y * hw + x] = (m[2 * y * w + 2 * x] + m[2 * y * w + 2 * x + 1] + m[(2 * y + 1) * w + 2 * x] + m[(2 * y + 1) * w + 2 * x + 1]) / 4;
        return o;
    }

    // 归一化相关；窗口内颜色几乎没有起伏（平地）的位置跳过
    static double Ncc(float[] img, int iw, float[] t, int n, int x, int y, double minVar)
    {
        double si = 0, si2 = 0, st = 0, st2 = 0, sti = 0; int N = n * n;
        for (int yy = 0; yy < n; yy++)
        {
            int row = (y + yy) * iw + x, trow = yy * n;
            for (int xx = 0; xx < n; xx++) { double v = img[row + xx], q = t[trow + xx]; si += v; si2 += v * v; st += q; st2 += q * q; sti += v * q; }
        }
        double iVar = si2 - si * si / N, tVar = st2 - st * st / N;
        if (iVar / N < minVar || tVar <= 1e-9) return -2;
        return (sti - st * si / N) / Math.Sqrt(iVar * tVar);
    }

    // 四角检查：四条臂的最小亮度要明显高于四个角的最大亮度
    static double Corner(float[] m, double cx, double cy, double s)
    {
        float Mean(double px, double py, int r)
        {
            int x0 = (int)px, y0 = (int)py; double sum = 0; int c = 0;
            for (int y = y0 - r; y <= y0 + r; y++) for (int x = x0 - r; x <= x0 + r; x++)
                    if (x >= 0 && y >= 0 && x < HudPanelFrame.W && y < HudPanelFrame.H) { sum += m[y * HudPanelFrame.W + x]; c++; }
            return c == 0 ? 0 : (float)(sum / c);
        }
        double arm = double.MaxValue, q = 0;
        foreach (var (dx, dy) in new[] { (0, -7), (0, 7), (-7, 0), (7, 0) }) arm = Math.Min(arm, Mean(cx + dx * s, cy + dy * s, 1));
        foreach (var (dx, dy) in new[] { (-7, -7), (7, -7), (-7, 7), (7, 7) }) q = Math.Max(q, Mean(cx + dx * s, cy + dy * s, 2));
        return (arm - q) / Math.Max(arm, 1);
    }

    public record struct Hit(double Score, double Cx, double Cy, double Scale, double Corner);

    // 在 (x0..x1, y0..y1) 范围内找（十字中心坐标）；返回通过四角检查的最好一个（圆环中心坐标）
    public Hit? Find(float[] m, int x0, int y0, int x1, int y1, bool coarse)
    {
        var cands = new List<(double s, double cx, double cy, int si)>();
        if (coarse)
        {
            var h = Half(m, HudPanelFrame.W, HudPanelFrame.H, out int hw, out int hh);
            for (int si = 0; si < Scales.Length; si++)
            {
                int n = twHalf[si]; var top = new List<(double s, int x, int y)>();
                for (int y = Math.Max(0, y0 / 2 - n / 2); y + n <= Math.Min(hh, y1 / 2 + n / 2 + 1); y += 2)
                    for (int x = Math.Max(0, x0 / 2 - n / 2); x + n <= Math.Min(hw, x1 / 2 + n / 2 + 1); x += 2)
                    {
                        double sc = Ncc(h, hw, tplHalf[si], n, x, y, MinStd * MinStd);
                        if (sc < MinScore - 0.1) continue;
                        top.Add((sc, x, y));
                    }
                top.Sort((a, b) => b.s.CompareTo(a.s));
                var kept = new List<(double s, int x, int y)>();
                foreach (var c in top) { if (kept.All(k => Math.Abs(k.x - c.x) > 6 || Math.Abs(k.y - c.y) > 6)) kept.Add(c); if (kept.Count >= 6) break; }
                foreach (var c in kept) cands.Add((c.s, (c.x + n / 2.0) * 2, (c.y + n / 2.0) * 2, si));
            }
        }
        else
        {
            for (int si = 0; si < Scales.Length; si++) cands.Add((0, (x0 + x1) / 2.0, (y0 + y1) / 2.0, si));
        }
        Hit? best = null;
        int R = coarse ? 5 : Math.Max(3, (x1 - x0) / 2);
        foreach (var (_, ccx, ccy, si) in cands)
        {
            int n = tw[si]; double bs = -2; int bx = 0, by = 0;
            int cx0 = (int)Math.Round(ccx - n / 2.0), cy0 = (int)Math.Round(ccy - n / 2.0);
            for (int y = cy0 - R; y <= cy0 + R; y++)
                for (int x = cx0 - R; x <= cx0 + R; x++)
                {
                    if (x < 0 || y < 0 || x + n > HudPanelFrame.W || y + n > HudPanelFrame.H) continue;
                    double sc = Ncc(m, HudPanelFrame.W, tpl[si], n, x, y, MinStd * MinStd);
                    if (sc > bs) { bs = sc; bx = x; by = y; }
                }
            if (bs < MinScore) continue;
            double pcx = bx + n / 2.0, pcy = by + n / 2.0, s = Scales[si];
            double corner = Corner(m, pcx, pcy, s);
            if (corner < MinCorner) continue;
            if (best == null || bs > best.Value.Score) best = new Hit(bs, pcx + OffX * s, pcy + OffY * s, s, corner);
        }
        return best;
    }
}
