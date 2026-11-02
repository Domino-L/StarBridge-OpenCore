using System.Globalization;
using System.Net.Http.Headers;
using System.Numerics;

namespace StarBridge.HostRuntime.Marketplace;

internal sealed partial class ScmMarketplaceReader
{
    // Wall time remains available for 24-hour metadata expiry and HTTP-date conversion only.
    internal TimeProvider MonotonicTime { get; init; } = TimeProvider.System;
    private (long Started, TimeSpan? Delay)? _categoryPause;

    // Called under _categoryLock. Null duration means an unrepresentably long server delay.
    private bool CategoriesPaused(long now) => _categoryPause is { } pause &&
        (pause.Delay is null || MonotonicTime.GetElapsedTime(pause.Started, now) < pause.Delay.Value);

    private void PauseCategories(HttpResponseMessage response)
    {
        lock (_categoryLock)
        {
            var now = MonotonicTime.GetTimestamp();
            var delay = RetryDelay(response, Clock());
            if (_categoryPause is { } pause && CategoriesPaused(now))
            {
                if (pause.Delay is null) return;
                var remaining = pause.Delay.Value - MonotonicTime.GetElapsedTime(pause.Started, now);
                if (delay is { } finite && finite <= remaining) return;
            }
            _categoryPause = (now, delay);
        }
    }

    private static TimeSpan? RetryDelay(HttpResponseMessage response, DateTimeOffset receivedAt)
    {
        if (!response.Headers.TryGetValues("Retry-After", out var values)) return TimeSpan.FromMinutes(2);
        var headers = values.ToArray();
        if (headers.Length != 1) return TimeSpan.FromMinutes(2);
        var raw = headers[0].Trim();
        // Read raw seconds as well: the typed HTTP header rejects negative delta-seconds.
        if (BigInteger.TryParse(raw, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var seconds))
        {
            if (seconds <= 0) return TimeSpan.Zero;
            var ticks = seconds * TimeSpan.TicksPerSecond;
            // Fail closed instead of shortening an extreme, but valid, Retry-After value.
            return ticks > TimeSpan.MaxValue.Ticks ? null : TimeSpan.FromTicks((long)ticks);
        }
        if (RetryConditionHeaderValue.TryParse(raw, out var retry) && retry.Date is { } date)
            return date > receivedAt ? date - receivedAt : TimeSpan.Zero;
        return TimeSpan.FromMinutes(2);
    }
}
