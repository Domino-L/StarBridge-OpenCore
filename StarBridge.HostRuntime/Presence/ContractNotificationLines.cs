namespace StarBridge.HostRuntime.Presence;

// Shared physical-line grammar for live reading and archive import. Joining keeps
// the first timestamp; repeated continuation timestamps belong to the same HUD event.
internal static class ContractNotificationLines
{
    internal const int MaximumLength = 65536;

    internal static bool IsIncompleteContractNotification(string line) =>
        IsContractNotification(line) && line.Count(c => c == '"') == 1;

    // Only an open notification quote plus a body/queue trailer can continue it; a
    // different diagnostic record must still reach the normal identity/city/parser path.
    internal static bool TryContractContinuation(string pending, string line, out string body)
    {
        body = line;
        if (pending.Count(c => c == '"') != 1) return false;
        if (line.StartsWith('<') && line.Length > 1 && char.IsAsciiDigit(line[1]))
        {
            var end = line.IndexOf('>');
            if (end < 0 || !DateTimeOffset.TryParse(line.AsSpan(1, end - 1),
                System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.AssumeUniversal, out _)) return false;
            body = line[(end + 1)..].TrimStart();
            // Both audited examples end their notification text here. Tags such as
            // [Notice] <PlayerOnline> and other new diagnostics are never joined.
            if (!System.Text.RegularExpressions.Regex.IsMatch(body,
                "^[^\"\\r\\n]*\" \\[[0-9]+\\] to queue\\..*MissionId:",
                System.Text.RegularExpressions.RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100))) return false;
        }
        return CompleteContractNotification(pending + " " + body);
    }

    internal static bool IsContractNotification(string line) =>
        line.Contains("<SHUDEvent_OnNotification> Added notification", StringComparison.Ordinal) &&
        new[] { "已接受合约", "Contract Accepted", "新的任务", "New Objective", "任务完成", "Objective Complete" }
            .Any(text => line.Contains(text, StringComparison.OrdinalIgnoreCase));

    internal static bool CompleteContractNotification(string line)
    {
        var field = line.IndexOf("ObjectiveId:", StringComparison.OrdinalIgnoreCase);
        return field >= 0 && line.IndexOf(']', field) >= 0 && line.Contains("MissionId:", StringComparison.OrdinalIgnoreCase);
    }
}
