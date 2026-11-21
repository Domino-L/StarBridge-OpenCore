using System.Diagnostics;
using System.Globalization;

namespace StarBridge.HostRuntime.HealthReading;

internal sealed class HudHealthSample
{
    public double T;
    public string State = "";          // black / not_found / no_ring / ok
    public float Score;
    public double Cx, Cy;              // 圆心（面板坐标）
    public bool FullSearch;
    public int ArcDeg = -1;
    public double? RingEst;
    public float PctScore;
    public float[]?[] Probs = new float[]?[3];
    public int? CnnRaw;                // CNN 单帧直接读出的数（未过滤）
    public int? Display;               // 推算后显示的血量
    // Display 是"最后是满血、图标已收起"沿用出来的 100，不是这一帧读到的（读血服务按"没有格子"处理，满血由 SelfHealthFullHold 决定）
    public bool FoldedFull;
    // 这一帧本身有可用的读数证据（数字或圆环）；没有时 Display 只是从前几帧沿用下来的
    public bool Evidence;
    // 这一帧数字自己最支持的数（含十位纠正）；这一帧没用上数字时为 null。满血记忆只认清楚的数字
    public int? FrameDigits;
    // 这一帧用上的圆环读数（没用上时为 null）。只有圆环时，用它判断明显掉血
    public double? FrameRing;
    public string Note = "";
    public double P;
    public double MsLocate, MsRing, MsDigits, MsHmm, MsTotal;
    // 圆环外侧背景太亮（沙地、白墙），这一帧的圆环读数不可信
    public bool RingUnreliable;
    // 找不到图标，但在原位置读到了和当前显示接近的数（流血时"+"和血滴交替）
    public bool InPlace;
    // 诊断用（11-14 用户："突然识别出极低血量 但当前血量正常"，只计次数）：
    // 颜色法或备用图标在离确认过的位置较远处找到、又没有圆环确认，这一帧没采信
    public bool OffHomeRejected;
    // 大幅往下（15 以上）：这一帧开始确认 / 确认够了换上了 / 没等到换上就作废了
    public bool BigDropStarted, BigDropShown, BigDropAbandoned;
}

// 找血量图标：每帧先在"最后一次可靠位置"附近找（跟踪）；找不到时，隔一段时间整块找一次
internal sealed class HudIconLocator
{
    readonly HudHealthModel a;
    double homeCx = -1, homeCy = -1; int homeScale = 1;
    double lastFullT = -1e9;
    public double FullSearchMinInterval = 0.5;
    public int TrackRadius = 14;

    public HudIconLocator(HudHealthModel a) { this.a = a; }

    public void Reset() { lastFullT = -1e9; lastColourFullT = -1e9; homeCx = homeCy = -1; confCx = confCy = -1; }
    public (double cx, double cy, int si) Home => (homeCx, homeCy, homeScale);

    // 边缘法"+"模板以 0.6 以上认出的位置（不算备用图标、不算颜色法）。颜色法整块找时会锁到相邻的别的格子，
    // 读出那个格子的百分比（98q 录像 433 秒：真实约 84，显示 1，持续 13 秒；11-14 用户："突然识别出极低血量"）。
    // 只在停止截取（Reset）时清掉：换命时 HUD 布局不变。
    double confCx = -1, confCy = -1;
    public (double cx, double cy)? Confirmed => confCx >= 0 ? (confCx, confCy) : null;
    // 也用于颜色法、备用图标读到圆环和有效数的位置（复审 P2：只有颜色法认得出的格子，之后圆环空了也能原地放行）
    internal void Confirm(double cx, double cy) { confCx = cx; confCy = cy; }

    public (float score, double cx, double cy, int scaleIdx, bool full) Find(HudPanelFrame f, double t)
    {
        LastFromColour = false; LastAlt = false; altMoved = false;
        (float score, double cx, double cy, int si, bool alt) tr = (-1, homeCx, homeCy, homeScale, false);
        if (homeCx >= 0)
        {
            tr = Track(f, homeCx, homeCy);
            if (tr.score >= a.Thr)
            {
                if (tr.score >= 0.6) { SetHome(tr.cx, tr.cy, tr.si, tr.alt); if (!tr.alt) Confirm(tr.cx, tr.cy); }
                LastAlt = tr.alt; return (tr.score, tr.cx, tr.cy, tr.si, false);
            }
        }
        // 边缘法跟丢：先按颜色在上次位置附近找
        float[]? cm = null;
        if (UseColour && homeCx >= 0)
        {
            var cmLocal = HudColourPlus.Map(f, (int)homeCx - 60, (int)homeCy - 60, (int)homeCx + 60, (int)homeCy + 60);
            var h = cp.Find(cmLocal, (int)homeCx - 16, (int)homeCy - 16, (int)homeCx + 16, (int)homeCy + 16, false);
            if (h is { } hh) return FromColour(hh, false);
        }
        if (t - lastFullT < FullSearchMinInterval)
        {
            LastAlt = tr.alt; return (tr.score, tr.cx, tr.cy, tr.si, false);
        }
        lastFullT = t;
        var fu = Full(f);
        if (fu.score >= 0.6) { SetHome(fu.cx, fu.cy, fu.si, fu.alt); if (!fu.alt) Confirm(fu.cx, fu.cy); LastAlt = fu.alt; return (fu.score, fu.cx, fu.cy, fu.si, true); }
        if (UseColour && t - lastColourFullT >= ColourFullInterval)
        {
            lastColourFullT = t;
            cm ??= HudColourPlus.Map(f);
            var h = cp.Find(cm, 0, 0, HudPanelFrame.W, HudPanelFrame.H, true);
            if (h is { } hh) return FromColour(hh, true);
        }
        if (fu.score >= tr.score) { LastAlt = fu.alt; return (fu.score, fu.cx, fu.cy, fu.si, true); }
        LastAlt = tr.alt; return (tr.score, tr.cx, tr.cy, tr.si, true);
    }

    // 备用图标找到的位置要先存下原来的位置：下方读不出有效的 % 数字时退回
    void SetHome(double cx, double cy, int si, bool alt)
    {
        if (alt) { prevAltHome = (homeCx, homeCy, homeScale); altMoved = true; }
        homeCx = cx; homeCy = cy; homeScale = si;
    }
    (double cx, double cy, int si) prevAltHome = (-1, -1, 1); bool altMoved;
    public void RejectAlt() { if (LastAlt && altMoved) (homeCx, homeCy, homeScale) = prevAltHome; LastAlt = false; altMoved = false; }

    readonly HudColourPlus cp = new();
    double lastColourFullT = -1e9;
    public double ColourFullInterval = 2.0;   // 整块按颜色找比较费，跟丢时最多每 2 秒一次
    public bool UseColour = true;
    public bool LastFromColour { get; private set; }
    (double cx, double cy, int si) prevHome = (-1, -1, 1);
    // 颜色法找到的位置下方没有 % 号：不认，退回原来的位置
    public void RejectColour() { if (LastFromColour) { (homeCx, homeCy, homeScale) = prevHome; LastFromColour = false; } }

    (float score, double cx, double cy, int scaleIdx, bool full) FromColour(HudColourPlus.Hit h, bool full)
    {
        // 颜色法的比例（实测大小 = 1.0）换成边缘模板的比例（录像大小 = 1.0；实测约大 8%）
        double vs = h.Scale * 1.08; int si = 0;
        for (int i = 1; i < a.Plus.Count; i++) if (Math.Abs(a.Plus[i].Scale - vs) < Math.Abs(a.Plus[si].Scale - vs)) si = i;
        prevHome = (homeCx, homeCy, homeScale);
        homeCx = h.Cx; homeCy = h.Cy; homeScale = si; LastFromColour = true;
        return ((float)Math.Max(0.6, h.Score), h.Cx, h.Cy, si, full);
    }

    // 整块找：先用中间尺寸的模板每隔 3 像素粗扫，留下分数最高的几个候选，再在候选附近用 3 个尺寸精细比对
    (float score, double cx, double cy, int si, bool alt) Full(HudPanelFrame f)
    {
        var e = HudImageOps.EdgeRegion(f, 0, 0, HudPanelFrame.W, HudPanelFrame.H);
        var best = new (float s, double cx, double cy, int si)[2] { (-2, 0, 0, 1), (-2, 0, 0, 1) };
        foreach (var (set, isAlt) in Sets())
        {
            var mid = set[1];
            var cands = HudImageOps.MatchTopK(e, HudPanelFrame.W, HudPanelFrame.H, mid, 3, 5, 12);
            foreach (var (cx0, cy0) in cands)
                for (int si = 0; si < set.Count; si++)
                {
                    var t = set[si];
                    int tx = (int)Math.Round(cx0 - t.W / 2.0), ty = (int)Math.Round(cy0 - t.H / 2.0);
                    var r = HudImageOps.MatchBest(e, HudPanelFrame.W, HudPanelFrame.H, t, tx - 4, tx + 4, ty - 4, ty + 4, 1);
                    int k = isAlt ? 1 : 0;
                    if (r.score > best[k].s) best[k] = (r.score, r.x + t.W / 2.0, r.y + t.H / 2.0, si);
                }
        }
        return Pick(best);
    }

    // 备用图标在普通背景上也能到 0.5~0.58，所以只有分数到 AltMin 以上、并且比"+"高时才用它
    public float AltMin = 0.7f;
    (float score, double cx, double cy, int si, bool alt) Pick((float s, double cx, double cy, int si)[] b)
        => b[1].s >= AltMin && b[1].s > b[0].s ? (b[1].s, b[1].cx, b[1].cy, b[1].si, true) : (b[0].s, b[0].cx, b[0].cy, b[0].si, false);

    // "+"，以及缺氧时换成的备用图标（同样以圆环中心为准、同样 3 个比例）
    public bool UseAlt = true;
    public bool LastAlt { get; private set; }
    IEnumerable<(List<HudTemplate> set, bool alt)> Sets()
    {
        yield return (a.Plus, false);
        if (UseAlt && a.Alt.Count == a.Plus.Count) yield return (a.Alt, true);
    }

    (float score, double cx, double cy, int si, bool alt) Track(HudPanelFrame f, double lastCx, double lastCy)
    {
        int R = TrackRadius, maxT = Sets().Max(z => z.set.Max(p => p.W)), pad = 6;
        int x0 = Math.Max(0, (int)(lastCx - maxT / 2.0 - R - pad)), y0 = Math.Max(0, (int)(lastCy - maxT / 2.0 - R - pad));
        int x1 = Math.Min(HudPanelFrame.W, (int)(lastCx + maxT / 2.0 + R + pad)), y1 = Math.Min(HudPanelFrame.H, (int)(lastCy + maxT / 2.0 + R + pad));
        int w = x1 - x0, h = y1 - y0;
        if (w < maxT + 2 || h < maxT + 2) return (-1, lastCx, lastCy, 1, false);
        var e = HudImageOps.EdgeRegion(f, x0, y0, w, h);
        var best = new (float s, double cx, double cy, int si)[2] { (-2, lastCx, lastCy, 1), (-2, lastCx, lastCy, 1) };
        foreach (var (set, isAlt) in Sets())
            for (int si = 0; si < set.Count; si++)
            {
                var t = set[si];
                int tx = (int)Math.Round(lastCx - t.W / 2.0) - x0, ty = (int)Math.Round(lastCy - t.H / 2.0) - y0;
                var r = HudImageOps.MatchBest(e, w, h, t, tx - R, tx + R, ty - R, ty + R, 1);
                int k = isAlt ? 1 : 0;
                if (r.score > best[k].s) best[k] = (r.score, r.x + x0 + t.W / 2.0, r.y + y0 + t.H / 2.0, si);
            }
        return Pick(best);
    }
}

// 读格子下方的百分比数字：找 % 号，往左切 3 位，交给 CNN
internal sealed class HudDigitReader
{
    readonly HudHealthModel a; readonly HudDigitCnn cnn;
    int lastPx = -1, lastPy = -1;
    public HudDigitReader(HudHealthModel a, HudDigitCnn cnn) { this.a = a; this.cnn = cnn; }

    // 实测（11-11）：玩家游戏里的数字可能比训练录像大几个百分点，固定格距会切偏。
    // 所以把数字带按几种比例重采样，各找一次 % 号；每个比例的 % 号匹配分数做长期平均，
    // 用平均最高的比例切数字交给模型（同一个玩家的数字大小不会变，平均越久越稳）。
    public static readonly double[] Scales = { 0.86, 0.88, 0.90, 0.92, 0.94, 0.96, 0.98, 1.0, 1.02 };
    public bool MultiScale = true;
    public int Spread = 0;
    readonly double[] pctAvg = new double[Scales.Length]; int avgCount; long frameNo;
    public double LastScale { get; private set; } = 1.0;
    // 训练取样用：最近一次交给模型的三个数字位小图（25x11，个位在前）
    public readonly float[]?[] LastPatches = new float[]?[3];

    public void ResetScale() { Array.Clear(pctAvg); avgCount = 0; frameNo = 0; LastScale = 1.0; }

    public (float pct, float[]?[] probs) Read(HudPanelFrame f, double cx, double cy)
    {
        if (!MultiScale) { var b = Band(f, cx, cy, 1.0, null); return b == null ? (-1, new float[]?[3]) : Slice(b.Value); }
        var bands = new (float[] v, float bp, int px, int py)?[Scales.Length];
        float bestBp = -2;
        int cur0 = Array.IndexOf(Scales, LastScale); if (cur0 < 0) cur0 = Array.IndexOf(Scales, 1.0);
        // 省电：只有建立阶段和每 8 次才把所有比例都找一遍（更新平均）；平时只算选定比例和左右各一个
        bool sweep = frameNo < 30 || (frameNo % 8) == 0; frameNo++;
        // 先在当前比例上完整找 % 号，其他比例只在按比例换算出的位置附近找（省时）
        bands[cur0] = Band(f, cx, cy, Scales[cur0], null);
        (int x, int y)? HintFor(int i) => bands[cur0] is { } m0 && m0.bp >= 0.6f
            ? ((int)Math.Round(BW / 2.0 + (m0.px - BW / 2.0) * Scales[i] / Scales[cur0]), (int)Math.Round(BH / 2.0 + (m0.py - BH / 2.0) * Scales[i] / Scales[cur0]))
            : null;
        for (int i = 0; i < Scales.Length; i++)
        {
            if (i == cur0 || (!sweep && Math.Abs(i - cur0) > Spread)) continue;
            bands[i] = Band(f, cx, cy, Scales[i], HintFor(i));
        }
        foreach (var bb in bands) if (bb is { } b0 && b0.bp > bestBp) bestBp = b0.bp;
        // 只用 % 号看得很清楚的帧来平均；前 30 帧快速建立，之后慢慢更新
        if (sweep && bestBp >= 0.8f)
        {
            double k = avgCount < 30 ? 1.0 / (avgCount + 1) : 0.01; avgCount++;
            for (int i = 0; i < Scales.Length; i++) pctAvg[i] += k * ((bands[i]?.bp ?? 0) - pctAvg[i]);
        }
        // 换比例要明显更好才换（防止来回跳）
        int cur = Array.IndexOf(Scales, LastScale); if (cur < 0) cur = Array.IndexOf(Scales, 1.0);
        int bi = cur;
        if (sweep && avgCount >= 5)
        {
            // % 号匹配分数在正确比例附近是一段平台：取平台中间那个比例
            int top = 0; for (int i = 1; i < Scales.Length; i++) if (pctAvg[i] > pctAvg[top]) top = i;
            int lo = top, hi = top;
            while (lo > 0 && pctAvg[lo - 1] >= pctAvg[top] - 0.006) lo--;
            while (hi < Scales.Length - 1 && pctAvg[hi + 1] >= pctAvg[top] - 0.006) hi++;
            int mid = (lo + hi) / 2;
            if (cur < lo || cur > hi) bi = mid;
            else if (Math.Abs(cur - mid) >= 2) bi = mid;
        }
        LastScale = Scales[bi];
        bands[bi] ??= Band(f, cx, cy, Scales[bi], HintFor(bi));
        for (int i = Math.Max(0, bi - Spread); i <= Math.Min(Scales.Length - 1, bi + Spread); i++) bands[i] ??= Band(f, cx, cy, Scales[i], HintFor(i));
        if (bands[bi] == null) return (-1, new float[]?[3]);
        var main = Slice(bands[bi]!.Value);
        if (Spread <= 0) return main;
        // 在选定比例附近的几个比例各读一次，把每一位的概率平均：单个比例切偏读错时，不会一家说了算
        var sum = new float[]?[3]; int n = 0;
        for (int i = Math.Max(0, bi - Spread); i <= Math.Min(Scales.Length - 1, bi + Spread); i++)
        {
            if (bands[i] is not { } b || b.bp < 0.6f) continue;
            var r = i == bi ? main : Slice(b);
            bool same = true; for (int k = 0; k < 3; k++) if ((r.probs[k] == null) != (main.probs[k] == null)) same = false;
            if (!same) continue;
            for (int k = 0; k < 3; k++) if (r.probs[k] is { } q) { sum[k] ??= new float[11]; for (int c = 0; c < 11; c++) sum[k]![c] += q[c]; }
            n++;
        }
        if (n <= 1) return main;
        for (int k = 0; k < 3; k++) if (sum[k] is { } q) for (int c = 0; c < 11; c++) q[c] /= n;
        return (main.pct, sum);
    }

    (float[] v, float bp, int px, int py)? Band(HudPanelFrame f, double cx, double cy, double s, (int x, int y)? hint)
    {
        int icx = (int)Math.Round(cx), icy = (int)Math.Round(cy);
        int bw = BW, bh = BH;
        // 数字带中心在图标下方；缩放以这个中心为准（s<1 = 把画面缩小）
        double ccx = icx, ccy = icy + 36 + bh / 2.0;
        double sx0 = ccx - bw / 2.0 / s, sy0 = ccy - bh / 2.0 / s;
        if (sx0 < 0 || sy0 < 0 || sx0 + bw / s + 1 >= HudPanelFrame.W || sy0 + bh / s + 1 >= HudPanelFrame.H) return null;
        var v = new float[bw * bh];
        for (int y = 0; y < bh; y++)
            for (int x = 0; x < bw; x++)
            {
                double fx = sx0 + (x + 0.5) / s - 0.5, fy = sy0 + (y + 0.5) / s - 0.5;
                int x0 = (int)Math.Floor(fx), y0 = (int)Math.Floor(fy);
                double ax = fx - x0, ay = fy - y0;
                float Vp(int xx, int yy) { int i = (yy * HudPanelFrame.W + xx) * 3; return HudImageOps.V(f.Bgr[i], f.Bgr[i + 1], f.Bgr[i + 2]); }
                v[y * bw + x] = (float)((1 - ay) * ((1 - ax) * Vp(x0, y0) + ax * Vp(x0 + 1, y0)) + ay * ((1 - ax) * Vp(x0, y0 + 1) + ax * Vp(x0 + 1, y0 + 1)));
            }
        // % 号：先用 6 个代表模板在整条数字带里粗找，再用全部模板在最好位置 ±1 像素精找
        float bp = -2; int px = 0, py = 0;
        for (int ti = 0; ti < a.Pct.Count; ti += Math.Max(1, a.Pct.Count / 6))
        {
            var r = hint is { } h0 ? HudImageOps.MatchBestDense(v, bw, bh, a.Pct[ti], h0.x - 3, h0.x + 3, h0.y - 3, h0.y + 3) : HudImageOps.MatchBestDense(v, bw, bh, a.Pct[ti]);
            if (r.score > bp) { bp = r.score; px = r.x; py = r.y; }
        }
        int cx0 = px, cy0 = py;
        foreach (var t in a.Pct)
        {
            var r = HudImageOps.MatchBestDense(v, bw, bh, t, cx0 - 1, cx0 + 1, cy0 - 1, cy0 + 1);
            if (r.score > bp) { bp = r.score; px = r.x; py = r.y; }
        }
        return (v, bp, px, py);
    }

    const int BW = 92, BH = 36;

    (float pct, float[]?[] probs) Slice((float[] v, float bp, int px, int py) band)
    {
        var (v, bp, px, py) = band; int bw = BW, bh = BH;
        Array.Clear(LastPatches);
        var probs = new float[]?[3];
        const int PITCH = 11, ROWS = 25;
        for (int k = 1; k <= 3; k++)
        {
            int ax = px - PITCH * k;
            if (ax < 0 || py + ROWS > bh) continue;
            var patch = new float[ROWS * PITCH];
            for (int y = 0; y < ROWS; y++) for (int x = 0; x < PITCH; x++) patch[y * PITCH + x] = v[(py + y) * bw + ax + x];
            probs[k - 1] = cnn.Predict(patch); LastPatches[k - 1] = patch;
        }
        return (bp, probs);
    }

    public static int? RawValue(float[]?[] probs)
    {
        var s = "";
        for (int k = 2; k >= 0; k--)
        {
            var q = probs[k]; if (q == null) continue;
            int am = Array.IndexOf(q, q.Max());
            if (am != 10) s += am.ToString(CultureInfo.InvariantCulture);
        }
        if (s.Length == 0 || !int.TryParse(s, out int v) || v > 100) return null;
        return v;
    }
}

// 按血量变化规律逐帧推算（移植自 scripts/hmm_filter.py，CNN 模式）
internal sealed class SelfHealthFilter
{
    const int N = 101;
    public double PStay15 = 0.985, PDrift15 = 0.01, PJump15 = 0.001;
    public double RingSigma = 8, RingTrust = 0.4, DigitTrust = 0.3, ShowP = 0.6, Hold = 2.0, Strong = 0.6;
    public double Settle = 0.07, SettleSmall = 0.07, SettleRev = 0.07, RevWin = 3.0, Gamma = 1.5;
    public int Big = 15, RingAgree = 12;
    // 掉血可以一下掉很多，回血通常是慢慢涨：往上跳（超过 2）要多确认一会儿（用户 11-12 "加进 r6"）；
    // 刚掉下去又回到掉之前的数以内（多半是刚才那次读错了）不算，照常快速改回
    public double SettleUp = 0.25;
    int? beforeDrop; double upSince = -1, lastUpT = -1e9;
    // 最近一次往上换显示之前的值：刚往上变过又回落到它附近（多半是刚才误读成高了），大幅往下照旧快速改回（复审 P2）
    int? beforeUp;
    public double UpGap = 0.3;
    // 大幅往下（比显示低 Big 以上）要多确认（11-14 用户："突然识别出极低血量 但当前血量正常"）：推算换到新值以后，
    // 这一帧自己的读数也要在显示值 Big 以下，连续 SettleBigDown 秒才换；掉到 DeepBelow 以下、一下掉 DeepDrop 以上的，
    // 要 SettleDeepDown 秒，除非近 1 秒的圆环也同意。计时和往上一样：丢一两帧不算中断。往上、小变化都不变。
    public double SettleBigDown = 0.375, SettleDeepDown = 1.0;
    public int DeepBelow = 20, DeepDrop = 30;
    // 已经在确认时，读数在 Big 边界附近晃（比如显示 80，读数 65、66 交替）不算作废（复审 P2）
    public int DownKeep = 3;
    double downSince = -1, lastDownT = -1e9;
    // 短暂黑屏只暂停大跌确认（复审 P1）：黑屏那段时间不算进确认时长；黑屏前后这一帧的读数相差超过 BlackSameTarget，重新确认
    public int BlackSameTarget = 6;
    double lastStepT = -1e9; int? downM; bool downCrossedBlack;
    double[,] T = new double[N, N]; double tHz = -1;
    double[] post = Uniform();
    int? shown; double lastConfT = -1e9; int? pend; double pendT;
    public int? Shown => shown;
    int lastDir; double lastChangeT = -1e9;
    (double cx, double cy)? home;
    readonly List<(double t, double v)> ringHist = new();
    // 数字和圆环对不上时用：最近一段的圆环读数、最近一帧数字的对数似然
    readonly List<(double t, double v)> ringLong = new();
    double[]? lastLL; double lastLLT = -1e9;
    public double ConflictPts = 6, AltNear = 5, AltMargin = 7, RingSpread = 8;
    public bool ConflictGuard = true;
    public string ConflictNote { get; private set; } = "";
    double blackSince = -1;

    static double[] Uniform() { var p = new double[N]; Array.Fill(p, 1.0 / N); return p; }

    public void Reset() { post = Uniform(); shown = null; pend = null; lastDir = 0; home = null; ringHist.Clear(); ringLong.Clear(); lastLL = null; blackSince = -1; beforeDrop = null; upSince = -1; lastUpT = -1e9; downSince = -1; lastDownT = -1e9; beforeUp = null; lastStepT = -1e9; downM = null; downCrossedBlack = false; }

    // 有一次大幅下跌正在确认（换命、停止截取前用来记一次作废，复审 P3）
    internal bool BigDropPending => downSince >= 0;

    void AbandonDown(HudHealthSample r) { if (downSince >= 0) { downSince = -1; r.BigDropAbandoned = true; } downM = null; downCrossedBlack = false; }

    static double Median(List<(double t, double v)> xs)
    {
        var vs = xs.Select(z => z.v).OrderBy(x => x).ToArray();
        return vs.Length % 2 == 1 ? vs[vs.Length / 2] : (vs[vs.Length / 2 - 1] + vs[vs.Length / 2]) / 2;
    }

    void EnsureT(double hz)
    {
        if (Math.Abs(hz - tHz) < 1e-6) return;
        tHz = hz;
        double k = 15.0 / hz;
        double pd = Math.Min(0.3, PDrift15 * k), pj = Math.Min(0.1, PJump15 * k), ps = 1 - pd - pj;
        for (int i = 0; i < N; i++)
        {
            double sum = 0;
            for (int j = 0; j < N; j++) T[i, j] = pj / N;
            T[i, i] += ps;
            foreach (var (d, w) in new[] { (1, 0.6), (2, 0.4) })
                foreach (int j in new[] { i - d, i + d })
                    if (j >= 0 && j < N) T[i, j] += pd * w / 2;
            for (int j = 0; j < N; j++) sum += T[i, j];
            for (int j = 0; j < N; j++) T[i, j] /= sum;
        }
    }

    public void Step(HudHealthSample r, double hz)
    {
        double t = r.T;
        double stepDt = Math.Clamp(t - lastStepT, 0, 0.45); lastStepT = t;
        if (r.State == "black")
        {
            if (blackSince < 0) blackSince = t;
            if (t - blackSince >= 0.45)
            {
                post = Uniform(); if (shown is < 99) shown = null;
                r.Display = null; r.Note = "黑屏"; r.P = 0; return;
            }
            // 短暂黑屏（不到 0.45 秒）只暂停正在确认的大幅下跌（98q 录像 1165 秒、275 秒：真实往下掉一截时夹了三帧黑屏，
            // 重新计时让显示晚了约 1 秒）：不算中断，也不算进确认时长（复审 P1：黑屏不能替误读凑时间）
            // 先按上一次证据的时间判断是否已经断档（复审 REVIEW3：断采一秒后接一帧黑屏不能续上），没断才暂停
            if (downSince >= 0 && t - lastDownT > Math.Max(UpGap, 2.5 / hz) + 1e-9) AbandonDown(r);
            if (downSince >= 0) { downSince += stepDt; lastDownT = t; downCrossedBlack = true; }
        }
        else blackSince = -1;
        EnsureT(hz);
        int? frameDigitBest = null;   // 这一帧数字（按推算实际用的逐位概率，含十位纠正）最支持的数
        var np = new double[N];
        for (int j = 0; j < N; j++) { double s = 0; for (int i = 0; i < N; i++) s += post[i] * T[i, j]; np[j] = s; }
        post = np;
        if (r.Score >= Strong && r.State == "ok") home = (r.Cx, r.Cy);
        // 亮背景下圆环不可信：这一帧不拿（之前的）圆环读数来纠正数字，也不拿它限制大幅变化
        bool ringUsable = !r.RingUnreliable;
        bool hasCenter = r.State is "ok" or "no_ring";
        bool usable = hasCenter && (r.Score >= Strong || (home.HasValue && Math.Abs(r.Cx - home.Value.cx) < 10 && Math.Abs(r.Cy - home.Value.cy) < 10 && r.Score >= 0.45));
        var used = new List<string>();
        if (usable)
        {
            double? ring = r.RingEst;
            double hi = 0; for (int v = 15; v < N; v++) hi += post[v];
            bool priorHigh = hi > 0.9;
            if (r.PctScore >= 0.6)
            {
                var ll = new double[N];
                for (int k = 0; k < 3; k++)
                {
                    var pr0 = r.Probs[k]; if (pr0 == null) continue;
                    var pr = pr0.Select(x => Math.Max((double)x, 0.02)).ToArray();
                    if (k == 1 && ((ring.HasValue && ring.Value >= 15) || priorHigh)) pr[10] = Math.Min(pr[10], 0.1);
                    double s = pr.Sum(); for (int c = 0; c < 11; c++) pr[c] /= s;
                    for (int v = 0; v < N; v++)
                    {
                        var str = v.ToString(CultureInfo.InvariantCulture);
                        int c = k < str.Length ? str[str.Length - 1 - k] - '0' : 10;
                        ll[v] += Gamma * Math.Log(pr[c]);
                    }
                }
                lastLL = (double[])ll.Clone(); lastLLT = t;
                { int fb = 0; for (int v = 1; v < N; v++) if (ll[v] > ll[fb]) fb = v; frameDigitBest = fb; }
                double mx = ll.Max(), sl = 0; var lik = new double[N];
                for (int v = 0; v < N; v++) { lik[v] = Math.Exp(ll[v] - mx); sl += lik[v]; }
                for (int v = 0; v < N; v++) post[v] *= DigitTrust * lik[v] / sl + (1 - DigitTrust) / N;
                used.Add("数字");
            }
            if (ring.HasValue)
            {
                var g = new double[N]; double sg = 0;
                for (int v = 0; v < N; v++) { g[v] = Math.Exp(-0.5 * Math.Pow((v - ring.Value) / RingSigma, 2)); sg += g[v]; }
                for (int v = 0; v < N; v++) post[v] *= RingTrust * g[v] / sg + (1 - RingTrust) / N;
                used.Add("圆环");
                r.FrameRing = ring.Value;
            }
            double ps = post.Sum(); for (int v = 0; v < N; v++) post[v] /= ps;
            if (ring.HasValue) { ringHist.Add((t, ring.Value)); ringLong.Add((t, ring.Value)); }
        }
        ringHist.RemoveAll(z => t - z.t > 1.0);
        double longWin = Math.Max(2.0, 4.0 / hz);
        ringLong.RemoveAll(z => t - z.t > longWin);
        int m = 0; for (int v = 1; v < N; v++) if (post[v] > post[m]) m = v;
        double pm = post[m];
        // 数字和圆环对不上：最近几次圆环读数彼此一致、但和数字推算差得多（比如 71 被认成 77），
        // 就在数字的各种读法里挑一个和圆环接近、又不太离谱的；挑不到就按圆环，同时降低把握。
        if (ConflictGuard && ringUsable && ringLong.Count >= 3)
        {
            var vs = ringLong.Select(z => z.v).OrderBy(x => x).ToArray();
            double med = vs.Length % 2 == 1 ? vs[vs.Length / 2] : (vs[vs.Length / 2 - 1] + vs[vs.Length / 2]) / 2;
            if (vs[^1] - vs[0] <= RingSpread && Math.Abs(med - m) > ConflictPts)
            {
                int alt = -1;
                if (lastLL != null && t - lastLLT <= longWin)
                {
                    double bestLL = double.NegativeInfinity;
                    // 似然差不多时，取离圆环近的
                    for (int v = 0; v < N; v++)
                    {
                        double sc = lastLL[v] - 0.05 * Math.Abs(v - med);
                        if (Math.Abs(v - med) <= AltNear && sc > bestLL) { bestLL = sc; alt = v; }
                    }
                    if (alt >= 0 && lastLL[m] - lastLL[alt] > AltMargin) alt = -1;
                }
                if (alt >= 0) { m = alt; pm = 0.75; ConflictNote = "数字和圆环对不上，取接近圆环的读法"; }
                else { m = (int)Math.Round(Math.Clamp(med, 0, 100)); pm = 0.6; ConflictNote = "数字和圆环对不上，按圆环"; }
            }
            else ConflictNote = "";
        }
        else ConflictNote = "";
        // 往上的确认要连续（复审 R8）：超过 UpGap 秒没有新的"高于显示"的可用读数，就重新计时；只丢一两帧不算中断
        // （每次都清零会让 03-28 录像里真实回血一直被短暂丢帧打断：每秒 8 次平均误差 4.03 → 5.64）
        // 间隔按采样周期放宽：每秒读得少时，相邻两帧本身就隔得久，不能算中断（复审 R9）
        if (upSince >= 0 && t - lastUpT > Math.Max(UpGap, 2.5 / hz) + 1e-9) upSince = -1;
        if (downSince >= 0 && t - lastDownT > Math.Max(UpGap, 2.5 / hz) + 1e-9) AbandonDown(r);
        if (pm >= ShowP)
        {
            if (shown == null || m == shown) { shown = m; lastConfT = t; pend = null; upSince = -1; AbandonDown(r); }
            else
            {
                if (pend != m) { pend = m; pendT = t; }
                int dir = m > shown ? 1 : -1;
                bool reversal = lastDir != 0 && dir != lastDir && t - lastChangeT < RevWin;
                bool backUp = dir > 0 && reversal && beforeDrop is { } bd && m <= bd;
                double need = Math.Abs(m - shown.Value) <= 2 ? SettleSmall
                    : dir > 0 && !backUp ? Math.Max(SettleUp, Settle)
                    : (reversal ? SettleRev : Settle);
                bool ringOk = true;
                if (ringUsable && Math.Abs(m - shown.Value) >= Big && ringHist.Count >= 3)
                {
                    var vs = ringHist.Select(z => z.v).OrderBy(x => x).ToArray();
                    double med = vs.Length % 2 == 1 ? vs[vs.Length / 2] : (vs[vs.Length / 2 - 1] + vs[vs.Length / 2]) / 2;
                    ringOk = Math.Abs(med - m) <= RingAgree;
                }
                // 往上：回血时数值每帧都在涨，等不到"同一个数"持续够久；所以看"读数一直高于显示"持续了多久，到了就显示最新的数
                bool upHold = dir > 0 && !backUp && Math.Abs(m - shown.Value) > 2;
                // 这一帧自己读到了比显示高的数（数字或可信的圆环），才算往上的证据（复审 R9：只看定位不够）
                // 数字证据用推算实际采用的逐位概率（含十位纠正），和推算一致（复审 R10：只看 CnnRaw 会和推算不一致）
                bool upEvidence = usable && ((frameDigitBest is int fbv && fbv > shown.Value + 2)
                    || (ringUsable && r.RingEst is double rg && rg > shown.Value + 2));
                if (!upHold) upSince = -1;
                else if (upEvidence) { if (upSince < 0) upSince = t; lastUpT = t; }
                // 大幅往下：和往上一样看"这一帧自己的读数也在显示值 Big 以下"持续了多久，不看同一个数持续多久
                // （真被打掉一大截时读数会在相邻几个数之间晃）。只有刚往上变过、又回落到往上之前的值附近，才照旧按 SettleRev
                // 快速改回；回血后马上误读成极低，仍要确认（复审 P2）。
                int bigAt = downSince >= 0 ? Big - DownKeep : Big;
                bool backDown = reversal && beforeUp is int bu && m >= bu - 2;
                bool bigDown = dir < 0 && !backDown && shown.Value - m >= bigAt;
                bool downEvidence = usable && ((frameDigitBest is int fdd && fdd <= shown.Value - bigAt)
                    || (ringUsable && r.RingEst is double rgd && rgd <= shown.Value - bigAt));
                if (!bigDown) AbandonDown(r);
                else
                {
                    // 黑屏前后这一帧自己的读数不是同一个值（相差超过 BlackSameTarget）：两次不相干的读数不拼成一次确认，重新开始。
                    // 比的是这一帧的读数（数字，没有就圆环），不是推算值：推算值黑屏后会慢一帧才跟过去。
                    int? ev = frameDigitBest is int fde && fde <= shown.Value - bigAt ? fde
                        : ringUsable && r.RingEst is double rge && rge <= shown.Value - bigAt ? (int)Math.Round(rge) : null;
                    if (downEvidence && downSince >= 0 && downCrossedBlack && downM is int dm && ev is int ev0 && Math.Abs(ev0 - dm) > BlackSameTarget) AbandonDown(r);
                    if (downEvidence)
                    {
                        if (downSince < 0) { downSince = t; r.BigDropStarted = true; }
                        lastDownT = t; downM = ev; downCrossedBlack = false;
                    }
                    need = Math.Max(need, SettleBigDown);
                    bool ringAgrees = ringUsable && ringHist.Count >= 3 && Math.Abs(Median(ringHist) - m) <= RingAgree;
                    if (m < DeepBelow && shown.Value - m >= DeepDrop && !ringAgrees) need = Math.Max(need, SettleDeepDown);
                }
                // 往上换显示的这一帧本身要有往上的证据（没读到数的帧不能把显示改上去）；大幅往下同样
                double since = upHold ? (upEvidence && upSince >= 0 ? t - upSince : 0)
                    : bigDown ? (downEvidence && downSince >= 0 ? t - downSince : 0)
                    : t - pendT;
                if (since >= need - 1e-9 && ringOk)
                {
                    if (bigDown) { r.BigDropShown = true; downSince = -1; }
                    beforeDrop = dir < 0 ? shown : null; beforeUp = dir > 0 ? shown : null; shown = m; lastConfT = t; pend = null; lastDir = dir; lastChangeT = t; upSince = -1;
                }
                else lastConfT = t;
            }
        }
        r.P = pm;
        r.Evidence = used.Count > 0;
        r.FrameDigits = frameDigitBest;
        if (ConflictNote.Length > 0) used.Add(ConflictNote);
        if (shown != null && t - lastConfT <= Math.Max(Hold, 3.0 / hz)) { r.Display = shown; r.Note = string.Join("+", used); }
        else if (shown is >= 99) { r.Display = 100; r.Note = "图标已收起"; r.FoldedFull = true; }
        else { r.Display = null; r.Note = "图标不在或被挡"; }
    }
}

internal sealed class HudHealthRecognizer
{
    public readonly HudHealthModel A; readonly HudIconLocator loc; readonly HudDigitReader dr; public readonly SelfHealthFilter Filter = new();

    public HudHealthRecognizer(HudHealthModel model)
    {
        A = model;
        loc = new HudIconLocator(A); dr = new HudDigitReader(A, new HudDigitCnn(A));
    }

    public HudIconLocator Loc => loc;

    // 停止读取后再开始：推算、找图标的位置、数字比例的长期平均全部重来（HUD 缩放可能变了）
    public void Reset() { Filter.Reset(); loc.Reset(); dr.ResetScale(); lastLockT = -1e9; }

    // 换命（阵亡、倒地、进出服务器等）：只重来推算。格子位置、确认过的位置、数字比例都留着，HUD 布局不会因为换命改变。
    public void ResetEstimate() { Filter.Reset(); lastLockT = -1e9; }

    // 颜色法、备用图标找到的位置离"确认过的位置"在这个范围内（面板像素；面板总是按 1440p 比例缩放成 900x490）才算原地。
    // 同一个格子，颜色法和边缘法的位置最多差约 3 像素；相邻格子大约隔 126 像素。HUD 布局会变：98q 录像里血量格子
    // 从第一个位置挪到第二个，第一个位置换成另一个带 % 的格子，它的十字离旧位置只有约 14 像素，所以不能放宽到 20。
    public const double ConfirmedNearPx = 8;

    // distance：离确认过的位置多远，null = 还没有确认过的位置；ringReadable：这个位置读到了圆环（亮背景下不算）
    internal static bool AcceptOffHome(double? distance, bool ringReadable) =>
        ringReadable || (distance is double d && d <= ConfirmedNearPx);

    double? DistanceToConfirmed(double cx, double cy) =>
        loc.Confirmed is { } c ? Math.Sqrt((cx - c.cx) * (cx - c.cx) + (cy - c.cy) * (cy - c.cy)) : null;

    // 流血时血量格子里"+"和血滴交替出现（网上视频 8xm 686~692 秒、719~722 秒）。找不到图标时按原位置继续读，
    // 条件：当前显示不是满血（满血时格子会收起，原位置可能换成别的格子）、最近 InPlaceWindow 秒内确实认出过
    // 图标（InPlaceEligible），并且原位置下方读出的数和当前显示相差不超过 InPlaceNear（InPlaceAccept）。
    public bool UseInPlace = true;
    public double InPlaceWindow = 8.0; public int InPlaceNear = 10;
    double lastLockT = -1e9;

    internal static bool InPlaceEligible(int? shown, double sinceLock, double window) =>
        shown is int sv && sv < 99 && sinceLock <= window;
    internal static bool InPlaceAccept(int? shown, int? reading, int near) =>
        shown is int sv && reading is int v && Math.Abs(v - sv) <= near;
    // 试过"原位置在确认位置附近、圆环读得出来、和读数一致就认"（为了流血中真掉一大截时跟得上），录像回归里不行：
    // aZlQ 录像 1211 秒，血量格子消失、饮水格子（99%）挪到原位置，它的竖条被读成满圆环，显示了 140 秒满血。已撤掉。

    public double BrightBackground = 150;

    // 亮背景（沙地、白墙）：不管圆环这一帧读没读出来，都标记圆环不可信（之前的圆环读数也不能拿来纠正数字）
    public static void ApplyBrightBackground(HudHealthSample r, HudPanelFrame f, double cx, double cy, double ringR, double limit)
    {
        if (OutsideBrightness(f, cx, cy, ringR) <= limit) return;
        r.RingUnreliable = true; r.ArcDeg = -1; r.RingEst = null;
    }

    // 圆环外侧一圈（半径 +5..+10）的亮度中位数
    static double OutsideBrightness(HudPanelFrame f, double cx, double cy, double r)
    {
        var vals = new List<int>(240);
        for (int rr = (int)r + 5; rr <= (int)r + 10; rr++)
            for (int i = 0; i < 40; i++)
            {
                double a = i * Math.PI * 2 / 40;
                int x = (int)Math.Round(cx + rr * Math.Cos(a)), y = (int)Math.Round(cy + rr * Math.Sin(a));
                if (x < 0 || y < 0 || x >= HudPanelFrame.W || y >= HudPanelFrame.H) continue;
                int j = (y * HudPanelFrame.W + x) * 3;
                vals.Add(HudImageOps.V(f.Bgr[j], f.Bgr[j + 1], f.Bgr[j + 2]));
            }
        if (vals.Count == 0) return 0;
        vals.Sort(); return vals[vals.Count / 2];
    }
    public HudDigitReader Digits => dr;

    public HudHealthSample Process(HudPanelFrame f, double t, double hz)
    {
        var r = new HudHealthSample { T = t };
        var sw = Stopwatch.StartNew();
        if (HudImageOps.MeanBgr(f) < 10) { r.State = "black"; }
        else
        {
            var fd = loc.Find(f, t);
            r.Score = fd.score; r.Cx = fd.cx; r.Cy = fd.cy; r.FullSearch = fd.full;
            r.MsLocate = sw.Elapsed.TotalMilliseconds;
            if (fd.score < A.Thr)
            {
                r.State = "not_found";
                var hm = loc.Home;
                if (UseInPlace && hm.cx >= 0 && InPlaceEligible(Filter.Shown, t - lastLockT, InPlaceWindow))
                {
                    var (pct, probs) = dr.Read(f, hm.cx, hm.cy);
                    int? v = pct >= 0.6 ? HudDigitReader.RawValue(probs) : null;
                    if (InPlaceAccept(Filter.Shown, v, InPlaceNear))
                    {
                        r.InPlace = true; r.Cx = hm.cx; r.Cy = hm.cy; r.Score = 0.6f;
                        double ringR = A.R0 * A.Plus[hm.si].Scale;
                        r.ArcDeg = HudRing.ArcDegrees(f, hm.cx, hm.cy, ringR);
                        ApplyBrightBackground(r, f, hm.cx, hm.cy, ringR, BrightBackground);
                        r.State = r.ArcDeg < 0 ? "no_ring" : "ok";
                        if (r.ArcDeg >= 0) r.RingEst = r.ArcDeg >= 360 ? 100 : Math.Max(0, r.ArcDeg / 3.6 - 3.0);
                        r.PctScore = pct; r.Probs = probs; r.CnnRaw = v;
                    }
                }
            }
            else
            {
                double t1 = sw.Elapsed.TotalMilliseconds;
                double ringR = A.R0 * A.Plus[fd.scaleIdx].Scale;
                r.ArcDeg = HudRing.ArcDegrees(f, fd.cx, fd.cy, ringR);
                // 亮背景（沙地、白墙）上圆环没填满的那一段也是亮的，圆环读数不可信：不用圆环，只看数字
                ApplyBrightBackground(r, f, fd.cx, fd.cy, ringR, BrightBackground);
                r.State = r.ArcDeg < 0 ? "no_ring" : "ok";
                if (r.ArcDeg >= 0) r.RingEst = r.ArcDeg >= 360 ? 100 : Math.Max(0, r.ArcDeg / 3.6 - 3.0);
                double t2 = sw.Elapsed.TotalMilliseconds; r.MsRing = t2 - t1;
                var (pct, probs) = dr.Read(f, fd.cx, fd.cy);
                r.PctScore = pct; r.Probs = probs;
                if (pct >= 0.6) r.CnnRaw = HudDigitReader.RawValue(probs);
                // 颜色法找到的位置：下方要有 % 号、并且读得出一个有效的数，才认
                // 备用图标（缺氧时"+"换成的图标）同样：下方要有 % 号并读出有效数，才认
                if (loc.LastAlt && (pct < 0.6 || r.CnnRaw == null)) { loc.RejectAlt(); r.State = "not_found"; r.RingEst = null; r.ArcDeg = -1; r.Probs = new float[]?[3]; r.PctScore = pct; }
                else if (loc.LastFromColour && (pct < 0.6 || r.CnnRaw == null)) { loc.RejectColour(); r.State = "not_found"; r.RingEst = null; r.ArcDeg = -1; r.Probs = new float[]?[3]; r.PctScore = pct; }
                // 离确认过的位置较远（或者还没有确认过的位置）时，颜色法、备用图标找到的东西要读得到圆环才认
                else if ((loc.LastAlt || loc.LastFromColour) && !AcceptOffHome(DistanceToConfirmed(fd.cx, fd.cy), r.ArcDeg >= 0 && !r.RingUnreliable))
                {
                    if (loc.LastAlt) loc.RejectAlt(); else loc.RejectColour();
                    r.State = "not_found"; r.RingEst = null; r.ArcDeg = -1; r.Probs = new float[]?[3]; r.PctScore = pct; r.CnnRaw = null;
                    r.OffHomeRejected = true;
                }
                // 读到了圆环、又读出了有效数：这个位置也算确认过
                else if ((loc.LastAlt || loc.LastFromColour) && r.ArcDeg >= 0 && !r.RingUnreliable) loc.Confirm(fd.cx, fd.cy);
                r.MsDigits = sw.Elapsed.TotalMilliseconds - t2;
            }
        }
        if (!r.InPlace && r.State is "ok" or "no_ring" && r.Score >= 0.6f) lastLockT = t;
        double t3 = sw.Elapsed.TotalMilliseconds;
        Filter.Step(r, hz);
        r.MsHmm = sw.Elapsed.TotalMilliseconds - t3;
        r.MsTotal = sw.Elapsed.TotalMilliseconds;
        return r;
    }
}
