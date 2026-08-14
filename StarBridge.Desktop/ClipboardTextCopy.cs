namespace StarBridge.Desktop;

internal static class ClipboardTextCopy
{
    private const int MaximumAttempts = 3;
    private static readonly TimeSpan RetryDelay = TimeSpan.FromMilliseconds(80);

    internal static Task<bool> TryWriteAsync(string text) =>
        TryWriteAsync(
            text,
            System.Windows.Clipboard.SetText,
            static () => System.Windows.Clipboard.ContainsText(System.Windows.TextDataFormat.UnicodeText)
                ? System.Windows.Clipboard.GetText(System.Windows.TextDataFormat.UnicodeText)
                : null,
            static delay => Task.Delay(delay));

    internal static async Task<bool> TryWriteAsync(
        string text,
        Action<string> writeText,
        Func<string?> readText,
        Func<TimeSpan, Task> delay)
    {
        ArgumentNullException.ThrowIfNull(writeText);
        ArgumentNullException.ThrowIfNull(readText);
        ArgumentNullException.ThrowIfNull(delay);

        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        for (var attempt = 0; attempt < MaximumAttempts; attempt++)
        {
            try
            {
                writeText(text);
                return true;
            }
            catch
            {
                if (ContainsRequestedText(text, readText))
                {
                    return true;
                }

                if (attempt == MaximumAttempts - 1)
                {
                    return false;
                }

                await delay(RetryDelay);
                if (ContainsRequestedText(text, readText))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static bool ContainsRequestedText(string expected, Func<string?> readText)
    {
        try
        {
            return string.Equals(readText(), expected, StringComparison.Ordinal);
        }
        catch
        {
            return false;
        }
    }
}
