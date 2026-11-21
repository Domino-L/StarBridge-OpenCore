namespace StarBridge.HostRuntime.Achievements;

internal static class AchievementObservationRetry
{
    // Four-city policy shared by contract observations: 4/8/16/30/30 seconds,
    // or one normal read period for a lasting rejection/unsupported receipt.
    internal static int DelaySeconds(Exception error, int failures)
    {
        var rejected = error is Auth.ScmApiRateLimitException or Auth.ScmApiProtocolException or InvalidDataException ||
            error is HttpRequestException { StatusCode: >= System.Net.HttpStatusCode.BadRequest and < System.Net.HttpStatusCode.InternalServerError }
                and not HttpRequestException { StatusCode: System.Net.HttpStatusCode.Unauthorized };
        return rejected ? 300 : Math.Min(30, 1 << Math.Min(failures + 1, 5));
    }
}
