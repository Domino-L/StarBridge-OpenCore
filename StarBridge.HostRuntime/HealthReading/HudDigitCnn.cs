namespace StarBridge.HostRuntime.HealthReading;

// 小型数字识别 CNN 的推理（手写，不依赖外部库；权重来自 data/cnn_digits_v2.pt）
// 结构：conv3x3(1→16)+ReLU+池化 → conv(16→32)+ReLU+池化 → conv(32→48)+ReLU → 平均池化到 3x1 → 全连接 144→64→11
internal sealed class HudDigitCnn
{
    readonly (int[] s, float[] d) w0, b0, w1, b1, w2, b2, l0, lb0, l1, lb1;

    public HudDigitCnn(HudHealthModel a)
    {
        w0 = a.Cnn["f.0.weight"]; b0 = a.Cnn["f.0.bias"];
        w1 = a.Cnn["f.3.weight"]; b1 = a.Cnn["f.3.bias"];
        w2 = a.Cnn["f.6.weight"]; b2 = a.Cnn["f.6.bias"];
        l0 = a.Cnn["f.10.weight"]; lb0 = a.Cnn["f.10.bias"];
        l1 = a.Cnn["f.13.weight"]; lb1 = a.Cnn["f.13.bias"];
    }

    static float[] Conv(float[] x, int cin, int h, int w, (int[] s, float[] d) W, (int[] s, float[] d) B)
    {
        int cout = W.s[0];
        var o = new float[cout * h * w];
        for (int co = 0; co < cout; co++)
            for (int y = 0; y < h; y++)
                for (int xx = 0; xx < w; xx++)
                {
                    float s = B.d[co];
                    for (int ci = 0; ci < cin; ci++)
                        for (int ky = 0; ky < 3; ky++)
                        {
                            int yy = y + ky - 1; if (yy < 0 || yy >= h) continue;
                            for (int kx = 0; kx < 3; kx++)
                            {
                                int x2 = xx + kx - 1; if (x2 < 0 || x2 >= w) continue;
                                s += W.d[((co * cin + ci) * 3 + ky) * 3 + kx] * x[(ci * h + yy) * w + x2];
                            }
                        }
                    o[(co * h + y) * w + xx] = s > 0 ? s : 0;
                }
        return o;
    }

    static float[] Pool2(float[] x, int c, int h, int w, out int oh, out int ow)
    {
        oh = h / 2; ow = w / 2;
        var o = new float[c * oh * ow];
        for (int ci = 0; ci < c; ci++)
            for (int y = 0; y < oh; y++)
                for (int xx = 0; xx < ow; xx++)
                {
                    float m = float.MinValue;
                    for (int a = 0; a < 2; a++) for (int b = 0; b < 2; b++) m = Math.Max(m, x[(ci * h + 2 * y + a) * w + 2 * xx + b]);
                    o[(ci * oh + y) * ow + xx] = m;
                }
        return o;
    }

    // 输入：25x11 的亮度小图（0..255）；输出 11 个概率（0~9，10 = 空位）
    public float[] Predict(float[] patch)
    {
        var p = Prep(patch);
        var a = Conv(p, 1, 25, 11, w0, b0);
        a = Pool2(a, 16, 25, 11, out int h1, out int w1_);
        a = Conv(a, 16, h1, w1_, w1, b1);
        a = Pool2(a, 32, h1, w1_, out int h2, out int w2_);
        a = Conv(a, 32, h2, w2_, w2, b2);
        // 平均池化到 3x1（6x2 → 每 2 行 x 2 列取平均）
        int c = 48; var f = new float[c * 3];
        for (int ci = 0; ci < c; ci++)
            for (int i = 0; i < 3; i++)
            {
                int r0 = i * h2 / 3, r1 = (int)Math.Ceiling((i + 1) * h2 / 3.0);
                float s = 0; int n = 0;
                for (int y = r0; y < r1; y++) for (int x = 0; x < w2_; x++) { s += a[(ci * h2 + y) * w2_ + x]; n++; }
                f[ci * 3 + i] = s / n;
            }
        var hdn = new float[64];
        for (int j = 0; j < 64; j++) { float s = lb0.d[j]; for (int k = 0; k < 144; k++) s += l0.d[j * 144 + k] * f[k]; hdn[j] = s > 0 ? s : 0; }
        var o = new float[11];
        for (int j = 0; j < 11; j++) { float s = lb1.d[j]; for (int k = 0; k < 64; k++) s += l1.d[j * 64 + k] * hdn[k]; o[j] = s; }
        float mx = o.Max(), sum = 0;
        for (int j = 0; j < 11; j++) { o[j] = MathF.Exp(o[j] - mx); sum += o[j]; }
        for (int j = 0; j < 11; j++) o[j] /= sum;
        return o;
    }

    static float Percentile(float[] sorted, double q)
    {
        double idx = q / 100.0 * (sorted.Length - 1);
        int lo = (int)Math.Floor(idx), hi = Math.Min(lo + 1, sorted.Length - 1);
        return (float)(sorted[lo] + (sorted[hi] - sorted[lo]) * (idx - lo));
    }

    static float[] Prep(float[] p)
    {
        var s = (float[])p.Clone(); Array.Sort(s);
        float lo = Percentile(s, 5), hi = Percentile(s, 99);
        float den = Math.Max(hi - lo, 1f);
        var o = new float[p.Length];
        for (int i = 0; i < p.Length; i++) o[i] = Math.Clamp((p[i] - lo) / den, 0f, 1.5f);
        return o;
    }
}
