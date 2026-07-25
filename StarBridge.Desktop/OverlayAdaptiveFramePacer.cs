namespace StarBridge.Desktop;

internal sealed class OverlayAdaptiveFramePacer
{
    private const int AdaptiveFloorFramesPerSecond = 60;
    private const int OverloadThreshold = 6;
    private const long FallbackHoldMilliseconds = 4_000;

    private int _overloadScore;
    private long _fallbackUntilMilliseconds;

    public int Resolve(int requestedFramesPerSecond, long nowMilliseconds)
    {
        var requested = Math.Clamp(requestedFramesPerSecond, 1, 120);
        return requested > AdaptiveFloorFramesPerSecond && nowMilliseconds < _fallbackUntilMilliseconds
            ? AdaptiveFloorFramesPerSecond
            : requested;
    }

    public void ReportFrame(int requestedFramesPerSecond, double elapsedMilliseconds, long nowMilliseconds)
    {
        var requested = Math.Clamp(requestedFramesPerSecond, 1, 120);
        if (requested <= AdaptiveFloorFramesPerSecond)
        {
            _overloadScore = 0;
            _fallbackUntilMilliseconds = 0;
            return;
        }

        if (nowMilliseconds < _fallbackUntilMilliseconds)
        {
            return;
        }

        var budgetMilliseconds = 1000.0 / requested;
        if (elapsedMilliseconds > budgetMilliseconds * 2)
        {
            _overloadScore += 3;
        }
        else if (elapsedMilliseconds > budgetMilliseconds * 1.15)
        {
            _overloadScore++;
        }
        else
        {
            _overloadScore = Math.Max(0, _overloadScore - 1);
        }

        if (_overloadScore < OverloadThreshold)
        {
            return;
        }

        _overloadScore = 0;
        _fallbackUntilMilliseconds = nowMilliseconds + FallbackHoldMilliseconds;
    }
}
