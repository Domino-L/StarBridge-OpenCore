namespace StarBridge.HostRuntime.HealthReading;

// Turns a captured BGRA region (any size) into the 900x490 BGR panel the recognizer expects.
// At 2560x1440 the region is already 900x490 and is copied as is; other heights are scaled
// bilinearly (pixel centres aligned, edges clamped).
internal static class HudPanelScaler
{
    public static void FromBgra(byte[] region, int rw, int rh, HudPanelFrame frame)
    {
        var o = frame.Bgr;
        if (rw == HudPanelFrame.W && rh == HudPanelFrame.H)
        {
            for (int i = 0, j = 0; i < o.Length; i += 3, j += 4) { o[i] = region[j]; o[i + 1] = region[j + 1]; o[i + 2] = region[j + 2]; }
            return;
        }
        double sx = (double)rw / HudPanelFrame.W, sy = (double)rh / HudPanelFrame.H;
        for (int y = 0; y < HudPanelFrame.H; y++)
        {
            double fy = (y + 0.5) * sy - 0.5;
            int y0 = Math.Clamp((int)Math.Floor(fy), 0, rh - 1), y1 = Math.Min(y0 + 1, rh - 1);
            double ay = Math.Clamp(fy - y0, 0, 1);
            for (int x = 0; x < HudPanelFrame.W; x++)
            {
                double fx = (x + 0.5) * sx - 0.5;
                int x0 = Math.Clamp((int)Math.Floor(fx), 0, rw - 1), x1 = Math.Min(x0 + 1, rw - 1);
                double ax = Math.Clamp(fx - x0, 0, 1);
                for (int c = 0; c < 3; c++)
                {
                    double v = (1 - ay) * ((1 - ax) * region[(y0 * rw + x0) * 4 + c] + ax * region[(y0 * rw + x1) * 4 + c])
                             + ay * ((1 - ax) * region[(y1 * rw + x0) * 4 + c] + ax * region[(y1 * rw + x1) * 4 + c]);
                    o[(y * HudPanelFrame.W + x) * 3 + c] = (byte)Math.Round(v);
                }
            }
        }
    }
}
