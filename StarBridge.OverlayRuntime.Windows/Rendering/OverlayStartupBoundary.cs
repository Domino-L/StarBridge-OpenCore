namespace StarBridge.Desktop;

internal static class OverlayStartupBoundary
{
    internal static bool TryShow(
        Action show,
        Action close,
        Action<Exception> reportFailure)
    {
        try
        {
            show();
            return true;
        }
        catch (Exception startupException)
        {
            Exception failure = startupException;
            try
            {
                close();
            }
            catch (Exception cleanupException)
            {
                failure = new AggregateException(
                    "Overlay startup and cleanup both failed.",
                    startupException,
                    cleanupException);
            }

            try
            {
                reportFailure(failure);
            }
            catch
            {
                // The operational boundary must never turn failure reporting
                // into another unhandled UI-thread exception.
            }

            return false;
        }
    }
}
