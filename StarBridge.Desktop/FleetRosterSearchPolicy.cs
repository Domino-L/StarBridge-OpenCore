namespace StarBridge.Desktop;

internal static class FleetRosterSearchPolicy
{
    internal static bool Matches(string? searchText, params string?[] values)
    {
        var tokens = (searchText ?? "")
            .Split(
                (char[]?)null,
                StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (tokens.Length == 0)
        {
            return true;
        }

        return tokens.All(token => values.Any(value =>
            !string.IsNullOrWhiteSpace(value) &&
            value.Contains(token, StringComparison.CurrentCultureIgnoreCase)));
    }
}
