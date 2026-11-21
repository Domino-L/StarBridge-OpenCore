using System.Numerics;

namespace StarBridge.HostRuntime.HealthReading;

// 左下角面板画面：900x490，BGR，每像素 3 字节（相当于 2560x1440 画面里 x0..900, y950..1440）。
internal sealed class HudPanelFrame
{
    public const int W = 900, H = 490;
    public readonly byte[] Bgr = new byte[W * H * 3];
    public double TimeSec;
}

// Reused work buffers (11-13 performance check, user: "开着读屏，鼠标和画面都明显卡顿"): allocating them for every read
// made about 50 MB of garbage a second while the health tile was not on screen (at full health, most of the time), and
// the Host ran about four full garbage collections a second, which also pause the visor drawn by the same process.
// One set per thread (only the reader thread reads). A buffer can be longer than asked for; callers index by width.
internal static class HudScratch
{
    internal const int EdgeGray = 1, BlurSum = 2, BlurOut = 3, CannyDx = 4, CannyDy = 5, CannyMag = 6, CannyClass = 7,
        CannyOut = 8, EdgeFull = 9, EdgePart = 10, IntegralA = 11, IntegralB = 12, ColourLocal = 13, ColourFull = 14, ColourHalf = 15;

    [ThreadStatic] static Dictionary<int, Array>? t_slots;
    [ThreadStatic] static Stack<int>? t_stack;

    // clear: the first `length` items are zero on return (a new array always is).
    public static T[] Get<T>(int slot, int length, bool clear)
    {
        var slots = t_slots ??= new Dictionary<int, Array>();
        if (slots.TryGetValue(slot, out var existing) && existing is T[] array && array.Length >= length)
        {
            if (clear) Array.Clear(array, 0, length);
            return array;
        }
        var fresh = new T[length];
        slots[slot] = fresh;
        return fresh;
    }

    public static Stack<int> Stack() { var s = t_stack ??= new Stack<int>(); s.Clear(); return s; }
}

internal static class HudImageOps
{
    // OpenCV 的 BGR→灰度（定点）
    public static byte Gray(byte b, byte g, byte r) => (byte)((b * 1868 + g * 9617 + r * 4899 + 8192) >> 14);

    public static byte V(byte b, byte g, byte r) => Math.Max(b, Math.Max(g, r));

    // OpenCV 8 位 HSV：H 0..180，S 0..255
    public static (int h, int s) HS(byte b, byte g, byte r)
    {
        int v = Math.Max(b, Math.Max(g, r)), mn = Math.Min(b, Math.Min(g, r));
        int diff = v - mn;
        int s = v == 0 ? 0 : (int)Math.Round(diff * 255.0 / v);
        double h;
        if (diff == 0) h = 0;
        else if (v == r) h = (g - b) * 60.0 / diff;
        else if (v == g) h = 120 + (b - r) * 60.0 / diff;
        else h = 240 + (r - g) * 60.0 / diff;
        if (h < 0) h += 360;
        return ((int)Math.Round(h / 2) % 180, s);
    }

    public static double MeanBgr(HudPanelFrame f)
    {
        long sum = 0; var a = f.Bgr;
        for (int i = 0; i < a.Length; i += 12) sum += a[i] + a[i + 1] + a[i + 2];
        return sum / (a.Length / 12 * 3.0);
    }

    // 子区域 → 灰度 → 3x3 高斯 → Canny(40,120) → 2x2 膨胀；返回 0/255 浮点图（和 Python 版 edge() 对齐）
    // The result is a reused buffer (one for the whole panel, one for smaller regions): valid until the next call of
    // the same kind on this thread.
    public static float[] EdgeRegion(HudPanelFrame f, int x0, int y0, int w, int h)
    {
        var g = HudScratch.Get<byte>(HudScratch.EdgeGray, w * h, clear: false);
        for (int y = 0; y < h; y++)
        {
            int sy = y0 + y, row = sy * HudPanelFrame.W * 3;
            for (int x = 0; x < w; x++)
            {
                int i = row + (x0 + x) * 3;
                g[y * w + x] = Gray(f.Bgr[i], f.Bgr[i + 1], f.Bgr[i + 2]);
            }
        }
        var bl = Blur3(g, w, h);
        var e = Canny(bl, w, h, 40, 120);
        var whole = w == HudPanelFrame.W && h == HudPanelFrame.H;
        var d = HudScratch.Get<float>(whole ? HudScratch.EdgeFull : HudScratch.EdgePart, w * h, clear: false);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                byte m = e[y * w + x];
                if (x > 0) m = Math.Max(m, e[y * w + x - 1]);
                if (y > 0) { m = Math.Max(m, e[(y - 1) * w + x]); if (x > 0) m = Math.Max(m, e[(y - 1) * w + x - 1]); }
                d[y * w + x] = m;
            }
        return d;
    }

    static int Reflect101(int i, int n) => i < 0 ? -i : (i >= n ? 2 * n - 2 - i : i);

    static byte[] Blur3(byte[] s, int w, int h)
    {
        var t = HudScratch.Get<int>(HudScratch.BlurSum, w * h, clear: false);
        var o = HudScratch.Get<byte>(HudScratch.BlurOut, w * h, clear: false);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                t[y * w + x] = s[y * w + Reflect101(x - 1, w)] + 2 * s[y * w + x] + s[y * w + Reflect101(x + 1, w)];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                o[y * w + x] = (byte)((t[Reflect101(y - 1, h) * w + x] + 2 * t[y * w + x] + t[Reflect101(y + 1, h) * w + x] + 8) >> 4);
        return o;
    }

    static byte[] Canny(byte[] s, int w, int h, int low, int high)
    {
        var dx = HudScratch.Get<int>(HudScratch.CannyDx, w * h, clear: false);
        var dy = HudScratch.Get<int>(HudScratch.CannyDy, w * h, clear: false);
        var mag = HudScratch.Get<int>(HudScratch.CannyMag, w * h, clear: false);
        int P(int x, int y) => s[Math.Clamp(y, 0, h - 1) * w + Math.Clamp(x, 0, w - 1)];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int gx = -P(x - 1, y - 1) - 2 * P(x - 1, y) - P(x - 1, y + 1) + P(x + 1, y - 1) + 2 * P(x + 1, y) + P(x + 1, y + 1);
                int gy = -P(x - 1, y - 1) - 2 * P(x, y - 1) - P(x + 1, y - 1) + P(x - 1, y + 1) + 2 * P(x, y + 1) + P(x + 1, y + 1);
                dx[y * w + x] = gx; dy[y * w + x] = gy; mag[y * w + x] = Math.Abs(gx) + Math.Abs(gy);
            }
        // 0 = 不是边，1 = 弱边，2 = 强边
        var cls = HudScratch.Get<byte>(HudScratch.CannyClass, w * h, clear: true);
        const int TG22 = (int)(0.4142135623730950488016887242097 * (1 << 15) + 0.5);
        for (int y = 1; y < h - 1; y++)
            for (int x = 1; x < w - 1; x++)
            {
                int i = y * w + x, m = mag[i];
                if (m <= low) continue;
                int xs = dx[i], ys = dy[i];
                int ax = Math.Abs(xs), ay = Math.Abs(ys) << 15;
                int tg22x = ax * TG22, tg67x = tg22x + (ax << 16);
                bool keep;
                if (ay < tg22x) keep = m > mag[i - 1] && m >= mag[i + 1];
                else if (ay > tg67x) keep = m > mag[i - w] && m >= mag[i + w];
                else
                {
                    int sgn = (xs ^ ys) < 0 ? -1 : 1;
                    keep = m > mag[i - w - sgn] && m > mag[i + w + sgn];
                }
                if (keep) cls[i] = (byte)(m > high ? 2 : 1);
            }
        var o = HudScratch.Get<byte>(HudScratch.CannyOut, w * h, clear: true);
        var stack = HudScratch.Stack();
        for (int i = 0; i < w * h; i++) if (cls[i] == 2) { o[i] = 255; stack.Push(i); }
        while (stack.Count > 0)
        {
            int i = stack.Pop(), x = i % w, y = i / w;
            for (int yy = -1; yy <= 1; yy++)
                for (int xx = -1; xx <= 1; xx++)
                {
                    int nx = x + xx, ny = y + yy;
                    if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                    int j = ny * w + nx;
                    if (cls[j] == 1 && o[j] == 0) { o[j] = 255; stack.Push(j); }
                }
        }
        return o;
    }

    // 归一化相关（等同 OpenCV TM_CCOEFF_NORMED），在 [xs0,xs1]×[ys0,ys1] 的左上角位置里找最大值
    public static (float score, int x, int y) MatchBest(float[] img, int iw, int ih, HudTemplate t,
        int xs0, int xs1, int ys0, int ys1, int step = 1)
    {
        xs0 = Math.Max(0, xs0); ys0 = Math.Max(0, ys0);
        xs1 = Math.Min(iw - t.W, xs1); ys1 = Math.Min(ih - t.H, ys1);
        if (xs1 < xs0 || ys1 < ys0) return (-1, 0, 0);
        int n = t.W * t.H;
        double st = 0, st2 = 0;
        foreach (var v in t.Data) { st += v; st2 += v * v; }
        double tVar = st2 - st * st / n;
        if (tVar <= 1e-9) return (-1, 0, 0);
        // 积分图（只算需要的范围）
        int rx0 = xs0, ry0 = ys0, rw = xs1 - xs0 + t.W, rh = ys1 - ys0 + t.H;
        // the first row and column must be zero
        var I1 = HudScratch.Get<double>(HudScratch.IntegralA, (rw + 1) * (rh + 1), clear: true);
        var I2 = HudScratch.Get<double>(HudScratch.IntegralB, (rw + 1) * (rh + 1), clear: true);
        for (int y = 0; y < rh; y++)
        {
            double r1 = 0, r2 = 0;
            for (int x = 0; x < rw; x++)
            {
                double v = img[(ry0 + y) * iw + rx0 + x]; r1 += v; r2 += v * v;
                I1[(y + 1) * (rw + 1) + x + 1] = I1[y * (rw + 1) + x + 1] + r1;
                I2[(y + 1) * (rw + 1) + x + 1] = I2[y * (rw + 1) + x + 1] + r2;
            }
        }
        // 模板里非零的位置（边缘模板很稀疏）
        var nzIdx = new List<int>(); var nzVal = new List<float>();
        for (int y = 0; y < t.H; y++)
            for (int x = 0; x < t.W; x++)
            {
                float v = t.Data[y * t.W + x];
                if (v != 0) { nzIdx.Add(y * iw + x); nzVal.Add(v); }
            }
        var idx = nzIdx.ToArray(); var val = nzVal.ToArray();
        float best = -2; int bx = 0, by = 0;
        for (int y = ys0; y <= ys1; y += step)
            for (int x = xs0; x <= xs1; x += step)
            {
                int lx = x - rx0, ly = y - ry0;
                int a = ly * (rw + 1) + lx, b = a + t.W, c = (ly + t.H) * (rw + 1) + lx, d = c + t.W;
                double si = I1[d] - I1[b] - I1[c] + I1[a];
                double si2 = I2[d] - I2[b] - I2[c] + I2[a];
                double iVar = si2 - si * si / n;
                if (iVar <= 1e-6) continue;
                int baseI = y * iw + x;
                double sti = 0;
                for (int k = 0; k < idx.Length; k++) sti += val[k] * img[baseI + idx[k]];
                double num = sti - st * si / n;
                float sc = (float)(num / Math.Sqrt(tVar * iVar));
                if (sc > best) { best = sc; bx = x; by = y; }
            }
        return (best, bx, by);
    }

    // 粗扫：每隔 step 像素算一次分数，返回分数最高、彼此相距 >= minDist 的 k 个候选的中心
    public static List<(double cx, double cy)> MatchTopK(float[] img, int iw, int ih, HudTemplate t, int step, int k, int minDist)
    {
        int n = t.W * t.H;
        double st = 0, st2 = 0;
        foreach (var v in t.Data) { st += v; st2 += v * v; }
        double tVar = st2 - st * st / n;
        // the first row and column must be zero
        var I1 = HudScratch.Get<double>(HudScratch.IntegralA, (iw + 1) * (ih + 1), clear: true);
        var I2 = HudScratch.Get<double>(HudScratch.IntegralB, (iw + 1) * (ih + 1), clear: true);
        for (int y = 0; y < ih; y++)
        {
            double r1 = 0, r2 = 0;
            for (int x = 0; x < iw; x++)
            {
                double v = img[y * iw + x]; r1 += v; r2 += v * v;
                I1[(y + 1) * (iw + 1) + x + 1] = I1[y * (iw + 1) + x + 1] + r1;
                I2[(y + 1) * (iw + 1) + x + 1] = I2[y * (iw + 1) + x + 1] + r2;
            }
        }
        var idxL = new List<int>(); var valL = new List<float>();
        for (int y = 0; y < t.H; y++) for (int x = 0; x < t.W; x++) { float v = t.Data[y * t.W + x]; if (v != 0) { idxL.Add(y * iw + x); valL.Add(v); } }
        var idx = idxL.ToArray(); var val = valL.ToArray();
        var top = new List<(float s, int x, int y)>();
        for (int y = 0; y + t.H <= ih; y += step)
            for (int x = 0; x + t.W <= iw; x += step)
            {
                int a = y * (iw + 1) + x, b = a + t.W, c = (y + t.H) * (iw + 1) + x, d = c + t.W;
                double si = I1[d] - I1[b] - I1[c] + I1[a];
                if (si <= 0) continue;
                double iVar = (I2[d] - I2[b] - I2[c] + I2[a]) - si * si / n;
                if (iVar <= 1e-6) continue;
                int baseI = y * iw + x; double sti = 0;
                for (int q = 0; q < idx.Length; q++) sti += val[q] * img[baseI + idx[q]];
                float sc = (float)((sti - st * si / n) / Math.Sqrt(tVar * iVar));
                if (top.Count < k * 8 || sc > top[^1].s)
                {
                    top.Add((sc, x, y)); top.Sort((p, q) => q.s.CompareTo(p.s));
                    if (top.Count > k * 8) top.RemoveAt(top.Count - 1);
                }
            }
        var res = new List<(double, double)>();
        foreach (var c in top)
        {
            double cx = c.x + t.W / 2.0, cy = c.y + t.H / 2.0;
            if (res.All(r => Math.Abs(r.Item1 - cx) >= minDist || Math.Abs(r.Item2 - cy) >= minDist)) res.Add((cx, cy));
            if (res.Count >= k) break;
        }
        return res;
    }

    // 稠密模板版（% 号模板不稀疏），行内用 SIMD 点积
    public static (float score, int x, int y) MatchBestDense(float[] img, int iw, int ih, HudTemplate t, int xs0 = 0, int xs1 = int.MaxValue, int ys0 = 0, int ys1 = int.MaxValue)
    {
        xs0 = Math.Max(0, xs0); ys0 = Math.Max(0, ys0); xs1 = Math.Min(iw - t.W, xs1); ys1 = Math.Min(ih - t.H, ys1);
        int n = t.W * t.H;
        double st = 0, st2 = 0;
        foreach (var v in t.Data) { st += v; st2 += v * v; }
        double tVar = st2 - st * st / n;
        float best = -2; int bx = 0, by = 0;
        for (int y = ys0; y <= ys1; y++)
            for (int x = xs0; x <= xs1; x++)
            {
                double si = 0, si2 = 0, sti = 0;
                for (int ty = 0; ty < t.H; ty++)
                {
                    var row = new ReadOnlySpan<float>(img, (y + ty) * iw + x, t.W);
                    var trow = new ReadOnlySpan<float>(t.Data, ty * t.W, t.W);
                    int k = 0;
                    if (Vector.IsHardwareAccelerated)
                    {
                        var vs = Vector<float>.Zero; var vs2 = Vector<float>.Zero; var vst = Vector<float>.Zero;
                        int vc = Vector<float>.Count;
                        for (; k + vc <= t.W; k += vc)
                        {
                            var a = new Vector<float>(row.Slice(k, vc)); var b = new Vector<float>(trow.Slice(k, vc));
                            vs += a; vs2 += a * a; vst += a * b;
                        }
                        si += Vector.Sum(vs); si2 += Vector.Sum(vs2); sti += Vector.Sum(vst);
                    }
                    for (; k < t.W; k++) { float a = row[k]; si += a; si2 += a * a; sti += a * trow[k]; }
                }
                double iVar = si2 - si * si / n;
                if (iVar <= 1e-6) continue;
                float sc = (float)((sti - st * si / n) / Math.Sqrt(tVar * iVar));
                if (sc > best) { best = sc; bx = x; by = y; }
            }
        return (best, bx, by);
    }
}
